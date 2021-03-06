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

module SlamData.Workspace.Card.Setups.Chart.Scatter.Component
  ( scatterBuilderComponent
  ) where

import SlamData.Prelude

import Data.Lens ((^?), _Just)

import Global (readFloat, isNaN)

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.HTML.Properties.ARIA as ARIA
import Halogen.Themes.Bootstrap3 as B

import SlamData.Render.Common (row)
import SlamData.Workspace.Card.CardType as CT
import SlamData.Workspace.Card.CardType.ChartType as CHT
import SlamData.Workspace.Card.Component as CC
import SlamData.Workspace.Card.Eval.State as ES
import SlamData.Workspace.Card.Model as M
import SlamData.Workspace.Card.Setups.CSS as CSS
import SlamData.Workspace.Card.Setups.Chart.Scatter.Component.ChildSlot as CS
import SlamData.Workspace.Card.Setups.Chart.Scatter.Component.Query as Q
import SlamData.Workspace.Card.Setups.Chart.Scatter.Component.State as ST
import SlamData.Workspace.Card.Setups.Dimension as D
import SlamData.Workspace.Card.Setups.DimensionMap.Component as DM
import SlamData.Workspace.Card.Setups.DimensionMap.Component.Query as DQ
import SlamData.Workspace.Card.Setups.DimensionMap.Component.State as DS
import SlamData.Workspace.Card.Setups.Package.DSL as P
import SlamData.Workspace.Card.Setups.Package.Lenses as PL
import SlamData.Workspace.Card.Setups.Package.Projection as PP
import SlamData.Workspace.LevelOfDetails (LevelOfDetails(..))

type DSL = CC.InnerCardParentDSL ST.State Q.Query CS.ChildQuery CS.ChildSlot
type HTML = CC.InnerCardParentHTML Q.Query CS.ChildQuery CS.ChildSlot

package ∷ DS.Package
package = P.onPrism (M._BuildScatter ∘ _Just) $ DS.interpret do
  abscissa ←
    P.field PL._abscissa PP._abscissa
      >>= P.addSource _.value
  ordinate ←
    P.field PL._ordinate PP._scatterOrdinate
      >>= P.addSource _.value
      >>= P.isFilteredBy abscissa
  size ←
    P.optional PL._size PP._scatterSize
      >>= P.addSource _.value
      >>= P.isFilteredBy abscissa
      >>= P.isFilteredBy ordinate
  series ←
    P.optional PL._series PP._series
      >>= P.addSource _.category
  parallel ←
    P.optional PL._parallel PP._parallel
      >>= P.addSource _.category
      >>= P.isFilteredBy series
  pure unit

scatterBuilderComponent ∷ CC.CardOptions → CC.CardComponent
scatterBuilderComponent =
  CC.makeCardComponent (CT.ChartOptions CHT.Scatter) $ H.parentComponent
    { render
    , eval: cardEval ⨁ setupEval
    , initialState: const ST.initialState
    , receiver: const Nothing
    }

render ∷ ST.State → HTML
render state =
  HH.div
    [ HP.classes [ CSS.chartEditor ] ]
    [ HH.slot' CS.cpDims unit (DM.component package) unit
        $ HE.input \l → right ∘ Q.HandleDims l
    , HH.hr_
    , row [ renderMinSize state, renderMaxSize state ]
    ]

renderMinSize ∷ ST.State → HTML
renderMinSize state =
  HH.div
    [ HP.classes [ B.colXs6, CSS.axisLabelParam ]
    ]
    [ HH.label [ HP.classes [ B.controlLabel ] ] [ HH.text "Min size" ]
    , HH.input
        [ HP.classes [ B.formControl ]
        , HP.value $ show $ state.minSize
        , ARIA.label "Min size"
        , HE.onValueChange $ HE.input (\s → right ∘ Q.SetMinSymbolSize s)
        ]
    ]

renderMaxSize ∷ ST.State → HTML
renderMaxSize state =
  HH.div
    [ HP.classes [ B.colXs6, CSS.axisLabelParam ]
    ]
    [ HH.label [ HP.classes [ B.controlLabel ] ] [ HH.text "Max size" ]
    , HH.input
        [ HP.classes [ B.formControl ]
        , HP.value $ show $ state.maxSize
        , ARIA.label "Max size"
        , HE.onValueChange $ HE.input (\s → right ∘ Q.SetMaxSymbolSize s)
        ]
    ]

cardEval ∷ CC.CardEvalQuery ~> DSL
cardEval = case _ of
  CC.Activate next →
    pure next
  CC.Deactivate next →
    pure next
  CC.Save k → do
    st ← H.get
    let
      inp = M.BuildScatter $ Just
        { abscissa: D.topDimension
        , ordinate: D.topDimension
        , size: Nothing
        , series: Nothing
        , parallel: Nothing
        , minSize: st.minSize
        , maxSize: st.maxSize
        }
    out ← H.query' CS.cpDims unit $ H.request $ DQ.Save inp
    pure $ k case join out of
      Nothing → M.BuildScatter Nothing
      Just a → a
  CC.Load m next → do
    H.query' CS.cpDims unit $ H.action $ DQ.Load $ Just m
    for_ (m ^? M._BuildScatter ∘ _Just) \r →
      H.modify _{ minSize = r.minSize, maxSize = r.maxSize }
    pure next
  CC.ReceiveInput _ _ next →
    pure next
  CC.ReceiveOutput _ _ next →
    pure next
  CC.ReceiveState evalState next → do
    for_ (evalState ^? ES._Axes) \axes → do
      H.query' CS.cpDims unit $ H.action $ DQ.SetAxes axes
    pure next
  CC.ReceiveDimensions dims reply → do
    pure $ reply
      if dims.width < 576.0 ∨ dims.height < 416.0
      then Low
      else High

raiseUpdate ∷ DSL Unit
raiseUpdate =
  H.raise CC.modelUpdate

setupEval ∷ Q.Query ~> DSL
setupEval = case _ of
  Q.SetMinSymbolSize str next → do
    let fl = readFloat str
    unless (isNaN fl) do
      H.modify _{minSize = fl}
      raiseUpdate
    pure next
  Q.SetMaxSymbolSize str next → do
    let fl = readFloat str
    unless (isNaN fl) do
      H.modify _{maxSize = fl}
      raiseUpdate
    pure next
  Q.HandleDims q next → do
    case q of
      DQ.Update _ → raiseUpdate
    pure next
