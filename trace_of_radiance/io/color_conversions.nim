# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Color conversion
# ------------------------------------------------------

# This files implements RGB24 to Y'CbCr 420 conversion
#
# References:
# - BT.601 norm: https://en.wikipedia.org/wiki/Rec._601
#   - Used in SD, when no color matrix is available video with width < 1280
#     are assumed in this colorspace
# - BT.709 norm: https://en.wikipedia.org/wiki/Rec._709
#   - Used in HD, when no color matrix is available video with width < 1280
#     are assumed in this colorspace

# 601 vs 709 gone wrong: https://blog.maxofs2d.net/post/148346073513/bt601-vs-bt709
# Color conversion FAQ: http://www.martinreddy.net/gfx/faqs/colorconv.faq
# YUV to RGB confusion: http://www.fourcc.org/fccyvrgb.php
# YUV: https://wiki.videolan.org/YUV
# YUV and luminance considered harmful: https://poynton.ca/PDFs/YUV_and_luminance_harmful.pdf
# Color difference: https://poynton.ca/notes/colour_and_gamma/ColorFAQ.html#RTFToC26

# Terminology:
# Y'CbCr 420
# - has 1 luma field Y'
# - has 2 chroma fields UB
# - stored in a Struct of arrays layout.
# - Those are different from analog luminance and chrominance
#
# Y' stands for gamma corrected luma. The conversions are valid
# from gamma corrected RGB (usually via pow(color, 1/2.2))
#
# The RGB range is [0, 255]
# The Y' range is [16, 235]
# The UV range is [16, 240]
#
# Note JPEG uses the full range [0, 255] ...
#
# 420 indicates that the luma Y' has full resolution
# while the chromas are half-resolution in both width and height
# meaning a chroma value corresponds (and interpolates) 4 adjacent pixels

# ITU-R BT.601
# Kr = 0.299
# Kg = 0.587
# Kb = 0.114
#
# with the sum equal to 1 (with R'G'B' gamma corrected, see spec)
# Y' = 0.299 R' + 0.587 G' + 0.114 B'
#
# Cb and Cr (Chroma difference blue and Chroma difference red)
# are computed via
# - Fb * (B' - Y')
# - Fr * (R' - Y')
# with the scaling Fb and Fr computed to cover
# the target range [16, 240] or [0, 255]
# and UV == 0 on pure white or pure black

# Algorithm - See description at the bottom
# We reuse the algorithm from Adrien Descamps
# https://github.com/descampsa/yuv2rgb

type
  RGB_to_YCbCr_Coefs = object
    ## Coefficients for RGB24 -> Y'CbCr conversion
    kr, kg, kb: uint8 # luma conversion factor
    fb: uint8         # Chroma difference blue factor: (CbMax - CbMin)/(255*CbNorm)
    fr: uint8         # Chroma difference red factor: (CrMax - CrMin)/(255*CrNorm)
    y_scale: uint8    # (Ymax-Ymin)/255
    y_min: uint8

  RGB_Concept* = concept rgb
    ## RGB data stored in any order,
    ## RGB or BGR or ...
    rgb.r is uint8
    rgb.g is uint8
    rgb.b is uint8

  ChannelDescriptor*[T] = object
    ## A descriptor that describes how to access a color channel
    # TODO: openarray as value to ensure lifetime
    buffer: ptr UncheckedArray[T]
    stride: int32

  ChannelLossless[T] = object
    ## {.borrow: `.`.} broken with generics
    ## https://github.com/nim-lang/Nim/issues/14449
    buffer: ptr UncheckedArray[T]
    stride: int32

  ChannelSubSampled[T] = object
    ## {.borrow: `.`.} broken with generics
    ## https://github.com/nim-lang/Nim/issues/14449
    buffer: ptr UncheckedArray[T]
    stride: int32

  YCbCrKind* = enum
    BT601

func toFixedPoint(x: float64, I:typedesc[SomeInteger], precision: int): I {.inline.} =
  I(x * float64(1 shl precision) + 0.5) # 0.5 for rounding

