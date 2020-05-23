# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

const Tolerance = 1e-5

func relative_error*[T: SomeFloat](y, y_true: T): T {.inline.} =
  ## Relative error, |y_true - y|/max(|y_true|, |y|)
  ## Normally the relative error is defined as |y_true - y| / |y_true|,
  ## but here max is used to make it symmetric and to prevent dividing by zero,
  ## guaranteed to return zero in the case when both values are zero.
  let denom = max(abs(y_true), abs(y))
  if denom == 0.T:
    return 0.T
  result = abs(y_true - y) / denom

func absolute_error*[T: SomeFloat](y, y_true: T): T {.inline.} =
  ## Absolute error for a single value, |y_true - y|
  result = abs(y_true - y)

template ensureWithinRelTol*[T: SomeFloat](y, y_true: T, tol = Tolerance): untyped =
  ## If asserts, check that a value `y` is approximately `y_true`
  ## within a relative tolerance `tol`
  ## This is a no-op without assertions
  assert relative_error(y, y_true) <= tol

template ensureWithinAbsTol*[T: SomeFloat](y, y_true: T, tol = Tolerance): untyped =
  ## If asserts, check that a value `y` is approximately `y_true`
  ## within a absolute tolerance `tol`
  ## This is a no-op without assertions
  assert absolute_error(y, y_true) <= tol
