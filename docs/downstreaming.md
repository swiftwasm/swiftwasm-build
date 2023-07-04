# Downstreaming from [`apple/swift`](https://github.com/apple/swift/)

We are applying several patches maintained in this repository on top of the upstream Swift source code. While we are maintaining our patches, the upstream evolves continuously and drastically.
To keep our patches up-to-date, we are periodically rebasing our patches on top of the upstream. This process is called "downstreaming".

The upstream snapshot revision we are rebasing on is defined in [`./schemes/<scheme>/manifest.json` as `base-tag`](https://github.com/swiftwasm/swiftwasm-build/blob/main/schemes/main/manifest.json#L2) for each scheme.

## Downstreaming process

Our downstreaming process is usually triggered by the upstream's snapshot release. The process is as follows:

1. Upstream [`apple/swift`](https://github.com/apple/swift/) releases a new snapshot toolchain.
2. Create a new branch in this repository and update `manifest.json` in this repository to point to the new upstream snapshot.
3. Apply our patches on top of the new upstream snapshot by running:
  ```
  $ ./tools/git-swift-workspace --scheme main
  ```
4. If conflicts or the upstream changes break build or tests, fix them by modifying our patches.
   If the root cause of the breakage is in the upstream, we should report it to the upstream and also send a pull request to fix it.
5. After ensuring that the build and tests pass, merge the new branch into `main` branch.

Step 1 and 2 are usually done automatically by [a daily GitHub Action workflow](https://github.com/swiftwasm/swiftwasm-build/blob/main/.github/workflows/update-snapshot.yml). It creates a new PR to update the base upstream snapshot tag name.
You can also do it manually by running:

```console
$ ./tools/gh-pr-update-snapshot
```

Step 3 and later are usually done by CI checks in the PR. If no conflicts and no breakage are found, we can merge the PR without any manual operation. If the CI checks failed, we need to look closely at the failure.


## How to fix conflicts

When the upstream changes break our patches, we need to fix the conflicts. The following steps are the recommended way to resolve the conflicts:

1. Run `./tools/git-swift-workspace --scheme main` to apply our patches on top of the upstream snapshot.
2. `git-am` fails with conflicts in `../swift` directory. Resolve the conflicts by editing the files in `../swift` directory and amend the conflicting commit.
3. Generate an updated `.patch` file by `git format-patch -1` and replace the original conflicted patch in `./schemes/<scheme>/swift` directory with the generated `.patch` file.
4. Repeat the above steps 1~3 until `git-am` succeeds for all patches.

Please note that each patch should be well-organized and ready to be upstreamed as much as possible.
