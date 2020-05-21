# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[random, math],
  ./primitives

# Random routines
# ------------------------------------------------------

var globalRng = initRand(0xFACADE) # TODO: init per thread

proc random*(_: type float64): float64 =
  globalRng.rand(1.0)

proc random*(_: type float64, min, max: float64): float64 =
  globalRng.rand(min..max)

# Vector
# ------------------------------------------------------

proc random(_: type Vec3): Vec3 =
  result.x = float64.random()
  result.y = float64.random()
  result.z = float64.random()

proc random(_: type Vec3, min, max: float64): Vec3 =
  result.x = globalRng.rand(min..max)
  result.y = globalRng.rand(min..max)
  result.z = globalRng.rand(min..max)

proc random_in_unit_sphere*(_: type Vec3): Vec3 =
  while true:
    let p = Vec3.random(-1, 1)
    if p.length_squared() < 1.0:
      return p

proc random_unit_vector*(): Vec3 =
  let a = globalRng.rand(0.0 .. 2*PI)
  let z = globalRng.rand(-1.0 .. 1.0)
  let r = sqrt(1.0 - z*z)
  return vec3(r*cos(a), r*sin(a), z)

proc random_in_hemisphere*(normal: Vec3): Vec3 =
  let in_unit_sphere = Vec3.random_in_unit_sphere()
  if in_unit_sphere.dot(normal) > 0.0: # In the same hemisphere as normal
    return in_unit_sphere
  else:
    return -in_unit_sphere

proc random_in_unit_disk*(): Vec3 =
  while true:
    result = vec3(globalRng.rand(-1.0..1.0), globalRng.rand(-1.0..1.0), 0)
    if result.length_squared() < 1:
      return

# Color
# ------------------------------------------------------

proc random*(_: type Attenuation): Attenuation =
  result.x = float64.random()
  result.y = float64.random()
  result.z = float64.random()

proc random*(_: type Attenuation, min, max: float64): Attenuation =
  result.x = globalRng.rand(min..max)
  result.y = globalRng.rand(min..max)
  result.z = globalRng.rand(min..max)
