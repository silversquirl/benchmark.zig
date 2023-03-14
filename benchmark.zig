const std = @import("std");

pub const Options = struct {
    target: u64 = std.time.ns_per_s, // Target time, in nanoseconds
    limit: u64 = std.time.ns_per_s, // Maximum number of benchmark executions
};

pub fn main(comptime options: Options, comptime benchmarks: type) fn () std.fs.File.WriteError!void {
    return struct {
        fn actualMain() !void {
            const stderr = std.io.getStdErr();
            const config = std.debug.detectTTYConfig(stderr);
            const w = stderr.writer();

            if (@import("builtin").mode == .Debug) {
                try config.setColor(w, .Red);
                try config.setColor(w, .Bold);
                try w.print("WARNING: Running benchmarks in debug mode!\n", .{});
                try config.setColor(w, .Reset);
            }

            try config.setColor(w, .Bold);
            try w.print("{s:<30} {s:>10}    {s}\n", .{ "BENCHMARK", "ITERATIONS", "TIME" });
            try config.setColor(w, .Reset);

            inline for (comptime std.meta.declarations(benchmarks)) |decl| {
                if (!decl.is_pub) continue;
                try w.print("{s:<30}", .{decl.name});
                if (runBench(@field(benchmarks, decl.name), options)) |res| {
                    try w.print(" {:>10}    {}/op ({} total)\n", .{
                        res.n,
                        std.fmt.fmtDuration(res.t / res.n),
                        std.fmt.fmtDuration(res.t),
                    });
                } else |err| {
                    if (err == error.BenchmarkCanceled) {
                        try config.setColor(w, .Cyan);
                        try w.writeAll(" CANCELED\n");
                        try config.setColor(w, .Reset);
                    } else {
                        try config.setColor(w, .Red);
                        try w.print(" FAILED: {s}\n", .{@errorName(err)});
                        try config.setColor(w, .Reset);
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    }
                }
            }
        }
    }.actualMain;
}

fn runBench(comptime benchFn: anytype, comptime options: Options) anyerror!BenchResult {
    var b = B{
        .timer = try std.time.Timer.start(),
        .options = options,
    };
    try @call(.never_inline, benchFn, .{&b});
    return b.result;
}

const BenchResult = struct {
    t: u64 = 0,
    n: u64 = 0,
};

pub const B = struct {
    timer: std.time.Timer,
    options: Options,
    next_target: u64 = 0,
    result: BenchResult = .{},

    pub inline fn step(b: *B) bool {
        switch (b.result.n) {
            0 => {
                b.result.n = 1;
                b.timer.reset();
                return true;
            },

            1 => {},

            else => if (b.result.n < b.next_target) {
                b.result.n += 1;
                return true;
            },
        }

        b.result.t += b.timer.lap();
        b.result.t -|= b.timer.read(); // Roughly correct for timer read

        if (b.result.n >= b.options.limit or b.result.t >= b.options.target) {
            return false;
        }

        // Try to predict the future
        const avg = b.result.t / b.result.n;
        const rem = b.options.target - b.result.t;
        var off = rem / (avg + 1);
        if (b.next_target + off > b.options.limit) {
            off = b.options.limit - b.next_target;
        }
        off /= 8;
        b.next_target += off;

        b.result.n += 1;
        b.timer.reset();
        return true;
    }

    pub inline fn cancel(_: B) error{BenchmarkCanceled} {
        return error.BenchmarkCanceled;
    }
    pub inline fn use(_: B, x: anytype) void {
        std.mem.doNotOptimizeAway(&x);
    }
};
