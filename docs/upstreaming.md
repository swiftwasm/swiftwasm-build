# Upstreaming to [`apple/swift`](https://github.com/apple/swift/)

One of the goals of SwiftWasm is to upstream our changes to [`apple/swift`](https://github.com/apple/swift/) as much as possible.
This document describes our upstreaming process and how we should keep our friendly fork.

## Our current status

We are maintaining several patches in [`swiftwasm/swiftwasm-build`](https://github.com/swiftwasm/swiftwasm-build/tree/main/schemes/main/swift).
We had been maintaining a fork of [`apple/swift`](https://github.com/apple/swift) before, but we stopped it because we already have upstreamed most of our changes, and it is hard to maintain the fork for several reasons (See [faq.md](./faq.md) for details).

Most of our patches are ready to be upstreamed, but some of them marked as `HACK` are not ready yet.

## Getting started with Swift compiler development

If you are new to Swift compiler development, please read [Getting Started with Swift Development](https://github.com/apple/swift/blob/main/docs/HowToGuides/GettingStarted.md)

## Upstreaming Process

1. Check if the patch is already upstreamed or not. Some patches are already upstreamed but nightly snapshot tag can be not updated yet.
2. If the patch is not upstreamed yet and ready to be upstreamed, create a PR to [`apple/swift`](https://github.com/apple/swift).
3. Test the PR in [`ci.swift.org`](https://ci.swift.org/) and [`ci-external.swift.org`](https://ci-external.swift.org/). Use the following CI command:

   ```
   @swift-ci Please smoke test
   ```
   ```
   preset=buildbot_incremental_linux_crosscompile_wasm
   @swift-ci Please test with preset Linux Platform
   ```
4. If the CI is green and got approval from the upstream reviewers, merge the PR.
5. Ensure that the patch does not break the CI. If it breaks the CI, revert the commit or fix it ASAP.

## What we should keep in green ✅

1. ci.swift.org: Jenkins CI hosted by Apple and used to test every PR and the latest `main` branch commit of [`apple/swift`](https://github.com/apple/swift).
2. [WebAssembly cross-compiler test in ci-external.swift.org](https://ci-external.swift.org/job/oss-swift-RA-linux-ubuntu-20.04-webassembly/): Jenkins CI hosted by SwiftWasm but joins the Apple's Swift CI system. Run tests for the latest `main` branch commit of [`apple/swift`](https://github.com/apple/swift). The CI status is notified in SwiftWasm Discord server.

If our upstreaming commits break ci.swift.org, we should revert the commit or fix it ASAP.

## Milestones

1. Upstream compiler patches

   If we upstream all of our compiler patches, we can stop building our own compiler and use the official Swift compiler instead.
   After that, we can focus on building standard library and save much time.

2. Upstream standard library patches
3. Set up WebAssembly check in ci.swift.org and make it mandatory to pass the check to merge a PR like [the Windows check](https://ci-external.swift.org/job/swift-PR-windows/)

## Checkout-build-edit-test cycle

Building the Swift toolchain is a time-consuming process. We recommend to use powerful machine or cloud service to build the toolchain. (FYI: [Yuta](https://github.com/kateinoigakukun) usually uses [CPX51 by Hetzner](https://pcr.cloud-mercato.com/providers/hetzner/flavors/cpx51))

Please basically follow the [README](../README.md) process to set up the build environment.

### Checkout

If it's first time to build or patch files are changed, you need to checkout the source code:

```
./tools/git-swift-workspace --scheme main
```

### Build

If you want to build the whole toolchain, run the following command:

```
./tools/build/build-toolchain.sh
```

If you already built the compiler and want to build only the standard library for WebAssembly, run the following command:

```
./tools/build/build-toolchain.sh --skip-build-host-toolchain
```

### Edit

If you want to add a new patch, edit the Swift source code and commit it on the current branch, which is created by `git-swift-workspace` and includes our existing patches.

If you want to edit an existing patch (e.g. to resolve conflicts with upstream changes, or to improve the patch), please edit the commit history by `git rebase -i`.

After editing the source code, you need to rebuild the toolchain, and if you are sure that the patch is OK, you can update our `.patch` files by the follwoing command:

```
./tools/git-swift-update-patch --scheme main
```


### Test

The above build command does not run tests. If you want to run tests, run the following command:

```
ninja -C ../build/WebAssembly/swift-stdlib-wasi-wasm32 check-swift-wasi-wasm32-custom
```
