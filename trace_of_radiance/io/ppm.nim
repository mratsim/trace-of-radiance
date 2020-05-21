# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Stdlib
  std/[strformat, math],
  # internal
  ../primitives

proc write*(f: File, pixelColor: Color, samples_per_pixel: int) =
  var r = pixelColor.x
  var g = pixelColor.y
  var b = pixelColor.z

  # Divide the color total by the number of samples
  # We also do gamma correction for gamma = 2, i.e. pixel^(1/2)
  let scale = 1.0 / float64(samples_per_pixel)
  r = sqrt(scale * r)
  g = sqrt(scale * g)
  b = sqrt(scale * b)

  template conv(c: float64): int =
    int(256 * clamp(c, 0.0, 0.999))

  # Write the translated [0, 255] value of each color component
  f.write &"{conv(r)} {conv(g)} {conv(b)}\n"
