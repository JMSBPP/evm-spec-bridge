{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | IO shell for the Foundry<->HEVM relay: a Unix-domain-socket daemon that
-- multiplexes a single HEVM (data-plane) connection against many short-lived
-- Foundry control connections, driving the pure 'Bridge.Relay.Session' state
-- machine and matching outbound replies via a waiter map keyed by canonical
-- JSON-RPC id.
module Bridge.Relay.Daemon
  ( Config (..)
  , runRelayd
  , safeWrite -- exported for direct unit testing of the write-failure contract
  ) where

import Bridge.Relay.Control
  ( decodeControlReq
  , encodeControlResp
  )
import Bridge.Relay.Session
  ( PendingInbound (..)
  , Session
  , SessionEffect (..)
  , SessionEvent (..)
  , canonicalId
  , markAlive
  , newSession
  , step
  )
import Bridge.Relay.Types (ControlReq (..), ControlResp (..))
import Bridge.Relay.Wire
  ( RpcRequest (..)
  , RpcResponse (..)
  , decodeRequest
  , decodeResponse
  , encodeRequest
  , encodeResponse
  , respId
  )
import Control.Concurrent (forkIO)
import Control.Concurrent.Async (concurrently_)
import Control.Concurrent.STM
  ( STM
  , TVar
  , atomically
  , modifyTVar'
  , newTVarIO
  , readTVar
  , readTVarIO
  , writeTVar
  )
import Control.Concurrent.STM.TMVar
  ( TMVar
  , newEmptyTMVarIO
  , putTMVar
  , takeTMVar
  , tryPutTMVar
  )
import Control.Exception
  ( IOException
  , catch
  , finally
  , try
  )
import Control.Monad (forever, void)
import Data.Aeson (Value (Null, String))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Network.Socket
  ( Family (AF_UNIX)
  , SockAddr (SockAddrUnix)
  , Socket
  , SocketType (Stream)
  , accept
  , bind
  , close
  , defaultProtocol
  , listen
  , socket
  , socketToHandle
  )
import System.Directory (removePathForcibly)
import System.IO
  ( BufferMode (LineBuffering)
  , Handle
  , IOMode (ReadWriteMode)
  , hClose
  , hFlush
  , hPutStrLn
  , hSetBuffering
  , stderr
  )
import System.Timeout (timeout)

-- | Daemon configuration. 'cfgCtlSock' defaults to @cfgDataSock <> ".ctl"@
-- when not explicitly supplied by the caller (see 'app/relayd/Main.hs').
data Config = Config
  { cfgDataSock :: FilePath
  , cfgCtlSock :: FilePath
  , cfgTimeoutSec :: Int
  , cfgQueueBound :: Int
  }
  deriving (Eq, Show)

-- | Shared mutable daemon state.
data DaemonState = DaemonState
  { dsSession :: TVar Session
  , dsHevmHandle :: TVar (Maybe Handle)
  , dsWaiters :: TVar (Map Text (TMVar RpcResponse))
  }

-- | Run the relay daemon. Blocks forever, running the data-plane accept loop
-- and the control-plane accept loop concurrently.
runRelayd :: Config -> IO ()
runRelayd cfg = do
  removePathForcibly (cfgDataSock cfg)
  removePathForcibly (cfgCtlSock cfg)
  -- Start with sessAlive = False: no HEVM connection has been accepted yet,
  -- so outbound 'send' must fail until the first data-plane accept.
  let sess0 = fst (step EvDisconnect (newSession (cfgQueueBound cfg)))
  ds <-
    DaemonState
      <$> newTVarIO sess0
      <*> newTVarIO Nothing
      <*> newTVarIO Map.empty
  dataSock <- listenUnix (cfgDataSock cfg)
  ctlSock <- listenUnix (cfgCtlSock cfg)
  -- Both loops run forever; this blocks until one of them raises (which, in
  -- normal operation, never happens). Only synchronous IO failures are
  -- caught here so the daemon can clean up its sockets and report the
  -- failure; asynchronous exceptions (e.g. a test harness cancelling this
  -- thread) propagate as usual.
  concurrently_ (dataLoop ds dataSock) (ctlLoop cfg ds ctlSock)
    `catch` \(e :: IOException) ->
      hPutStrLn stderr ("relayd: main loop terminated unexpectedly: " ++ show e)
  close dataSock
  close ctlSock

listenUnix :: FilePath -> IO Socket
listenUnix path = do
  sock <- socket AF_UNIX Stream defaultProtocol
  bind sock (SockAddrUnix path)
  listen sock 128
  pure sock

--------------------------------------------------------------------------------
-- Data plane: one HEVM connection at a time.
--------------------------------------------------------------------------------

dataLoop :: DaemonState -> Socket -> IO ()
dataLoop ds sock = forever $ do
  (conn, _) <- accept sock
  h <- socketToHandle conn ReadWriteMode
  hSetBuffering h LineBuffering
  mOld <- atomically $ do
    old <- readTVar (dsHevmHandle ds)
    _ <- stepTVar (dsSession ds) EvDisconnect
    writeTVar (dsHevmHandle ds) (Just h)
    modifyTVar' (dsSession ds) markAlive
    pure old
  case mOld of
    Just oldH -> hClose oldH `catch` \(_ :: IOException) -> pure ()
    Nothing -> pure ()
  readHevmLines ds h
  atomically $ do
    cur <- readTVar (dsHevmHandle ds)
    case cur of
      Just curH | curH == h -> do
        writeTVar (dsHevmHandle ds) Nothing
        void (stepTVar (dsSession ds) EvDisconnect)
        -- The connection we were reading from just dropped: any outbound
        -- 'send' currently blocked awaiting a reply on this handle will
        -- never get one, so fail it now instead of idling out the full
        -- 'cfgTimeoutSec'.
        failOutstandingWaiters ds
      _ -> pure ()

readHevmLines :: DaemonState -> Handle -> IO ()
readHevmLines ds h = do
  result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
  case result of
    Left _ -> pure ()
    Right lineBs -> do
      handleHevmLine ds h lineBs
      readHevmLines ds h

handleHevmLine :: DaemonState -> Handle -> BS.ByteString -> IO ()
handleHevmLine ds h lineBs =
  case decodeRequest lineBs of
    Right req -> do
      eff <- atomically (stepTVar (dsSession ds) (EvInbound req))
      case eff of
        EffRejectInbound rid msg -> do
          writeResult <- safeWrite h (encodeResponse (RpcError rid (String msg)))
          case writeResult of
            Left e ->
              hPutStrLn stderr ("relayd: failed to write overflow rejection to hevm: " ++ show e)
            Right () -> pure ()
        _ -> pure ()
    Left _ ->
      case decodeResponse lineBs of
        Right resp -> do
          let idText = canonicalId (respId resp)
          mtmv <- atomically $ do
            m <- readTVar (dsWaiters ds)
            pure (Map.lookup idText m)
          case mtmv of
            Just tmv -> atomically (putTMVar tmv resp)
            Nothing -> pure ()
        Left respErr ->
          hPutStrLn
            stderr
            ( "relayd: dropping undecodable hevm line (neither a request nor a response): "
                ++ respErr
            )

--------------------------------------------------------------------------------
-- Control plane: many short-lived connections.
--------------------------------------------------------------------------------

ctlLoop :: Config -> DaemonState -> Socket -> IO ()
ctlLoop cfg ds sock = forever $ do
  (conn, _) <- accept sock
  void $ forkIO $
    (do
      h <- socketToHandle conn ReadWriteMode
      hSetBuffering h LineBuffering
      handleCtlConn cfg ds h
    )
      `catch` \(e :: IOException) ->
        hPutStrLn stderr ("relayd: control connection handler failed: " ++ show e)

-- | Handle one control connection end-to-end, always closing the handle
-- on the way out (whether the request was malformed, the handler threw,
-- or everything went fine) so a throwing 'processControlReq' can't leak
-- the fd. The one-request-per-connection contract is unaffected: the
-- handle is still closed exactly once, right after (at most) one
-- request/response round-trip.
handleCtlConn :: Config -> DaemonState -> Handle -> IO ()
handleCtlConn cfg ds h = handleCtlConn' `finally` hClose h
  where
    handleCtlConn' = do
      result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
      case result of
        Left _ -> pure ()
        Right lineBs -> do
          resp <- case decodeControlReq lineBs of
            Left err -> pure (ControlErr (T.pack ("bad request: " <> err)))
            Right req -> processControlReq cfg ds req
          _ <- safeWrite h (encodeControlResp resp)
          pure ()

processControlReq :: Config -> DaemonState -> ControlReq -> IO ControlResp
processControlReq cfg ds req = case req of
  PollReq -> do
    eff <- atomically (stepTVar (dsSession ds) EvPoll)
    pure $ case eff of
      EffPollResult Nothing -> PollEmpty
      EffPollResult (Just pin) -> PollOk (pinId pin) (pinMethod pin) (pinParams pin)
      _ -> ControlErr "internal error: unexpected poll effect"
  ReplyReq rid result -> do
    eff <- atomically (stepTVar (dsSession ds) (EvReply rid result))
    case eff of
      EffWriteResponse resp -> do
        mh <- readTVarIO (dsHevmHandle ds)
        case mh of
          Just h -> do
            writeResult <- safeWrite h (encodeResponse resp)
            pure $ case writeResult of
              Left _ -> ControlErr "hevm write failed"
              Right () -> ReplyOk
          Nothing -> pure (ControlErr "hevm not connected")
      EffFail msg -> pure (ControlErr msg)
      _ -> pure (ControlErr "internal error: unexpected reply effect")
  SendReq method params -> do
    allocEff <- atomically (stepTVar (dsSession ds) EvSendAlloc)
    case allocEff of
      EffFail msg -> pure (ControlErr msg)
      EffAllocatedId rid -> do
        mh <- readTVarIO (dsHevmHandle ds)
        case mh of
          Nothing -> pure (ControlErr "hevm not connected")
          Just h -> sendAndAwait cfg ds h rid method params
      _ -> pure (ControlErr "internal error: unexpected alloc effect")

-- | Register a waiter, write the outbound request, and await the matching
-- response (or timeout). A write failure fails the control caller promptly
-- with @ControlErr "hevm write failed"@ rather than idling out the full
-- 'cfgTimeoutSec' waiting for a reply that will never arrive.
sendAndAwait :: Config -> DaemonState -> Handle -> Value -> Text -> Value -> IO ControlResp
sendAndAwait cfg ds h rid method params = do
  tmv <- newEmptyTMVarIO
  let idText = canonicalId rid
  atomically $ modifyTVar' (dsWaiters ds) (Map.insert idText tmv)
  writeResult <- safeWrite h (encodeRequest (RpcRequest rid method params))
  case writeResult of
    Left _ -> do
      atomically $ modifyTVar' (dsWaiters ds) (Map.delete idText)
      pure (ControlErr "hevm write failed")
    Right () -> do
      mresp <- timeout (cfgTimeoutSec cfg * 1000000) (atomically (takeTMVar tmv))
      atomically $ modifyTVar' (dsWaiters ds) (Map.delete idText)
      pure $ case mresp of
        Nothing -> ControlErr "timeout"
        Just (RpcResult _ result) -> SendOk result
        Just (RpcError _ errVal) -> ControlErr (errText errVal)

--------------------------------------------------------------------------------
-- Small shared helpers.
--------------------------------------------------------------------------------

stepTVar :: TVar Session -> SessionEvent -> STM SessionEffect
stepTVar var ev = do
  s <- readTVar var
  let (s', eff) = step ev s
  writeTVar var s'
  pure eff

-- | Unblock every currently pending outbound-send waiter with a synthetic
-- disconnection error rather than leaving it to idle out the full
-- 'cfgTimeoutSec'. Uses 'tryPutTMVar' (not 'putTMVar') because a waiter may
-- already have been filled by a genuine reply that 'sendAndAwait' hasn't
-- yet drained from 'dsWaiters'; blocking on a full TMVar here would
-- deadlock the data-plane loop.
failOutstandingWaiters :: DaemonState -> STM ()
failOutstandingWaiters ds = do
  m <- readTVar (dsWaiters ds)
  mapM_ (\tmv -> void (tryPutTMVar tmv (RpcError Null (String "hevm disconnected")))) (Map.elems m)
  writeTVar (dsWaiters ds) Map.empty

-- | Render an HEVM-supplied JSON-RPC error 'Value' as stderr/control-error
-- text. A plain JSON string error (the common case) is unwrapped to its
-- raw text instead of aeson-encoding it (which would wrap it in quotes,
-- e.g. @"boom"@), so genuine HEVM error tokens are distinguishable from
-- relayd's own sentinels (@timeout@, @unknown id@, @hevm disconnected@)
-- rather than all being uniformly quoted. Non-string error payloads (an
-- object or array, say) fall back to a compact JSON encoding since there
-- is no plain-text rendering to unwrap to.
errText :: Value -> Text
errText (String s) = s
errText other = canonicalId other

-- | Write a line to 'Handle', catching only synchronous 'IOException's (a
-- closed/broken pipe, say) so callers can react to a failed write instead of
-- having it silently swallowed. Asynchronous exceptions are not caught here.
safeWrite :: Handle -> BS.ByteString -> IO (Either IOException ())
safeWrite h bs = try (BS.hPut h bs >> hFlush h)
