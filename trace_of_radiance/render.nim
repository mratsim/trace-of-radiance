# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/strformat,
  ./primitives,
  ./sampling,
  ./io/ppm,
  ./physics/[core, hittables, cameras, materials]

# Rendering routines
# ------------------------------------------------------------------------

func radiance*(ray: Ray, world: Hittable, max_depth: int, rng: var Rng): Color =
  var attenuation = attenuation(1.0, 1.0, 1.0)
  var ray = ray

  for _ in 0 ..< max_depth:
    # Hit surface?
    var rec: HitRecord
    let maybeRec = world.hit(ray, 0.001, Inf, rec)
    if maybeRec:
      var materialAttenuation: Attenuation
      var scattered: Ray
      let maybeScatter = rec.material.scatter(ray, rec, rng, materialAttenuation, scattered)
      # Bounce on surface
      if maybeScatter:
        attenuation *= materialAttenuation
        ray = scattered
        continue
      return color(0, 0, 0)

    # No hit
    let unit_direction = ray.direction.unit_vector()
    let t = 0.5 * unit_direction.y + 1.0
    result = (1.0 - t) * color(1, 1, 1) + t*color(0.5, 0.7, 1)
    result *= attenuation
    return

  return color(0, 0, 0)

proc renderToPPM*(output: File, cam: Camera, world: HittableList,
                  image_height, image_width, samples_per_pixel, max_depth: int) =
  for j in countdown(image_height-1, 0):
    stderr.write &"\rScanlines remaining: {j} "
    stderr.flushFile()
    for i in 0 ..< image_width:
      var rng: Rng   # We reseed per pixel to be able to parallelize the outer loops
      rng.seed(j, i) # And use a "perfect hash" as the seed
      var pixel = color(0, 0, 0)
      for s in 0 ..< samples_per_pixel:
        let u = (i.float64 + rng.random(float64)) / float64(image_width - 1)
        let v = (j.float64 + rng.random(float64)) / float64(image_height - 1)
        let r = cam.ray(u, v, rng)
        pixel += radiance(r, world, max_depth, rng)
      output.write(pixel, samples_per_pixel)
