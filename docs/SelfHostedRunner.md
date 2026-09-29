# Self-hosted macOS runner

The `macOS / Apple Swift 6.5-dev` job (`macos-swift-64`) in `.github/workflows/ci.yml` runs on a macOS arm64 runner registered to this repository. GitHub-hosted jobs can't start while the account's Actions billing is locked, but self-hosted jobs still run.

## Registration

| Field | Value |
|-------|-------|
| Labels | `self-hosted`, `macOS`, `ARM64`, `gama` |
| Register at | [Settings → Actions → Runners → New self-hosted runner](https://github.com/donaldfilimon/gama/settings/actions/runners/new?arch=arm64) |

A runner is registered to one repository. If the same Mac already runs the `abi` runner, install a second runner in its own directory (for example `~/actions-runner-gama`), add the custom label `gama`, then run `./svc.sh install && ./svc.sh start`.

Until a runner with these labels is online, same-repo jobs wait in the queue.

## Host requirements

- Xcode 27 as the selected developer directory (`xcode-select -p`). The iOS, tvOS and visionOS compile gates use its default Swift 6.4 toolchain.
- Homebrew, which the MLIR step uses to install `llvm`.
- The job installs the pinned Swift 6.5-dev snapshot per user into `~/Library/Developer/Toolchains`, so the runner account needs no `sudo`. It checks the same URL and SHA-256 as the hosted job.

## Security

This repository is public, so the self-hosted job runs only for `push`, `workflow_dispatch` and pull requests from branches in this repository. Fork pull requests use the GitHub-hosted `macos-swift-64-hosted` job. Checkouts use `persist-credentials: false`, and the workflow token stays `contents: read`.

Where you can, use a dedicated macOS user for the runner rather than your daily account. Keep no production secrets on the host.

## Not covered

The Linux, WebAssembly, Android, Embedded, Windows and Pages jobs still need GitHub-hosted runners (Linux or Windows hosts). They stay blocked until the billing lock is cleared.
