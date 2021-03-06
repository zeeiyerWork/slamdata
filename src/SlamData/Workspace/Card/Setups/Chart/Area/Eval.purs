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

module SlamData.Workspace.Card.Setups.Chart.Area.Eval
  ( eval
  , module SlamData.Workspace.Card.Setups.Chart.Area.Model
  ) where

import SlamData.Prelude

import Control.Monad.State (class MonadState)
import Control.Monad.Throw (class MonadThrow)

import Data.Argonaut (JArray, Json)
import Data.Array ((!!))
import Data.Array as A
import Data.Lens (preview, _Just, (^?))
import Data.Map as M
import Data.Set as Set

import ECharts.Monad (DSL)
import ECharts.Commands as E
import ECharts.Types as ET
import ECharts.Types.Phantom (OptionI)
import ECharts.Types.Phantom as ETP

import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Workspace.Card.Setups.Common.Eval (type (>>))
import SlamData.Workspace.Card.Setups.Common.Eval as BCE
import SlamData.Workspace.Card.Setups.Chart.Area.Model (Model, ModelR)
import SlamData.Workspace.Card.CardType.ChartType (ChartType(Area))
import SlamData.Workspace.Card.Setups.Transform.Aggregation as Ag
import SlamData.Workspace.Card.Setups.Transform as T
import SlamData.Workspace.Card.Setups.Axis as Ax
import SlamData.Workspace.Card.Setups.Semantics (getMaybeString, getValues)
import SlamData.Workspace.Card.Setups.Chart.ColorScheme (colors, getShadeColor)
import SlamData.Workspace.Card.Setups.Chart.Common.Positioning as BCP
import SlamData.Workspace.Card.Setups.Chart.Common.Tooltip as CCT
import SlamData.Workspace.Card.Setups.Dimension as D
import SlamData.Workspace.Card.Eval.Monad as CEM
import SlamData.Workspace.Card.Port as Port

import Utils.Array (enumerate)

