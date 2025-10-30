pub const Options = struct {
    target: u64 = std.time.ns_per_s, // Target time, in nanoseconds
    limit: u64 = std.time.ns_per_s, // Maximum number of benchmark executions
};

var tty: std.io.tty.Config = .no_color;

pub const Error = error{ WriteFailed, TimerUnsupported, Unexpected };
pub fn main(comptime options: Options, comptime benchmarks: type) fn () Error!void {
    return struct {
        fn actualMain() !void {
            tty = .detect(.stderr());

            if (@import("builtin").mode == .Debug) {
                std.log.warn("Running benchmarks in debug mode!", .{});
            }

            {
                var buf: [64]u8 = undefined;
                const w = std.debug.lockStderrWriter(&buf);
                defer std.debug.unlockStderrWriter();
                try tty.setColor(w, .bold);
                try w.print("{s:<30} {s:>10}    {s}\n", .{ "BENCHMARK", "ITERATIONS", "TIME" });
                try tty.setColor(w, .reset);
            }

            var b: B = .{
                .timer = try .start(),
                .options = options,
            };

            inline for (comptime std.meta.declarations(benchmarks)) |decl| {
                const result = b.run(@field(benchmarks, decl.name));
                try printResult(decl.name, result);
            }
        }
    }.actualMain;
}

fn printResult(name: []const u8, result: anyerror!B.Result) !void {
    var buf: [64]u8 = undefined;
    const w = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();

    if (result) |res| {
        try w.print("{s:<30} {:>10}    {D}/it (σ={D})\n", .{
            name,
            res.total_count,
            res.total_ns / res.total_count,
            std.math.sqrt(res.total_sq_dev / res.total_count),
        });
    } else |err| {
        if (err == error.BenchmarkCanceled) {
            std.log.info("Benchmark '{s}' canceled", .{name});
        } else {
            std.log.err("Benchmark '{s}' failed: {s}", .{ name, @errorName(err) });
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
    }
}

pub const std_options: std.Options = .{ .logFn = logFn };
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buf: [256]u8 = undefined;
    const w = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();

    tty.setColor(w, switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .cyan,
        .debug => .gray,
    }) catch return;
    tty.setColor(w, .bold) catch return;

    const scope_text = if (scope == .default) "" else "(" ++ @tagName(scope) ++ ")";
    w.writeAll(comptime level.asText() ++ scope_text ++ ":") catch return;

    tty.setColor(w, .reset) catch return;

    w.print(" " ++ format ++ "\n", args) catch return;
}

pub const B = struct {
    timer: Timer,
    options: Options,
    next_target: u64 = undefined,
    result: Result = undefined,

    const Result = struct {
        total_ns: u64,
        total_sq_dev: u64,
        total_count: u64,
    };

    fn reset(b: *B) void {
        b.next_target = 0;
        b.result = .{
            .total_ns = 0,
            .total_sq_dev = 0,
            .total_count = 0,
        };
        // timer is reset upon first call to `step`, so no need to reset it here
    }
    noinline fn run(b: *B, comptime benchFn: anytype) anyerror!B.Result {
        b.reset();
        fence.begin();
        try benchFn(b);
        fence.end();
        return b.result;
    }

    pub fn step(b: *B) bool {
        if (b.result.total_count == 0) {
            b.result.total_count = 1;
            b.timer.reset();
            return true;
        }

        const time = b.timer.read();

        // Welford online algorithm
        {
            const mean1 = if (b.result.total_count == 1)
                0
            else
                b.result.total_ns / (b.result.total_count - 1);
            b.result.total_ns += time;
            const mean2 = b.result.total_ns / b.result.total_count;

            const signed: i65 = time;
            b.result.total_sq_dev += @intCast((signed - mean1) * (signed - mean2));
        }

        if (b.result.total_count >= b.options.limit or b.result.total_ns >= b.options.target) {
            return false;
        }

        b.result.total_count += 1;
        b.timer.reset();
        return true;
    }

    pub fn cancel(_: B) error{BenchmarkCanceled} {
        return error.BenchmarkCanceled;
    }
    pub fn use(_: B, x: anytype) void {
        std.mem.doNotOptimizeAway(&x);
    }
};

const Timer: type =
    if (@hasDecl(@import("root"), "benchmark_timer"))
        @import("root").benchmark_timer
    else switch (@import("builtin").cpu.arch) {
        .x86, .x86_64 => RdtscTimer,
        else => std.time.Timer,
    };

