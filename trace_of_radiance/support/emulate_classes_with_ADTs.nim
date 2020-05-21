# Trace of Radiance
# Copyright (c) 2020 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

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
# The downside, making harder to add new hittable objects
# in a self-contained file (the so-called expression problem):
# - is not an issue in this codebase which is a demo
# - can easily be solved with "register" macros
#   that collect types and the proc they implement
#
# We don't use shared pointer / refcounting
# (which is builtin to Nim GC).
# - Same reason: no heap memory wanted
# - Copying is better than sharing for multithreading
# - The type that we use are write-once at initialization
#   and their state don't evolve other time
# - Memory management of stack object is also automatic and much easier to reason about
#   than reference counting.
# - No bookkeeping

# This file implements routines to emulate inheritance
# with ADTs and benefitting from both:
# ADTs:
# - purely on stack, no memory management
# - friendly to multithreading
# - easy to optimize for the compiler, dispatch friendly to branch prediction (especially on Haswell+ CPU)
# - easy to add new functions (switch on all existing types)
#
# Classes:
# - easy to add new types
# - the book uses classes

# This is completely unnecessary and overkill when we only deal with:
# - Hittables: Spheres
# - Materials: Lambertian, Metal, Dielectric
# but it's fun, see at the bottom for the code automated away.


import std/[macros, tables, hashes]

proc hash*(x: NimNode): Hash =
  assert x.kind == nnkIdent
  result = hash($x)

var ClassRegistry {.compileTime.}: Table[NimNode, tuple[subtypes: seq[NimNode], routines: seq[NimNode]]]

macro declareClass*(className: untyped) =
  doAssert className notin ClassRegistry
  ClassRegistry[className] = default(tuple[subtypes: seq[NimNode], routines: seq[NimNode]])

macro registerSubType*(className, subclass: untyped) =
  ## Usage:
  ##   registerSubType(Material, Lambertian)
  ClassRegistry[className].subtypes.add subclass

macro registerRoutine*(className, routine: untyped) =
  ## Usage:
  ##   registerRoutine(Material):
  ##     scatter(self: Material, r_in: Ray, rec: HitRecord): Option[color: attenuation, scattered: Ray]
  ClassRegistry[className].routines.add routine

proc exported(name: string): NimNode =
  nnkPostfix.newTree(
    newIdentNode"*",
    newIdentNode name
  )

macro generateClass*(className, constructorName: untyped) =
  ## Once all subtypes and routines have been registered
  ## call "generateClass" to generate a concrete ADTs
  ## which provides class functionality (without heap memory, GC, thread-safe, ...)
  ##
  ## And a constructor overloaded for each kind

  let class = ClassRegistry[className]
  var enumValues = nnkEnumTy.newTree()
  enumValues.add newEmptyNode()

  var adtCases = nnkRecCase.newTree()
  # case kind: classNameKind
  adtCases.add newIdentDefs(exported"kind", ident($className & "Kind"))

  var constructors = newStmtList()

  for subtype in class.subtypes:
    let kind = ident("k" & $subtype)  # kSphere, kLambertian
    let field = ident("f" & $subtype) # fSphere, fLambertian

    enumValues.add kind

    # of kLambertian:
    #   fLambertian: Lambertian
    adtCases.add nnkOfBranch.newTree(
      kind,
      nnkRecList.newTree(
        newIdentDefs(exported $field, subtype)
      )
    )

    let input = ident"subtype"
    constructors.add quote do:
      func `constructorName`*(`input`: `subType`): `className` {.inline.}=
        `className`(kind: `kind`, `field`: `input`)

  # Create the type section
  result = nnkStmtList.newTree(
    nnkTypeSection.newTree(
      # type MaterialKind* = enum
      #   kLambertian, kMetal, ...
      nnkTypeDef.newTree(
        exported($className & "Kind"),
        newEmptyNode(),
        enumValues
      ),
      # type Material = object
      #   case kind: MaterialKind
      #   of kLambertian:
      #     fLambertian: Lambertian
      #   of kMetal:
      #     fMetal: Metal
      nnkTypeDef.newTree(
        exported $className,
        newEmptyNode(), # Generic params
        nnkObjectTy.newTree(
          newEmptyNode(),
          newEmptyNode(),
          adtCases
        )
      )
    )
  )
  result.add constructors

  # Debug display
  # echo result.toStrLit()

proc replaceNode(ast, toReplace, replaceBy: NimNode): NimNode =
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of {nnkIdent, nnkSym}:
      if node.eqIdent(toReplace):
        return replaceBy
      return node
    of nnkEmpty: return node
    of nnkLiterals: return node
    else:
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add inspect(child)
      return rTree
  result = inspect(ast)

