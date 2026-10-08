# Existing runner

The workflow uses the existing trusted self-hosted macOS ARM64 runner with label gama. Fork pull requests are excluded. Permissions remain contents: read and checkout persist-credentials is false. PR revisions may cancel earlier PR work; push/dispatch runs use unique groups.

Provision the exact Zig pin, Python 3, Node, tmux and mlir-opt separately. The workflow runs `scripts/check.sh` and uploads bounded build evidence. It does not install toolchains or modify registration, credentials, service configuration or external runner directories. The old Pages deployment is retired. A workflow file is configuration, not a hosted execution receipt; [Capabilities](Capabilities.md) states the proof gap.
