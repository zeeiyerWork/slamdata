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

module SlamData.Workspace.Card.Setups.Chart.Bar.Component.State where

import Data.Lens (Lens', lens)

type State =
  { axisLabelAngle ∷ Number }

initialState ∷ State
initialState =
  { axisLabelAngle: 0.0 }

_axisLabelAngle ∷ Lens' State Number
_axisLabelAngle = lens _.axisLabelAngle _{ axisLabelAngle = _ }
