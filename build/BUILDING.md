# Building the Termux binaries

This documents how the `opencode` binary published in
[releases](https://github.com/nurb14n/opencode-termux/releases) was produced,
so the port can be repeated for future upstream versions.

Pinned versions: OpenCode `v2.2.0`, Bun `1.4.4`, `@opentui/core` `0.7.0`,
zig `0.16.0` (Termux package), Android API level 24.

## 0. Sources

- `git clone --depth 1 --branch v2.2.0 https://github.com/anomalyco/opencode.git`
- `@opentui/core@0.7.0` JS comes from npm; its native lib must be rebuilt
  from the OpenTUI tree **at tag `v0.7.0`** (newer commits renamed FFI
  symbols, e.g. `ot_buffer_draw_scene_text` → `ot_buffer_draw_scene_body`).

## 1. `libopentui.so` (Bionic)

Toolchain: Termux `zig` 0.16.0 + NDK sysroot in `$PREFIX`
(`$PREFIX/include`, CRTs in `$PREFIX/lib`, arch headers in
`$PREFIX/include/aarch64-linux-android`, link against `/system/lib64`).

Key adaptations in `build/build-android.zig` (run from
`opentui/packages/native`):

- single target `aarch64-linux-android` + `.android_api_level = 24`;
- static `build_options` / `ghostty_vt_options` modules
  (`build/build-android-opts/`) instead of `std.Build.Step.Options`
  (its hardlink-based cache writes fail under proot);
- `--libc` file pointing `include_dir`/`sys_include_dir` at a merged
  Termux sysroot and `crt_dir` at a dir containing the Termux CRTs plus
  `libc.so`/`libm.so`/`libdl.so` symlinks to `/system/lib64`;
- `-D__ANDROID_API__=24 -D__ANDROID_MIN_SDK_VERSION__=24` on all C/C++
  and translate-c steps (unversioned triples are rejected by NDK headers);
- shadow `sys/time.h` working around a zig translate-c nullability
  limitation;
- `port-android-shim.c`: provides `pthread_tryjoin_np` (absent from
  Bionic) via `pthread_kill(tid, 0)` probing + `pthread_join`.

```
zig build --build-file build-android.zig --libc android-libc.txt \
  -Doptimize=ReleaseSafe --prefix zig-out
# → zig-out/lib/libopentui.so  (NEEDED: libc.so, libm.so, libdl.so only)
```

Verify: every symbol in the `@opentui/core` JS FFI tables
(`nativeSymbols` + `yogaSymbols` + extras) must be exported (`nm -D`).

## 2. Store grafts & patches (before `bun build`)

With `bun install` done (Bun 1.4.4, incl. platform packages
`@opentui/core-linux-arm64`, `@opencode-ai/pty-linux-arm64-{gnu,musl}`,
`@parcel/watcher-linux-arm64-glibc`, `@ff-labs/fff-bin-android-arm64`):

1. Copy the Bionic `libopentui.so` over every
   `@opentui/core-linux-arm64/libopentui.so` in the store.
2. `@opentui/core` chunk (`chunk-bun-*.js`):
   `platform: process.platform` → `"linux"`,
   `if (process.platform === "linux")` → `if (true)`
   (Android reports `platform === "android"`).
3. Same chunk, MTE/tagged-pointer support: `toPointer` keeps `bigint`
   (Bun FFI accepts it for `ptr` args); `toBunPointer`/`toBunPointer2`
   clear the tag for `Bun.toArrayBuffer` numeric reads.
4. `@ff-labs/fff-bun` `src/embedded.ts`: add the
   `process.platform === "android"` branch importing
   `@ff-labs/fff-bin-android-arm64/libfff_c.so`.
5. `@ff-labs/fff-bun` `src/ffi.ts`: replace `read.ptr` with `read.u64`
   (exact `bigint`), make null checks `bigint`-aware (`0n`), and wrap
   pointer arithmetic in `BigInt(…)`.
6. `bun-pty`: replace glibc `rust-pty/target/release/librust_pty_arm64.so`
   with a Bionic build (same 8-symbol FFI surface).
7. PTY helper: build resolves `@opencode-ai/pty-linux-arm64-musl`
   (fully static, runs on Bionic).

## 3. CLI binary

`packages/cli/script/build-android.ts` (adapted from upstream
`script/build.ts`): single `bun-linux-arm64-android` target, full web-UI
app archive included:

```
OPENCODE_VERSION=2.2.0 OPENCODE_CHANNEL=latest \
  bun run script/build-android.ts --skip-install \
  --outdir=dist-android
# → dist-android/cli-linux-arm64-android/bin/opencode
```

## 4. Release

```
sha256sum opencode > SHA256SUMS   # plus README/install.sh hashes
gh release create v2.2.0 opencode SHA256SUMS --title "opencode v2.2.0 for Termux"
```

`install.sh` downloads `opencode` + `SHA256SUMS` from
`…/releases/latest/download/` and verifies before installing to
`$PREFIX/bin/opencode`.
