# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../support/emulate_classes_with_ADTs

# Type declarations
# ------------------------------------------------------------------------------------------

type
  Lambertian* = object
    albedo*: Attenuation
  Metal* = object
    albedo*: Attenuation
    fuzz*: float64
  Dielectric* = object
    refraction_index*: float64

declareClass(Material)
registerSubType(Material, Lambertian)
registerSubType(Material, Metal)
registerSubType(Material, Dielectric)
generateClass(Material, material)

type
  HitRecord* = object
    p*: Point3
    normal*: Vec3
    material*: Material
    t*: float64        # t_min < t < t_max, the ray position
    front_face*: bool

  Hittable* = concept self
    # All hittables implement
    # func hit(self: Hittable, r: Ray, t_min: float64, t_max: float64): Option[HitRecord]
    # We use Option instead of passing a mutable reference like in the tutorial.
    self.hit(Ray, float64, float64, var HitRecord) is bool

# Routines
# ------------------------------------------------------------------------------------------

func set_face_normal*(rec: var HitRecord, r: Ray, outward_normal: Vec3) {.inline.} =
  rec.front_face = r.direction.dot(outward_normal) < 0
  rec.normal = if rec.front_face: outward_normal else: -outward_normal
