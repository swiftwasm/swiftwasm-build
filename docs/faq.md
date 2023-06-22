# FAQ for this repository

## Why not simply fork the [`apple/swift`](https://github.com/apple/swift/)

We had been maintaining a fork of the official Swift repository for a long time. However, it was not easy to keep up with the official repository. We used a simple merge strategy that merges upstream `main` branch into our forked branch. This strategy is very straightforward, but we had several problems:

1. Hard to find the branch-cut point of the release branch
2. Upstream repositories has nightly snapshot tags which points the build-able commits across the repositories (like `llvm-project`, `swift`, `swift-corelibs-foundation`, etc). But our fork has different commit history, so we can't use those tags at all, and that makes it hard to find build-able combination of `llvm-project` and `swift` revisions.
3. 2. also makes it hard to merge upstream changes step by step. We had to merge all the upstream changes at once because we don't know build-able revisions except for the latest commits.
4. Our patches often conflicts with upstream changes, but conflict resolution is recorded in the merge commit. So we had to format the patch by gathering conflict resolutino history before sending it to the upstream.

There were several solutions to these problems:

1. Use `git rebase --onto` to rebase our forked branch on top of the upstream branch.
2. Use merging rebase strategy, which is used by `git-for-windows/git` repository. See [this blog post](https://github.blog/2022-05-02-friend-zone-strategies-friendly-fork-management)
3. Manage `.patch` files for our changes and apply them on top of the upstream branch.

1 and 2 are git-way solutions, but they are not easy to automate the daily work for keeping up with the upstream. 3 is not a git-way solution, but it's much easier to manage our changes.
Currently the number of our patches is relatively small, so we decided to employ the current `.patch` based solution.
