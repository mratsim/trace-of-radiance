# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Stdlib
  std/math,
  # Internal
  ./vec3s, ./point3s

type Ray* = object
  origin*: Point3
  direction*: Vec3

func ray*(origin: Point3, direction: Vec3): Ray {.inline.} =
  result.origin = origin
  result.direction = direction

func at*(ray: Ray, t: float64): Point3 {.inline.} =
  ray.origin + t * ray.direction

func reflect*(u, n: Vec3): Vec3 {.inline.} =
  u - 2*dot(u, n)*n

func refract*(uv: UnitVector, n: Vec3, etaI_over_etaT: float64): Vec3 =
  ## Snell's Law:
  ##    η sin θ = η′ sin θ′
  ## uv: unit_vector
  let cos_theta = dot(-uv, n)
  let r_out_parallel = etaI_over_etaT * (uv + cos_theta * n)
  let r_out_perpendicular = -sqrt(1.0 - r_out_parallel.length_squared()) * n
  return r_out_parallel + r_out_perpendicular
