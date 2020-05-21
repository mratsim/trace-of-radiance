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
  ../core,
  ../../primitives

type Sphere* = object
  center*: Point3
  radius*: float64
  material*: Material

func sphere*(center: Point3, radius: float64, material: Material): Sphere {.inline.} =
  result.center = center
  result.radius = radius
  result.material = material

func sphere*[T](center: Point3, radius: float64, materialKind: T): Sphere {.inline.} =
  sphere(center, radius, material(materialKind))

func hit*(self: Sphere, r: Ray, t_min, t_max: float64, rec: var HitRecord): bool =
  let oc = r.origin - self.center
  let a = r.direction.length_squared()
  let half_b = oc.dot(r.direction)
  let c = oc.length_squared() - self.radius*self.radius
  let discriminant = half_b*half_b - a*c

  if discriminant > 0:
    let root = discriminant.sqrt()
    for sol in [(-half_b - root)/a, (-half_b + root)/a]:
      if t_min < sol and sol < t_max:

        rec.t = sol
        rec.p = r.at(rec.t)
        let outward_normal = (rec.p - self.center) / self.radius
        rec.set_face_normal(r, outward_normal)
        rec.material = self.material
        return true
  return false

# Sanity checks
# -----------------------------------------------------

static: doAssert Sphere is Hittable
