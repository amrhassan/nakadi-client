{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}

module Network.Nakadi.EventTypes.Test where

import           ClassyPrelude

import           Conduit
import           Control.Concurrent.Async                      (link)
import           Control.Lens
import           Data.Function                                 ((&))
import           Network.Nakadi
import           Network.Nakadi.EventTypes.CursorsLag.Test
import           Network.Nakadi.EventTypes.ShiftedCursors.Test
import qualified Network.Nakadi.Lenses                         as L
import           Network.Nakadi.Tests.Common
import           System.IO.Unsafe
import           Test.Tasty
import           Test.Tasty.HUnit

testEventTypes :: Config -> TestTree
testEventTypes conf = testGroup "EventTypes"
  [ testCase "EventTypesPrepare" (testEventTypesPrepare conf)
  , testCase "EventTypesGet" (testEventTypesGet conf)
  , testCase "EventTypesDeleteCreateAndGet" (testEventTypesDeleteCreateGet conf)
  , testCase "EventTypePartitionsGet" (testEventTypePartitionsGet conf)
  , testCase "EventTypeCursorDistances0" (testEventTypeCursorDistances0 conf)
  , testCase "EventTypeCursorDistances10" (testEventTypeCursorDistances10 conf)
  , testCase "EventTypePublishData" (testEventTypePublishData conf)
  , testCase "EventTypeParseFlowId" (testEventTypeParseFlowId conf)
  , testCase "EventTypeDeserializationFailure" (testEventTypeDeserializationFailure conf)
  , testEventTypesShiftedCursors conf
  , testEventTypesCursorsLag conf
  ]

testEventTypesPrepare :: Config -> Assertion
testEventTypesPrepare conf = do
  subscriptions <- subscriptionsList conf Nothing Nothing
  let subscriptionIds = catMaybes . map (view L.id) $ subscriptions
  forM_ subscriptionIds (subscriptionDelete conf)

testEventTypesGet :: Config -> Assertion
testEventTypesGet conf =
  void $ eventTypesList conf

testEventTypesDeleteCreateGet :: Config -> Assertion
testEventTypesDeleteCreateGet conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  myEventTypes <- filterMyEvent <$> eventTypesList conf
  length myEventTypes @=? 1
  eventTypeDelete conf myEventTypeName
  myEventTypes' <- filterMyEvent <$> eventTypesList conf
  length myEventTypes' @=? 0

  where filterMyEvent = filter ((myEventTypeName ==) . (view L.name))

testEventTypePartitionsGet :: Config -> Assertion
testEventTypePartitionsGet conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  void $ eventTypePartitions conf myEventTypeName

testEventTypeCursorDistances0 :: Config -> Assertion
testEventTypeCursorDistances0 conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  partitions <- eventTypePartitions conf myEventTypeName
  let cursors = map extractCursor partitions
  forM_ cursors $ \cursor -> do
    distance <- cursorDistance conf myEventTypeName cursor cursor
    distance @=? 0

testEventTypeCursorDistances10 :: Config -> Assertion
testEventTypeCursorDistances10 conf = do
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  partitions <- eventTypePartitions conf myEventTypeName
  let cursors = map extractCursor partitions

  forM_ [1..10] $ \_ -> do
    now <- getCurrentTime
    eid <- EventId <$> genRandomUUID
    eventPublish conf myEventTypeName Nothing [myDataChangeEvent eid now]

  cursorPairs <- forM cursors $ \cursor@Cursor { .. } -> do
    part <- eventTypePartition conf myEventTypeName _partition
    let cursor' = extractCursor part
    return (cursor, cursor')

  distances <- forM cursorPairs $ \(c, c') -> do
    cursorDistance conf myEventTypeName c c'

  let totalDistances = sum distances
  totalDistances @=? 10

consumeParametersSingle :: ConsumeParameters
consumeParametersSingle = defaultConsumeParameters
                          & setBatchLimit 1
                          & setBatchFlushTimeout 1

testEventTypePublishData :: Config -> Assertion
testEventTypePublishData conf = do
  now <- getCurrentTime
  eid <- EventId <$> genRandomUUID
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  let event = DataChangeEvent { _payload = Foo "Hello!"
                              , _metadata = EventMetadata { _eid = eid
                                                          , _occurredAt = Timestamp now
                                                          , _parentEids = Nothing
                                                          , _partition  = Nothing
                                                          }
                              , _dataType = "test.FOO"
                              , _dataOp = DataOpUpdate
                              }
  withAsync (delayedPublish conf Nothing [event]) $ \asyncHandle -> do
    link asyncHandle
    eventConsumed :: Maybe (EventStreamBatch Foo) <- runResourceT $ do
      source <- eventSource conf (Just consumeParametersSingle) myEventTypeName Nothing
      runConduit $ source .| headC
    isJust eventConsumed @=? True

testEventTypeParseFlowId :: Config -> Assertion
testEventTypeParseFlowId conf = do
  now <- getCurrentTime
  eid <- EventId <$> genRandomUUID
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  let event = DataChangeEvent { _payload = Foo "Hello!"
                              , _metadata = EventMetadata { _eid = eid
                                                          , _occurredAt = Timestamp now
                                                          , _parentEids = Nothing
                                                          , _partition  = Nothing
                                                          }
                              , _dataType = "test.FOO"
                              , _dataOp = DataOpUpdate
                              }
      expectedFlowId = Just $ FlowId "12345"
  withAsync (delayedPublish conf expectedFlowId [event]) $ \asyncHandle -> do
    link asyncHandle
    eventConsumed :: Maybe (EventStreamBatch (DataChangeEventEnriched Foo)) <- runResourceT $ do
      source <- eventSource conf (Just consumeParametersSingle) myEventTypeName Nothing
      runConduit $ source .| headC
    isJust eventConsumed @=? True
    let events = eventConsumed >>= (\batch -> batch^.L.events)
    isJust events @=? True

    case events of
      Nothing -> assertFailure "Received no events"
      Just v -> case toList v of
        [DataChangeEventEnriched _ x _ _] ->
          x^.L.flowId @=? expectedFlowId
        _ -> assertFailure "Received not a singleton event list"

testEventTypeDeserializationFailure :: Config -> Assertion
testEventTypeDeserializationFailure conf' = do
  now <- getCurrentTime
  eid <- EventId <$> genRandomUUID
  eventTypeDelete conf myEventTypeName `catch` (ignoreExnNotFound ())
  eventTypeCreate conf myEventType
  let event = DataChangeEvent { _payload = Foo "Hello!"
                              , _metadata = EventMetadata { _eid = eid
                                                          , _occurredAt = Timestamp now
                                                          , _parentEids = Nothing
                                                          , _partition  = Nothing
                                                          }
                              , _dataType = "test.FOO"
                              , _dataOp = DataOpUpdate
                              }
  withAsync (delayedPublish conf Nothing [event]) $ \asyncHandle -> do
    link asyncHandle
    eventConsumed :: Maybe (EventStreamBatch WrongFoo) <- runResourceT $ do
      source <- eventSource conf (Just consumeParametersSingle) myEventTypeName Nothing
      runConduit $ source .| headC
    isJust eventConsumed @=? True

  counter <- atomically $ readTVar deserializationFailureCounter
  1 @=? counter

  where conf = conf'
               & setDeserializationFailureCallback (deserializationFailureCb deserializationFailureCounter)

        deserializationFailureCb counter _ _ =
          atomically $ modifyTVar counter (+ 1)

        deserializationFailureCounter = unsafePerformIO $ newTVarIO 0
