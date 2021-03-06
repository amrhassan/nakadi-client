{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE RecordWildCards       #-}

module Network.Nakadi.Internal.Http.Test
  ( testHttp
  ) where

import           Network.HTTP.Client
import           Network.HTTP.Types
import           Test.Tasty
import           Test.Tasty.HUnit
import           Control.Monad
import           Control.Monad.Reader
import           ClassyPrelude
import           Network.Nakadi.Internal.Http
import           Network.HTTP.Client.Internal (CookieJar (..), Request(..), Response (..), ResponseClose (..))
import           Network.Nakadi
import           Conduit

testHttp :: TestTree
testHttp = testGroup "Http"
  [ testCase "HttpRequestModifier" testHttpRequestModifier
  ]

resp :: Response (IO ByteString)
resp = Response
    { responseStatus = status200
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = pure ""
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    }

headers :: RequestHeaders
headers = [("test-header", "header-value")]

dummyResponseOpen :: Request -> Manager -> IO (Response (IO ByteString))
dummyResponseOpen Request { .. } _ = do
  requestHeaders @=? headers
  pure resp

dummyHttpBackend :: HttpBackend
dummyHttpBackend = defaultHttpBackend {
    _responseOpen = dummyResponseOpen
}

dummyRequestModifier :: Request -> IO Request
dummyRequestModifier request = pure (request { requestHeaders = headers })

testHttpRequestModifier :: Assertion
testHttpRequestModifier = do
    conf <- newConfig Nothing defaultRequest
    let config = conf {_http = dummyHttpBackend, _requestModifier = dummyRequestModifier }
    (_, source) <- runResourceT $ httpJsonBodyStream config ok200 (const (Right ())) [] id
    (_ :: Maybe Text) <- runResourceT $ runReaderT (runConduit $ source .| headC) ()
    return ()