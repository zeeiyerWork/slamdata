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

module SlamData.Workspace.Card.Setups.Chart.Line.Eval
  ( eval
  , module SlamData.Workspace.Card.Setups.Chart.Line.Model
  ) where

import SlamData.Prelude

import Control.Monad.State (class MonadState)
import Control.Monad.Throw (class MonadThrow)

import Data.Argonaut (JArray, Json)
import Data.Array as A
import Data.Foldable as F
import Data.Int as Int
import Data.Lens ((^?), _Just)
import Data.Map as M
import Data.Set as Set

import ECharts.Monad (DSL)
import ECharts.Commands as E
import ECharts.Types as ET
import ECharts.Types.Phantom (OptionI)
import ECharts.Types.Phantom as ETP

import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Workspace.Card.CardType.ChartType (ChartType(Line))
import SlamData.Workspace.Card.Eval.Monad as CEM
import SlamData.Workspace.Card.Port as Port
import SlamData.Workspace.Card.Setups.Axis (Axes)
import SlamData.Workspace.Card.Setups.Axis as Ax
import SlamData.Workspace.Card.Setups.Chart.ColorScheme (colors)
import SlamData.Workspace.Card.Setups.Chart.Common.Positioning as BCP
import SlamData.Workspace.Card.Setups.Chart.Line.Model (Model, ModelR)
import SlamData.Workspace.Card.Setups.Common.Eval (type (>>))
import SlamData.Workspace.Card.Setups.Common.Eval as BCE
import SlamData.Workspace.Card.Setups.Dimension as D
import SlamData.Workspace.Card.Setups.Semantics (getMaybeString, getValues)
import SlamData.Workspace.Card.Setups.Transform as T
import SlamData.Workspace.Card.Setups.Transform.Aggregation as Ag

