# Release workflow for the toolchain

We are publishing two types of our toolchain binaries to [GitHub Releases](https://github.com/swiftwasm/swift/releases), one is nightly snapshot release, and the other one is officially versioned release.

## Nightly snapshot release

We are publishing nightly snapshot releases if we have any new changes in the toolchain. The release is usually triggered by [the CI workflow](https://github.com/swiftwasm/swift/blob/swiftwasm-distribution/.github/workflows/nightly-distribution.yml) every midnight in GMT.

We can also trigger the release manually by running the following command:

```bash
$ gh workflow run manual-distribution.yml --repo swiftwasm/swift -f scheme=main -f run-id=latest
```

## Officially versioned release

We usually publish a versioned release once the upstream officially releases a new version of Swift.

> **Note**
> The upstream usually releases a new version in March and September every year and cut a new release branch for the next version in March and November.

The release process starts when the upstream cuts a new release branch and the first snapshot for the release branch is published.
We are usually doing the following steps:

1. Create a new release scheme in [swiftwasm-build's `./schemes` directory](https://github.com/swiftwasm/swiftwasm-build/tree/main/schemes) by copying the patches from `main` scheme at the moment.
    ```console
    $ cp -r schemes/main schemes/release-5.x
    ```
2. Update `schemes/<release-scheme>/manifest.json`
    - `base-tag` field should be updated to the tag of the new release branch.
    - `update-checkout-scheme` field should be updated to the one passed to `--scheme` option of [`utils/update-checkout`](https://github.com/swiftlang/swift/blob/main/utils/update-checkout) script.
    - `swift-org-download-channel` field should be updated to the new release branch.
        e.g. If a download link of a new release snapshot is "https://download.swift.org/swift-6.1-branch/xcode/swift-6.1-DEVELOPMENT-SNAPSHOT-2024-11-19-a/swift-6.1-DEVELOPMENT-SNAPSHOT-2024-11-19-a-osx.pkg", the value should be "swift-6.1-branch".
3. Update `.github/scripts/build-matrix.rb` to pin the builder container image version for the new release scheme:
3. Update CI configuration to build the new release scheme:
    - [`.github/workflows/nightly-distribution.yml`](https://github.com/swiftwasm/swift/blob/0895044e2ba31ccd1aade8068088b1fd3137fffb/.github/workflows/nightly-distribution.yml#L8-L11)

Once the upstream publishes their official release, we are doing the following steps:

1. Update `schemes/<release-scheme>/manifest.json`
    - `base-tag` field should be updated to the tag of the official release.
    - `swift-org-download-channel` field should be updated to the new release branch.
        e.g. If a download link of a new release is `https://download.swift.org/swift-6.0.2-release/xcode/swift-6.0.2-RELEASE/swift-6.0.2-RELEASE-osx.pkg`, the value should be "swift-6.0.2-release".
2. Quality assurance of our latest release candidate snapshot toolchain
    1. Check core libraries and tools we are maintaining work properly with the toolchain. List of the libraries and tools we are maintaining:
        - [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit): See [the past PR](https://github.com/swiftwasm/JavaScriptKit/pull/227)
        - [carton](https://github.com/swiftwasm/carton): See [the past PR](https://github.com/swiftwasm/carton/pull/398)
        - [switwasm-docker](https://github.com/swiftwasm/swiftwasm-docker): Add a new Docker image for the new release if it's major release. Update the existing Docker image if it's minor release.
        - [swiftwasm-action](https://github.com/swiftwasm/swiftwasm-action): Update the base carton image version.
        - [setup-swiftwasm](https://github.com/swiftwasm/setup-swiftwasm): Update the default toolchain version.
    2. Collect feedback from the community by asking them to try a release candidate snapshot.
3. Once we are ready to release, trigger GitHub Actions workflow by running the following command:

    ```console
    $ gh workflow run manual-distribution.yml --repo swiftwasm/swift -f scheme=6.3 -f run-id=<replace-run-id> -f override-name=swift-wasm-6.3.0-RELEASE -f display_name="Swift for WebAssembly 6.3.0 Release $(date +'%Y-%m-%d')" -f display_name_short="Swift for WebAssembly 6.3.0 Release"
    ```

    Please replace `6.3` with the version number you are releasing and `<replace-run-id>` with the run ID of [the GitHub Actions workflow in `swiftwasm/swiftwasm-build`](https://github.com/swiftwasm/swiftwasm-build/actions/workflows/build-toolchain.yml)

3. Once the workflow is finished, the release will be published to [GitHub Releases](https://github.com/swiftwasm/swift/releases)
4. Release new versions of the libraries and tools.
    - [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit): Create a new git tag and publish a new release on GitHub.
    - [switwasm-docker](https://github.com/swiftwasm/swiftwasm-docker): Docker images will be automatically published after committing the changes to the `main` branch.
    - [carton](https://github.com/swiftwasm/carton): Create a new git tag and publish a new release on GitHub. Also release a new version of the Homebrew formula by following [the release guide](https://github.com/swiftwasm/homebrew-tap/blob/main/Docs/RELEASE_MANUAL.md)
    - [swiftwasm-action](https://github.com/swiftwasm/swiftwasm-action): Create a new git tag and publish a new release on GitHub Marketplace.
    - [setup-swiftwasm](https://github.com/swiftwasm/setup-swiftwasm): Create a new git tag and publish a new release on GitHub Marketplace.
5. Update the setup guide in [book.swiftwasm.org](https://github.com/swiftwasm/swiftwasm-book/blob/main/src/getting-started/setup.md)
6. Create an announcement blog post on [blog.swiftwasm.org](https://github.com/swiftwasm/blog.swiftwasm.org)


### Past releases

- https://github.com/swiftwasm/swift/issues/5362
- https://github.com/swiftwasm/swift/issues/4903
