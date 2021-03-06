{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Workspace.Deck.Common where

import Data.List as L

import Halogen as H

import SlamData.Prelude
import SlamData.Monad (Slam)
import SlamData.Workspace.AccessType (AccessType)
import SlamData.Workspace.AccessType as AT
import SlamData.Workspace.Deck.Component.ChildSlot (ChildSlot, ChildQuery)
import SlamData.Workspace.Deck.Component.Query (Query, Message)
import SlamData.Workspace.Deck.Component.State (State)
import SlamData.Workspace.Deck.DeckId (DeckId)

type DeckHTML = H.ParentHTML Query ChildQuery ChildSlot Slam

type DeckDSL = H.ParentDSL State Query ChildQuery ChildSlot Message Slam

type DeckOptions =
  { accessType ∷ AccessType
  , cursor ∷ L.List DeckId -- Absolute cursor within the graph
  , displayCursor ∷ L.List DeckId -- Relative cursor within the UI
  , deckId ∷ DeckId
  }

willBePresentedWithChildFrameWhenFocused ∷ DeckOptions → State → Boolean
willBePresentedWithChildFrameWhenFocused opts st =
  (opts.accessType ≠ AT.ReadOnly) ∧ (L.length opts.displayCursor ≡ 1)

sizerRef ∷ H.RefLabel
sizerRef = H.RefLabel "sizer"
