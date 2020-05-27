# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Runtime dispatch
# ----------------------------------------------

# Note: We want to have a parallel RayTracer
#       we should use plain objects as much as possible
#       instead of involving the GC with
#       ref types and inheriance.
#       Instead we use concepts so that `hit` is statically dispatched
#       and object variants (ADT / Abstract Data Types)
#       for runtime dispatch on stack objects.
#
# This has the following benefits:
# - No GC-memory
# - No heap allocation
# - Easy to send across threads via trivial copy
# - pointer dereference is very often a cache miss
#   a branch misprediction is much less costly
#
# We also don't use shared pointer / refcounting
# (which is builtin to Nim GC).
# - Same reason: no heap memory wanted
# - Copying is better than sharing for multithreading
# - The type that we use are write-once at initialization
#   and their state don't evolve other time
# - Memory management of stack object is also automatic and much easier to reason about
#   than reference counting.
# - No bookkeeping
#
# A set of macros allow us to emulate classes
# with ADTs in a convenient way

import
  ../../support/emulate_classes_with_ADTs,
  ../../primitives,
  ../core,
  ./spheres, ./moving_spheres

# Hittables
# -----------------------------------------------------

import ./spheres

declareClass(HittableVariant)
registerSubType(HittableVariant, Sphere)
registerSubType(HittableVariant, MovingSphere)
registerRoutine(HittableVariant):
  func hit*(self: HittableVariant, r: Ray, t_min, t_max: float64, rec: var HitRecord): bool {.inline.}

generateClass(HittableVariant, toVariant)
generateRoutines(HittableVariant)

# Sanity checks
# -----------------------------------------------------

static: doAssert HittableVariant is Hittable
