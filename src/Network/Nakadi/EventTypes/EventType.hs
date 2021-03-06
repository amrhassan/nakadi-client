{-|
Module      : Network.Nakadi.EventTypes.EventType
Description : Implementation of Nakadi EventTypes API
Copyright   : (c) Moritz Schulte 2017
License     : BSD3
Maintainer  : mtesseract@silverratio.net
Stability   : experimental
Portability : POSIX

This module implements the @\/event-types\/EVENT-TYPE@ API.
-}

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Network.Nakadi.EventTypes.EventType
  ( eventTypeGet
  , eventTypeGetR
  , eventTypeUpdate
  , eventTypeUpdateR
  , eventTypeDelete
  , eventTypeDeleteR
  ) where

import           Network.Nakadi.Internal.Prelude

import           Control.Lens
import           Network.Nakadi.Internal.Http
import qualified Network.Nakadi.Internal.Lenses  as L

path :: EventTypeName -> ByteString
path eventTypeName = "/event-types/" <> encodeUtf8 (unEventTypeName eventTypeName)

-- | Retrieves an 'EventType' by its 'EventTypeName'. @GET@ to
-- @\/event-types\/EVENT-TYPE@.
eventTypeGet ::
  MonadNakadi m
  => Config        -- ^ Configuration
  -> EventTypeName -- ^ Name of Event Type
  -> m EventType   -- ^ Event Type information
eventTypeGet config eventTypeName =
  httpJsonBody config ok200 [(status404, errorEventTypeNotFound)]
  (setRequestMethod "GET"
   . setRequestPath (path eventTypeName))

-- | Retrieves an 'EventType' by its 'EventTypeName', using the
-- configuration found in the environment. @GET@ to
-- @\/event-types\/EVENT-TYPE@.
eventTypeGetR ::
  MonadNakadiEnv r m
  => EventTypeName -- ^ Name of Event Type
  -> m EventType   -- ^ Event Type information
eventTypeGetR eventTypeName = do
  config <- asks (view L.nakadiConfig)
  eventTypeGet config eventTypeName

-- | Updates an event type given its 'EventTypeName' and its new
-- 'EventType' description. @PUT@ to @\/event-types\/EVENT-TYPE@.
eventTypeUpdate ::
  MonadNakadi m
  => Config        -- ^ Configuration
  -> EventTypeName -- ^ Name of Event Type
  -> EventType     -- ^ Event Type Settings
  -> m ()
eventTypeUpdate config eventTypeName eventType =
  httpJsonNoBody config ok200 []
  (setRequestMethod "PUT"
   . setRequestPath (path eventTypeName)
   . setRequestBodyJSON eventType)

-- | Updates an event type given its 'EventTypeName' and its new
-- 'EventType' description, using the configuration found in the
-- environment. @PUT@ to @\/event-types\/EVENT-TYPE@.
eventTypeUpdateR ::
  MonadNakadiEnv r m
  => EventTypeName -- ^ Name of Event Type
  -> EventType     -- ^ Event Type Settings
  -> m ()
eventTypeUpdateR eventTypeName eventType = do
  config <- asks (view L.nakadiConfig)
  eventTypeUpdate config eventTypeName eventType

-- | Deletes an event type given its 'EventTypeName'. @DELETE@ to
-- @\/event-types\/EVENT-TYPE@.
eventTypeDelete ::
  MonadNakadi m
  => Config        -- ^ Configuration
  -> EventTypeName -- ^ Name of Event Type
  -> m ()
eventTypeDelete config eventTypeName =
  httpJsonNoBody config ok200 [(status404, errorEventTypeNotFound)]
  (setRequestMethod "DELETE" . setRequestPath (path eventTypeName))

-- | Deletes an event type given its 'EventTypeName', using the
-- configuration found in the environment. @DELETE@ to
-- @\/event-types\/EVENT-TYPE@.
eventTypeDeleteR ::
  MonadNakadiEnv r m
  => EventTypeName -- ^ Name of Event Type
  -> m ()
eventTypeDeleteR eventTypeName = do
  config <- asks (view L.nakadiConfig)
  eventTypeDelete config eventTypeName
