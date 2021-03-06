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

module SlamData.Workspace.Card.Setups.Chart.Candlestick.Eval
  ( eval
  , module SlamData.Workspace.Card.Setups.Chart.Candlestick.Model
  ) where

import SlamData.Prelude

import Control.Monad.State (class MonadState)
import Control.Monad.Throw (class MonadThrow)

import Data.Argonaut (JArray, Json)
import Data.Array as A
import Data.Lens ((^?), preview, _Just)
import Data.Map as Map

import ECharts.Monad (DSL)
import ECharts.Commands as E
import ECharts.Types as ET
import ECharts.Types.Phantom (OptionI)

import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Workspace.Card.CardType.ChartType (ChartType(Candlestick))
import SlamData.Workspace.Card.Eval.Monad as CEM
import SlamData.Workspace.Card.Port as Port
import SlamData.Workspace.Card.Setups.Axis as Ax
import SlamData.Workspace.Card.Setups.Chart.Candlestick.Model (ModelR, Model)
import SlamData.Workspace.Card.Setups.Chart.ColorScheme (colors)
import SlamData.Workspace.Card.Setups.Chart.Common.Positioning as BCP
import SlamData.Workspace.Card.Setups.Chart.Common.Tooltip as CCT
import SlamData.Workspace.Card.Setups.Common.Eval (type (>>))
import SlamData.Workspace.Card.Setups.Common.Eval as BCE
import SlamData.Workspace.Card.Setups.Dimension as D
import SlamData.Workspace.Card.Setups.Semantics as Sem
import SlamData.Workspace.Card.Setups.Transform as T
import SlamData.Workspace.Card.Setups.Transform.Aggregation as Ag
import Utils.Foldable (enumeratedFor_)