proc dispatcher(fnCall: NimNode, toReplace: NimNode, subtypes: seq[NimNode]): NimNode =
  # From a function call
  # scatter(self, rec)
  #
  # Create
  # case self.kind
  # of kMetal:      scatter(self.fMetal, rec)
  # of kLambertian: scatter(self.fLambertian, rec)
  # of kDielectric: scatter(self.fDielectric, rec)

  fnCall.expectKind(nnkCall)
  toReplace.expectKind(nnkIdent)
  result = nnkCaseStmt.newTree()
  result.add nnkDotExpr.newTree(toReplace, ident"kind")

  for subtype in subtypes:
    result.add nnkOfBranch.newTree(
      ident("k" & $subtype),
      fnCall.replaceNode(
        toReplace,
        nnkDotExpr.newTree(
          toReplace,
          ident("f" & $subtype)
        )
      )
    )

macro generateRoutines*(className: untyped) =
  ## Once all subtypes and routines have been registered
  ## call "generateRoutines" to generate a wrapper routine
  ## that dispatches to the subtype implementation

  let class = ClassRegistry[className]
  result = newStmtList()

  for routine in class.routines:
    routine.expectKind(nnkStmtList)
    let routine = routine[0]
    routine.expectKind {nnkProcDef, nnkFuncDef}

    var fnCall = newCall(routine.name)
    let params = routine.params
    # The param 0 is the return type

    # First, find the symbol of the Class param,
    # for example for "func scatter(self: Material; rec: HitRecord)"
    # we need to extract self
    # param = (symbol, type, defaultValue)
    var classParam: NimNode
    for i in 1 ..< params.len:
      let typePos = params[i].len - 2
      for j in 0 ..< typePos: # Deal with foo(a, b: float64) i.e. (symbol1, symbol2, type, defaultValue)
        fnCall.add params[i][j]
      if params[i][typePos].eqIdent className:
        doAssert typePos == 1, "The class input parameter appears twice in routine: " & $routine.toStrLit()
        doAssert classParam.isNil, "The class input parameter appears twice in routine: " & $routine.toStrLit()
        classParam = params[i][0]

    doAssert not classParam.isNil, "\nNo input parameter is of type \"" &
      $className & "\"" & " for routine:\n  " & $routine.toStrLit()

    let procDef = routine.copyNimTree()
    procDef.body = nnkStmtList.newTree(
      fnCall.dispatcher(classParam, class.subtypes)
    )
    result.add procDef

  # Debug display
  # echo result.toStrLit()

# Sanity checks
# -----------------------------------------------------------------------------------------------
when isMainModule:
  import std/options

  type
    Color = object
    Ray = object
    HitRecord = object

    Metal = object
    Lambertian = object
    Dielectric = object

  func scatter(self: Metal, r_in: Ray, rec: HitRecord): Option[tuple[attenuation: Color, scattered: Ray]] =
    debugEcho "Scatter on Metal"
  func scatter(self: Lambertian, r_in: Ray, rec: HitRecord): Option[tuple[attenuation: Color, scattered: Ray]] =
    debugEcho "Scatter on Lambertian"
  func scatter(self: Dielectric, r_in: Ray, rec: HitRecord): Option[tuple[attenuation: Color, scattered: Ray]] =
    debugEcho "Scatter on Dielectric"

  declareClass(Material)

  registerSubType(Material, Metal)
  registerSubType(Material, Lambertian)
  registerSubType(Material, Dielectric)
  registerRoutine(Material):
    func scatter(self: Material, r_in: Ray, rec: HitRecord): Option[tuple[attenuation: Color, scattered: Ray]]

  expandMacros:
    generateClass(Material, material)
    generateRoutines(Material)

  let m = material(Lambertian())

  discard scatter(m, Ray(), HitRecord())

  # Output

  # # Compile-time
  # # -------------------------------------------
  # type
  #   MaterialKind = enum
  #     kMetal, kLambertian, kDielectric
  #   Material = object case kind*: MaterialKind
  #   of kMetal:
  #       fMetal: Metal

  #   of kLambertian:
  #       fLambertian: Lambertian

  #   of kDielectric:
  #       fDielectric: Dielectric

  # func material(subtype: Metal): Material {.inline.} =
  #   result = Material(kind: kMetal, fMetal: subtype)

  # func material(subtype: Lambertian): Material {.inline.} =
  #   result = Material(kind: kLambertian, fLambertian: subtype)

  # func material(subtype: Dielectric): Material {.inline.} =
  #   result = Material(kind: kDielectric, fDielectric: subtype)

  # func scatter(self: Material; r_in: Ray; rec: HitRecord): Option[
  #     tuple[attenuation: Color, scattered: Ray]] =
  #   result = case self.kind
  #   of kMetal:
  #     scatter(self.fMetal, r_in, rec)
  #   of kLambertian:
  #     scatter(self.fLambertian, r_in, rec)
  #   of kDielectric:
  #     scatter(self.fDielectric, r_in, rec)

  # # Runtime
  # # -------------------------------------------
  # Scatter on Lambertian