func compute_RGB_to_YCbCr_Coefs(
       kr, kb, ymin, ymax, cbCrRange: float64
     ): RGB_to_YCbCr_Coefs {.compileTime.} =
  result.kr = kr.toFixedPoint(uint8, 8)
  result.kb = kb.toFixedPoint(uint8, 8)
  result.kg = uint8(256 - result.kr - result.kb) # preserves unity range
  result.fb = ((cbCrRange/255.0) / (2.0*(1.0-kb))).toFixedPoint(uint8, 8)
  result.fr = ((cbCrRange/255.0) / (2.0*(1.0-kr))).toFixedPoint(uint8, 8)
  result.y_scale = ((ymax-ymin)/255.0).toFixedPoint(uint8, 7)
  result.y_min = uint8(y_min)

func initChannelDesc*[T](buffer: var T, width: SomeInteger,
                               subsampled: static bool
                              ): ChannelDescriptor[T] {.inline.} =
  ## Create a descriptor for a color channel.
  ## Use subsampled == true for a subsambpled channel
  ## Assumes that images are stored with "width" laid out contiguously
  ##
  ## Note: ensure that the buffer lifetime is greater than
  ## the color conversion routines.
  result.buffer = cast[ptr UncheckedArray[T]](buffer.addr)
  when subsampled:
    result.stride = int32 (width+1) div 2
  else:
    result.stride = int32 width

func initChannelDesc*[T](buffer: (ptr T) or (ptr UncheckedArray[T]),
                               width: SomeInteger,
                               subsampled: static bool
                              ): ChannelDescriptor[T] {.inline.}=
  ## Create a descriptor for a color channel.
  ## Use subsampled == true for a subsambpled channel
  ## Assumes that images are stored with "width" laid out contiguously
  ##
  ## Note: ensure that the buffer lifetime is greater than
  ## the color conversion routines.
  result.buffer = cast[ptr UncheckedArray[T]](buffer)
  when subsampled:
    result.stride = int32 (width+1) div 2
  else:
    result.stride = int32 width

template `[]`[T](channel: ChannelLossless[T], row, col: SomeInteger): T =
  channel.buffer[row*channel.stride + col]

template `[]=`[T](channel: ChannelLossless[T], row, col: SomeInteger, value: T) =
  channel.buffer[row*channel.stride + col] = value

template `[]=`[T](channel: ChannelSubSampled[T], row, col: SomeInteger, value: T) =
  channel.buffer[(row shr 1)*channel.stride + (col shr 1)] = value

const RGB_YCbCr_Coefs = [
    BT601: compute_RGB_to_YCbCr_Coefs(0.299, 0.114, 16.0, 235.0, 240.0-16.0)
  ]

