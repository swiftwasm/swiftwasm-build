# Hermetic full-LTO Swift SDK variant

The `main` scheme can build a second, size-optimised flavour of the WebAssembly
Swift SDK. Setting `SWIFTWASM_HERMETIC_LTO=1` ships the Swift standard library,
the Swift runtime and the Foundation stack as **LLVM bitcode** inside their
static archives, compiled **without library evolution** and with the compiler
told that every client of the library is visible at the final link.

`wasm-ld` then runs whole-program link-time optimisation over the application
plus the libraries and discards everything unreachable, including protocol
conformance records that the resilient standard library has to keep. An earlier
measurement of a hello-world program with this configuration shrank the
executable from 3,438,013 bytes to 1,693,294 bytes.

This variant is **binary-incompatible** with the normal Swift SDK. It exists
alongside it, never in place of it.

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

  and nothing else. `--extra-cmake-options` is appended last to the WASI stdlib
  configure, so these override the defaults in swift's `wasmstdlibhelpers.py`.

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

## Recommended application flags

Nothing is mandatory: `wasm-ld` recognises bitcode archive members by itself,
and `toolset.json` in the bundle is byte-identical to the normal SDK's. The
following are recommendations, deliberately *not* baked into the SDK — flags in
an SDK toolset leak into host-side macro and plugin builds, where they are
wrong.

Put them in your own package's toolset, or pass them on the command line:

- `-lto=llvm-full` for your own modules, so the application is optimised
  together with the sealed library rather than merely against it.
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
| `0002-build-script-Add-WASI-Swift-SDK-LTO-options.patch` | Adds `--wasi-swift-sdk-lto` and `--wasi-swift-sdk-hermetic-seal-at-link` to `utils/build-script`, threading LTO flags into the Foundation stack (corelibs-foundation with the swift-foundation sources, CoreFoundation, FoundationICU, libxml2). `SWIFT_STDLIB_ENABLE_LTO` never reaches those; they are separate CMake projects with their own flags. | upstream PR to be opened by the maintainer (prepared on branch `katei/wasi-swift-sdk-lto-option`) | merged into the pinned base snapshot |

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
