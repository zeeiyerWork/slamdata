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

module SlamData.Workspace.Card.Setups.Chart.Scatter.Eval
  ( eval
  , module SlamData.Workspace.Card.Setups.Chart.Scatter.Model
  ) where

import SlamData.Prelude

import Color as C

import Control.Monad.State (class MonadState)
import Control.Monad.Throw (class MonadThrow)

import Data.Argonaut (JArray, Json)
import Data.Array as A
import Data.Foldable as F
import Data.Lens ((^?), _Just)
import Data.Map as M
import Data.Set as Set

import Global (infinity)

import ECharts.Monad (DSL)
import ECharts.Commands as E
import ECharts.Types as ET
import ECharts.Types.Phantom (OptionI)
import ECharts.Types.Phantom as ETP

import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Workspace.Card.CardType.ChartType (ChartType(Scatter))
import SlamData.Workspace.Card.Eval.Monad as CEM
import SlamData.Workspace.Card.Port as Port
import SlamData.Workspace.Card.Setups.Chart.ColorScheme (colors, getTransparentColor)
import SlamData.Workspace.Card.Setups.Chart.Common.Positioning as BCP
import SlamData.Workspace.Card.Setups.Chart.Common.Tooltip as CCT
import SlamData.Workspace.Card.Setups.Chart.Scatter.Model (Model, ModelR)
import SlamData.Workspace.Card.Setups.Common.Eval (type (>>))
import SlamData.Workspace.Card.Setups.Common.Eval as BCE
import SlamData.Workspace.Card.Setups.Semantics (getMaybeString, getValues)
import SlamData.Workspace.Card.Setups.Dimension as D
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
eval m = BCE.buildChartEval Scatter (const buildScatter) m \axes → m

type ScatterSeries =
  { name ∷ Maybe String
  , w ∷ Maybe Number
  , h ∷ Maybe Number
  , x ∷ Maybe Number
  , y ∷ Maybe Number
  , fontSize ∷ Maybe Int
  , series ∷ Array OnOneGrid
  }

type OnOneGrid =
  { name ∷ Maybe String
  , items ∷ Array {x ∷ Number, y ∷ Number, r ∷ Number}
  }

type ScatterData = Array ScatterSeries

buildScatterData ∷ ModelR → JArray → ScatterData
buildScatterData r records = series
  where
  -- | maybe parallel >> maybe series >> array xs × array ys × array rs
  dataMap ∷ Maybe String >> Maybe String >> (Array Number × Array Number × Array Number)
  dataMap =
    foldl dataMapFoldFn M.empty records

  dataMapFoldFn
    ∷ Maybe String >> Maybe String >> (Array Number × Array Number × Array Number)
    → Json
    → Maybe String >> Maybe String >> (Array Number × Array Number × Array Number)
  dataMapFoldFn acc js =
    let
      getValuesFromJson = getValues js
      getMaybeStringFromJson = getMaybeString js

      mbSeries =
        getMaybeStringFromJson =<< r.series ^? _Just ∘ D._value ∘ D._projection

      mbParallel =
        getMaybeStringFromJson =<< r.parallel ^? _Just ∘ D._value ∘ D._projection

      xs =
        getValuesFromJson $ r.abscissa ^? D._value ∘ D._projection
      ys =
        getValuesFromJson $ r.ordinate ^? D._value ∘ D._projection
      rs =
        getValuesFromJson $ r.size ^? _Just ∘ D._value ∘ D._projection

      alterParallelFn
        ∷ Maybe (Maybe String >> (Array Number × Array Number × Array Number))
        → Maybe (Maybe String >> (Array Number × Array Number × Array Number))
      alterParallelFn Nothing =
        Just $ M.singleton mbSeries $ xs × ys × rs
      alterParallelFn (Just parallel) =
        Just $ M.alter alterSeriesFn mbSeries parallel

      alterSeriesFn
        ∷ Maybe (Array Number × Array Number × Array Number)
        → Maybe (Array Number × Array Number × Array Number)
      alterSeriesFn Nothing =
        Just $ xs × ys × rs
      alterSeriesFn (Just (xxs × yys × rrs)) =
        Just $ (xxs ⊕ xs) × (yys ⊕ ys) × (rrs ⊕ rs)

    in
      M.alter alterParallelFn mbParallel acc

  rawSeries ∷ Array ScatterSeries
  rawSeries =
    foldMap mkScatterSeries $ M.toList dataMap

  series ∷ Array ScatterSeries
  series = BCP.adjustRectangularPositions rawSeries

  mkScatterSeries
    ∷ Maybe String × (Maybe String >> (Array Number × Array Number × Array Number))
    → Array ScatterSeries
  mkScatterSeries (name × mp) =
    [{ name
     , x: Nothing
     , y: Nothing
     , w: Nothing
     , h: Nothing
     , fontSize: Nothing
     , series: foldMap mkOneGrid $ M.toList mp
     }]

  mkOneGrid
    ∷ Maybe String × (Array Number × Array Number × Array Number)
    → Array OnOneGrid
  mkOneGrid (name × items) =
    [{ name
     , items: adjustSymbolSizes $ mkScatterItem items
     }]

  mkScatterItem
    ∷ (Array Number × Array Number × Array Number)
    → Array {x ∷ Number, y ∷ Number, r ∷ Number }
  mkScatterItem (xs × ys × rs)
    | A.null xs = []
    | A.null ys = []
    | otherwise =
      let
        len =
          max (A.length xs) $ max (A.length ys) (A.length rs)

        abscissas =
          case r.abscissa ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation of
            Nothing → xs
            Just ag →
              let
                v = Ag.runAggregation ag xs
              in
                map (const v) $ A.range 0 $ len - 1
        ordinates =
          case r.ordinate ^? D._value ∘ D._transform ∘ _Just ∘ T._Aggregation of
            Nothing → ys
            Just ag →
              let
                v = Ag.runAggregation ag ys
              in
                map (const v) $ A.range 0 $ len - 1

        sizes =
          case r.size ^? _Just ∘ D._value ∘ D._transform ∘ _Just ∘ T._Aggregation of
            Just ag →
              let
                v = Ag.runAggregation ag rs
              in
                map (const v) $ A.range 0 $ len - 1
            Nothing
              | A.null rs →
                map (\_ → r.minSize) rs
            Nothing →
              rs
        zipped = A.zip abscissas $ A.zip ordinates sizes
      in
        zipped <#> \(x × y × r) → {x, y, r}

  adjustSymbolSizes
    ∷ Array {x ∷ Number, y ∷ Number, r ∷ Number}
    → Array {x ∷ Number, y ∷ Number, r ∷ Number}
  adjustSymbolSizes items =
    let
      minValue =
        fromMaybe (-1.0 * infinity) $ map _.r $ F.maximumBy (\a b → compare a.r b.r) items
      maxValue =
        fromMaybe infinity $ map _.r $ F.maximumBy (\a b → compare a.r b.r) items
      distance =
        maxValue - minValue
      sizeDistance =
        r.maxSize - r.minSize

      relativeSize ∷ Number → Number
      relativeSize val
        | distance ≡ zero = val
        | otherwise =
            r.maxSize - sizeDistance / distance * (maxValue - val)
    in
      map (\x → x{r = relativeSize x.r}) items


