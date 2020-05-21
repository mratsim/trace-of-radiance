# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ./hittables_variants,
  ../core,
  ../../primitives

type
  HittableList* = object
    objects: seq[HittableVariant]

func add*(self: var HittableList, h: HittableVariant) {.inline.} =
  self.objects.add h

func add*[T](self: var HittableList, h: T) {.inline.} =
  self.objects.add h.toVariant()

func clear*(self: var HittableList) {.inline.} =
  self.objects.setLen(0)

func hit*(self: HittableList, r: Ray, t_min, t_max: float64, rec: var HitRecord): bool =
  var closest_so_far = t_max

  # TODO: perf issue: https://github.com/nim-lang/Nim/issues/14421
  for i in 0 ..< self.objects.len:
    let hit = self.objects[i].hit(r, t_min, closest_so_far, rec)
    if hit:
      closest_so_far = rec.t
      result = true

# Sanity checks
# -----------------------------------------------------

static: doAssert HittableList is Hittable
