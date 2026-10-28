#!/usr/bin/env bun

// Android/Bionic port of script/build.ts: builds a single
// `opencode-linux-arm64-android` target (Bionic ELF, runs on Termux).
//
// Prerequisites (android-port):
//   1. `bun install` with platform packages for linux arm64 (gnu + musl),
//      `@ff-labs/fff-bin-android-arm64`, and `@parcel/watcher-linux-arm64-glibc`.
//   2. Bionic `libopentui.so` grafted over every
//      `@opentui/core-linux-arm64/libopentui.so` copy, plus the
//      `platform: process.platform` / `if (process.platform === "linux")`
//      patch in the bundled `@opentui/core` chunk (see port notes).
//   3. Bionic `librust_pty_arm64.so` replacing the glibc one in `bun-pty`.
//   4. `src/embedded.ts` of `@ff-labs/fff-bun` patched with the
//      `process.platform === "android"` branch.
// The PTY helper is taken from `@opencode-ai/pty-linux-arm64-musl`
// (fully static, runs on Bionic).

import { $ } from "bun"
import { mkdir, rm } from "fs/promises"
import path from "path"
import { Script } from "@opencode/script"
import { embed } from "@opencode/script/highlights"
import { createSolidTransformPlugin } from "@opentui/solid/bun-plugin"
import type { BunPlugin } from "bun"
import pkg from "../package.json"
import { discoverPluginRuntimeSpecifiers, pluginRuntimeLoaderCode } from "@opencode/plugin/runtime-modules"
import { buildAppArchive } from "./app-assets"
import { verifyArtifact, verifySimulationGraph } from "./verify-artifact"
import { resolveOpencodePty } from "./opencode-pty"
import { NativeArch } from "../../../script/native-arch"
import { bundledModelsSnapshot, modelsSnapshotPlugin } from "../../core/script/models-snapshot"

const dir = path.resolve(import.meta.dirname, "..")
const binary = "opencode"
const outdir = path.resolve(
  dir,
  process.argv.find((arg) => arg.startsWith("--outdir="))?.slice("--outdir=".length) ?? "dist-android",
)
if (outdir === dir) throw new Error("--outdir must not be the package directory")
process.chdir(dir)

await rm(outdir, { recursive: true, force: true })

const skipInstall = process.argv.includes("--skip-install")
const skipWebUi = process.argv.includes("--skip-web-ui")
const solidPlugin = createSolidTransformPlugin()
const highlights = Script.preview ? undefined : embed(process.env.OPENCODE_RELEASE_NOTES)
const modelsSnapshot = modelsSnapshotPlugin(await bundledModelsSnapshot())

const item = { os: "linux", arch: "arm64", abi: "android" } as const

// PTY helper packages for every other platform, like upstream CI does.
if (!skipInstall)
  await $`bun install --os="*" --cpu="*" --libc="*" @opentui/core@${pkg.dependencies["@opentui/core"]} @opencode-ai/pty@${pkg.dependencies["@opencode-ai/pty"]}`
const appArchive = path.join(dir, ".cache", "bun-app-archive.bin")
await Bun.write(appArchive, await buildAppArchive(Script.channel, { skipBuild: skipWebUi }))
const appAssetsPlugin: BunPlugin = {
  name: "opencode-app-assets",
  setup(build) {
    build.onResolve({ filter: /^virtual:opencode-app-assets$/ }, () => ({
      path: "opencode-app-assets",
      namespace: "opencode",
    }))
    build.onLoad({ filter: /^opencode-app-assets$/, namespace: "opencode" }, () => ({
      loader: "js",
      contents: `import { readFileSync } from "node:fs"
import archive from ${JSON.stringify(appArchive.replaceAll("\\", "/"))} with { type: "file" }
export default () => readFileSync(archive)`,
    }))
  },
}
const pluginRuntimeEntries = discoverPluginRuntimeSpecifiers()
const pluginRuntimeModulesSource = [
  "export const resolveHostPackageRoots = () => []",
  "const modules = {",
  ...[...pluginRuntimeEntries.keys()].map(
    (specifier) => `  ${JSON.stringify(specifier)}: ${pluginRuntimeLoaderCode(specifier, pluginRuntimeEntries)},`,
  ),
  "}",
  "export const loadRuntimeModules = () => modules",
].join("\n")
const pluginRuntimePlugin: BunPlugin = {
  name: "opencode-plugin-runtime",
  setup(build) {
    build.onLoad({ filter: /plugin[/\\]src[/\\]runtime-modules\.ts$/ }, () => ({
      contents: pluginRuntimeModulesSource,
      loader: "ts",
    }))
    build.onLoad({ filter: /[/\\]internal[/\\]httpApi(?:Scalar|Swagger)\.js$/ }, () => ({
      contents:
        'export const css = ""; export const javascript = \'document.body.textContent = "Scalar/Swagger UI assets are not bundled in OpenCode"\'',
      loader: "js",
    }))
  },
}

