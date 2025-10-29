// TODO: allow using @This() instead of a struct arg?
pub const main = benchmark.main(.{}, struct {
    const B = benchmark.B;

    var world = "world";

    // Benchmarks are just public functions
    pub fn allocatingWriter(b: *B) !void {
        // Setup is not timed
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        while (b.step()) { // Number of iterations is automatically adjusted for accurate timing
            defer _ = arena.reset(.retain_capacity);

            var a: std.Io.Writer.Allocating = .init(arena.allocator());
            try a.writer.print("Hello, {s}!", .{world});

            // `use` is a helper that calls `std.mem.doNotOptimizeAway`
            b.use(a.written());
        }
    }

    pub fn allocPrint(b: *B) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        while (b.step()) {
            defer _ = arena.reset(.retain_capacity);

            const result = std.fmt.allocPrint(arena.allocator(), "Hello, {s}!", .{world});
            b.use(result);
        }
    }

    pub fn failing(_: *B) !void {
        // Errors are handled gracefully and do not prevent further benchmarks from running
        return error.OhNo;
    }
    pub fn cancel(b: *B) !void {
        // Benchmarks can be canceled at any point, for example if they rely on features unavailable on the current target
        return b.cancel();
    }
});

pub const std_options = benchmark.std_options;

const std = @import("std");
const benchmark = @import("benchmark");
