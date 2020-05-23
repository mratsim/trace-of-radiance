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
  ./core,
  ../primitives,
  ../sampling,
  # Utils
  ../support/emulate_classes_with_ADTs

# Lambert / Diffuse Materials
# ------------------------------------------------------------------------------------------

func lambertian*(albedo: Attenuation): Lambertian {.inline.} =
  result.albedo = albedo

func scatter(self: Lambertian, r_in: Ray,
              rec: HitRecord, rng: var Rng,
              attenuation: var Attenuation, scattered: var Ray): bool =
  let scatter_direction = rec.normal + rng.random(UnitVector)
  scattered = ray(rec.p, scatter_direction)
  attenuation = self.albedo
  return true

# Metal Materials
# ------------------------------------------------------------------------------------------

func metal*(albedo: Attenuation, fuzz: float64): Metal {.inline.} =
  result.albedo = albedo
  result.fuzz = min(fuzz, 1)

func scatter(self: Metal, r_in: Ray,
              rec: HitRecord, rng: var Rng,
              attenuation: var Attenuation, scattered: var Ray): bool =
  let reflected = r_in.direction.unit_vector().reflect(rec.normal)
  scattered = ray(rec.p, reflected + self.fuzz * rng.random_in_unit_sphere(Vec3))
  if scattered.direction.dot(rec.normal) > 0:
    attenuation = self.albedo
    return true
  return false

# Dielectric / Glass Materials
# ------------------------------------------------------------------------------------------

func dielectric*(refraction_index: float64): Dielectric {.inline.} =
  result.refraction_index = refraction_index

func schlick(cosine, refraction_index: float64): float64 =
  ## Glass reflectivity depends on the angle (i.e. it may become a mirror)
  ## This is a polynomial approximation of that
  var r0 = (1-refraction_index) / (1+refraction_index)
  r0 *= r0
  return r0 + (1-r0)*pow(1-cosine, 5)

func scatter(self: Dielectric, r_in: Ray,
              rec: HitRecord, rng: var Rng,
              attenuation: var Attenuation, scattered: var Ray): bool =
  attenuation = attenuation(1, 1, 1)
  let etaI_over_etaT = if rec.front_face: 1.0 / self.refraction_index
                       else: self.refraction_index

  let unit_direction = unit_vector(r_in.direction)
  let cos_theta = min(dot(-unit_direction, rec.normal), 1.0)
  let sin_theta = sqrt(1.0 - cos_theta*cos_theta)

  if etaI_over_etaT * sin_theta > 1.0:
    let reflected = unit_direction.reflect(rec.normal)
    scattered = ray(rec.p, reflected)
    return true

  let reflect_prob = schlick(cos_theta, etaI_over_etaT)
  if rng.random(float64) < reflect_prob:
    let reflected = unit_direction.reflect(rec.normal)
    scattered = ray(rec.p, reflected)
    return true

  let refracted = unit_direction.refract(rec.normal, etaI_over_etaT)
  scattered = ray(rec.p, refracted)
  return true

# Generate ADT
# ------------------------------------------------------------------------------------------

registerRoutine(Material):
  func scatter*(self: Material, r_in: Ray, rec: HitRecord,
                rng: var Rng,
                attenuation: var Attenuation, scattered: var Ray): bool

generateRoutines(Material)