// Android port: static musl PTY helper runs on Bionic.
const opencodePty = await resolveOpencodePty({
  platform: "linux",
  arch: "arm64",
  libc: "musl",
})
const opencodePtyPlugin: BunPlugin = {
  name: "opencode-pty-binary",
  setup(build) {
    build.onLoad({ filter: /persistent-pty[/\\]pty-binding\.ts$/ }, () => ({
      loader: "js",
      contents: opencodePty
        ? `import file from ${JSON.stringify(opencodePty.source)} with { type: "file" }
export default { path: file, version: ${JSON.stringify(opencodePty.version)}, sha256: ${JSON.stringify(opencodePty.sha256)} }`
        : "export default undefined",
    }))
  },
}
const simulationInputs = new Set<string>()
const simulationGraphPlugin: BunPlugin = {
  name: "opencode-simulation-graph",
  setup(build) {
    build.onLoad(
      { filter: /packages[/\\]simulation[/\\]src[/\\](frontend[/\\](simulation|server)|control-server)\.ts$/ },
      (args) => void simulationInputs.add(args.path),
    )
  },
}
const parcelWatcherPackage = `@parcel/watcher-linux-arm64-glibc`
const parcelWatcherPlugin: BunPlugin = {
  name: "parcel-watcher-binding",
  setup(build) {
    build.onLoad({ filter: /filesystem[/\\]watcher-binding\.ts$/ }, () => ({
      contents: `export default () => require(${JSON.stringify(parcelWatcherPackage)})`,
      loader: "js",
    }))
  },
}
const target = "opencode-linux-arm64-android"
const name = "cli-linux-arm64-android"
const executablePath = undefined
console.log(`building ${name}`)
const result = await Bun.build({
  entrypoints: ["./src/index.ts", "./src/photon-worker.ts"],
  tsconfig: "./tsconfig.json",
  plugins: [
    appAssetsPlugin,
    solidPlugin,
    parcelWatcherPlugin,
    opencodePtyPlugin,
    pluginRuntimePlugin,
    simulationGraphPlugin,
    modelsSnapshot,
  ],
  external: ["node-gyp"],
  format: "esm",
  minify: true,
  bytecode: true,
  sourcemap: Script.channel === "dev" || Script.channel === "local" ? "inline" : "none",
  splitting: true,
  compile: {
    autoloadBunfig: false,
    autoloadDotenv: false,
    autoloadTsconfig: true,
    autoloadPackageJson: true,
    target: "bun-linux-arm64-android" as Bun.Build.CompileTarget,
    ...(executablePath ? { executablePath } : {}),
    outfile: path.join(outdir, name, "bin", binary),
    execArgv: [
      "--smol",
      `--user-agent=opencode/${Script.channel}/${Script.version}/cli`,
      "--use-system-ca",
      "--no-warnings",
      "--",
    ],
    windows: {},
  },
  define: {
    OPENCODE_VERSION: `'${Script.version}'`,
    OPENCODE_CLI_NAME: "'opencode'",
    OPENCODE_CHANNEL: `'${Script.channel}'`,
    OPENCODE_ARTIFACT: `'cli'`,
    ...(highlights ? { OPENCODE_RELEASE_HIGHLIGHTS: JSON.stringify(highlights) } : {}),
    // Runtime platform on device is "android", so these only matter for
    // build-time module resolution. "gnu" keeps the linux fff branch
    // resolvable; it is never taken on device.
    OPENCODE_LIBC: `'glibc'`,
    FFF_LIBC: `'gnu'`,
  },
})

if (!result.success) {
  for (const log of result.logs) console.error(log)
  process.exit(1)
}
verifySimulationGraph(simulationInputs)
await NativeArch.verify(path.join(outdir, name, "bin", binary), item.arch)

await Bun.write(
  path.join(outdir, name, "package.json"),
  JSON.stringify(
    {
      name: `@opencode/${name}`,
      version: Script.version,
      license: "MIT",
      repository: { type: "git", url: "git+https://github.com/anomalyco/opencode.git" },
      os: ["android"],
      cpu: ["arm64"],
    },
    null,
    2,
  ),
)
await verifyArtifact(path.join(outdir, name))
