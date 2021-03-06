{-|
Module      : Network.Nakadi.EventTypes.ShiftedCursors
Description : Implementation of Nakadi ShiftedCursors API
Copyright   : (c) Moritz Schulte 2017
License     : BSD3
Maintainer  : mtesseract@silverratio.net
Stability   : experimental
Portability : POSIX

This module implements the
@\/event-types\/EVENT-TYPE\/shifted-cursors@ API.
-}

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards       #-}

module Network.Nakadi.EventTypes.ShiftedCursors
  ( cursorsShift'
  , cursorsShiftR'
  , cursorsShift
  , cursorsShiftR
  ) where

import           Network.Nakadi.Internal.Prelude

import           Control.Lens
import           Network.Nakadi.Internal.Http
import qualified Network.Nakadi.Internal.Lenses  as L

path :: EventTypeName -> ByteString
path eventTypeName =
  "/event-types/"
  <> encodeUtf8 (unEventTypeName eventTypeName)
  <> "/shifted-cursors"

-- | @POST@ to @\/event-types\/EVENT-TYPE\/shifted-cursors@. Low level
-- interface.
cursorsShift' ::
  MonadNakadi m
  => Config          -- ^ Configuration
  -> EventTypeName   -- ^ Event Type
  -> [ShiftedCursor] -- ^ Cursors with Shift Distances
  -> m [Cursor]      -- ^ Resulting Cursors
cursorsShift' config eventTypeName cursors =
  httpJsonBody config ok200 []
  (setRequestMethod "POST"
   . setRequestPath (path eventTypeName)
   . setRequestBodyJSON cursors)

-- | @POST@ to @\/event-types\/EVENT-TYPE\/shifted-cursors@. Low level
-- interface. Retrieves the configuration from the environment.
cursorsShiftR' ::
  MonadNakadiEnv r m
  => EventTypeName   -- ^ Event Type
  -> [ShiftedCursor] -- ^ Cursors with Shift Distances
  -> m [Cursor]      -- ^ Resulting Cursors
cursorsShiftR' eventTypeName cursors = do
  config <- asks (view L.nakadiConfig)
  cursorsShift' config eventTypeName cursors

-- | @POST@ to @\/event-types\/EVENT-TYPE\/shifted-cursors@. High
-- level interface.
cursorsShift ::
  MonadNakadi m
  => Config        -- ^ Configuration
  -> EventTypeName -- ^ Event Type
  -> [Cursor]      -- ^ Cursors to shift
  -> Int64         -- ^ Shift Distance
  -> m [Cursor]    -- ^ Resulting Cursors
cursorsShift config eventTypeName cursors n =
  cursorsShift' config eventTypeName (map makeShiftCursor cursors)

  where makeShiftCursor Cursor { .. } =
          ShiftedCursor { _partition = _partition
                        , _offset    = _offset
                        , _shift     = n }

-- | @POST@ to @\/event-types\/EVENT-TYPE\/shifted-cursors@. High
-- level interface. Retrieves the configuration from the environment.
cursorsShiftR ::
  MonadNakadiEnv r m
  => EventTypeName -- ^ Event Type
  -> [Cursor]      -- ^ Cursors to shift
  -> Int64         -- ^ Shift Distance
  -> m [Cursor]    -- ^ Resulting Cursors
cursorsShiftR eventTypeName cursors n = do
  config <- asks (view L.nakadiConfig)
  cursorsShift config eventTypeName cursors n
