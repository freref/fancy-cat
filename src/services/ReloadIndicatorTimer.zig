const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");
const Config = @import("../config/Config.zig");
const Event = @import("../Context.zig").Event;

const Timer = std.time.Timer;

mutex: std.Thread.Mutex,
condition: std.Thread.Condition,
thread: ?std.Thread,
should_quit: bool,
loop: ?*vaxis.Loop(Event),
reload_indicator_duration_ns: u64,
reload_timer: ?Timer,
generation: usize,
pending: bool,
config: *Config,

pub fn init(config: *Config) Self {
    return .{
        .mutex = std.Thread.Mutex{},
        .condition = std.Thread.Condition{},
        .thread = null,
        .should_quit = false,
        .loop = null,
        .reload_indicator_duration_ns = 0,
        .reload_timer = null,
        .generation = 0,
        .pending = false,
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    self.should_quit = true;
    self.condition.signal();
    self.mutex.unlock();

    if (self.thread) |thread| {
        thread.join();
        self.thread = null;
    }
}

pub fn start(self: *Self, loop: ?*vaxis.Loop(Event)) !void {
    self.mutex.lock();
    self.reload_indicator_duration_ns = @as(u64, @intFromFloat(@as(f32, self.config.file_monitor.reload_indicator_duration) * std.time.ns_per_s));
    self.loop = loop;
    self.reload_timer = try Timer.start();
    self.pending = false;
    self.mutex.unlock();

    if (self.thread == null) {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }
}

fn run(self: *Self) void {
    const check_interval_ns = self.reload_indicator_duration_ns / 4;

    while (true) {
        self.mutex.lock();

        if (self.should_quit) {
            self.mutex.unlock();
            break;
        }

        _ = self.condition.timedWait(&self.mutex, check_interval_ns) catch {};

        const current_loop = self.loop;
        const generation = self.generation;
        const pending = self.pending;

        var elapsed_ns: u64 = 0;
        if (self.reload_timer) |*timer| elapsed_ns = timer.read();

        self.mutex.unlock();

        if (pending and (elapsed_ns >= self.reload_indicator_duration_ns)) {
            if (current_loop) |loop| loop.postEvent(.{ .reload_done = generation });

            self.mutex.lock();
            self.pending = false;
            if (self.reload_timer) |*timer| timer.reset();
            self.mutex.unlock();
        }
    }
}

pub fn notifyChange(self: *Self) void {
    self.mutex.lock();
    self.generation += 1;
    if (self.reload_timer) |*timer| timer.reset();
    self.pending = true;
    self.condition.signal();
    self.mutex.unlock();
}
