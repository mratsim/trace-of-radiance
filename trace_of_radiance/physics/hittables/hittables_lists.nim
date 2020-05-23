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
  Scene* = object
    ## A list of hittable objects.
    ## ⚠ not thread-safe
    objects: seq[HittableVariant]

  HittableList* = object
    ## TODO openarray as value
    ## ⚠: lifetime
    len: int
    objects: ptr UncheckedArray[HittableVariant]

# Mutable routines
# ---------------------------------------------------------

func add*(self: var Scene, h: HittableVariant) {.inline.} =
  self.objects.add h

func add*[T](self: var Scene, h: T) {.inline.} =
  self.objects.add h.toVariant()

func clear*(self: var Scene) {.inline.} =
  self.objects.setLen(0)

# Immutable routines
# ---------------------------------------------------------

func list*(scene: Scene): HittableList {.inline.} =
  assert scene.objects.len > 0
  result.len = scene.objects.len
  result.objects = cast[ptr UncheckedArray[HittableVariant]](
    scene.objects[0].unsafeAddr
  )

func hit*(self: HittableList, r: Ray, t_min, t_max: float64, rec: var HitRecord): bool =
  var closest_so_far = t_max

  for i in 0 ..< self.len:
    let hit = self.objects[i].hit(r, t_min, closest_so_far, rec)
    if hit:
      closest_so_far = rec.t
      result = true

# Sanity checks
# -----------------------------------------------------

static: doAssert HittableList is Hittable
