const std = @import("std");
pub fn build(b: *std.Build) !void {
    const benchmark = b.addModule("benchmark", .{
        .root_source_file = b.path("benchmark.zig"),
    });

    try b.modules.put(b.dupe("benchmark"), benchmark);

    // example exe and run
    var example_exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    example_exe.root_module.addImport("benchmark", benchmark);

    const example_run_step = b.step("run", "run the example");

    const example_run = b.addRunArtifact(example_exe);
    example_run_step.dependOn(&example_run.step);
}
