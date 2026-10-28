# opencode-termux

**OpenCode v2.2.0 — native Android/Bionic port for Termux**

OpenCode is an open source AI coding agent (terminal TUI, desktop, web).
Official binaries target Linux glibc/musl and do **not** run on Android's Bionic libc.
This project ports OpenCode v2 to run natively on Termux (aarch64, Android 9+),
with zero glibc dependencies at runtime.

> This is an **unofficial, community port**. It is not affiliated with,
> endorsed by, or supported by Anomaly (the OpenCode project) or its maintainers.

## One-liner install (Termux)

```bash
curl -fsSL https://raw.githubusercontent.com/nurb14n/opencode-termux/main/install.sh | bash
```

After install:

```bash
pkg install ripgrep git openssh   # optional but recommended
opencode --version                 # opencode v2.2.0
```

Then `cd` into your project, run `opencode`, and use `/connect` in the TUI
to sign in to a provider.

## Requirements

- Termux (F-Droid or GitHub release build), aarch64
- Android 9+ (API 28+)
- ~300 MB free storage
- Optional: `ripgrep`, `git`, `openssh` (`pkg install …`)

## What's different from upstream

- Binary is a Bionic ELF (`/system/bin/linker64`), runs directly in Termux —
  no glibc runner, no proot.
- TUI renderer (`libopentui.so`) rebuilt for `aarch64-linux-android`.
- PTY helper uses a static-musl build (runs on Bionic).
- File search uses the system `rg` (Termux `ripgrep` package).
- File watcher falls back to `node:fs` (native watcher is glibc-only).
  Note: in very large directories project scanning is slower and plugin
  activation has a 5s timeout — avoid starting `opencode` in huge trees.
- Fuzzy file finder (`fff`) uses the official
  `@ff-labs/fff-bin-android-arm64` build.

## Credits & Attribution

This port would not exist without the following projects and people.
All credit for the original work belongs to them.

- **OpenCode** — [anomalyco/opencode](https://github.com/anomalyco/opencode) (MIT).
  All core product, TUI, server, SDK, and tooling. Version pinned: `v2.2.0`.
- **Bun** — [oven-sh/bun](https://github.com/oven-sh/bun) (MIT).
  Runtime and `--compile` target `bun-linux-arm64-android` used to produce
  the Bionic binary.
- **OpenTUI** — [anomalyco/opentui](https://github.com/anomalyco/opentui) (MIT).
  Zig TUI renderer rebuilt for Android (aarch64, API 24) with a
  `pthread_tryjoin_np` shim.
- **@ff-labs/fff** — fuzzy file finder, Android arm64 build
  (`fff-bin-android-arm64`).
- **@opencode-ai/pty** — persistent PTY helper (static musl variant used
  on Bionic).
- **Termux** — [termux/termux-app](https://github.com/termux/termux-app) and
  the Termux package ecosystem (zig, clang, NDK headers).
- **Hope2333/opencode-termux**, **guysoft/opencode-termux**,
  **HanSoBored/opencode-termux**, and **MuYuanXing/opencode-termux** —
  prior art and build recipes that informed this port (glibc-shim,
  B-line native build, module-graph transplant, Ctrl+B fix).

## License

OpenCode is MIT-licensed. This repository redistributes OpenCode binaries
built from its source under the same MIT license. See `LICENSE` (upstream)
for full terms.
Build scripts, patches, and installer in this repo are released under MIT
as well.

## Disclaimer

- Unofficial port. No warranty. Use at your own risk.
- Android/Termux is not an officially supported platform for OpenCode;
  behavior may differ from desktop/Linux.
- Do not report issues caused by this port to the upstream OpenCode tracker
  unless reproducible on an officially supported platform.
- API keys and credentials are stored locally by OpenCode; this port does
  not collect or transmit them.

## Contributing

Issues and PRs welcome for Termux-specific problems (build, install,
runtime on Android). For OpenCode product bugs, please report upstream.
See `build/BUILDING.md` for how the binaries in the releases were produced.