eval
  ∷ ∀ m
  . ( MonadState CEM.CardState m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ Model
  → Port.Resource
  → m Port.Port
eval m = BCE.buildChartEval Area buildArea m \axes → m

type AreaSeries =
  { name ∷ Maybe String
  , items ∷ String >> Number
  }

buildAreaData ∷ ModelR → JArray → Array AreaSeries
buildAreaData r records = series
  where
  -- | maybe series >> dimension >> values
  dataMap ∷ Maybe String >> String >> Array Number
  dataMap =
    foldl dataMapFoldFn M.empty records

  dataMapFoldFn
    ∷ Maybe String >> String >> Array Number
    → Json
    → Maybe String >> String >> Array Number
  dataMapFoldFn acc js =
    let
      getValuesFromJson = getValues js
      getMaybeStringFromJson = getMaybeString js
    in case getMaybeStringFromJson =<< (r.dimension ^? D._value ∘ D._projection) of
      Nothing → acc
      Just dimKey →
        let
          mbSeries =
            getMaybeStringFromJson =<< (preview $ D._value ∘ D._projection) =<< r.series
          values =
            getValuesFromJson (r.value ^? D._value ∘ D._projection)

          alterSeriesFn
            ∷ Maybe (String >> Array Number)
            → Maybe (String >> Array Number)
          alterSeriesFn Nothing =
            Just $ M.singleton dimKey values
          alterSeriesFn (Just dims) =
            Just $ M.alter alterDimFn dimKey dims

          alterDimFn
            ∷ Maybe (Array Number)
            → Maybe (Array Number)
          alterDimFn Nothing = Just values
          alterDimFn (Just arr) = Just $ arr ⊕ values
        in
          M.alter alterSeriesFn mbSeries acc

  series ∷ Array AreaSeries
  series =
    foldMap mkAreaSerie $ M.toList dataMap

  mkAreaSerie
    ∷ Maybe String × (String >> Array Number)
    → Array AreaSeries
  mkAreaSerie (name × items) =
    [{ name
     , items:
         map (Ag.runAggregation
              (fromMaybe Ag.Sum $ r.value ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation) )
           items
     }]

buildArea ∷ Ax.Axes → ModelR → JArray → DSL OptionI
buildArea axes r records = do
  let
    cols =
      [ { label: D.jcursorLabel r.dimension, value: CCT.formatValueIx 0 }
      , { label: D.jcursorLabel r.value, value: CCT.formatValueIx 1 }
      ]
    opts = flip foldMap r.series \dim →
      [ { label: D.jcursorLabel dim, value: _.seriesName } ]

  E.tooltip do
    E.formatterAxis (CCT.tableFormatter (pure ∘ _.color) (cols <> opts))
    E.triggerAxis
    E.textStyle do
      E.fontFamily "Ubuntu, sans"
      E.fontSize 12
    E.axisPointer do
      E.lineAxisPointer
      E.lineStyle do
        E.width 1
        E.solidLine

  E.yAxis do
    E.axisType ET.Value
    E.axisLabel $ E.textStyle do
      E.fontFamily "Ubuntu, sans"
    E.axisLine $ E.lineStyle do
      E.width 1
    E.splitLine $ E.lineStyle do
      E.width 1

  E.xAxis do
    E.axisType xAxisConfig.axisType
    traverse_ E.interval $ xAxisConfig.interval
    case xAxisConfig.axisType of
      ET.Category →
        E.items $ map ET.strItem xValues
      _ → pure unit
    E.disabledBoundaryGap
    E.axisTick do
      E.length 2
      E.lineStyle do
        E.width 1
    E.splitLine $ E.lineStyle do
      E.width 1
    E.axisLine $ E.lineStyle do
      E.width 1
    E.axisLabel do
      E.rotate r.axisLabelAngle
      E.textStyle do
        E.fontFamily "Ubuntu, sans"

  E.colors colors

  E.grid BCP.cartesian

  E.legend do
    E.textStyle $ E.fontFamily "Ubuntu, sans"
    E.items $ map ET.strItem seriesNames

  E.series series

  where
  areaData ∷ Array (Int × AreaSeries)
  areaData = enumerate $ buildAreaData r records

  xAxisType ∷ Ax.AxisType
  xAxisType =
    fromMaybe Ax.Category
    $ Ax.axisType <$> (r.dimension ^? D._value ∘ D._projection) <*> pure axes

  xAxisConfig ∷ Ax.EChartsAxisConfiguration
  xAxisConfig = Ax.axisConfiguration xAxisType

  xSortFn ∷ String → String → Ordering
  xSortFn = Ax.compareWithAxisType xAxisType

  xValues ∷ Array String
  xValues =
    A.sortBy xSortFn
      $ A.fromFoldable
      $ foldMap (snd ⋙_.items ⋙ M.keys ⋙ Set.fromFoldable)
        areaData

  seriesNames ∷ Array String
  seriesNames =
    A.fromFoldable
      $ foldMap (snd ⋙ _.name ⋙ Set.fromFoldable)
        areaData

  series ∷ ∀ i. DSL (line ∷ ETP.I|i)
  series = for_ areaData \(ix × serie) → E.line do
    E.buildItems $ for_ xValues \key → do
      case M.lookup key serie.items of
        Nothing → E.missingItem
        Just v → E.addItem do
          E.name key
          E.buildValues do
            E.addStringValue key
            E.addValue v
    for_ serie.name E.name
    for_ (colors !! ix) \color → do
      E.itemStyle $ E.normal $ E.color color
      E.areaStyle $ E.normal $ E.color $ getShadeColor color (if r.isStacked then 1.0 else 0.5)
    E.lineStyle $ E.normal $ E.width 2
    E.symbol ET.Circle
    E.symbolSize 0
    E.smooth r.isSmooth
    when r.isStacked $ E.stack "stack"
