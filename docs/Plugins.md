# Cooperative static plugins

Tier 1 plugins are ordinary in-process Zig values installed by `PluginRuntime`; they are not a security sandbox. Required capabilities must exactly match grants. Filesystem scopes use lexical path validation, not kernel isolation. Unsupported services fail explicitly. No dynamic package loader or new plugin tiers are implemented.

Installation is transactional; failure releases candidate payloads. Deterministic installation order and identities drive command/scene contributions. Uninstall revokes cached Context, Command and service handles before later use; reinstall cannot revive an old generation. The runtime owns plugin storage, while supplied services and callback userdata must outlive it. Use `examples/plugins.zig` for install, perform and revocation.
