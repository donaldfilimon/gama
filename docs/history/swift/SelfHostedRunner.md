# Self-hosted macOS runner

Both jobs in `.github/workflows/ci.yml`, `macOS / Apple Swift 6.5-dev` (`macos-swift-64`) and `Embedded / exact Swift 6.5-dev snapshot` (`embedded-swift-64`), run on a macOS arm64 runner registered to this repository. GitHub-hosted jobs can't start while the account's Actions billing is locked, but self-hosted jobs still run.

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
- The job installs the pinned Swift 6.5-dev snapshot per user into `~/Library/Developer/Toolchains`, so the runner account needs no `sudo`. Both jobs check the same URL and SHA-256 from `Toolchains.toml`.

## Security

This repository is public, so the self-hosted job runs only for `push`, `workflow_dispatch` and pull requests from branches in this repository. Fork pull requests get no CI job: the GitHub-hosted fork fallback was removed on 2026-09-28. Checkouts use `persist-credentials: false`, and the workflow token stays `contents: read`.

Where you can, use a dedicated macOS user for the runner rather than your daily account. Keep no production secrets on the host.

## Not covered

The GitHub-hosted Linux, WebAssembly, Android and Windows jobs were removed from `ci.yml` on 2026-09-28; their gates are local only. The Pages workflow (`.github/workflows/pages.yml`) still needs a GitHub-hosted Ubuntu runner and stays blocked until the billing lock is cleared.