func rgbRaw_to_ycbcr420(
       width, height: int32,
       rgb: ChannelDescriptor[RGB_Concept],
       luma: ChannelDescriptor[uint8],
       chromaBlue: ChannelDescriptor[uint8],
       chromaRed: ChannelDescriptor[uint8],
       ycbcrKind: static YCbCrKind
     ) =
  ## Convert raw RGB stored in any order (RGB, BGR, ...)
  ## to Y'CbCr stored in contiguous arrays with 420 chroma subsampling
  ## YYYYYYYY UU VV
  ##
  ## The RGB datatype must expose "r", "g", "b" as field or proc
  ## The RGB values are expected to be gamma corrected beforehand
  ##
  ## Height and Width MUST be a multiple of 2
  # TODO: slow, look into Intel IPP or libYUV speed for SIMD
  const coefs = RGB_YCbCr_Coefs[ycbcrKind] # Get the conversion coefficients

  assert (width and 1) == 0, "Width must be a multiple of 2"
  assert (height and 1) == 0, "Height must be a multiple of 2"

  # TODO, should be distinct type and avoid cast: https://github.com/nim-lang/Nim/issues/14449
  let rgb = cast[ChannelLossless[RGB_Raw]](rgb)
  let Y = cast[ChannelLossless[uint8]](luma)
  let U = cast[ChannelSubSampled[uint8]](chromaBlue)
  let V = cast[ChannelSubSampled[uint8]](chromaRed)

  # TODO: for some reason tiling doesn't help
  # const tile = 32
  # for i in countup(0, height-1, tile):
  #   for j in countup(0, width-1, tile):
  #     for ii in countup(i, min(i+tile, height-1), 2):
  #       for jj in countup(j, min(j+tile, width-1), 2):
  for ii in countup(0, height-1, 2):
    for jj in countup(0, width-1, 2):
      ## For subsampling we accumulate the chroma over 4 pixels
      var tY: uint16
      var tU, tV: int16

      template i16(x): untyped = int16(x)
      template u16(x): untyped = uint16(x)

      tY = (coefs.kr.u16 * rgb[ii, jj].r.u16 +
            coefs.kg.u16 * rgb[ii, jj].g.u16 +
            coefs.kb.u16 * rgb[ii, jj].b.u16) shr 8
      tU += rgb[ii, jj].b.i16 - tY.i16
      tV += rgb[ii, jj].r.i16 - tY.i16
      Y[ii, jj] = uint8((tY.u16 * coefs.y_scale.u16) shr 7) + coefs.y_min

      tY = (coefs.kr.u16 * rgb[ii, jj+1].r.u16 +
            coefs.kg.u16 * rgb[ii, jj+1].g.u16 +
            coefs.kb.u16 * rgb[ii, jj+1].b.u16) shr 8
      tU += rgb[ii, jj+1].b.i16 - tY.i16
      tV += rgb[ii, jj+1].r.i16 - tY.i16
      Y[ii, jj+1] = uint8((tY.u16 * coefs.y_scale.u16) shr 7) + coefs.y_min

      tY = (coefs.kr.u16 * rgb[ii+1, jj].r.u16 +
            coefs.kg.u16 * rgb[ii+1, jj].g.u16 +
            coefs.kb.u16 * rgb[ii+1, jj].b.u16) shr 8
      tU += rgb[ii+1, jj].b.i16 - tY.i16
      tV += rgb[ii+1, jj].r.i16 - tY.i16
      Y[ii+1, jj] = uint8((tY.u16 * coefs.y_scale.u16) shr 7) + coefs.y_min

      tY = (coefs.kr.u16 * rgb[ii+1, jj+1].r.u16 +
            coefs.kg.u16 * rgb[ii+1, jj+1].g.u16 +
            coefs.kb.u16 * rgb[ii+1, jj+1].b.u16) shr 8
      tU += rgb[ii+1, jj+1].b.i16 - tY.i16
      tV += rgb[ii+1, jj+1].r.i16 - tY.i16
      Y[ii+1, jj+1] = uint8((tY.u16 * coefs.y_scale.u16) shr 7) + coefs.y_min

      U[ii, jj] = uint8(((tU shr 2) * coefs.fb.i16) shr 8 + 128)
      V[ii, jj] = uint8(((tV shr 2) * coefs.fr.i16) shr 8 + 128)

# Algorithm
# ------------------------------------------------------
# See https://github.com/descampsa/yuv2rgb

