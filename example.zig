const std = @import("std");
const benchmark = @import("benchmark");

pub const main = benchmark.main(.{}, struct {
    // Benchmarks are just public functions
    pub fn arrayListWriter(b: *benchmark.B) !void {
        // Setup is not timed
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        while (b.step()) { // Number of iterations is automatically adjusted for accurate timing
            defer _ = arena.reset(.retain_capacity);

            var a: std.Io.Writer.Allocating = .init(arena.allocator());
            try a.writer.print("Hello, {s}!", .{"world"});

            // `use` is a helper that calls `std.mem.doNotOptimizeAway`
            b.use(a.written());
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
