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
  )
import Control.Exception
  ( IOException
  , SomeException
  , catch
  , try
  )
import Control.Monad (forever, void)
import Data.Aeson (Value (String))
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
  , hSetBuffering
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
  -- normal operation, never happens).
  concurrently_ (dataLoop ds dataSock) (ctlLoop cfg ds ctlSock)
    `catch` \(_ :: SomeException) -> pure ()
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
    Just oldH -> hClose oldH `catch` \(_ :: SomeException) -> pure ()
    Nothing -> pure ()
  readHevmLines ds h
  atomically $ do
    cur <- readTVar (dsHevmHandle ds)
    case cur of
      Just curH | curH == h -> do
        writeTVar (dsHevmHandle ds) Nothing
        void (stepTVar (dsSession ds) EvDisconnect)
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
        EffRejectInbound rid msg ->
          safeWrite h (encodeResponse (RpcError rid (String msg)))
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
        Left _ -> pure ()

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
      `catch` \(_ :: SomeException) -> pure ()

handleCtlConn :: Config -> DaemonState -> Handle -> IO ()
handleCtlConn cfg ds h = do
  result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
  case result of
    Left _ -> hClose h
    Right lineBs -> do
      resp <- case decodeControlReq lineBs of
        Left err -> pure (ControlErr (T.pack ("bad request: " <> err)))
        Right req -> processControlReq cfg ds req
      safeWrite h (encodeControlResp resp)
      hClose h

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
            safeWrite h (encodeResponse resp)
            pure ReplyOk
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

sendAndAwait :: Config -> DaemonState -> Handle -> Value -> Text -> Value -> IO ControlResp
sendAndAwait cfg ds h rid method params = do
  tmv <- newEmptyTMVarIO
  let idText = canonicalId rid
  atomically $ modifyTVar' (dsWaiters ds) (Map.insert idText tmv)
  mresp <-
    (do
      safeWrite h (encodeRequest (RpcRequest rid method params))
      timeout (cfgTimeoutSec cfg * 1000000) (atomically (takeTMVar tmv))
    )
      `catch` \(_ :: SomeException) -> pure Nothing
  atomically $ modifyTVar' (dsWaiters ds) (Map.delete idText)
  pure $ case mresp of
    Nothing -> ControlErr "timeout"
    Just (RpcResult _ result) -> SendOk result
    Just (RpcError _ errVal) -> ControlErr (canonicalId errVal)

--------------------------------------------------------------------------------
-- Small shared helpers.
--------------------------------------------------------------------------------

stepTVar :: TVar Session -> SessionEvent -> STM SessionEffect
stepTVar var ev = do
  s <- readTVar var
  let (s', eff) = step ev s
  writeTVar var s'
  pure eff

safeWrite :: Handle -> BS.ByteString -> IO ()
safeWrite h bs = (BS.hPut h bs >> hFlush h) `catch` \(_ :: SomeException) -> pure ()
