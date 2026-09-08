module Bridge.Relay.Queue
  ( Queue
  , Overflow (..)
  , emptyQueue
  , push
  , pop
  ) where

data Overflow = Overflow
  deriving (Eq, Show)

data Queue a = Queue
  { qBound :: Int
  , qItems :: [a] -- front is head
  }
  deriving (Eq, Show)

emptyQueue :: Int -> Queue a
emptyQueue n = Queue {qBound = n, qItems = []}

push :: a -> Queue a -> Either Overflow (Queue a)
push x q
  | length (qItems q) >= qBound q = Left Overflow
  | otherwise = Right q {qItems = qItems q ++ [x]}

pop :: Queue a -> (Maybe a, Queue a)
pop q =
  case qItems q of
    [] -> (Nothing, q)
    (x : xs) -> (Just x, q {qItems = xs})
