const std = @import("std");

const BuildMode = enum { nif_lib, sema };

pub fn build(b: *std.Build) void {
    const resolved_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sema_output_path = b.option([]const u8, "zigler-sema-out", "Path to write sema JSON") orelse "sema.json";

    const mode = b.option(BuildMode, "zigler-mode", "Build either the nif library or the sema analysis module") orelse .nif_lib;

    switch (mode) {
        .nif_lib => {
            const erl_nif_raw_translate = b.addTranslateC(.{
                .root_source_file = b.path("zigler_erl_nif.h"),
                .target = resolved_target,
                .optimize = optimize,
                .link_libc = true,
            });
            erl_nif_raw_translate.addIncludePath(b.path("zigler_erl_include"));
            erl_nif_raw_translate.addIncludePath(b.path("zigler_erl_nif_win"));
            const erl_nif_raw = erl_nif_raw_translate.createModule();

            const erl_nif = b.createModule(.{
                .root_source_file = b.path("zigler_beam/erl_nif.zig"),
                .imports = &[_]std.Build.Module.Import{
                    .{ .name = "erl_nif_raw", .module = erl_nif_raw },
                },
            });

            const beam = b.createModule(.{
                .root_source_file = b.path("zigler_beam/beam.zig"),
                .imports = &[_]std.Build.Module.Import{
                    .{ .name = "erl_nif", .module = erl_nif },
                },
            });

            const attributes = b.createModule(.{
                .root_source_file = .{ .cwd_relative = "attributes.zig" },
                .imports = &[_]std.Build.Module.Import{},
            });

            const module = b.createModule(.{
                .root_source_file = b.path("build_files/module.zig"),
                .imports = &[_]std.Build.Module.Import{},
            });

            const nif = b.createModule(.{
                .root_source_file = b.path("nif.zig"),
                .imports = &[_]std.Build.Module.Import{
                    .{ .name = "erl_nif", .module = erl_nif },

                    .{ .name = "beam", .module = beam },

                    .{ .name = "attributes", .module = attributes },

                    .{ .name = "module", .module = module },
                },

                .link_libc = true,
            });

            const nif_shim = b.createModule(.{ .root_source_file = .{ .cwd_relative = "module.zig" }, .imports = &[_]std.Build.Module.Import{
                .{ .name = "beam", .module = beam },

                .{ .name = "erl_nif", .module = erl_nif },

                .{ .name = "nif", .module = nif },
            }, .target = resolved_target, .optimize = optimize });

            const lib = b.addLibrary(.{ .name = "Elixir.ZiglerTest.CornerCases.BuildFilesOverrideTest", .linkage = .dynamic, .version = .{ .major = 0, .minor = 15, .patch = 1 }, .root_module = nif_shim });

            lib.linker_allow_shlib_undefined = true;

            // the native backend still causes segfaults, so we must disable it for now.
            lib.use_llvm = true;

            b.installArtifact(lib);
        },
        .sema => {
            const erl_nif = b.createModule(.{
                .root_source_file = b.path("zigler_beam/stub_erl_nif.zig"),
                .imports = &[_]std.Build.Module.Import{},
            });

            const beam = b.createModule(.{
                .root_source_file = b.path("zigler_beam/beam.zig"),
                .imports = &[_]std.Build.Module.Import{
                    .{ .name = "erl_nif", .module = erl_nif },
                },
            });

            const attributes = b.createModule(.{
                .root_source_file = .{ .cwd_relative = "attributes.zig" },
                .imports = &[_]std.Build.Module.Import{},
            });

            const module = b.createModule(.{
                .root_source_file = b.path("build_files/module.zig"),
                .imports = &[_]std.Build.Module.Import{},
            });

            const nif = b.createModule(.{
                .root_source_file = b.path("nif.zig"),
                .imports = &[_]std.Build.Module.Import{
                    .{ .name = "erl_nif", .module = erl_nif },

                    .{ .name = "beam", .module = beam },

                    .{ .name = "attributes", .module = attributes },

                    .{ .name = "module", .module = module },
                },

                .link_libc = true,
            });

            const sema = b.createModule(.{ .root_source_file = b.path("zigler_beam/sema.zig"), .imports = &[_]std.Build.Module.Import{
                .{ .name = "nif", .module = nif },
                .{ .name = "beam", .module = beam },
                .{ .name = "erl_nif", .module = erl_nif },
            }, .target = resolved_target, .optimize = optimize });

            const sema_exe = b.addExecutable(.{ .name = "sema", .root_module = sema });

            b.installArtifact(sema_exe);

            const sema_run_cmd = b.addRunArtifact(sema_exe);
            sema_run_cmd.addArg(sema_output_path);
            if (b.args) |args| sema_run_cmd.addArgs(args);
            const sema_step = b.step("sema", "Run sema");
            sema_step.dependOn(&sema_run_cmd.step);
        },
    }
}
