# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/endians

# A hacky H264 lossless encoder
# ------------------------------------------------------

type
  BitBuffer = object
    shift: int
    cache: uint32
    buf: ptr UncheckedArray[byte]
    cursor: int

  Frame = ptr object
    Y: ptr UncheckedArray[uint8]
    Cb, Cr: ptr UncheckedArray[uint8]
    lumaWidth, lumaHeight: int32
    size: int32
    buffer: UncheckedArray[uint8]

  H264Encoder* = object
    sps: seq[byte]
    pps: seq[byte]
    slice_header: seq[byte]
    needCropping: bool
    output: File
    frame: Frame

func `=`(dst: var H264Encoder, src: H264Encoder) {.error: "An H264 encoder cannot be copied, only moved".}

const PPS = [byte 0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x38, 0x80]
const SliceHeader = [byte 0x00, 0x00, 0x00, 0x01, 0x05, 0x88, 0x84, 0x21, 0xa0]
const MacroblockHeader = [byte 0x0d, 0x00]
const SliceStopBit = 0x80

# Accessors Pointer arithmetics
# ------------------------------------------------------

template luma(frame: Frame, x, y: int): uint8 =
  frame.Y[x * frame.lumaWidth + y]

template chromaB(frame: Frame, x, y: int): uint8 =
  frame.Cb[x * (frame.lumaWidth shr 1) + y]

template chromaR(frame: Frame, x, y: int): uint8 =
  frame.Cr[x * (frame.lumaWidth shr 1) + y]

template offset*(p: ptr, bytes: int): ptr =
  cast[typeof(p)](cast[ByteAddress](p) +% bytes)

# Initialization
# ------------------------------------------------------

func put(bb: var BitBuffer, n: int, val: uint32) =
  assert (val shr n) == 0, "Value does not fit in the number of bits"
  bb.shift -= n
  assert n <= 32
  if bb.shift < 0:
    assert -bb.shift < 32
    bb.cache = bb.cache or (val shr -bb.shift)
    bb.buf[bb.cursor].addr.bigEndian32(bb.cache.addr)
    bb.cursor += 4
    bb.shift += 32
    bb.cache = 0
  bb.cache = bb.cache or (val shl bb.shift)

func putGolomb(bb: var BitBuffer, val: uint32) =
  var size = 1
  var t = val+1
  while (t = t shr 1; t != 0):
    inc size
  bb.put(2*size - 1, val+1)

func flush(bb: var BitBuffer) =
  bb.buf[bb.cursor].addr.bigEndian32(bb.cache.addr)
  bb.cursor += 4

template U(nbits: int, val: uint32): untyped {.dirty.} =
  bb.put(nbits, val)

template UE(val: SomeInteger): untyped {.dirty.} =
  bb.putGolomb(uint32 val)

func initSPS(enc: var H264_Encoder, width, height: int) =

  enc.sps.newSeq(32) # A hack to avoid realloc
  var bb = BitBuffer(
    shift: 0,
    cache: 0,
    buf: cast[ptr UncheckedArray[byte]](enc.sps[0].addr),
    cursor: 0
  )

  # Start
  enc.sps[0 ..< 4] = [byte 0x00, 0x00, 0x00, 0x01]
  bb.shift = 32 # wrote 32 bits
  bb.cursor = 4 # Wrote 4 bytes

  # SPS:
  U(1, 0)  # forbidden_zero_bit
  U(2, 3)  # nal_ref_idc
  U(5, 7)  # nal_unit_type

  U(8, 66) # Baseline profile

  # Constraints
  U(1, 0)  # constraint_set0_flag
  U(1, 0)  # constraint_set1_flag
  U(1, 0)  # constraint_set2_flag
  U(1, 0)  # constraint_set3_flag

  U(4, 0)  # reserved_zero_4bits
  U(8, 10) # level_idc, Level 1, sec A.3.1
  UE(0)    # seq_parameter_set_id
  UE(0)    # log2_max_frame_num_minus4
  UE(0)    # pic_order_cnt_type
  UE(0)    # log2_max_pic_order_cnt_lsb_minus4

  UE(0)    # num_ref_frames
  U(1, 0)  # gaps_in_frame_num_value_allowed_flag

  UE((width + 15) shr 4 - 1)  # pic_width_in_mbs_minus_1
  UE((height + 15) shr 4 - 1) # pic_height_in_map_units_minus_1
  U(1, 1)  # frame_mbs_only_flag
  U(1, 0)  # direct_8x8_inference_flag
  U(1, uint32(enc.needCropping)) # frame_cropping_flag
  if enc.needCropping:
    UE(0)
    UE((enc.frame.lumaWidth - width) shr 1)
    UE(0)
    UE((enc.frame.lumaHeight - height) shr 1)
  U(1, 0)  # vui_parameters_present_flag
  U(1, 1)  # Stop bit

  bb.flush()
  enc.sps.setLen(bb.cursor - bb.shift div 8)