buildScatter ∷ ModelR → JArray → DSL OptionI
buildScatter r records = do
  let
    cols =
      [ { label: D.jcursorLabel r.abscissa, value: CCT.formatValueIx 0 }
      , { label: D.jcursorLabel r.ordinate, value: CCT.formatValueIx 1 }
      ]
    opts = A.catMaybes
      [ r.size <#> \dim → { label: D.jcursorLabel dim, value: CCT.formatValueIx 2 }
      , r.series <#> \dim → { label: D.jcursorLabel dim, value: _.seriesName }
      ]
  E.tooltip do
    E.formatterItem (CCT.tableFormatter (pure ∘ _.color) (cols <> opts) ∘ pure)
    E.triggerAxis
    E.textStyle do
      E.fontFamily "Ubuntu, sans"
      E.fontSize 12
    E.axisPointer do
      E.crossAxisPointer
      E.crossStyle do
        E.color $ C.rgba 170 170 170 0.6
        E.widthNum 0.2
        E.solidLine
  E.colors colors

  BCP.rectangularGrids scatterData
  BCP.rectangularTitles scatterData

  E.grid BCP.cartesian
  E.xAxes $ valueAxes E.addXAxis
  E.yAxes $ valueAxes E.addYAxis

  E.legend do
    E.topBottom
    E.textStyle $ E.fontFamily "Ubuntu, sans"
    E.items $ map ET.strItem seriesNames

  E.series series

  where
  scatterData ∷ ScatterData
  scatterData = buildScatterData r records

  valueAxes ∷ ∀ i a. (DSL (ETP.AxisI (gridIndex ∷ ETP.I|i)) → DSL a) → DSL a
  valueAxes addAxis = enumeratedFor_ scatterData \(ix × _) → addAxis do
    E.gridIndex ix
    E.axisType ET.Value
    E.axisLabel $ E.textStyle $ E.fontFamily "Ubuntu, sans"
    E.axisLine $ E.lineStyle do
      E.color $ C.rgba 184 184 184 1.0
      E.width 1
    E.splitLine $ E.lineStyle do
      E.color $ C.rgba 204 204 204 0.2
      E.width 1

  seriesNames ∷ Array String
  seriesNames =
    A.fromFoldable
    $ foldMap (_.series ⋙ foldMap (_.name ⋙ Set.fromFoldable)) scatterData

  series ∷ ∀ i. DSL (scatter ∷ ETP.I|i)
  series = enumeratedFor_ scatterData \(gridIx × onOneGrid) →
    enumeratedFor_ onOneGrid.series \(ix × serie) → E.scatter do
      E.xAxisIndex gridIx
      E.yAxisIndex gridIx
      for_ serie.name E.name
      for_ (A.index colors $ mod ix $ A.length colors) \color → do
        E.itemStyle $ E.normal $ E.color $ getTransparentColor color 0.5
      E.symbol ET.Circle
      E.buildItems $ for_ serie.items \item → E.addItem $ E.buildValues do
        E.addValue item.x
        E.addValue item.y
        E.addValue item.r
