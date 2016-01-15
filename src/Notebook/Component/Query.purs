{-
Copyright 2015 SlamData, Inc.

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

module Notebook.Component.Query (NotebookQuery(..)) where

import Data.BrowserFeatures (BrowserFeatures())
import Data.Maybe (Maybe())
import Data.These (These())
import Data.Path.Pathy (DirName())

import Model.AccessType (AccessType())

import Notebook.Cell.CellId (CellId())
import Notebook.Cell.CellType (CellType())

import Utils.Path (FilePath(), DirPath())

-- | GetNameToSave returns name if it hasn't been saved.
-- | If there is no need to saving notebook name returns `Nothing`
data NotebookQuery a
  = AddCell CellType a
  | RunActiveCell a
  | RunPendingCells a
  | ToggleAddCellMenu a
  | GetNameToSave (Maybe DirName -> a)
  | GetPath (Maybe DirPath -> a)
  | SetViewingCell (Maybe CellId) a
  | SetName String a
  | SetAccessType AccessType a
  | ExploreFile BrowserFeatures FilePath a
  | Publish a
  | LoadNotebook BrowserFeatures DirPath a
  | SaveNotebook a
  | Reset BrowserFeatures DirPath a