const std = @import("std");

const themes = @import("src/build/themes.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version_opt = b.option([]const u8, "version", "version string");
    const version_string = if (version_opt) |version| version else @import("build.zig.zon").version;

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version_string);

    const mod = b.addModule("prismacat", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "generated_themes", .module = themes.module(b) },
        },
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "prismacat", .module = mod },
        },
    });
    exe_module.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "prismacat",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
