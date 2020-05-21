# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/math

func clamp*(x, min, max: float64): float64 {.inline.} =
  # Nim builtin clamp is not inline :/
  if x < min: return min
  if x > max: return max
  return x

# Angles
# ------------------------------------------------------
# We prevent mismatch between degrees and radians
# via compiler-enforced type-checking

type
  Degrees* = distinct float64
  Radians* = distinct float64

template degToRad*(deg: Degrees): Radians =
  Radians degToRad float64 deg

template radToDeg*(rad: Radians): Degrees =
  Degrees radToDeg float64 rad

# For now we don't create our full safe unit library
# with proper cos/sin/tan radians enforcing
# and auto-convert to float
converter toF64*(rad: Radians): float64 {.inline.} =
  float64 rad
