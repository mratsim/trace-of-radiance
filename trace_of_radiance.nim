# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strformat, monotimes],
  # 3rd party
  weave,
  # Internals
  ./trace_of_radiance/[
    primitives,
    physics/cameras,
    physics/hittables,
    render,
    scenes,
    sampling,
    io/ppm
  ],
  # Extra
  ./trace_of_radiance/scenes_animated

import times except Time

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
  defer: canvas.delete()

  init(Weave)
  canvas.render(cam, world.list(), max_depth)
  exit(Weave)

  canvas.exportToPPM stdout
  stderr.write "\nDone.\n"

proc main_animation() =
  const aspect_ratio = 16.0 / 9.0
  const image_width = 384
  const image_height = int32(image_width / aspect_ratio)
  const samples_per_pixel = 100
  const gamma_correction = 2.2
  const max_depth = 50

  const
    dt = 0.005
    t_min = 0.0
    t_max = 2.0
    skip = 6 # Render every 6 physics update

  const
    destDir = "build"/"rendered"
    series = "animation"

  var worldRNG: Rng
  worldRNG.seed 0xFACADE

  var animation = worldRNG.random_moving_spheres(
    image_height, image_width, dt.Time, t_min.Time, t_max.Time
  )

  var canvas = newCanvas(
                 image_height, image_width,
                 samples_per_pixel,
                 gamma_correction
               )
  defer: canvas.delete()

  createDir(destDir)

  let totalScenes = int((t_max - t_min)/(dt*skip))
  stderr.write &"Total scenes: {totalScenes}"

  init(Weave)
  var sceneID = 0
  var elapsed: Duration
  for camera, scene in scenes(animation, skip = 6):
    let remaining = totalScenes-sceneID
    let timeSpent = inSeconds(elapsed)
    let timeLeft = remaining * timeSpent
    stderr.write &"\rScenes remaining: {remaining:>5}, {timeSpent:>2} seconds/scene, estimated time left {timeLeft:>4} seconds"
    stderr.flushFile()
    let start = getMonoTime()
    canvas.render(camera, scene.list(), maxdepth)
    syncRoot(Weave)

    canvas.exportToPPM destDir, series, sceneID

    inc sceneID
    elapsed = getMonoTime() - start

  exit(Weave)

# main()
main_animation()