proc initialize(frame: var Frame, width, height: int) =
  doAssert frame.isNil

  # 3 channels, Luma full size
  # and Chroma half size
  let fullSized = width*height
  let halfSized = ((width+1) shr 1)*((height+1) shr 1)
  let size = fullSized +
             halfSized +
             halfSized

  frame = cast[Frame](
      allocShared0(
        3*sizeof(pointer) +
        3*sizeof(int32) +
        size
      )
    )
  frame.size = size.int32
  frame.lumaWidth = width.int32
  frame.lumaHeight = height.int32
  frame.Y = cast[ptr UncheckedArray[uint8]](frame.buffer.addr)
  frame.Cb = frame.buffer.addr.offset(fullSized)
  frame.Cr = frame.Cb.offset(halfSized)

proc init*(_: type H264Encoder, width, height: int, output: File): H264Encoder =
  ## Initialize a H264
  result.frame.initialize(width = width, height = height)
  result.initSPS(width = width, height = height)
  result.output = output

  # Write H264 header
  discard result.output.writeBytes(result.sps, 0, result.sps.len)
  discard result.output.writeBytes(PPS, 0, PPS.len)

  # TODO cropping for non-multiple of 16

proc finish*(enc: var H264Encoder) =
  ## Closes and deallocate the H264Encoder
  ## This does NOT close the output.
  enc.frame.deallocShared

# Encoding
# ------------------------------------------------------

proc encodeMacroblock(enc: var H264Encoder, i, j: int) =

  if not(i == 0 and j == 0):
    discard enc.output.writeBytes(MacroblockHeader, 0, MacroblockHeader.len)

  for x in i*16 ..< (i+1) * 16:
    for y in j*16 ..< (j+1) * 16:
      enc.output.write char enc.frame.luma(x, y)
  for x in i*8 ..< (i+1) * 8:
    for y in j*8 ..< (j+1) * 8:
      enc.output.write char enc.frame.chromaB(x, y)
  for x in i*8 ..< (i+1) * 8:
    for y in j*8 ..< (j+1) * 8:
      enc.output.write char enc.frame.chromaR(x, y)

# API
# ------------------------------------------------------

func getFrameBuffers*(enc: var H264Encoder): tuple[Y, Cb, Cr: ptr UncheckedArray[uint8]] =
  ## Return the frame buffers of the encoder
  ## for zero-copy update of the frame
  ## Y' is the gamma-corrected luma
  ## Cb is the chroma blue difference
  ## Cr is the chroma red difference
  ##
  ## Y' is of size width*height
  ## Cb and Cr are of size width/2 * height/2
  ##
  ## i.e. Y'CbCr 420 (horizontal and vertical chroma subsampling)
  ##
  ## It is recommended to use BT.601 color matrix for width < 1280
  ## and BT.709 for width >= 1280 because video players often have this heuristic
  result.Y = enc.frame.Y
  result.Cb = enc.frame.Cb
  result.Cr = enc.frame.Cr

func getFrameBuffer*(enc: var H264Encoder): ptr UncheckedArray[uint8] =
  ## Return the buffer to the whole frame
  ## store contiguously Y' then Cb then Cr
  ##
  ## Y' is of size width*height
  ## Cb and Cr are of size (width+1)/2 * (height+1)/2 (i.e. half size rounded up)
  enc.frame.buffer.addr

func getFrameBufferSize*(enc: var H264Encoder): int32 =
  ## Return the frame buffer size
  enc.frame.size

func getWidth*(enc: var H264Encoder): int32 =
  ## Return the video width
  ## - The Y' channel has the same width
  ## - The chroma channel Cb and Cr are half width
  enc.frame.lumaWidth

func getHeight*(enc: var H264Encoder): int32 =
  ## Return the video height
  ## - The Y' channel has the same height
  ## - The chroma channel Cb and Cr are half height
  enc.frame.lumaHeight

proc flushFrame*(enc: var H264Encoder) =
  ## Flush the current buffered frame to the output file
  ## The frame flushed stay in the buffer and small updates
  ## can be done before a re-flush
  discard enc.output.writeBytes(SliceHeader, 0, SliceHeader.len)

  for i in 0 ..< enc.frame.lumaHeight div 16:
    for j in 0 ..< enc.frame.lumaWidth div 16:
      enc.encodeMacroblock(i, j)

  enc.output.write char SliceStopBit

# Sanity checks
# ------------------------------------------------------

when isMainModule:
  import system/[os, ansi_c]

  proc c_feof(f: File): cint {.
    importc: "feof", header: "<stdio.h>".}

  proc main() =
    # build/h264 < foo.yuv > foo.264

    const LumaWidth = 128
    const LumaHeight = 96

    var enc = H264Encoder.init(LumaWidth, LumaHeight, stdout)

    while stdin.c_feof() == 0:
      discard stdin.readBuffer(enc.getFrameBuffer, enc.getFrameBufferSize)
      enc.flushFrame()

    enc.finish()
    stdout.close()
    quit 0

  main()
