# Architecture

What/why of design decisions for the `even` autostart repo. How-to procedures live in `README.md`.

## Goal

Auto-start `@evenrealities/even-terminal` on PC login so Even Realities G2 glasses can connect to Claude Code sessions without per-session manual steps (manual launch, QR re-scan).

## Approach: symmetric platform mirror

Windows and POSIX implementations are independent scripts sharing only the external contract — file layout, config schema, CLI flags, and lifecycle stages (install / start / uninstall).

Considered alternatives:

- **Common helper layer with thin platform wrappers** — rejected: PowerShell and bash share almost no reusable logic for process management, network detection, and config writing. The abstraction cost exceeds the benefit.
- **Windows-only MVP, POSIX stub** — rejected: the agreed scope requires both platforms in this iteration.

Symmetric mirror keeps each script idiomatic in its own language while preserving cross-platform predictability through identical config schema and CLI flags.

## Config SSOT

`~/.config/even-terminal/config.json` (same path on every platform) is the single source of truth. Scripts read it at runtime; nothing else (no `.env` loading, no shell exports). The `executable` field stores the absolute path resolved at install time — service contexts often have a reduced `PATH` that does not include fnm/nvm shims, so deferring resolution to start time is unreliable.

## Already-running detection: TCP + HTTP probe

`scripts/lib/probe-server.{ps1,sh}` checks both:

1. TCP connect to `127.0.0.1:<port>` (cheap liveness check).
2. HTTP `GET /` and accept `200`, `401`, or `404` as evidence that an HTTP server is present.

TCP alone has too many false positives — any process holding the port would suppress restart. The HTTP step filters out non-HTTP listeners. The acceptable-status set tolerates routing changes inside even-terminal (auth-required endpoints return 401, missing routes return 404; both are valid "HTTP server is alive" signals).

The probe can still match an unrelated HTTP server on the same port. The trade-off is acceptable because a port conflict is a user-visible misconfiguration that surfaces in install logs (warning: "server did not start within 30s") and the start-script skip message. On Windows, the probe timeout is non-fatal — Task Scheduler registration is the primary success condition; the Connect URL is still printed so the user can verify connectivity independently.

## Tailscale vs LAN: `--tailscale` flag vs `--interface`

`even-terminal` accepts `--tailscale` (auto-detects the Tailscale IP) or `--interface <NIC name>` (binds to a specific adapter). These are mutually exclusive.

The `auto` mode (default) re-evaluates at each start:

- If a Tailscale adapter is up → use `--tailscale`.
- Otherwise → detect the primary LAN NIC (lowest-metric default-gateway adapter) and pass `--interface <NIC>`.

`auto` re-evaluation matters because Tailscale daemons sometimes start after login; the start-script's re-check at each launch handles the transition automatically. Users can also pin `network_mode` to `tailscale`, `lan`, or `loopback` in `config.json`.

## Token delivery: `BRIDGE_TOKEN` env var, not CLI flag

`even-terminal`'s entry (`dist/index.js`) reads `process.env.BRIDGE_TOKEN` and `process.env.PORT`. Passing the token via env var keeps it out of `ps`-listings and Task Scheduler action arguments, which are visible to other users on the host.

Risk: `BRIDGE_TOKEN` and `PORT` are internal implementation details of the upstream package. Future versions may rename them. Mitigations:

- `--port` is also passed as a CLI flag (documented and unlikely to be renamed).
- `--token` is **not** passed as a CLI flag (security trumps belt-and-suspenders here).
- Pin the upstream version when re-evaluating; bumping major versions should be paired with a re-read of `dist/index.js` and a manual smoke test.

## Token protection at rest

- POSIX: `chmod 600` on `config.json`; parent dir `chmod 700`.
- Windows: `%USERPROFILE%` is inaccessible to other users by default ACL.
- `.bak` files written by `uninstall` inherit the same permissions.

The token is also displayed once in the Connect URL printed by the install script. Treat the install transcript as sensitive (don't paste it into public bug reports).

## Test isolation

`EVEN_TERMINAL_CONFIG_DIR` and `EVEN_TERMINAL_TASK_NAME` env-var overrides, plus `--dry-run` / `-DryRun` flags, let tests use temporary config directories and unique task names without touching production state. Tests live in `tests/`; the actual write-and-run loop is delegated to the `/write-tests` skill.
