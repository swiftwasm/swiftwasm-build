# Hermetic full-LTO Swift SDK variant

The `main` scheme can build a second, size-optimised flavour of the WebAssembly
Swift SDK. Setting `SWIFTWASM_HERMETIC_LTO=1` ships the Swift standard library,
the Swift runtime and the Foundation stack as **LLVM bitcode** inside their
static archives, compiled **without library evolution**, and tells the compiler
that every client of the standard library and the runtime is visible at the
final link.

`wasm-ld` then runs whole-program link-time optimisation over the application
plus the libraries and discards everything unreachable, including protocol
conformance records that the resilient standard library has to keep.

**Bitcode and sealing are two different things here.** Everything shipped as
bitcode takes part in the whole-program LTO: the standard library, the Swift
runtime, the Foundation stack (corelibs-foundation with the swift-foundation
sources, CoreFoundation, FoundationICU) and libxml2. But only the standard
library and the runtime are additionally *hermetically sealed*
(`-experimental-hermetic-seal-at-link`, which enables virtual-function and
witness-method elimination). Foundation is not sealed, because the compiler in
the pinned base snapshot asserts when it is: sealing makes it emit
virtual-method type ids, and it cannot map an *overriding* designated
initializer back to its base method, so
`swift-frontend` aborts in `typeIdForMethod` (`GenClass.cpp`) on
`NSMutableDictionary.init(sharedKeySet:)`. Foundation therefore still gets LTO
and dead-code elimination, just not devirtualisation-driven elimination. The
seal will be turned on for Foundation once that compiler bug is fixed upstream.

XCTest and swift-testing are neither bitcode nor sealed.

This variant is **binary-incompatible** with the normal Swift SDK. It exists
alongside it, never in place of it.

