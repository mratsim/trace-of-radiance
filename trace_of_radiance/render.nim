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

proc render*(canvas: var Canvas, cam: Camera, world: HittableList, max_depth: int) =
  for row in 0'i32 ..< canvas.nrows:
    stderr.write &"\rScanlines remaining: {canvas.nrows - row}"
    stderr.flushFile()
    for col in 0'i32 ..< canvas.ncols:
      var rng: Rng   # We reseed per pixel to be able to parallelize the outer loops
      rng.seed(row, col) # And use a "perfect hash" as the seed
      var pixel = color(0, 0, 0)
      for _ in 0 ..< canvas.samples_per_pixel:
        let u = (col.float64 + rng.random(float64)) / float64(canvas.ncols - 1)
        let v = (row.float64 + rng.random(float64)) / float64(canvas.nrows - 1)
        let r = cam.ray(u, v, rng)
        pixel += radiance(r, world, max_depth, rng)
      canvas.draw(row, col, pixel)
