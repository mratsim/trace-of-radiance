# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./physics/[hittables, materials],
  ./sampling,
  ./primitives

func random_scene*(rng: var Rng): HittableList =
  let ground_material = lambertian attenuation(0.5,0.5,0.5)
  result.add sphere(center = point3(0,-1000,0), 1000, ground_material)

  for a in -11 ..< 11:
    for b in -11 ..< 11:
      let choose_mat = rng.random(float64)
      let center = point3(
        a.float64 + 0.9*rng.random(float64),
        0.2,
        b.float64 + 0.9*rng.random(float64)
      )

      # In the book it's vec3(4, 0.2, 0) but it doesn't make physical sense
      # as center is a point, substracting a vector gives a point
      # length of a point ??unless it is meant distance from the origin (0,0,0)
      if length(center - point3(4, 0.2, 0)) > 0.9:
        if choose_mat < 0.8:
          # Diffuse
          let albedo = rng.random(Attenuation) * rng.random(Attenuation)
          let sphere_material = lambertian albedo
          result.add sphere(center, 0.2, sphere_material)
        elif choose_mat < 0.95:
          # Metal
          let albedo = rng.random(Attenuation, 0.5, 1)
          let fuzz = rng.random(float64, max = 0.5)
          let sphere_material = metal(albedo, fuzz)
          result.add sphere(center, 0.2, sphere_material)
        else:
          # Glass
          let sphere_material = dielectric 1.5
          result.add sphere(center, 0.2, sphere_material)

  result.add sphere(center = point3(0,1,0), 1.0, dielectric 1.5)
  result.add sphere(center = point3(-4,1,0), 1.0, lambertian attenuation(0.4, 0.2, 0.1))
  result.add sphere(center = point3(4,1,0), 1.0, metal(attenuation(0.7, 0.6, 0.5), fuzz = 0.0))
