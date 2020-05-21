# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./vec3s

# Colors
# -----------------------------------------------------
# We use Nim distinct types to model Color after Vec3 (via "borrow")
# but ensuring we don't mismatch usage

type Color* {.borrow: `.`.} = distinct Vec3

func color*(x, y, z: float64): Color {.inline.} =
  result.x = x
  result.y = y
  result.z = z

func `==`*(a, b: Color): bool {.inline.} =
  Vec3(a) == Vec3(b)

func `$`*(a: Color): string {.inline.} =
  $Vec3(a)

func `*=`*(a: var Color, scalar: float64) {.borrow.}
func `*`*(a: Color, scalar: float64): Color {.borrow.}
func `*`*(scalar: float64, a: Color): Color {.borrow.}

func `+=`*(a: var Color, b: Color) {.borrow.}
func `+`*(a, b: Color): Color {.borrow.}
func `-`*(a, b: Color): Color {.borrow.}

func `*`*(a, b: Color): Color {.error: "Multiplying 2 Colors doesn't make physical sense".}

# Attenuation
# -----------------------------------------------------
# We use Nim distinct types to model Attenuation after Color (via "borrow")
# but ensuring we don't mismatch usage

type Attenuation* {.borrow: `.`.} = distinct Color

func attenuation*(x, y, z: float64): Attenuation {.inline.} =
  result.x = x
  result.y = y
  result.z = z

func `*=`*(a: var Attenuation, b: Attenuation) {.inline.} =
  # Multiply a color by a per-channel attenuation factor
  a.x *= b.x
  a.y *= b.y
  a.z *= b.z

func `*`*(a, b: Attenuation): Attenuation {.inline.} =
  # Multiply a color by a per-channel attenuation factor
  result.x = a.x * b.x
  result.y = a.y * b.y
  result.z = a.z * b.z

func `*=`*(a: var Color, b: Attenuation) {.inline.} =
  # Multiply a color by a per-channel attenuation factor
  a.x *= b.x
  a.y *= b.y
  a.z *= b.z
