# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Random Number Generator
# ----------------------------------------------------------------------------------

# We use the high bits of xoshiro256+
# as we are focused on floating points.
#
# http://prng.di.unimi.it/
#
# We initialize the RNG with SplitMix64

type Rng* = object
  s0, s1, s2, s3: uint64

func pair(x, y: SomeInteger): uint64 {.inline.} =
  ## A simple way to produce a unique uint64
  ## from 2 integers
  ## Simpler and faster than
  ## - Cantor pairing: https://en.wikipedia.org/wiki/Pairing_function#Cantor_pairing_function
  ## - Szudzik pairing: http://szudzik.com/ElegantPairing.pdf
  ## for integers bounded to uint32.
  ## Beyond there is collision
  (x.uint64 shl 32) xor y.uint64

func splitMix64(state: var uint64): uint64 =
  state += 0x9e3779b97f4a7c15'u64
  result = state
  result = (result xor (result shr 30)) * 0xbf58476d1ce4e5b9'u64
  result = (result xor (result shr 27)) * 0xbf58476d1ce4e5b9'u64
  result = result xor (result shr 31)

func seed*(rng: var Rng, x: SomeInteger) =
  ## Seed the random number generator with a fixed seed
  var sm64 = uint64(x)
  rng.s0 = splitMix64(sm64)
  rng.s1 = splitMix64(sm64)
  rng.s2 = splitMix64(sm64)
  rng.s3 = splitMix64(sm64)

func seed*(rng: var Rng, x, y: SomeInteger) =
  ## Seed the random number generator from 2 integers
  ## for example, the iteration variable
  var sm64 = pair(x, y)
  rng.s0 = splitMix64(sm64)
  rng.s1 = splitMix64(sm64)
  rng.s2 = splitMix64(sm64)
  rng.s3 = splitMix64(sm64)

func rotl(x: uint64, k: static int): uint64 {.inline.} =
  return (x shl k) or (x shr (64 - k))

func next(rng: var Rng): uint64 =
  ## Compute a random uint64 from the input state
  ## using xoshiro256+ algorithm by Vigna et al
  ## State is updated.
  ## The lowest 3-bit have low linear complexity
  ## For floating point use the 53 high bits
  result = rng.s0 + rng.s3
  let t = rng.s1 shl 17

  rng.s2 = rng.s2 xor rng.s0
  rng.s3 = rng.s3 xor rng.s1
  rng.s1 = rng.s1 xor rng.s2
  rng.s0 = rng.s0 xor rng.s3

  rng.s2 = rng.s2 xor t

  rng.s3 = rotl(rng.s3, 45)

func uniform*(rng: var Rng, maxExcl: uint32): uint32 =
  ## Generate a random integer in 0 ..< maxExclusive
  ## Uses an unbiaised generation method
  ## See Lemire's algorithm modified by Melissa O'Neill
  ##   https://www.pcg-random.org/posts/bounded-rands.html
  ## - Unbiaised
  ## - Features only a single modulo operation
  assert maxExcl > 0
  let max = maxExcl
  var x = uint32 (rng.next() shr 32) # The higher 32-bit are of higher quality with xoshiro256+
  var m = x.uint64 * max.uint64
  var l = uint32 m
  if l < max:
    var t = not(max) + 1 # -max
    if t >= max:
      t -= max
      if t >= max:
        t = t mod max
    while l < t:
      x = uint32 rng.next()
      m = x.uint64 * max.uint64
      l = uint32 m
  return uint32(m shr 32)

func uniform*[T: SomeInteger](rng: var Rng, minIncl, maxExcl: T): T =
  ## Return a random integer in the given range.
  ## The range bounds must fit in an int32.
  let maxExclusive = maxExcl - minIncl
  result = T(rng.uniform(uint32 maxExclusive))
  result += minIncl

# TODO, not enough research in float64 PRNG
# - Generating Random Floating-Point Numbers by Dividing Integers: a Case Study
#   Frédéric Goualard, 2020
#   http://frederic.goualard.net/publications/fpnglib1.pdf

const
  F64_Bits = 64
  F64_MantissaBits = 52

func uniform*(rng: var Rng, minIncl, maxExcl: float64): float64 =
  # Create a random mantissa with exponent of 1
  let mantissa = rng.next() shr (F64_Bits - F64_MantissaBits)
  let fl = mantissa or cast[uint64](1'f64)
  # Debiaised by removing 1
  let debiaised = cast[float64](fl) - 1'f64

  # Scale to the target range
  return max(
    minIncl,
    debiaised * (maxExcl - minIncl) + minIncl
  )

func uniform*(rng*: var float64, _: type float64): float64 =
  let mantissa = rng.next() shr (F64_Bits - F64_MantissaBits)
  let fl = mantissa or cast[uint64](1'f64)
  # Debiaised by removing 1
  return cast[float64](fl) - 1'f64

func uniform*(rng*: var float64, _: type float64): float64 =
  let mantissa = rng.next() shr (F64_Bits - F64_MantissaBits)
  let fl = mantissa or cast[uint64](1'f64)
  # Debiaised by removing 1
  return cast[float64](fl) - 1'f64

func uniform*(rng: var Rng, maxExcl: float64): float64 =
  # Create a random mantissa with exponent of 1
  let mantissa = rng.next() shr (F64_Bits - F64_MantissaBits)
  let fl = mantissa or cast[uint64](1'f64)
  # Debiaised by removing 1
  let debiaised = cast[float64](fl) - 1'f64

  # Scale to the target range
  return debiaised * maxExcl

# Sanity checks
# ------------------------------------------------------------

when isMainModule:
  import std/[tables, times]
  # TODO: proper statistical tests

  proc uniform_uint() =
    var rng: Rng
    let timeSeed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
    rng.seed(timeSeed)
    echo "prng_sanity_checks - uint32 - xoshiro256+ seed: ", timeSeed

    proc test[T](min, maxExcl: T) =
      var c = initCountTable[int]()

      for _ in 0 ..< 1_000_000:
        c.inc(rng.uniform(min, maxExcl))

      echo "1'000'000 pseudo-random outputs from ", min, " to ", maxExcl, " (excl): ", c

    test(0, 2)
    test(0, 3)
    test(1, 53)
    test(-10, 11)

  uniform_uint()
  echo "\n--------------------------------------------------------\n"

  proc uniform_f64() =
    var rng: Rng
    let timeSeed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
    rng.seed(timeSeed)
    echo "prng_sanity_checks - float64 - xoshiro256+ seed: ", timeSeed

    proc bin(f, bucketsWidth, min: float64): int =
      # Idea: we split the range into buckets
      # and we verify that the size of the buckets is similar
      int((f - min) / bucketsWidth)

    proc test[T](min, maxExcl: T, buckets: int) =

      var c = initCountTable[int]()

      let bucketsWidth = (maxExcl - min) / float64(buckets)

      for _ in 0 ..< 1_000_000:
        c.inc(rng.uniform(min, maxExcl).bin(bucketsWidth, min))

      echo "1'000'000 pseudo-random outputs from ", min, " to ", maxExcl, " (excl): ", c

    test(0.0, 2.0, 10)
    test(0.0, 2.0, 20)
    test(0.0, 3.0, 10)
    test(0.0, 1.0, 10)
    test(0.0, 1.0, 20)
    test(-1.0, 1.0, 10)
    test(-1.0, 1.0, 20)

  uniform_f64()
