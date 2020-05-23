# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/math,
  ./primitives,
  ./support/rng

export rng

# Random routines
# ------------------------------------------------------

func random*(rng: var Rng, _: type float64): float64 {.inline.} =
  rng.uniform(float64)

func random*(rng: var Rng, _: type float64, max: float64): float64 {.inline.} =
  rng.uniform(max)

func random*(rng: var Rng, _: type float64, min, max: float64): float64 {.inline.} =
  rng.uniform(min, max)

# Vector
# ------------------------------------------------------

func random(rng: var Rng, _: type Vec3): Vec3 {.inline.} =
  result.x = rng.random(float64)
  result.y = rng.random(float64)
  result.z = rng.random(float64)

func random(rng: var Rng, _: type Vec3, max: float64): Vec3 {.inline.} =
  result.x = rng.random(float64, max)
  result.y = rng.random(float64, max)
  result.z = rng.random(float64, max)

func random(rng: var Rng,  _: type Vec3, min, max: float64): Vec3 {.inline.} =
  result.x = rng.random(float64, min, max)
  result.y = rng.random(float64, min, max)
  result.z = rng.random(float64, min, max)

func random_in_unit_sphere*(rng: var Rng, _: type Vec3): Vec3 =
  while true:
    let p = rng.random(Vec3, -1, 1)
    if p.length_squared() < 1.0:
      return p

func random*(rng: var Rng, _: type UnitVector): UnitVector =
  let a = rng.random(float64, 2*PI)
  let z = rng.random(float64, -1.0, 1.0)
  let r = sqrt(1.0 - z*z)
  return toUV(vec3(r*cos(a), r*sin(a), z))

func random_in_hemisphere*(rng: var Rng, _: type Vec3, normal: Vec3): Vec3 =
  let in_unit_sphere = rng.random_in_unit_sphere(Vec3)
  if in_unit_sphere.dot(normal) > 0.0: # In the same hemisphere as normal
    return in_unit_sphere
  else:
    return -in_unit_sphere

func random_in_unit_disk*(rng: var Rng, _: type Vec3): Vec3 =
  while true:
    result = vec3(rng.random(float64, -1.0, 1.0), rng.random(float64, -1.0, 1.0), 0)
    if result.length_squared() < 1:
      return

# Color
# ------------------------------------------------------

func random*(rng: var Rng, _: type Attenuation): Attenuation {.inline.} =
  result.x = rng.random(float64)
  result.y = rng.random(float64)
  result.z = rng.random(float64)

func random*(rng: var Rng, _: type Attenuation, max: float64): Attenuation {.inline.} =
  result.x = rng.random(float64, max)
  result.y = rng.random(float64, max)
  result.z = rng.random(float64, max)

func random*(rng: var Rng, _: type Attenuation, min, max: float64): Attenuation {.inline.} =
  result.x = rng.random(float64, min, max)
  result.y = rng.random(float64, min, max)
  result.z = rng.random(float64, min, max)
