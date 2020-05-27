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
    physics/hittables,
    render,
    sampling,
    io/ppm
  ],
  # Extra
  ./trace_of_radiance/scenes_animated,
  ./trace_of_radiance/io/[
    color_conversions,
    h264,
    mp4,
    rgb
  ]

import times except Time

# Animated scene from book 1
# ------------------------------------------------------------------------
# This is an extra after book 1
# An animated scene with a rudimentary physics engine
# And either PPM series or MP4 output (video encoding in pure Nim!)
# This does not incorporate motion blur from book 2 or acceleration structures
# to speed up compute.

proc main_animation_ppm() =
  # Animation is an extra added at the end of the first book
  # it's slow, and defines its own moving spheres
  # that are different from the second book
  # (which they used just for motion blur not animation)
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
    image_height, image_width, dt.ATime, t_min.ATime, t_max.ATime
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

proc main_animation_mp4() =
  # Animation is an extra added at the end of the first book
  # it's slow, and defines its own moving spheres
  # that are different from the second book
  # (which they used just for motion blur not animation)
  when true: # Fast test
    const aspect_ratio = 16.0 / 9.0
    const image_width = 256 # so that we have multiples of 16 everywhere
    const image_height = int32(image_width / aspect_ratio)
    const samples_per_pixel = 10
    const gamma_correction = 2.2
    const max_depth = 50

    const
      dt = 0.005
      t_min = 0.0
      t_max = 1.0
      skip = 6 # Render every 6 physics update

  else: # Full render
    const aspect_ratio = 16.0 / 9.0
    const image_width = 576 # so that we have multiples of 16 everywhere
    const image_height = int32(image_width / aspect_ratio)
    const samples_per_pixel = 300
    const gamma_correction = 2.2
    const max_depth = 50

    const
      dt = 0.005
      t_min = 0.0
      t_max = 6.0
      skip = 6 # Render every 6 physics update

  const
    destDir = "build"/"rendered"
    series = "animation"

  var worldRNG: Rng
  worldRNG.seed 0xFACADE

  var animation = worldRNG.random_moving_spheres(
    image_height, image_width, dt.ATime, t_min.ATime, t_max.ATime
  )

  var canvas = newCanvas(
                 image_height, image_width,
                 samples_per_pixel,
                 gamma_correction
               )
  defer: canvas.delete()

  createDir(destDir)

  # Encoding
  # ----------------------------------------------------------------------
  let tmp264 = destDir/(series & ".264")
  let out264 = open(tmp264, fmWrite)
  var encoder = H264Encoder.init(image_width, image_height, out264)
  let (Y, Cb, Cr) = encoder.getFrameBuffers()

  let yD = Y.initChannelDesc(image_width, subsampled = false)
  let uD = Cb.initChannelDesc(image_width, subsampled = true)
  let vD = Cr.initChannelDesc(image_width, subsampled = true)

  # Rendering
  # ----------------------------------------------------------------------
  let totalScenes = int((t_max - t_min)/(dt*skip))
  stderr.write &"Total scenes: {totalScenes}"

  init(Weave)
  var sceneID = 0
  var elapsed: Duration
  for camera, scene in scenes(animation, skip = 6):
    let remaining = totalScenes-sceneID
    let timeSpent = inMicroSeconds(elapsed)
    let timeLeft = remaining.float64 * timeSpent.float64 * 1e-6
    let throughput = 1e6/timeSpent.float64
    stderr.write &"\rScenes remaining: {remaining:>5}, {throughput:>7.4f} scene(s)/second, estimated time left {timeLeft:>10.3f} seconds"
    stderr.flushFile()
    let start = getMonoTime()
    canvas.render(camera, scene.list(), maxdepth)
    syncRoot(Weave)


    # Video
    let rgb = canvas.toRGB_Raw()
    let rgbD = rgb[0].unsafeAddr.initChannelDesc(image_width, subsampled = false)
    rgbRaw_to_ycbcr420(
      image_width, image_height,
      rgb = rgbD,
      luma = yD,
      chromaBlue = uD,
      chromaRed = vD,
      BT601
    )
    encoder.flushFrame()

    inc sceneID
    elapsed = getMonoTime() - start

  exit(Weave)
  encoder.finish()
  out264.close()
  echo "\nFinished writing temporary \"", destDir/(series & ".264"),"\".\nMuxing into MP4"

  var mP4Muxer: MP4Muxer
  let mp4 = open(destDir/(series & ".mp4"), fmWrite)
  mP4Muxer.initialize(mp4, image_width, image_height)
  mP4Muxer.writeMP4_from(tmp264)

  mP4Muxer.close()
  mp4.close()
  # removeFile(tmp264)
  echo "Finished! Rendering available at \"", destDir/(series & ".mp4"),"\""

# main_animation_ppm()
main_animation_mp4()
