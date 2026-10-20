# Hermetic full-LTO Swift SDK variant

The `main` scheme can build a second, size-optimised flavour of the WebAssembly
Swift SDK. Setting `SWIFTWASM_HERMETIC_LTO=1` ships every library in the SDK -- the
Swift standard library, the Swift runtime, the Foundation stack, swift-testing
and XCTest -- as **LLVM bitcode** inside their static archives, compiled
**without library evolution**, and tells the compiler that every client of them
is visible at the final link.

`wasm-ld` then runs whole-program link-time optimisation over the application
plus the libraries and discards everything unreachable, including protocol
conformance records that the resilient standard library has to keep.

Every Swift library in the SDK is both bitcode and *hermetically sealed*
(`-experimental-hermetic-seal-at-link`, which enables virtual-function and
witness-method elimination): the standard library, the Swift runtime, the
Foundation stack (corelibs-foundation with the swift-foundation sources,
CoreFoundation, FoundationICU), swift-testing and XCTest. The C and C++ pieces
(libxml2, CoreFoundation's C sources, `_TestingInternals`) get `-flto=full`,
which is all the seal means for a language with no witness tables. Every
library therefore emits the dispatch thunks a sealed client calls, and a test
executable can meet the link contract like any other program.

swift-testing is additionally built **without library evolution** and installs
binary `.swiftmodule` files instead of `.swiftinterface` ones -- see
[Carried patches](#carried-patches). A resilient module cannot be sealed: the
driver rejects `-enable-library-evolution` together with
`-experimental-hermetic-seal-at-link`.

This variant is **binary-incompatible** with the normal Swift SDK. It exists
alongside it, never in place of it.

## The link contract

**Every Swift module that ends up in the link must be compiled with
`-experimental-hermetic-seal-at-link -lto=llvm-full`.** This is a requirement
for *correctness*, not a size preference, and it is the single most important
thing to know about this SDK.

The hermetic seal is a whole-program contract. It makes IRGen attach
virtual-function-elimination metadata to every witness table and vtable and
lower witness-method dispatch to `llvm.type.checked.load`. At link time
GlobalDCE keeps only the table slots for which it can see a matching checked
load. A module compiled *without* the seal dispatches through an ordinary load
that GlobalDCE cannot see, so it concludes the witness is dead and writes a
null into the slot -- and on WebAssembly a null function pointer is table index
0, so the program traps with `indirect call to null element` the first time it
reaches that requirement through unspecialised generic code. It is a
miscompile, not a missed optimisation.

The bundle's `toolset.json` therefore carries the contract, so that a normal
SwiftPM build gets it automatically:

```jsonc
{
  "swiftCompiler": { "extraCLIOptions": [
    "-static-stdlib",
    "-experimental-hermetic-seal-at-link",
    "-lto=llvm-full"
  ] },
  "linker": { "extraCLIOptions": [
    "-lswiftSwiftOnoneSupport", "-lswiftCore", "-lswiftObservation", ...
    "-lwasi-emulated-getpid", "-lwasi-emulated-mman", "-lwasi-emulated-signal",
    "-lxml2"
  ] }
}
```

Two things follow, and both are unavoidable today:

- **SwiftPM has to be told about the LTO mode as well**: build with
  `swift build --experimental-lto-mode=full`. With an LTO mode selected the
  driver writes LLVM bitcode, and SwiftPM only names its object files `.bc`
  (and hands them to the link) when its *own* flag is set. Without it an
  executable target fails with
  `clang: error: no such file or directory: '<module>.swift.o'`. The SDK
  toolset has no way to set a SwiftPM build setting.
- **`-lto=llvm-thin` is not an alternative.** A ThinLTO client cannot link
  against this SDK at all: `wasm-ld: error: inconsistent LTO Unit splitting
  (recompile with -fsplit-lto-unit)`. The sealed standard library is a
  full-LTO, split-LTO-unit module and the stock frontend does not emit ThinLTO
  bitcode for object output at all (see
  [Why full LTO and not thin](#why-full-lto-and-not-thin)).

The explicit `-l` list in `linker.extraCLIOptions` is there because a bitcode
client cannot autolink on WebAssembly with a stock toolchain: under `-lto=` the
client's objects are bitcode and carry no autolink information the linker
reads, so the `@*.autolink` response file the Swift driver normally builds with
`swift-autolink-extract` is empty and *no* Swift runtime archive reaches the
link (`static-executable-args.lnk` names only `-lswiftSwiftOnoneSupport`). The
SDK therefore names its own archives; `tools/build/package-toolchain` derives
the list from what the bundle actually ships, so it stays correct as the SDK's
contents change. The upstream fixes are pending on both sides -- Swift's IRGen
emitting `!llvm.dependent-libraries` for Wasm under LTO, and `wasm-ld` reading
it out of bitcode.

Please read [Known issues](#known-issues) before using it.

## Measured results

Against base snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a`, with the link
contract in force (which is what the toolset now does automatically):

| | normal SDK | this variant |
| --- | --- | --- |
| hello-world executable (`swift build`, unoptimised, unstripped) | 3,438,013 bytes | **2,394,531 bytes** |

Building and linking that hello-world from a clean scratch path took about
19 s wall clock against the variant, essentially all of it the LTO link.

An earlier measurement of the same program against this flavour reported
1,347,818 bytes, but that build did not honour the contract -- it was smaller
precisely because GlobalDCE had removed witness entries it should have kept.
Do not compare against it.

The e2e suite (`./tools/build/run-e2e-test --scheme main`) is green against the
variant bundle: 6 passed, 1 unsupported, 0 failed. The one unsupported is the
pre-existing `REQUIRES: GH-5587` skip on `clang-module.swift`.

The artifact bundles themselves are large, because every archive carries
bitcode rather than object code:

```
swift-wasm-DEVELOPMENT-SNAPSHOT-hermetic-lto-wasm32-unknown-wasip1.artifactbundle.zip          232,718,898 bytes
swift-wasm-DEVELOPMENT-SNAPSHOT-hermetic-lto-wasm32-unknown-wasip1-threads.artifactbundle.zip  232,748,369 bytes
```

## How to build it

> **This flavour needs a base compiler that carries the pending frontend
> fixes.** Sealing the Foundation stack makes the pinned 2026-08-30-a
> `swift-frontend` abort in `typeIdForMethod` (`GenClass.cpp`) on
> `NSMutableDictionary`'s overriding designated initializer, and in
> `addVTableTypeMetadata` (`GenMeta.cpp`) on an imported CF type. Both fixes
> are in a compiler patch series prepared for upstreaming and are **not** in
> any released snapshot yet, so the flavour only builds against a toolchain
> that contains them. Point the build at one with
> `SWIFTWASM_PREVIEW_TOOLCHAIN_URL` (the `preview_toolchain_url` input of
> `.github/workflows/build-toolchain.yml`), or, for a local build tree, with
> `--swift-bin` / `--clang-bin` / `--llvm-bin` on
> `schemes/main/build/build-target-toolchain.sh`. Once a pinned snapshot
> contains the fixes this note can be deleted.

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
  block also passes `--wasi-swift-sdk-lto=full` and
  `--wasi-swift-sdk-hermetic-seal-at-link` to `utils/build-script`, which is
  what carries LTO and the seal into the libraries that are built as their own
  CMake projects: the Foundation stack, swift-testing and XCTest.

- `tools/build/package-toolchain`, which inserts a `hermetic-lto-` infix before
  the target triple *and* post-processes each generated
  `<bundle>/<sdk-id>/<triple>/toolset.json` to carry the link contract (the two
  compiler flags and the explicit runtime-archive `-l` list). The `-l` list is
  derived from the archives the bundle actually ships rather than hardcoded;
  `embedded-toolset.json` is left as generated, because embedded Swift does not
  use those archives. `./tools/build/package-toolchain --self-test` checks that
  merge without needing a build tree.

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
- **swift-testing has no library evolution here.** The `Testing`,
  `_TestDiscovery`, `_TestingInterop` and `_Testing_Foundation` modules are
  shipped as binary `.swiftmodule` files rather than `.swiftinterface` files,
  so they are only usable with the compiler that built them -- the same
  constraint the standard library already has in this flavour.

## Known issues

### Running tests needs a preopened directory, and XCTest needs `--build-system native`

Both are pre-existing wasm problems, not consequences of this flavour: they
reproduce identically against the **normal** Swift SDK.

`XCTMain` reads `Bundle.main`, and on WASI `Bundle.main` traps when the runtime
has no preopened directory:

```
wasm trap: wasm `unreachable` instruction executed
    0: $s10Foundation6BundleC05_mainB0...LL_WZ
    1: swift::threading_impl::once_slow(...)
    2: $s6XCTest11XCTMainMisc_9arguments9observers...
```

Run the test binary with `wasmtime run --dir . <binary>` (any preopen will do).
swift-testing does not touch `Bundle.main` and runs without one.

SwiftPM's newer `swiftbuild` build system produces a test runner that discovers
**zero** XCTest cases on wasm; `swift build --build-system native --build-tests`
discovers them correctly. swift-testing discovery works under both.

Note also that swift-testing writes its report to **stderr**, so a pipeline that
checks its output needs `2>&1 |`.

### Autolinking still has to be spelled out for libraries the SDK does not ship

Under `-lto=` a stock toolchain emits no autolink information the linker can
read out of WebAssembly bitcode, so nothing is pulled from an archive unless it
is named on the link line. The SDK's own archives are **handled by the
toolset** (see [The link contract](#the-link-contract)). Any *other* autolinked
library -- a C library your package depends on, a system library a third-party
package expects to be picked up automatically -- has to be passed by hand with
`-Xlinker -l<name>`, plus `-Xlinker -L<dir>` if it is not on the default search
path.

The cause is upstream and needs two changes, one on each side: Swift's IRGen
emits `!llvm.dependent-libraries` metadata only when the output object format
is ELF and LTO is on, so for Wasm it emits nothing usable; and `wasm-ld` does
not read that metadata out of bitcode even when it is present. Until both land,
the explicit list is the only option. If you need to work out the list for a
package, build it once *without* LTO and run `swift-autolink-extract` over the
resulting native objects.

### The link is single-threaded by default

The static-executable response file the Swift driver uses for WASI passes
`--threads=1` to `wasm-ld`, which makes the LTO link serial. That is fine for
a normal build and expensive here, where the link is a whole-program compile.
Pass `-Xlinker --threads=N` from your own toolset to override it. The default
is upstream's call and is deliberately left alone in this repository.

### Resolved: `swift test` and Foundation dispatch thunks

Earlier revisions of this document said that `swift test` was unsupported and
that Foundation APIs dispatching through `open` class members could not link
(`undefined symbol: $s10Foundation6BundleC10bundlePathSSvgTj`). Both were the
same defect seen from two sides: a library that is not sealed emits no dispatch
thunks, and a sealed client calls them.

Both are gone. The Foundation stack is sealed -- which needed several
`swift-frontend` fixes (a `typeIdForMethod` assertion on overriding designated
initializers, a foreign-class context descriptor without a vtable, and a
`DISubprogram` nesting problem), all of which are in the base toolchain this
SDK is built with rather than in this repository -- and so are swift-testing
and XCTest, so every library in the SDK defines the thunks its clients call. The
three `UNSUPPORTED: hermetic-lto` markers on `test/swift-sdk/foundation/*.swift`
have been removed and those tests pass, and a sealed swift-testing executable --
including one built by `swift build --build-tests` -- runs its tests and reports
failures correctly.

### Resolved: the sealed standard library trapping at runtime

The first complete build of this flavour failed 28 of the 466 standard-library
and concurrency-runtime tests selected by the filtered executable lit run, 24
of them with `Trap: indirect call to null element (uninitialized element 0)`,
and it reproduced in five lines:

```swift
func mfw<T: FixedWidthInteger>(_ a: T, _ b: T) -> (high: T, low: T.Magnitude) {
  return a.multipliedFullWidth(by: b)
}
let r = mfw(UInt128(1234567890), UInt128(987654321))
print(r.high, r.low)
```

That was the unmet link contract, not a miscompiled library: the test
executables were built unsealed against a sealed standard library, so GlobalDCE
nulled the witness-table slots they dispatched through. The same program built
under the contract prints the right answer. The toolset now enforces the
contract for SwiftPM builds, so this is resolved for anything that goes through
`swift build`; anything that compiles Swift by hand has to pass the two flags
itself.

The escape hatch for code that genuinely cannot be sealed is
`-Xlinker --mllvm=-enable-vfe=false`, which turns virtual-function elimination
off for the whole link. It works with unsealed clients and costs roughly 40% of
the binary, i.e. most of what the seal buys.

## Application build flags

The link contract is not optional and is already in the toolset; see
[The link contract](#the-link-contract). Beyond it, and beyond the
`--experimental-lto-mode=full` that SwiftPM needs, these are worth setting:

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
| `0003-build-script-Build-the-WASI-Swift-SDK-test-libraries-with-LTO.patch` | Extends the two options above to `helpers.build_swift_testing()` and `helpers.build_xctest()`, which previously got no flags at all and shipped native, unsealed archives. `_TestingInternals` is C++ and needs `-flto=` too. When the seal is requested it also passes `SwiftTesting_ENABLE_LIBRARY_EVOLUTION=FALSE`, and it defines `SwiftTesting_DISABLE_SWIFT_SPLIT_COMPILATION` next to the Foundation one. | upstream PR to be opened by the maintainer | merged into the pinned base snapshot |

`schemes/main/swift-corelibs-foundation/`, `schemes/main/swift-foundation/` and
`schemes/main/swift-testing/` carry one patch each; `tools/git-swift-workspace`
applies `schemes/<scheme>/<repo>` for every repository it knows about, so the
directory name is the update-checkout repository name.

| Patch | What it does | Upstream | Removal condition |
| ----- | ------------ | -------- | ----------------- |
| `swift-corelibs-foundation/0001-cmake-Allow-opting-out-of-the-CMP0157-Swift-split-compilation-model.patch` | Makes the `cmake_policy(SET CMP0157 NEW)` line conditional on `FOUNDATION_DISABLE_SWIFT_SPLIT_COMPILATION`. CMake's Swift split-compilation model drives the compiler with an output-file-map naming only `object` outputs; under `-lto=` the driver emits LLVM bitcode, ignores those entries and derives `<basename>.bc` names in the working directory, so the object files CMake declared are never created and the archive step fails with `error opening input file ... .swift.obj`. Opting out restores the one-step compile-and-archive rule, where the driver names and archives its own outputs. The default is unchanged. | upstream PR to be opened by the maintainer | merged into the pinned base snapshot, or fixed in swift-driver / CMake so that split compilation and `-lto=` work together |
| `swift-foundation/0001-cmake-Allow-opting-out-of-the-CMP0157-Swift-split-compilation-model.patch` | The same one-line change in `swift-foundation`, whose sources are built by the same configure. | upstream PR to be opened by the maintainer | as above |
| `swift-testing/0001-cmake-Add-an-option-to-build-without-library-evolution.patch` | Adds `SwiftTesting_ENABLE_LIBRARY_EVOLUTION` (default `YES`). When `NO`, the testing library and its overlays drop `-enable-library-evolution`, stop emitting `.swiftinterface` files, install the binary `.swiftmodule` instead, and install the `_TestingInternals` Clang module (a binary module records every module it imports; an interface does not, which is why the resilient configuration never needed it). Sealing and library evolution are mutually exclusive in the driver. The patch also adds `SwiftTesting_DISABLE_SWIFT_SPLIT_COMPILATION`, the CMP0157 opt-out that swift-corelibs-foundation already has. | upstream PR to be opened by the maintainer | merged into the pinned base snapshot |

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
