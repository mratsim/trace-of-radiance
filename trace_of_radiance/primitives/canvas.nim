# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Low-level
  system/ansi_c,
  # Stdlib
  std/math,
  # Internal
  ./colors

# Canvas
# ------------------------------------------------------------------------
# A Canvas is a 2D Buffer

type
  Canvas* = object
    ## 2D Buffer
    ## Images are stored in row-major order
    # Size 24 bytes
    pixels*: ptr UncheckedArray[Color]
    nrows*, ncols*: int32
    samples_per_pixel*: int32
    gamma_correction*: float32


proc newCanvas*(
       height, width,
       samples_per_pixel: SomeInteger,
       gamma_correction: SomeFloat): Canvas =
  result.nrows = int32 height
  result.ncols = int32 width
  result.samples_per_pixel = int32 samples_per_pixel
  result.pixels = cast[ptr UncheckedArray[Color]](
    c_malloc(csize_t height * width * sizeof(Color))
  )
  result.gamma_correction = float32(gamma_correction)

proc delete*(canvas: var Canvas) {.inline.} =
  if not canvas.pixels.isNil:
    c_free(canvas.pixels)

func draw*(canvas: var Canvas, row, col: int32, pixel: Color) {.inline.} =
  # Draw a gamma-corrected pixel in the canvas
  let scale = 1.0 / canvas.samples_per_pixel.float64
  let gamma = 1.0 / canvas.gamma_correction.float64
  let pos = row*canvas.ncols + col
  canvas.pixels[pos].x = pow(scale * pixel.x, gamma)
  canvas.pixels[pos].y = pow(scale * pixel.y, gamma)
  canvas.pixels[pos].z = pow(scale * pixel.z, gamma)

proc `[]`*(canvas: Canvas, row, col: int32): Color {.inline.} =
  canvas.pixels[row*canvas.ncols + col]
