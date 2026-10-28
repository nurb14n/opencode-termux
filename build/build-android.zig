// Android/Bionic port build for libopentui.so (@opentui/core native lib).
//
// Why this file exists: `zig build` with the stock build.zig fails in this
// environment because `std.Build.Step.Options` materializes its output with a
// hardlink created via `linkat(AT_EMPTY_PATH)`, which the surrounding proot
// rejects with EINVAL. `zig build-exe`/`build-lib` and the other build steps
// work fine, so this file replicates `createLibraries()` for the single
// target `aarch64-linux-android` without any Options steps. The two option
// structs are provided as static files (port-android-opts/).
//
// Run from packages/native:
//   zig build --build-file build-android.zig -Doptimize=ReleaseSafe --prefix <out>
// Output: <out>/lib/libopentui.so

const std = @import("std");

const YOGA_CXX_FLAGS = [_][]const u8{
    "-std=c++20",
    "-fexceptions",
    "-frtti",
    "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24",
};

const YOGA_CXX_SOURCES = [_][]const u8{
    "yoga/YGConfig.cpp",
    "yoga/YGEnums.cpp",
    "yoga/YGNode.cpp",
    "yoga/YGNodeLayout.cpp",
    "yoga/YGNodeStyle.cpp",
    "yoga/YGPixelGrid.cpp",
    "yoga/YGValue.cpp",
    "yoga/algorithm/AbsoluteLayout.cpp",
    "yoga/algorithm/Baseline.cpp",
    "yoga/algorithm/Cache.cpp",
    "yoga/algorithm/CalculateLayout.cpp",
    "yoga/algorithm/FlexLine.cpp",
    "yoga/algorithm/PixelGrid.cpp",
    "yoga/config/Config.cpp",
    "yoga/debug/AssertFatal.cpp",
    "yoga/debug/Log.cpp",
    "yoga/event/event.cpp",
    "yoga/node/LayoutResults.cpp",
    "yoga/node/Node.cpp",
};

