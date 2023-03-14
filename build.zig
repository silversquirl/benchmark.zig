const std = @import("std");
pub fn build(b: *std.Build) void {
    _ = b.addModule("benchmark", .{
        .source_file = .{ .path = "benchmark.zig" },
    });
}