# Definitions
#
# E'R, E'G, E'B, E'Y, E'Cb and E'Cr refer to the analog signals
# E'R, E'G, E'B and E'Y range is [0:1], while E'Cb and E'Cr range is [-0.5:0.5]
# R, G, B, Y, Cb and Cr refer to the digitalized values
# The digitalized values can use their full range ([0:255] for 8bit values),
# or a subrange (typically [16:235] for Y and [16:240] for CbCr).
# We assume here that RGB range is always [0:255], since it is the case for
# most digitalized images.
# For 8bit values :
# * Y = round((YMax-YMin)*E'Y + YMin)
# * Cb = round((CbRange)*E'Cb + 128)
# * Cr = round((CrRange)*E'Cr + 128)
# Where *Min and *Max are the range of each channel
#
# In the analog domain , the RGB to YCbCr transformation is defined as:
# * E'Y = Rf*E'R + Gf*E'G + Bf*E'B
# Where Rf, Gf and Bf are constants defined in each standard, with
# Rf + Gf + Bf = 1 (necessary to ensure that E'Y range is [0:1])
# * E'Cb = (E'B - E'Y) / CbNorm
# * E'Cr = (E'R - E'Y) / CrNorm
# Where CbNorm and CrNorm are constants, dependent of Rf, Gf, Bf, computed
# to normalize to a [-0.5:0.5] range : CbNorm=2*(1-Bf) and CrNorm=2*(1-Rf)
#
# Algorithms
#
# Most operations will be made in a fixed point format for speed, using
# N bits of precision. In next section the [x] convention is used for
# a fixed point rounded value, that is (int being the c type conversion)
# * [x] = int(x*(2^N)+0.5)
# N can be different for each factor, we simply use the highest value
# that will not overflow in 16 bits intermediate variables.
#
# For RGB to YCbCr conversion, we start by generating a pseudo Y value
# (noted Y') in fixed point format, using the full range for now.
# * Y' = ([Rf]*R + [Gf]*G + [Bf]*B)>>N
# We can then compute Cb and Cr by
# * Cb = ((B - Y')*[CbRange/(255*CbNorm)])>>N + 128
# * Cr = ((R - Y')*[CrRange/(255*CrNorm)])>>N + 128
# And finally, we normalize Y to its digital range
# * Y = (Y'*[(YMax-YMin)/255])>>N + YMin
#
# For YCbCr to RGB conversion, we first compute the full range Y' value :
# * Y' = ((Y-YMin)*[255/(YMax-YMin)])>>N
# We can then compute B and R values by :
# * B = ((Cb-128)*[(255*CbNorm)/CbRange])>>N + Y'
# * R = ((Cr-128)*[(255*CrNorm)/CrRange])>>N + Y'
# And finally, for G we know that:
# * G = (Y' - (Rf*R + Bf*B)) / Gf
# From above:
# * G = (Y' - Rf * ((Cr-128)*(255*CrNorm)/CrRange + Y') - Bf * ((Cb-128)*(255*CbNorm)/CbRange + Y')) / Gf
# Since 1-Rf-Bf=Gf, we can take Y' out of the division by Gf, and we get:
# * G = Y' - (Cr-128)*Rf/Gf*(255*CrNorm)/CrRange - (Cb-128)*Bf/Gf*(255*CbNorm)/CbRange
# That we can compute, with fixed point arithmetic, by
# * G = Y' - ((Cr-128)*[Rf/Gf*(255*CrNorm)/CrRange] + (Cb-128)*[Bf/Gf*(255*CbNorm)/CbRange])>>N
#
# Note : in ITU-T T.871(JPEG), Y=Y', so that part could be optimized out

# Sanity checks
# ------------------------------------------------------