eval
  ∷ ∀ m
  . ( MonadState CEM.CardState m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ Model
  → Port.Resource
  → m Port.Port
-- TODO: why this sync here? for autoselect or?
eval m = BCE.buildChartEval Candlestick buildCandlestick m \axes → m
--  ST.save $ ST.synchronize $ ST.load m initialState{axes = axes}

type HLOC a =
  { low ∷ a
  , high ∷ a
  , open ∷ a
  , close ∷ a
  }

type Series = String >> HLOC Number

type OnOneGrid =
  { w ∷ Maybe Number
  , h ∷ Maybe Number
  , x ∷ Maybe Number
  , y ∷ Maybe Number
  , name ∷ Maybe String
  , fontSize ∷ Maybe Int
  , items ∷ Series
  }

type CandlestickData = Array OnOneGrid

buildCandlestickData ∷ ModelR → JArray → CandlestickData
buildCandlestickData r records = series
  where
  dataMap ∷ Maybe String >> String >> HLOC (Array Number)
  dataMap =
    foldl dataMapFoldFn Map.empty records

  dataMapFoldFn
    ∷ Maybe String >> String >> HLOC (Array Number)
    → Json
    → Maybe String >> String >> HLOC (Array Number)
  dataMapFoldFn acc js =
    let
      getMaybeString = Sem.getMaybeString js
      getValues = Sem.getValues js
    in case getMaybeString =<< (r.dimension ^? D._value ∘ D._projection)  of
      Nothing → acc
      Just dimKey →
        let
          high =
            getValues $ r.high ^? D._value ∘ D._projection
          low =
            getValues $ r.low ^? D._value ∘ D._projection
          open =
            getValues $ r.open ^? D._value ∘ D._projection
          close =
            getValues $ r.close ^? D._value ∘ D._projection

          hloc = {high, low, open, close}

          mbParallel =
            getMaybeString =<< (preview $ D._value ∘ D._projection) =<< r.parallel

          alterParallelFn
            ∷ Maybe (String >> HLOC (Array Number))
            → Maybe (String >> HLOC (Array Number))
          alterParallelFn Nothing =
            Just $ Map.singleton dimKey hloc
          alterParallelFn (Just parallel) =
            Just $ Map.alter alterDimFn dimKey parallel

          alterDimFn
            ∷ Maybe (HLOC (Array Number))
            → Maybe (HLOC (Array Number))
          alterDimFn Nothing = Just $ hloc
          alterDimFn (Just r') =
            Just { high: high ⊕ r'.high
                 , low: low ⊕ r'.low
                 , open: open ⊕ r'.open
                 , close: close ⊕ r'.close
                 }
        in
          Map.alter alterParallelFn mbParallel acc

  rawSeries ∷ CandlestickData
  rawSeries =
    foldMap mkOneGridData $ Map.toList dataMap

  mkOneGridData
    ∷ Maybe String × (String >> HLOC (Array Number))
    → Array OnOneGrid
  mkOneGridData (name × mp) =
    [ { x: Nothing
      , y: Nothing
      , w: Nothing
      , h: Nothing
      , fontSize: Nothing
      , name
      , items: map aggregateHLOC mp
      } ]

  aggregateHLOC ∷ HLOC (Array Number) → HLOC Number
  aggregateHLOC rr =
    { high:
        flip Ag.runAggregation rr.high
        $ fromMaybe Ag.Sum $ r.high ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
    , low:
        flip Ag.runAggregation rr.low
        $ fromMaybe Ag.Sum $ r.low ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
    , open:
        flip Ag.runAggregation rr.open
        $ fromMaybe Ag.Sum $ r.open ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
    , close:
        flip Ag.runAggregation rr.close
        $ fromMaybe Ag.Sum $ r.close ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
    }

  series ∷ CandlestickData
  series = BCP.adjustRectangularPositions rawSeries

buildCandlestick ∷ Ax.Axes → ModelR → JArray → DSL OptionI
buildCandlestick axes r records = do
  E.tooltip do
    E.triggerAxis
    E.textStyle do
      E.fontFamily "Ubuntu, sans"
      E.fontSize 12
    E.formatterAxis $ foldMap \fmt →
      CCT.tableRows
        [ D.jcursorLabel r.dimension × fmt.name
        , D.jcursorLabel r.open × CCT.formatValueIx 0 fmt
        , D.jcursorLabel r.close × CCT.formatValueIx 1 fmt
        , D.jcursorLabel r.low × CCT.formatValueIx 2 fmt
        , D.jcursorLabel r.high × CCT.formatValueIx 3 fmt
        ]

  BCP.rectangularTitles candlestickData
  BCP.rectangularGrids candlestickData

  E.colors colors

  E.xAxes xAxes
  E.yAxes yAxes
  E.series series

  where
  candlestickData ∷ CandlestickData
  candlestickData = buildCandlestickData r records

  xValues ∷ OnOneGrid → Array String
  xValues  = sortX ∘ foldMap A.singleton ∘ Map.keys ∘ _.items

  xAxisType ∷ Ax.AxisType
  xAxisType =
    fromMaybe Ax.Category
    $ Ax.axisType <$> (r.dimension ^? D._value ∘ D._projection) <*> pure axes


  sortX ∷ Array String → Array String
  sortX = A.sortBy $ Ax.compareWithAxisType xAxisType

  xAxes = enumeratedFor_ candlestickData \(ix × serie) → E.addXAxis do
    E.gridIndex ix
    E.axisType ET.Category
    E.axisLabel $ E.textStyle $ E.fontFamily "Ubuntu, sans"
    E.items $ map ET.strItem $ xValues serie

  yAxes = enumeratedFor_ candlestickData \(ix × _) → E.addYAxis do
    E.gridIndex ix
    E.axisType ET.Value

  series = enumeratedFor_  candlestickData \(ix × serie) → E.candlestick do
    for_ serie.name E.name
    E.xAxisIndex ix
    E.yAxisIndex ix
    E.buildItems $ for_ (xValues serie) \dim →
      for_ (Map.lookup dim serie.items) \{high, low, open, close} → E.addItem $ E.buildValues do
        E.addValue open
        E.addValue close
        E.addValue low
        E.addValue high
