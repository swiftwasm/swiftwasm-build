# SwiftWasm toolchain build

This repository contains the patches, build scripts, and CI configuration for the SwiftWasm toolchain.

## Building the toolchain

```
$ git clone https://github.com/swiftwasm/swiftwasm-build
$ cd swiftwasm-build
# Install WebAssembly specific dependencies into ../build-sdk
$ ./tools/build/install-build-sdk.sh main
# Checkout the Swift repositories and apply patches
$ ./tools/git-swift-workspace --scheme main
# Build the toolchain (this will take a while)
$ ./tools/build/build-toolchain.sh
```

See [SwiftWasm book](https://book.swiftwasm.org/contribution-guide/how-to-build-toolchain.html) for more details about dependencies you need to install and how to build on Docker.

## Project structure

- `schemes/<scheme>` - Scheme is the concept used in [Swift's `utils/update-checkout` script](https://github.com/apple/swift/blob/main/utils/update-checkout) to describe a set of build sources.
- `schemes/<scheme>/manifest.json` - The manifest file for the scheme, which describes the base source revisions to check out.
- `schemes/<scheme>/swift` - Patches to be applied on top of the checked out Swift repository. This is where the SwiftWasm-specific patches live. Most of them are ready to be upstreamed, but patches marked with `HACK` need modification or another solution.
- `tools/git-swift-workspace` - A tool to check out the Swift repositories and apply patches.
- `tools/git-swift-update-patch` - A tool to help daily patch maintenance.
- `tools/build` - Scheme agnostic build scripts.

## Contributing

See [docs/upstreaming.md](docs/upstreaming.md) for more details.
