# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Stdlib
  std/math,
  # Internals
  ../primitives,
  ../sampling

type Camera* = object
  origin: Point3
  lower_left_corner: Point3
  horizontal: Vec3
  vertical: Vec3
  u, v, w: Vec3   # Orthonormal basis that describe camera orientation
  lens_radius: float64

func camera*(lookFrom, lookAt: Point3, view_up: Vec3,
             vertical_field_of_view: Degrees, aspect_ratio: float64,
             aperture, focus_distance: float64
            ): Camera =
  let theta = vertical_field_of_view.degToRad()
  let h = tan(theta/2.0)
  let viewport_height = 2.0 * h
  let viewport_width = aspect_ratio * viewport_height

  result.w = unit_vector(lookFrom - lookAt)
  result.u = unit_vector(view_up.cross(result.w))
  result.v = result.w.cross(result.u)

  result.origin = lookFrom
  result.horizontal = focus_distance * viewport_width * result.u
  result.vertical = focus_distance * viewport_height * result.v
  result.lower_left_corner = result.origin - result.horizontal/2 -
                             result.vertical/2 - focus_distance*result.w
  result.lens_radius = aperture/2

func ray*(self: Camera, s, t: float64, rng: var Rng): Ray =
  let rd = self.lens_radius * rng.random_in_unit_disk(Vec3)
  let offset = self.u*rd.x + self.v*rd.y
  ray(
    origin = self.origin + offset,
    direction = self.lower_left_corner +
                  s*self.horizontal +
                  t*self.vertical -
                  self.origin - offset
  )
