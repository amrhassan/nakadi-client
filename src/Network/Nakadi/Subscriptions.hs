{-|
Module      : Network.Nakadi.Subscriptions.Stats
Description : Implementation of Nakadi Subscription API
Copyright   : (c) Moritz Schulte 2017
License     : BSD3
Maintainer  : mtesseract@silverratio.net
Stability   : experimental
Portability : POSIX

This module implements the @\/subscriptions@ API.
-}

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections         #-}

module Network.Nakadi.Subscriptions
  ( module Network.Nakadi.Subscriptions.Cursors
  , module Network.Nakadi.Subscriptions.Events
  , module Network.Nakadi.Subscriptions.Stats
  , module Network.Nakadi.Subscriptions.Subscription
  , subscriptionCreate'
  , subscriptionCreateR'
  , subscriptionCreate
  , subscriptionCreateR
  , subscriptionsList'
  , subscriptionsListR'
  , subscriptionsSource
  , subscriptionsSourceR
  , subscriptionsList
  , subscriptionsListR
  ) where

import           Network.Nakadi.Internal.Prelude

import           Conduit
import qualified Control.Exception.Safe                    as Safe
import           Control.Lens
import qualified Data.Text                                 as Text
import           Network.Nakadi.Internal.Http
import qualified Network.Nakadi.Internal.Lenses            as L
import           Network.Nakadi.Internal.Util
import           Network.Nakadi.Subscriptions.Cursors
import           Network.Nakadi.Subscriptions.Events
import           Network.Nakadi.Subscriptions.Stats
import           Network.Nakadi.Subscriptions.Subscription

path :: ByteString
path = "/subscriptions"

-- | @POST@ to @\/subscriptions@. Creates a new subscription. Low
-- level interface.
subscriptionCreate' :: MonadNakadi m
                    => Config
                    -> Subscription
                    -> m Subscription
subscriptionCreate' config subscription =
  httpJsonBody config status201 [(ok200, errorSubscriptionExistsAlready)]
  (setRequestMethod "POST" . setRequestPath path . setRequestBodyJSON subscription)

-- | @POST@ to @\/subscriptions@. Creates a new subscription. Low
-- level interface. Retrieves configuration from the environment.
subscriptionCreateR' ::
  MonadNakadiEnv r m
  => Subscription
  -> m Subscription
subscriptionCreateR' subscription = do
  config <- asks (view L.nakadiConfig)
  subscriptionCreate config subscription

-- | @POST@ to @\/subscriptions@. Creates a new subscription. Does not
-- fail if the requested subscription does already exist.
subscriptionCreate :: MonadNakadi m
                   => Config
                   -> Subscription
                   -> m Subscription
