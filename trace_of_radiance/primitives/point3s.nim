# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./vec3s

# Points3
# -----------------------------------------------------
# We use Nim distinct types to model Points3 after Vec3 (via "borrow")
# but ensuring we don't mismatch usage

type Point3* {.borrow: `.`.} = distinct Vec3 # The `.` annotation ensures that field access is possible

func point3*(x, y, z: float64): Point3 {.inline.} =
  result.x = x
  result.y = y
  result.z = z

func `*=`*(a: var Point3, scalar: float64) {.borrow.}
func `*`*(a: Point3, scalar: float64): Point3 {.borrow.}
func `*`*(scalar: float64, a: Point3): Point3 {.borrow.}

func `==`*(a, b: Point3): bool {.inline.} =
  Vec3(a) == Vec3(b)

func `$`*(a: Point3): string {.inline.} =
  $Vec3(a)

func `-`*(a, b: Point3): Vec3 {.inline.}=
  ## Substracting points from one point to the other
  ## gives a vector
  result.x = a.x - b.x
  result.y = a.y - b.y
  result.z = a.z - b.z

template `+`*(p: Point3, v: Vec3): Point3 =
  ## Adding a vector to a point results in a point
  Point3(Vec3(p) + v)

template `-`*(p: Point3, v: Vec3): Point3 =
  ## Substracting a vector to a point results in a point
  Point3(Vec3(p) - v)

func `+`*(a, b: Point3): Point3 {.error: "Adding 2 Point3 doesn't make physical sense".}
