# `benchmark.zig`

This is a tiny microbenchmark library for Zig, designed to be easy to use and very small.

## Usage

You can either manually copy `benchmark.zig` into your project, or add it as a dependency using the Zig package manager.

A basic usage example is shown below:

```zig
const std = @import("std");
const benchmark = @import("benchmark.zig");
pub const main = benchmark.main(.{}, struct {
    // Benchmarks are just public functions
    pub fn arrayListWriter(b: *benchmark.B) !void {
        // Setup is not timed
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        while (b.step()) { // Number of iterations is automatically adjusted for accurate timing
            defer _ = arena.reset(.retain_capacity);

            var a = std.ArrayList(u8).init(arena.allocator());
            try a.writer().print("Hello, {s}!", .{"world"});

            // `use` is a helper that calls `std.mem.doNotOptimizeAway`
            b.use(a.items);
        }
    }

    pub fn allocPrint(b: *benchmark.B) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        while (b.step()) {
            defer _ = arena.reset(.retain_capacity);

            const result = std.fmt.allocPrint(arena.allocator(), "Hello, {s}!", .{"world"});
            b.use(result);
        }
    }
});
```

Running this with `zig run -OReleaseFast example.zig` produces output similar to the following:
