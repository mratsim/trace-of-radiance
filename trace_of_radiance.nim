# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ./trace_of_radiance/[
    primitives,
    physics/cameras,
    physics/hittables,
    render,
    scenes,
    sampling,
    io/ppm
  ]

proc main() =
  const aspect_ratio = 16.0 / 9.0
  const image_width = 384
  const image_height = int(image_width / aspect_ratio)
  const samples_per_pixel = 100
  const gamma_correction = 2.2
  const max_depth = 50

  var worldRNG: Rng
  worldRNG.seed 0xFACADE
  let world = worldRNG.random_scene()

  let
    lookFrom = point3(13,2,3)
    lookAt = point3(0,0,0)
    vup = vec3(0,1,0)
    dist_to_focus = 10.0
    aperture = 0.1

  let cam = camera(
              lookFrom, lookAt,
              view_up = vup,
              vertical_field_of_view = 20.Degrees,
              aspect_ratio, aperture, dist_to_focus
            )

  var canvas = newCanvas(
                 image_height, image_width,
                 samples_per_pixel,
                 gamma_correction
               )

  canvas.render(cam, world.list(), max_depth)

  stdout.exportToPPM canvas
  stderr.write "\nDone.\n"

main()