Please read [Known issues](#known-issues) before using it: as of this writing
the sealed standard library still fails 28 executable standard-library tests at
runtime, so the variant is not ready for production use.

## Measured results

From the first complete build of this flavour, against base snapshot
`swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a`:

| | normal SDK | this variant |
| --- | --- | --- |
| hello-world executable (`swift build`, unoptimised, unstripped) | 3,438,013 bytes | **1,347,818 bytes** |

Building and linking that hello-world from a clean scratch path took about
11 s wall clock against the variant, essentially all of it the LTO link.

The e2e suite (`./tools/build/run-e2e-test --scheme main`) is green against the
variant bundle: 5 passed, 2 unsupported (both pre-existing `REQUIRES: GH-5587`),
0 failed.

The artifact bundles themselves are large, because every archive carries
bitcode rather than object code:

```
swift-wasm-DEVELOPMENT-SNAPSHOT-hermetic-lto-wasm32-unknown-wasip1.artifactbundle.zip          231,208,410 bytes
swift-wasm-DEVELOPMENT-SNAPSHOT-hermetic-lto-wasm32-unknown-wasip1-threads.artifactbundle.zip  231,246,052 bytes
```

The bundle's `toolset.json` is unchanged from the normal SDK's — still just
`"swiftCompiler": { "extraCLIOptions": ["-static-stdlib"] }`.

## How to build it

```
$ SWIFTWASM_HERMETIC_LTO=1 ./tools/build/ci.sh main
```

or, step by step:

```
$ ./tools/build/install-build-sdk.sh main
$ ./tools/git-swift-workspace --scheme main
$ SWIFTWASM_HERMETIC_LTO=1 ./tools/build/build-toolchain --scheme main
$ SWIFTWASM_HERMETIC_LTO=1 ./tools/build/package-toolchain --scheme main --daily-snapshot
```

The variable must be set for **both** the build and the packaging step: the
build step selects the CMake flags, the packaging step selects the names.

The environment variable is read in exactly two places:

- `schemes/main/build/build-target-toolchain.sh`, which appends to
  `--extra-cmake-options`:

  ```
  -DSWIFT_STDLIB_ENABLE_LTO=full
  -DSWIFT_STDLIB_EXPERIMENTAL_HERMETIC_SEAL_AT_LINK=TRUE
  -DSWIFT_STDLIB_STABLE_ABI=FALSE
  ```

  `--extra-cmake-options` is appended last to the WASI stdlib configure, so
  these override the defaults in swift's `wasmstdlibhelpers.py`. The same
  block also passes `--wasi-swift-sdk-lto=full` to `utils/build-script`, which
  is what carries LTO into the Foundation stack; it deliberately does *not*
  pass `--wasi-swift-sdk-hermetic-seal-at-link` (see the note on sealing
  above).

- `tools/build/package-toolchain`, which inserts a `hermetic-lto-` infix before
  the target triple.

With the variable unset, the `utils/build-script` argument vector and every
derived name are identical to the default build.

### Output names

|                 | default flavour | hermetic LTO flavour |
| --------------- | --------------- | -------------------- |
| Swift SDK id    | `<version>-<triple>` | `<version>-hermetic-lto-<triple>` |
| artifact bundle | `swift-wasm-<channel>-SNAPSHOT-<triple>.artifactbundle.zip` | `swift-wasm-<channel>-SNAPSHOT-hermetic-lto-<triple>.artifactbundle.zip` |
| CI artifact     | `main-<triple>-artifactbundle` | `main-hermetic-lto-<triple>-artifactbundle` |

The infix is placed **before** the triple on purpose:
`tools/gh-distribute-toolchain` derives the release tag by stripping the
trailing `-<triple>` from the SDK id, so a suffix after the triple would leave
the triple in the tag.

Both triples (`wasm32-unknown-wasip1` and `wasm32-unknown-wasip1-threads`) are
built, because one `utils/build-script` invocation builds both from the same
CMake flags.

In CI the variant is a separate matrix entry, "Swift SDK (hermetic LTO)", with
its own sccache key. Only the `main` scheme has it; release schemes do not.

## What it is incompatible with

- **No resilient standard library.** `SWIFT_STDLIB_STABLE_ABI=FALSE` removes
  library evolution from the standard library, so a binary built against this
  SDK is only valid against this exact SDK build. Do not mix object files,
  static archives or `.swiftmodule`s produced against the normal SDK with ones
  produced against this variant.
- **Static linking only.** Hermetic seal at link assumes there is no
  out-of-image client. Dynamic libraries are not supported (WebAssembly builds
  here are all-static anyway).
- **`-enable-library-evolution` is rejected together with hermetic seal.** The
  frontend refuses the combination, so application or package modules that you
  want sealed must not be built with library evolution. Modules that need
  library evolution can still be built normally; they simply do not get sealed.
- **Not for ABI-stability testing.** Anything that measures or asserts ABI
  stability, mangling stability across builds, or `swiftinterface`
  round-tripping against the standard library will not behave as it does with
  the normal SDK.
- **XCTest and swift-testing are untouched** by this flavour: they stay native
  and unsealed, because they are not part of a shipped product. Tests still
  build and run against the variant.

## Known issues

These are all open as of the first complete build of this flavour. The first
one means the variant **must not be used for production builds yet**.

### The sealed standard library traps at runtime in some generic code

28 of the 466 standard-library and concurrency-runtime tests selected by the
filtered executable lit run fail against the variant (233 pass, 204 are
unsupported, 1 fails expectedly). Every one of the 28 is a *runtime* failure,
not a compile failure; 24 of them are
`Trap: indirect call to null element (uninitialized element 0)`, i.e. a call
through a function-table slot that link-time elimination emptied while a live
path still reaches it.

It reproduces in five lines:

```swift
func mfw<T: FixedWidthInteger>(_ a: T, _ b: T) -> (high: T, low: T.Magnitude) {
  return a.multipliedFullWidth(by: b)
}
let r = mfw(UInt128(1234567890), UInt128(987654321))
print(r.high, r.low)
```

That program traps against the variant, prints the correct answer against the
normal SDK built from the same base snapshot, and prints the correct answer
against the variant when linked with `-Xlinker --lto-O0`. So it is not a
wasm32, WasmKit or snapshot regression, and it is not symbol resolution: it is
an LTO-pipeline optimisation over the sealed bitcode — most likely
virtual-function or witness-method elimination, or whole-program
devirtualisation — removing something a live path still calls.

Under investigation. Which of the two settings is responsible
(`SWIFT_STDLIB_ENABLE_LTO=full` or
`SWIFT_STDLIB_EXPERIMENTAL_HERMETIC_SEAL_AT_LINK=TRUE`) has not been determined
yet; that needs one more standard-library build with the seal turned off.

### Application-wide LTO does not autolink on WebAssembly

Compiling your *own* modules with `-lto=` and a stock toolchain produces
bitcode objects that carry no autolink information the linker can use, so no
Swift runtime archive is pulled into the link at all and it fails with a very
large number of undefined symbols (`swift_release`, `swift_retain`,
`_swiftEmptyArrayStorage`, ...).

The cause is upstream and needs two changes, one on each side: Swift's IRGen
emits `!llvm.dependent-libraries` metadata only when the output object format
is ELF and LTO is on, so for Wasm it emits nothing usable; and `wasm-ld` does
not read that metadata out of bitcode even when it is present. Until both land,
an application that compiles its own modules with `-lto=` has to pass the
needed `-l` archives explicitly on the link line. The exact set can be derived
by building the same package once *without* LTO and reading the autolink
entries out of the resulting native objects.

Applications that use the variant without `-lto=` on their own modules are not
affected: their objects are native, autolink works as usual, and the library
side still gets LTO.

### The link is single-threaded by default

The static-executable response file the Swift driver uses for WASI passes
`--threads=1` to `wasm-ld`, which makes the LTO link serial. That is fine for
a normal build and expensive here, where the link is a whole-program compile.
Pass `-Xlinker --threads=N` from your own toolset to override it. The default
is upstream's call and is deliberately left alone in this repository.

## Recommended application flags

Nothing is mandatory: `wasm-ld` recognises bitcode archive members by itself,
and `toolset.json` in the bundle is byte-identical to the normal SDK's. The
following are recommendations, deliberately *not* baked into the SDK — flags in
an SDK toolset leak into host-side macro and plugin builds, where they are
wrong.

Put them in your own package's toolset, or pass them on the command line:

- `-lto=llvm-full` for your own modules, so the application is optimised
  together with the sealed library rather than merely against it. Note that
  this currently requires spelling out the runtime archives to link; see
  [Known issues](#known-issues).
- `-Xlinker --lto-O1` — LTO codegen optimisation level at link time. `--lto-O2`
  and above cost a lot of link time for little size.
- `-Xlinker --gc-sections` — discard unreferenced sections.
- `-Xlinker --threads=N` — **important.** The static-executable response file
  used by the Swift driver for WASI passes `--threads=1`, which makes the LTO
  link single-threaded and very slow. Overriding it from your own toolset is
  the supported workaround; the default itself is upstream's call and is left
  alone here.

Then post-process the wasm in two steps rather than one:

```
$ wasm-opt --strip-dwarf -o app.stripped.wasm app.wasm
$ wasm-opt -Os -o app.opt.wasm app.stripped.wasm
```

Stripping DWARF first keeps `wasm-opt -Os` from spending time and memory
rewriting debug information it is about to discard, and avoids `wasm-opt`
running out of memory on large modules.

## Link-time expectations

Full LTO means the link is a compile: `wasm-ld` reads bitcode for the whole
standard library, runtime and Foundation and generates code once. Expect the
link step to dominate the build, and expect it to want memory proportional to
the whole program rather than to a single module. This is why `--threads=N` and
`--lto-O1` matter so much more here than in a normal build.

Incremental development against this SDK is therefore noticeably slower per
link. Use the normal SDK while iterating and the variant for release-shaped
builds and size measurements.

## Carried patches

`schemes/main/swift/` carries the patches this flavour needs on top of the base
snapshot pinned in `schemes/main/manifest.json`. Per
[docs/upstreaming.md](./upstreaming.md), each has an upstream pull request and
is dropped as soon as that pull request is in the pinned snapshot.

| Patch | What it does | Upstream | Removal condition |
| ----- | ------------ | -------- | ----------------- |
| `0001-stdlib-Pair-hermetic-seal-at-link-with-the-selected-stdlib-LTO-mode.patch` | Emits the matching `-lto=llvm-full` / `-lto=llvm-thin` inside the hermetic-seal block of `stdlib/cmake/modules/SwiftSource.cmake`, and raises a `FATAL_ERROR` for any other LTO value. The frontend rejects `-experimental-hermetic-seal-at-link` without an `-lto=` mode, and upstream computes the two in different CMake functions with no guard. | [swiftlang/swift#90654](https://github.com/swiftlang/swift/pull/90654) | merged into the pinned base snapshot |
| `0002-build-script-Add-WASI-Swift-SDK-LTO-options.patch` | Adds `--wasi-swift-sdk-lto` and `--wasi-swift-sdk-hermetic-seal-at-link` to `utils/build-script`, threading LTO flags into the Foundation stack (corelibs-foundation with the swift-foundation sources, CoreFoundation, FoundationICU, libxml2). `SWIFT_STDLIB_ENABLE_LTO` never reaches those; they are separate CMake projects with their own flags. With an LTO mode selected it also points `CMAKE_AR`/`CMAKE_RANLIB` at `--native-llvm-tools-path` (GNU `ar` cannot index bitcode produced by a newer LLVM than its plugin and silently writes an incomplete symbol table) and defines `FOUNDATION_DISABLE_SWIFT_SPLIT_COMPILATION`. | upstream PR to be opened by the maintainer (prepared on branch `katei/wasi-swift-sdk-lto-option`) | merged into the pinned base snapshot |

`schemes/main/swift-corelibs-foundation/` and `schemes/main/swift-foundation/`
carry one patch each; `tools/git-swift-workspace` applies
`schemes/<scheme>/<repo>` for every repository it knows about, so the directory
name is the update-checkout repository name.

| Patch | What it does | Upstream | Removal condition |
| ----- | ------------ | -------- | ----------------- |
| `swift-corelibs-foundation/0001-cmake-Allow-opting-out-of-the-CMP0157-Swift-split-compilation-model.patch` | Makes the `cmake_policy(SET CMP0157 NEW)` line conditional on `FOUNDATION_DISABLE_SWIFT_SPLIT_COMPILATION`. CMake's Swift split-compilation model drives the compiler with an output-file-map naming only `object` outputs; under `-lto=` the driver emits LLVM bitcode, ignores those entries and derives `<basename>.bc` names in the working directory, so the object files CMake declared are never created and the archive step fails with `error opening input file ... .swift.obj`. Opting out restores the one-step compile-and-archive rule, where the driver names and archives its own outputs. The default is unchanged. | upstream PR to be opened by the maintainer | merged into the pinned base snapshot, or fixed in swift-driver / CMake so that split compilation and `-lto=` work together |
| `swift-foundation/0001-cmake-Allow-opting-out-of-the-CMP0157-Swift-split-compilation-model.patch` | The same one-line change in `swift-foundation`, whose sources are built by the same configure. | upstream PR to be opened by the maintainer | as above |

## Why full LTO and not thin

Thin LTO would link faster and use far less memory, but `swift-frontend` does
not currently emit ThinLTO bitcode when it is asked for an object file: the
ThinLTO bitcode writer is wired only into the LLVM-bitcode output kind in
`lib/IRGen/IRGen.cpp`. With `-lto=llvm-thin -c` the frontend silently emits a
native object, so a thin variant of this SDK would ship a standard library that
is not bitcode at all and would get no LTO.

Fixing that is a compiler change, and this repository cannot patch the
compiler: CI uses a stock swift.org snapshot as the host compiler and builds
only the target side. So a thin flavour is blocked on that upstream compiler
change, and full LTO is what this variant offers. Full LTO also measured
smaller than thin in the earlier hello-world measurement.