eval
  ∷ ∀ m
  . ( MonadState CEM.CardState m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ Model
  → Port.Resource
  → m Port.Port
eval m = BCE.buildChartEval Line buildLine m \axes → m

type LineSerie =
  { name ∷ Maybe String
  , leftItems ∷ String >> {value ∷ Number, symbolSize ∷ Int}
  , rightItems ∷ String >> {value ∷ Number, symbolSize ∷ Int}
  }

buildLineData ∷ ModelR → JArray → Array LineSerie
buildLineData r records = series
  where
  -- | maybe series >> dimension >> left values × right values × symbol sizes
  dataMap ∷ Maybe String >> String >> (Array Number × Array Number × Array Number)
  dataMap =
    foldl dataMapFoldFn M.empty records

  dataMapFoldFn
    ∷ Maybe String >> String >> (Array Number × Array Number × Array Number)
    → Json
    → Maybe String >> String >> (Array Number × Array Number × Array Number)
  dataMapFoldFn acc js =
    let
      getMaybeStringFromJson = getMaybeString js
      getValuesFromJson = getValues js
    in case getMaybeStringFromJson =<< r.dimension ^? D._value ∘ D._projection of
      Nothing → acc
      Just dimKey →
        let
          mbSeries =
            getMaybeStringFromJson =<< r.series ^? _Just ∘ D._value ∘ D._projection
          leftValues =
            getValuesFromJson $ r.value ^? D._value ∘ D._projection
          rightValues =
            getValuesFromJson $ r.secondValue ^? _Just ∘ D._value ∘ D._projection
          sizes
            | r.optionalMarkers = [ ]
            | otherwise = getValuesFromJson $ r.size ^? _Just ∘ D._value ∘ D._projection

          alterSeriesFn
            ∷ Maybe (String >> (Array Number × Array Number × Array Number))
            → Maybe (String >> (Array Number × Array Number × Array Number))
          alterSeriesFn Nothing =
            Just $ M.singleton dimKey $ leftValues × rightValues × sizes
          alterSeriesFn (Just dims) =
            Just $ M.alter alterDimFn dimKey dims

          alterDimFn
            ∷ Maybe (Array Number × Array Number × Array Number)
            → Maybe (Array Number × Array Number × Array Number)
          alterDimFn Nothing =
            Just $ leftValues × rightValues × sizes
          alterDimFn (Just (ls × rs × ss)) =
            Just $ (ls ⊕ leftValues) × (rs ⊕ rightValues) × (ss ⊕ sizes)
        in
          M.alter alterSeriesFn mbSeries acc

  series ∷ Array LineSerie
  series =
    foldMap mkLineSerie $ M.toList dataMap

  mkLineSerie
    ∷ Maybe String × (String >> (Array Number × Array Number × Array Number))
    → Array LineSerie
  mkLineSerie (name × items) =
    [{ name
     , leftItems: adjustSymbolSizes $ map mkLeftItem items
     , rightItems: adjustSymbolSizes $ map mkRightItem items
     } ]

  mkLeftItem
    ∷ Array Number × Array Number × Array Number
    → {value ∷ Number, symbolSize ∷ Int}
  mkLeftItem (ls × _ × ss) =
    let
      value =
        flip Ag.runAggregation ls
        $ fromMaybe Ag.Sum
        $ r.value ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
      symbolSize
        | r.optionalMarkers = Int.floor r.minSize
        | otherwise =
          Int.floor
          $ flip Ag.runAggregation ss
          $ fromMaybe Ag.Sum
          $ r.size ^? _Just ∘ D._value ∘ D._transform ∘ _Just ∘ T._Aggregation

    in {value, symbolSize}

  mkRightItem
    ∷ Array Number × Array Number × Array Number
    → {value ∷ Number, symbolSize ∷ Int}
  mkRightItem (_ × rs × ss) =
    case r.secondValue ^? _Just ∘ D._value ∘ D._transform ∘ _Just ∘ T._Aggregation  of
      Nothing → {symbolSize: zero, value: zero}
      Just valAgg →
        let
          value = Ag.runAggregation valAgg rs
          symbolSize
            | r.optionalMarkers = Int.floor r.minSize
            | otherwise =
              Int.floor
              $ flip Ag.runAggregation ss
              $ fromMaybe Ag.Sum
              $ r.size ^? _Just ∘ D._value ∘ D._transform ∘ _Just ∘ T._Aggregation
        in {value, symbolSize}


  adjustSymbolSizes
    ∷ ∀ f
    . (Functor f, Foldable f)
    ⇒ f {value ∷ Number, symbolSize ∷ Int}
    → f {value ∷ Number, symbolSize ∷ Int}
  adjustSymbolSizes items
    | r.optionalMarkers = items
    | otherwise =
      let
        minValue ∷ Number
        minValue =
          Int.toNumber
            $ fromMaybe bottom
            $ map _.symbolSize
            $ F.minimumBy (\a b → compare a.symbolSize b.symbolSize) items

        maxValue ∷ Number
        maxValue =
          Int.toNumber
            $ fromMaybe top
            $ map _.symbolSize
            $ F.maximumBy (\a b → compare a.symbolSize b.symbolSize) items

        distance ∷ Number
        distance =
          maxValue - minValue

        sizeDistance ∷ Number
        sizeDistance =
          r.maxSize - r.minSize

        relativeSize ∷ Int → Int
        relativeSize val
          | distance ≡ 0.0 = val
          | otherwise =
            Int.floor
            $ r.maxSize
            - sizeDistance / distance * (maxValue - Int.toNumber val)
      in
        map (\x → x{symbolSize = relativeSize x.symbolSize}) items


buildLine ∷ Axes → ModelR → JArray → DSL OptionI
buildLine axes r records = do
  E.tooltip do
    if isJust r.size then E.triggerItem else E.triggerAxis
    E.textStyle $ E.fontSize 12

  E.colors colors
  E.grid BCP.cartesian
  E.series series

  E.xAxis do
    E.axisType xAxisConfig.axisType
    case xAxisConfig.axisType of
      ET.Category →
        E.items $ map ET.strItem xValues
      _ → pure unit
    E.axisLabel do
      E.rotate r.axisLabelAngle
      traverse_ E.interval xAxisConfig.interval
      E.textStyle do
        E.fontFamily "Ubuntu, sans"

  E.yAxes do
    E.addYAxis yAxis
    when needTwoAxes $ E.addYAxis yAxis

  E.legend do
    E.items $ map ET.strItem seriesNames
    E.textStyle $ E.fontFamily "Ubuntu, sans"

  where
  lineData ∷ Array LineSerie
  lineData = buildLineData r records

  xAxisType ∷ Ax.AxisType
  xAxisType =
    fromMaybe Ax.Category
    $ Ax.axisType
    <$> (r.dimension ^? D._value ∘ D._projection)
    <*> (pure axes)

  xAxisConfig ∷ Ax.EChartsAxisConfiguration
  xAxisConfig = Ax.axisConfiguration xAxisType

  xSortFn ∷ String → String → Ordering
  xSortFn = Ax.compareWithAxisType xAxisType

  xValues ∷ Array String
  xValues =
    A.sortBy xSortFn
      $ A.fromFoldable
      $ foldMap (\x → Set.fromFoldable $ M.keys x.leftItems ⊕ M.keys x.rightItems)
        lineData

  seriesNames ∷ Array String
  seriesNames = case r.series of
    Just _ → A.fromFoldable $ foldMap (_.name ⋙ foldMap Set.singleton) lineData
    Nothing →
      A.catMaybes
        [ Just $ D.jcursorLabel r.value
        , D.jcursorLabel <$> r.secondValue
        ]

  needTwoAxes ∷ Boolean
  needTwoAxes = isJust r.secondValue

  series ∷ ∀ i. DSL (line ∷ ETP.I|i)
  series = for_ lineData \lineSerie → do
    E.line do
      E.buildItems $ for_ xValues \key →
        case M.lookup key lineSerie.leftItems of
          Nothing → E.missingItem
          Just {value, symbolSize} → E.addItem do
            E.name key
            E.buildValues do
              E.addStringValue key
              E.addValue value
            E.symbolSize symbolSize
      E.yAxisIndex 0
      case r.series of
        Just _ →
          for_ lineSerie.name E.name
        Nothing →
          E.name $ D.jcursorLabel r.value

    when needTwoAxes $ E.line do
      E.buildItems $ for_ xValues \key →
        case M.lookup key lineSerie.rightItems of
          Nothing → E.missingItem
          Just {value, symbolSize} → E.addItem do
            E.name key
            E.buildValues do
              E.addStringValue key
              E.addValue value
            E.symbolSize symbolSize
      E.yAxisIndex 1
      case r.series of
        Just _ →
          for_ lineSerie.name E.name
        Nothing →
          for_ r.secondValue (E.name ∘ D.jcursorLabel)

  yAxis ∷ DSL ETP.YAxisI
  yAxis = do
    E.axisType ET.Value
    E.axisLabel $ E.textStyle do
      E.fontFamily "Ubuntu, sans"
