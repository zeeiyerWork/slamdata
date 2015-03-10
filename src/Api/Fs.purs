-- | Should be rewritten with purescript-aff
module Api.Fs where

import Control.Monad.Eff
import Data.Either 
import Data.Maybe
import Data.Foldable (foldl)

import DOM (DOM())
import qualified Data.DOM.Simple.Ajax as A
import Data.Argonaut.Core (Json())
import Data.Argonaut.Parser (jsonParser)
import Data.Argonaut.Decode (decodeJson, DecodeJson) 
import Data.Argonaut.Combinators ((.?))

import qualified Model as Model
import qualified Config as Config

-- Since we know exact form of metadata
-- we can decode it from json
newtype Metadata = Metadata {
  name :: String,
  mount :: Model.Mount
  }

newtype MetadataResponse = MetadataResponse {
  children :: [Metadata]
  }

instance decodeJsonMetadata :: DecodeJson Metadata where
  decodeJson json = do
    obj <- decodeJson json
    name <- obj .? "name"
    mount <- obj .? "type"
    return $ Metadata {
      name: name,
      mount: mount
      }

instance decodeJsonMetadataResponse :: DecodeJson MetadataResponse where
  decodeJson json = do
    obj <- decodeJson json
    children <- obj .? "children"
    return $ MetadataResponse {
      children: children
      }

metadata :: forall e. String -> ([Metadata] -> Eff (dom::DOM|e) Unit) -> 
            Eff (dom::DOM|e) Unit 
metadata path callback = do
  req <- A.makeXMLHttpRequest
  let action = do
        state <- A.readyState req
        case state of
          A.Done -> do
            response <- A.responseText req
            status <- A.status req
            if status /= 200 then
              callback []
              else 
              case jsonParser response >>= decodeJson of
                Left error -> do
                  pure unit
                Right (MetadataResponse{children: res}) ->
                  callback res
          _ -> return unit

  A.onReadyStateChange action req
  A.open A.GET (Config.metadataUrl <> path) req
  A.send A.NoData req
            


get :: forall e. String -> Maybe Number -> Maybe Number ->
       ([Json] -> Eff (dom::DOM) Unit) -> Eff (dom::DOM|e) Unit 
get path offset limit callback = do 
  req <- A.makeXMLHttpRequest
  let action = do
        state <- A.readyState req
        case state of
          A.Done -> do
            response <- A.responseText req
            case (jsonParser response >>= decodeJson) of
              Left error -> pure unit
              Right json -> callback json
          _ -> return unit

  A.onReadyStateChange action req
  let off = fromMaybe "" $ (\o -> "offset=" <> o) <$> (show <$> offset)
      lim = fromMaybe "" $ (\l -> "limit=" <> l) <$> (show <$> limit)
      args = foldl (\a b -> a <> "&" <> b) "" [off, lim]
      q = if args == "" then "" else "?" <> args
      url = Config.dataUrl <> path <> q 
  A.open A.GET (Config.dataUrl <> path) req
  A.send A.NoData req


post :: forall e. String -> Json -> ([Json] -> Eff (dom::DOM) Unit) ->
        Eff (dom::DOM|e) Unit
post path obj callback = do 
  req <- A.makeXMLHttpRequest
  let action = do
        state <- A.readyState req
        case state of
          A.Done -> do
            response <- A.responseText req
            case (jsonParser response >>= decodeJson) of
              Left error -> pure unit
              Right jsons -> callback jsons

  A.onReadyStateChange action req
  A.open A.POST (Config.dataUrl <> path) req
  A.send (A.JsonData obj) req 


put :: forall e. String -> Json -> (Boolean -> Eff (dom::DOM|e) Unit) -> 
       Eff (dom::DOM|e) Unit 
put path obj callback = do 
  req <- A.makeXMLHttpRequest
  let action = do
        state <- A.readyState req
        case state of
          A.Done -> do
            status <- A.status req
            callback $ status == 200
          _ -> return unit
  A.onReadyStateChange action req
  A.open A.PUT (Config.dataUrl <> path) req
  A.send (A.JsonData obj) req


move :: forall e. String -> String -> (Boolean -> Eff (dom::DOM|e) Unit) ->
        Eff (dom::DOM|e) Unit
move src tgt callback = do 
  req <- A.makeXMLHttpRequest
  let action = do
        state <- A.readyState req
        case state of 
          A.Done -> do
            status <- A.status req
            callback $ status == 200
          _ -> return unit
  A.onReadyStateChange action req
  A.open (A.HttpMethod "MOVE") (Config.dataUrl <> src) req
  A.setRequestHeader "Destination" tgt req
  A.send A.NoData req 