const LCMS2_SOURCES = [_][]const u8{
    "src/cmsalpha.c",
    "src/cmscam02.c",
    "src/cmscgats.c",
    "src/cmscnvrt.c",
    "src/cmserr.c",
    "src/cmsgamma.c",
    "src/cmsgmt.c",
    "src/cmshalf.c",
    "src/cmsintrp.c",
    "src/cmsio0.c",
    "src/cmsio1.c",
    "src/cmslut.c",
    "src/cmsmd5.c",
    "src/cmsmtrx.c",
    "src/cmsnamed.c",
    "src/cmsopt.c",
    "src/cmspack.c",
    "src/cmspcs.c",
    "src/cmsplugin.c",
    "src/cmsps2.c",
    "src/cmssamp.c",
    "src/cmssm.c",
    "src/cmstypes.c",
    "src/cmsvirt.c",
    "src/cmswtpnt.c",
    "src/cmsxform.c",
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .android,
        .android_api_level = 24,
    });
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
        .pic = true,
    });

    // Static stand-ins for the build Options steps.
    module.addImport("build_options", b.createModule(.{
        .root_source_file = b.path("build-android-opts/build_options.zig"),
        .target = target,
        .optimize = optimize,
    }));
    module.addImport("ghostty_vt_options", b.createModule(.{
        .root_source_file = b.path("build-android-opts/ghostty_vt_options.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // uucode (same fields as upstream applyDependencies).
    if (b.lazyDependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{
            "grapheme_break",
            "east_asian_width",
            "general_category",
            "is_default_ignorable",
        }),
        .fields_1 = @as([]const []const u8, &.{"wcwidth_zero_in_grapheme"}),
    })) |uucode_dep| {
        module.addImport("uucode", uucode_dep.module("uucode"));
    }

    // translate-c imports (miniaudio, yoga bridge, context ABI header).
    const miniaudio_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/vendor/miniaudio/miniaudio.h"),
        .target = target,
        .optimize = optimize,
    });
    miniaudio_translate.addIncludePath(b.path("src"));
    miniaudio_translate.addSystemIncludePath(b.path("ndk-shadow"));
    miniaudio_translate.addSystemIncludePath(b.path("ndk-include"));
    miniaudio_translate.addSystemIncludePath(b.path("ndk-arch-include"));
    miniaudio_translate.defineCMacro("__ANDROID_API__", "24");
    miniaudio_translate.defineCMacro("__ANDROID_MIN_SDK_VERSION__", "24");
    module.addImport("miniaudio", miniaudio_translate.createModule());

    const yoga_dep = b.dependency("yoga", .{});
    const yoga_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/yoga-bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    yoga_translate.addIncludePath(yoga_dep.path(""));
    yoga_translate.addSystemIncludePath(b.path("ndk-include"));
    yoga_translate.addSystemIncludePath(b.path("ndk-arch-include"));
    yoga_translate.defineCMacro("__ANDROID_API__", "24");
    yoga_translate.defineCMacro("__ANDROID_MIN_SDK_VERSION__", "24");
    module.addImport("yoga", yoga_translate.createModule());

    const abi_translate = b.addTranslateC(.{
        .root_source_file = b.path("include/opentui.h"),
        .target = target,
        .optimize = optimize,
    });
    abi_translate.addSystemIncludePath(b.path("ndk-include"));
    abi_translate.addSystemIncludePath(b.path("ndk-arch-include"));
    abi_translate.defineCMacro("__ANDROID_API__", "24");
    abi_translate.defineCMacro("__ANDROID_MIN_SDK_VERSION__", "24");
    module.addImport("context_abi_c", abi_translate.createModule());

    // Audio (miniaudio shim) + image (lcms2/webp) shims.
    module.link_libc = true;
    module.addIncludePath(b.path("src"));
    module.addSystemIncludePath(b.path("ndk-include"));
    module.addSystemIncludePath(b.path("ndk-arch-include"));
    module.addLibraryPath(b.path("ndk-syslib"));
    module.addCSourceFile(.{
        .file = b.path("src/miniaudio_shim.c"),
        .flags = &.{"-std=c99", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24"},
    });
    module.addCSourceFile(.{
        .file = b.path("src/image-shim.c"),
        .flags = &.{ "-std=c99", "-ffp-contract=off", "-fvisibility=hidden", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24" },
    });
    module.addIncludePath(b.path("src/vendor/lcms2/include"));
    module.addIncludePath(b.path("src/vendor/lcms2/src"));
    module.addCSourceFiles(.{
        .root = b.path("src/vendor/lcms2"),
        .files = &LCMS2_SOURCES,
        .flags = &.{ "-std=c99", "-ffp-contract=off", "-fvisibility=hidden", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24" },
    });
    module.addCSourceFile(.{
        .file = b.path("src/image-resize-shim.c"),
        .flags = &.{ "-std=c99", "-ffp-contract=off", "-fvisibility=hidden", "-fno-sanitize=bounds", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24" },
    });
    const webp_flags = [_][]const u8{ "-std=c99", "-fvisibility=hidden", "-DWEBP_EXTERN=extern", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24" };
    module.addIncludePath(b.path("src/vendor/libwebp"));
    module.addCSourceFile(.{
        .file = b.path("src/image-webp-config.c"),
        .flags = &webp_flags,
    });
    module.addCSourceFiles(.{
        .root = b.path("src/vendor/libwebp"),
        .files = &.{
            "src/dec/alpha_dec.c",
            "src/dec/buffer_dec.c",
            "src/dec/frame_dec.c",
            "src/dec/idec_dec.c",
            "src/dec/io_dec.c",
            "src/dec/quant_dec.c",
            "src/dec/tree_dec.c",
            "src/dec/vp8_dec.c",
            "src/dec/vp8l_dec.c",
            "src/dec/webp_dec.c",
            "src/dsp/alpha_processing.c",
            "src/dsp/cpu.c",
            "src/dsp/dec.c",
            "src/dsp/dec_clip_tables.c",
            "src/dsp/filters.c",
            "src/dsp/lossless.c",
            "src/dsp/rescaler.c",
            "src/dsp/upsampling.c",
            "src/dsp/yuv.c",
            "src/utils/bit_reader_utils.c",
            "src/utils/color_cache_utils.c",
            "src/utils/filters_utils.c",
            "src/utils/huffman_utils.c",
            "src/utils/palette.c",
            "src/utils/quant_levels_dec_utils.c",
            "src/utils/random_utils.c",
            "src/utils/rescaler_utils.c",
            "src/utils/thread_utils.c",
            "src/utils/utils.c",
            "src/dsp/alpha_processing_neon.c",
            "src/dsp/dec_neon.c",
            "src/dsp/filters_neon.c",
            "src/dsp/lossless_neon.c",
            "src/dsp/rescaler_neon.c",
            "src/dsp/upsampling_neon.c",
            "src/dsp/yuv_neon.c",
        },
        .flags = &webp_flags,
    });

    // Yoga (C++).
    module.link_libcpp = true;
    module.addIncludePath(yoga_dep.path(""));
    module.addCSourceFiles(.{
        .root = yoga_dep.path(""),
        .files = &YOGA_CXX_SOURCES,
        .flags = &YOGA_CXX_FLAGS,
    });
    module.addCSourceFile(.{ .file = b.path("src/yoga-bridge.cpp"), .flags = &YOGA_CXX_FLAGS });

    // Android/Bionic port shim (see port-android-shim.c).
    module.addCSourceFile(.{
        .file = b.path("port-android-shim.c"),
        .flags = &.{ "-std=c99", "-D__ANDROID_API__=24", "-D__ANDROID_MIN_SDK_VERSION__=24" },
    });
    // System libs (linux branch in upstream covers android: bionic edition).
    // NOTE: no libpthread on Bionic (in libc); libdl/libm exist.
    module.linkSystemLibrary("dl", .{});
    module.linkSystemLibrary("m", .{});

    const shared = b.addLibrary(.{
        .name = "opentui",
        .root_module = module,
        .linkage = .dynamic,
    });
    const install = b.addInstallArtifact(shared, .{});
    b.getInstallStep().dependOn(&install.step);
}