subscriptionCreate config subscription =
  Safe.catchJust exceptionPredicate (subscriptionCreate' config subscription) return

  where exceptionPredicate (SubscriptionExistsAlready s) = Just s
        exceptionPredicate _                             = Nothing

-- | @POST@ to @\/subscriptions@. Creates a new subscription. Does not
-- fail if the requested subscription does already exist. Retrieves
-- configuration from the environment.
subscriptionCreateR ::
  MonadNakadiEnv r m
  => Subscription
  -> m Subscription
subscriptionCreateR subscription = do
  config <- asks (view L.nakadiConfig)
  subscriptionCreate config subscription

-- | @GET@ to @\/subscriptions@. Internal low-level interface.
subscriptionsGet :: MonadNakadi m
                 => Config
                 -> [(ByteString, ByteString)]
                 -> m SubscriptionsListResponse
subscriptionsGet config queryParameters =
  httpJsonBody config ok200 []
  (setRequestMethod "GET"
   . setRequestPath path
   . setRequestQueryParameters queryParameters)

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. Low-level interface using pagination.
subscriptionsList' :: MonadNakadi m
                   => Config
                   -> Maybe ApplicationName
                   -> Maybe [EventTypeName]
                   -> Maybe Limit
                   -> Maybe Offset
                   -> m SubscriptionsListResponse
subscriptionsList' config maybeOwningApp maybeEventTypeNames maybeLimit maybeOffset =
  subscriptionsGet config queryParameters
  where queryParameters =
          buildQueryParameters maybeOwningApp maybeEventTypeNames maybeLimit maybeOffset

buildQueryParameters :: Maybe ApplicationName
                     -> Maybe [EventTypeName]
                     -> Maybe Limit
                     -> Maybe Offset
                     -> [(ByteString, ByteString)]
buildQueryParameters maybeOwningApp maybeEventTypeNames maybeLimit maybeOffset =
  catMaybes $
  [ ("owning_application",) . encodeUtf8 . unApplicationName <$> maybeOwningApp
  , ("limit",) . encodeUtf8 . tshow <$> maybeLimit
  , ("offset",) . encodeUtf8 . tshow <$> maybeOffset ]
  ++ case maybeEventTypeNames of
       Just eventTypeNames -> map (Just . ("event_type",) . encodeUtf8 . unEventTypeName) eventTypeNames
       Nothing -> []

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. Uses configuration contained in the
-- environment.
subscriptionsListR' ::
  (MonadNakadiEnv r m, MonadMask m)
  => Maybe ApplicationName
  -> Maybe [EventTypeName]
  -> Maybe Limit
  -> Maybe Offset
  -> m SubscriptionsListResponse
subscriptionsListR' owningApp eventTypeNames maybeLimit maybeOffset = do
  config <- asks (view L.nakadiConfig)
  subscriptionsList' config owningApp eventTypeNames maybeLimit maybeOffset

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. High-level Conduit interface.
subscriptionsSource :: (MonadNakadi m, MonadMask m)
                    => Config
                    -> Maybe ApplicationName
                    -> Maybe [EventTypeName]
                    -> Source m [Subscription]
subscriptionsSource config maybeOwningApp maybeEventTypeNames =
  nextPage initialQueryParameters

  where nextPage queryParameters = do
          resp <- lift $ subscriptionsGet config queryParameters
          yield (resp^.L.items)
          let maybeNextPath = Text.unpack . (view L.href) <$> (resp^.L.links.L.next)
          case maybeNextPath >>= extractQueryParametersFromPath  of
            Just nextQueryParameters -> do
              nextPage nextQueryParameters
            Nothing ->
              return ()

        initialQueryParameters =
          buildQueryParameters maybeOwningApp maybeEventTypeNames Nothing Nothing

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. High-level Conduit interface,
-- obtaining the configuration from the environment.
subscriptionsSourceR :: (MonadNakadiEnv r m, MonadMask m)
                     => Maybe ApplicationName
                     -> Maybe [EventTypeName]
                     -> Source m [Subscription]
subscriptionsSourceR maybeOwningApp maybeEventTypeNames = do
  config <- asks (view L.nakadiConfig)
  subscriptionsSource config maybeOwningApp maybeEventTypeNames

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. High-level list interface.
subscriptionsList :: (MonadNakadi m, MonadMask m)
                  => Config
                  -> Maybe ApplicationName
                  -> Maybe [EventTypeName]
                  -> m [Subscription]
subscriptionsList config maybeOwningApp maybeEventTypeNames = runConduit $
  subscriptionsSource config maybeOwningApp maybeEventTypeNames .| concatC .| sinkList

-- | @GET@ to @\/subscriptions@. Retrieves all subscriptions matching
-- the provided filter criteria. High-level Conduit interface,
-- obtaining the configuration from the environment.
subscriptionsListR :: (MonadNakadiEnv r m, MonadMask m)
                   => Maybe ApplicationName
                   -> Maybe [EventTypeName]
                   -> m [Subscription]
subscriptionsListR maybeOwningApp maybeEventTypeNames = do
  config <- asks (view L.nakadiConfig)
  subscriptionsList config maybeOwningApp maybeEventTypeNames
