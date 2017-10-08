{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeSynonymInstances #-}

module LamportClock
    ( Pid (..)
    , Time
    , Timestamp (..)
    , Clock (..)
    , LamportClock
    , runLamportClock
    , Process
    , runProcess
    , barrier
    ) where

import           Control.Monad.Reader (ReaderT, ask, runReaderT)
import           Control.Monad.State.Strict (MonadState, State, evalState,
                                             modify, state)
import           Data.EnumMap.Strict (EnumMap)
import qualified Data.EnumMap.Strict as EnumMap
import           Data.Functor (($>))
import           Data.Maybe (fromMaybe)
import           Data.Word (Word32)

type Time = Word

-- | Unique process identifier
newtype Pid = Pid Word32
    deriving (Enum, Eq, Ord, Show)

-- | TODO(cblp, 2017-09-28) Use bounded-intmap
type LamportClock = State (EnumMap Pid Time)

-- | XXX Make sure all subsequent calls to 'newTimestamp' return timestamps
-- greater than all prior calls.
barrier :: [Pid] -> LamportClock ()
barrier pids =
    modify $ \clocks -> let
        selectedClocks = EnumMap.fromList
            [(pid, fromMaybe 0 $ EnumMap.lookup pid clocks) | pid <- pids]
        in
        if null selectedClocks then
            clocks
        else
            EnumMap.union
                (selectedClocks $> succ (maximum selectedClocks))
                clocks

-- | Timestamps are assumed unique, totally ordered,
-- and consistent with causal order;
-- i.e., if assignment 1 happened-before assignment 2,
-- the former’s timestamp is less than the latter’s.
data Timestamp = Timestamp !Time !Pid
    deriving (Eq, Ord, Show)

class Applicative f => Clock f where
    -- | Get another unique timestamp
    newTimestamp :: f Timestamp

type Process = ReaderT Pid LamportClock

instance Clock Process where
    newTimestamp = do
        pid <- ask
        time <- postIncrementAt pid
        pure $ Timestamp time pid

runLamportClock :: LamportClock a -> a
runLamportClock action = evalState action mempty

runProcess :: Pid -> Process a -> LamportClock a
runProcess pid action = runReaderT action pid

postIncrementAt :: (MonadState (EnumMap k v) m, Enum k, Num v) => k -> m v
postIncrementAt k = state $ \m ->
    let v = fromMaybe 0 $ EnumMap.lookup k m
    in  (v, EnumMap.insert k (v + 1) m)