when isMainModule:
  # We test vs yuv2rgb which was tested against FFMPEG
  # https://github.com/descampsa/yuv2rgb
  # TODO: more thorough testing like libYUV

  import std/[strutils, os, sequtils, random]

  const
    yuv_rgb_Path = currentSourcePath.rsplit(DirSep, 1)[0]

  {.localPassC: "-I" & yuv_rgb_Path.}
  {.pragma: yuv_rgb, importc, header: yuv_rgb_Path / "yuv_rgb.h".}
  {.compile: "yuv_rgb.c".}

  type YCbCrType {.size: sizeof(cint).} = enum
    YCbCr_JPEG,
    YCbCr_601
    YCbCr_709

  type RGB_Raw = object
    r, g, b: uint8

  static: doAssert: RGB_Raw is RGB_Concept

  # Note: The standard C implementation has a factor bug
  #       correct it before testing
  # https://github.com/descampsa/yuv2rgb/issues/15

  proc rgb24_yuv420_std(
         width, height: uint32,
         rgb: pointer, rgb_stride: uint32,
         y, u, v: pointer,
         y_stride, uv_stride: uint32,
         yuv_type: YCbCrType
       ) {.yuv_rgb.}


  proc randRGB(rng: var Rand): RGB_Raw =
    result.r = uint8 rng.rand(255)
    result.g = uint8 rng.rand(255)
    result.b = uint8 rng.rand(255)

  proc main() =

    for width in [16, 32, 64, 96, 384, 512, 1024]:
      for height in [16, 32, 64, 96, 384, 512, 1024]:
        let width = 16  # * 64  # 1024
        let height = 16 #  * 10 # 160
        var rng = initRand(0xFACADE)

        let rgb = newSeqWith(width * height, rng.randRGB())

        var y_ref = newSeq[uint8](width*height)
        var u_ref = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow
        var v_ref = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow

        rgb24_yuv420_std(
          width.uint32, height.uint32,
          rgb[0].unsafeAddr, rgb_stride = width.uint32 * 3,
          y_ref[0].addr, u_ref[0].addr, v_ref[0].addr,
          y_stride = width.uint32, uv_stride = uint32(width+1) div 2,
          YCbCr_601
        )

        # echo "Y: ", y_ref
        # echo "U: ", u_ref
        # echo "V: ", v_ref

        # echo "-----------------------------------------------------"

        var y_cc = newSeq[uint8](width*height)
        var u_cc = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow
        var v_cc = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow

        let rgbD = initChannelDesc(rgb[0].unsafeAddr, width, subsampled = false)
        let yD = initChannelDesc(y_cc[0].addr, width, subsampled = false)
        let uD = initChannelDesc(u_cc[0].addr, width, subsampled = true)
        let vD = initChannelDesc(v_cc[0].addr, width, subsampled = true)

        rgbRaw_to_ycbcr420(
          width.int32, height.int32, rgbD, yD, uD, vD,
          BT601
        )

        # echo "Y: ", y_cc
        # echo "U: ", u_cc
        # echo "V: ", v_cc

        doAssert: y_cc == y_ref
        doAssert: u_cc == u_ref
        doAssert: v_cc == v_ref

    echo "SUCCESS"

  main()


  import std/[times, monotimes]

  proc bench() =
    let width = 1920
    let height = 1080
    let samples = 1000

    var rng = initRand(0xFACADE)

    let rgb = newSeqWith(width * height, rng.randRGB())

    block:
      var y_ref = newSeq[uint8](width*height)
      var u_ref = newSeq[uint8](width*height div 4)
      var v_ref = newSeq[uint8](width*height div 4)

      let start = getMonotime()
      for _ in 0 ..< samples:
        rgb24_yuv420_std(
          width.uint32, height.uint32,
          rgb[0].unsafeAddr, rgb_stride = width.uint32 * 3,
          y_ref[0].addr, u_ref[0].addr, v_ref[0].addr,
          y_stride = width.uint32, uv_stride = uint32(width+1) div 2,
          YCbCr_601
        )
      let stop = getMonotime()

      let elapsed = inMilliseconds(stop - start)
      echo "ref elapsed: ", elapsed, " ms"
      echo "ref throughput (",width,"x",height,"): ", samples.float64 * 1e3 / elapsed.float64, " conversions/second"

    block:
      var y_cc = newSeq[uint8](width*height)
      var u_cc = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow
      var v_cc = newSeq[uint8](width*height div 4 + 1) # An extra 1 initialized to 0 to catch overflow

      let rgbD = initChannelDesc(rgb[0].unsafeAddr, width, subsampled = false)
      let yD = initChannelDesc(y_cc[0].addr, width, subsampled = false)
      let uD = initChannelDesc(u_cc[0].addr, width, subsampled = true)
      let vD = initChannelDesc(v_cc[0].addr, width, subsampled = true)

      let start = getMonotime()
      for _ in 0 ..< samples:
        rgbRaw_to_ycbcr420(
          width.int32, height.int32, rgbD, yD, uD, vD,
          BT601
        )
      let stop = getMonotime()

      let elapsed = inMilliseconds(stop - start)
      echo "cc elapsed: ", elapsed, " ms"
      echo "cc throughput (",width,"x",height,"): ", samples.float64 * 1000'f64 / elapsed.float64, " conversions/second"

  bench()
