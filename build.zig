const std = @import("std");
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const benchmark = b.addModule("benchmark", .{
        .root_source_file = b.path("benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    try b.modules.put(b.dupe("benchmark"), benchmark);

    // example exe and run
    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "benchmark", .module = benchmark }},
        }),
    });

    const example_run_step = b.step("run", "run the example");

    const example_run = b.addRunArtifact(example_exe);
    example_run_step.dependOn(&example_run.step);
}