const RdtscTimer = struct {
    start_tsc: u64,
    numerator: u32 = 0,
    denominator: u32 = 0,

    /// This function performs calibration and is therefore very expensive. Try to reuse the timer if at all posible.
    pub fn start() std.time.Timer.Error!RdtscTimer {
        // Standard help message for initialization errors
        const help =
            \\
            \\This should not happen on CPUs made in the past decade - please report a bug.
            \\If you are on a very old CPU, try adding `pub const benchmark_timer = std.time.Timer` to your root source file.
        ;

        if (cpuid(1)[3] & (1 << 4) == 0) {
            std.log.err("Your CPU does not have timestamp counter support." ++ help, .{});
            return error.TimerUnsupported;
        }

        if (cpuid(0x80000001)[3] & (1 << 27) == 0) {
            std.log.err("Your CPU does not support RDTSCP." ++ help, .{});
            return error.TimerUnsupported;
        }
        if (cpuid(0x80000007)[3] & (1 << 8) == 0) {
            std.log.err("Your CPU's timestamp counter is not invariant." ++ help, .{});
            return error.TimerUnsupported;
        }

        // TODO: this doesn't work on AMD. If there's a way to do something similar on AMD, this would be preferable over the calibration method.
        // const tsc_denom, const tsc_num, const xtal_freq, _ = cpuid(0x15);
        // if (tsc_denom == 0 or tsc_num == 0 or xtal_freq == 0) {
        //     std.log.err("Unable to determine TSC speed." ++ help, .{});
        //     std.log.warn("tsc/core clock = {}/{}; core clock = {} Hz", .{ tsc_num, tsc_denom, xtal_freq });
        //     std.log.warn("{any}", .{cpuid(0x15)});
        //     return error.TimerUnsupported;
        // }
        // tsc_info = .{
        //     .numerator = tsc_denom,
        //     .denominator = tsc_num * xtal_freq,
        // };

        // Calibrate TSC frequency
        var cal_timer: std.time.Timer = try .start();
        const cal_start, _ = rdtscp();
        std.Thread.sleep(100 * std.time.ns_per_ms);
        const cal_ns = cal_timer.read();
        const cal_end, _ = rdtscp();

        if (cal_end <= cal_start) {
            @panic("rdtsc returned non-monotonic result!");
        }
        const numerator = std.math.cast(u32, cal_ns) orelse {
            // TODO: It's possible to gracefully handle this case, by scaling down both the numerator and denominator.
            //       However, this overflow can only happen if the system slept for over 2 seconds when asked for a 100ms sleep,
            //       in which case it's not in a fit state to be benchmarking anything anyway.
            std.debug.panic("calibration time delta {} does not fit into u32!", .{cal_ns});
        };
        const denominator = std.math.cast(u32, cal_end - cal_start) orelse {
            std.debug.panic("calibration tick delta {} does not fit into u32!", .{cal_end - cal_start});
        };

        // TODO: utilize processor ID
        const tsc, _ = rdtscp();
        return .{
            .start_tsc = tsc,
            .numerator = numerator,
            .denominator = denominator,
        };
    }

    pub fn read(timer: RdtscTimer) u64 {
        const tsc, _ = rdtscp();
        return timer.ns(tsc);
    }
    pub fn reset(timer: *RdtscTimer) void {
        timer.start_tsc, _ = rdtscp();
    }
    pub fn lap(timer: *RdtscTimer) u64 {
        const tsc, _ = rdtscp();
        defer timer.start_tsc = tsc;
        return timer.ns(tsc);
    }

    fn ns(timer: RdtscTimer, current_tsc: u64) u64 {
        const ticks = current_tsc - timer.start_tsc;
        return ticks * timer.numerator / timer.denominator;
    }

    fn rdtscp() struct { u64, u32 } {
        var d: u32 = undefined;
        var a: u32 = undefined;
        const proc_id = asm volatile ("rdtscp"
            : [a] "={eax}" (a),
              [d] "={edx}" (d),
              [c] "={ecx}" (-> u32),
        );
        return .{ @as(u64, d) << 32 | a, proc_id };
    }

    fn cpuid(eax: u32) [4]u32 {
        var a: u32 = undefined;
        var b: u32 = undefined;
        var c: u32 = undefined;
        var d: u32 = undefined;

        asm volatile ("cpuid"
            : [a] "={eax}" (a),
              [b] "={ebx}" (b),
              [c] "={ecx}" (c),
              [d] "={edx}" (d),
            : [a_in] "{eax}" (eax),
        );

        return .{ a, b, c, d };
    }
};

const fence = struct {
    fn begin() void {
        switch (@import("builtin").cpu.arch) {
            .x86, .x86_64 => asm volatile ("lfence"),
            else => {},
        }
    }
    fn end() void {
        switch (@import("builtin").cpu.arch) {
            .x86, .x86_64 => asm volatile ("mfence; lfence"),
            else => {},
        }
    }
};

const std = @import("std");
