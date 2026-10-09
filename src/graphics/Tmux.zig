//! Kitty graphics transport for tmux. APC packets bypass tmux; placeholder
//! cells do not: tmux must own them to clip and repaint its pane grid.
const std = @import("std");
const vaxis = @import("vaxis");
const diacritics = @import("diacritics.zig").values;
const Self = @This();
allocator: std.mem.Allocator,
next: u32,
glyphs: std.AutoHashMap(u32, []u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator, .next = std.crypto.random.intRangeLessThan(u32, 0, 65280), .glyphs = std.AutoHashMap(u32, []u8).init(allocator) };
}

pub fn deinit(self: *Self) void {
    var it = self.glyphs.valueIterator();
    while (it.next()) |glyph| self.allocator.free(glyph.*);
    self.glyphs.deinit();
}

pub fn packet(writer: *std.Io.Writer, bytes: []const u8) !void {
    try writer.writeAll("\x1bPtmux;");
    for (bytes) |b| {
        try writer.writeByte(b);
        if (b == 0x1b) try writer.writeByte(b);
    }
    try writer.writeAll("\x1b\\");
}

fn waitAck(vx: *vaxis.Vaxis, id: u32) bool {
    for (0..100) |_| {
        const ack = vx.graphics_ack.load(.acquire);
        if (ack >> 2 == id) return ack & 3 == 1;
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    return false;
}

pub fn probe(self: *Self, vx: *vaxis.Vaxis, writer: *std.Io.Writer) !void {
    // A real 1x1 RGB query, not the invalid empty query used by older vaxis.
    // Use the same DCS route as image transmissions and require a positive OK.
    const id = self.allocateId();
    for (0..4) |_| {
        vx.graphics_ack.store(0, .release);
        var buf: [160]u8 = undefined;
        try packet(writer, try std.fmt.bufPrint(&buf, "\x1b_Ga=q,t=d,f=24,s=1,v=1,i={d};AAAA\x1b\\", .{id}));
        try writer.flush();
        if (waitAck(vx, id)) return;
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    std.log.err("Kitty graphics query through tmux failed. Enable `set -g allow-passthrough on` and use a terminal supporting Kitty Unicode placeholders.", .{});
    return error.NoGraphicsCapability;
}

fn allocateId(self: *Self) u32 {
    const n = self.next % 65280;
    self.next = (self.next + 1) % 65280;
    // Indexed foreground survives tmux's truecolour downgrade. High byte is
    // carried in a third diacritic (kittyview's MuxSafe ID space).
    return ((n / 255) << 24) | (n % 255 + 1);
}

pub fn transmit(self: *Self, vx: *vaxis.Vaxis, writer: *std.Io.Writer, data: []const u8, width: u16, height: u16) !vaxis.Image {
    const image_id = self.allocateId();
    // tmux can discard a whole DCS packet during a pending redraw. q=0 gives
    // us the final transmission ACK; retransmitting the same ID is idempotent.
    for (0..4) |_| {
        vx.graphics_ack.store(0, .release);
        var offset: usize = 0;
        while (offset < data.len) {
            const end = @min(offset + 4096, data.len);
            const more: u8 = if (end < data.len) 1 else 0;
            var buf: [4352]u8 = undefined;
            const seq = if (offset == 0)
                try std.fmt.bufPrint(&buf, "\x1b_Ga=t,t=d,f=24,q=0,i={d},s={d},v={d},m={d};{s}\x1b\\", .{ image_id, width, height, more, data[offset..end] })
            else
                try std.fmt.bufPrint(&buf, "\x1b_Gm={d};{s}\x1b\\", .{ more, data[offset..end] });
            try packet(writer, seq);
            offset = end;
        }
        try writer.flush();
        if (waitAck(vx, image_id)) return .{ .id = image_id, .width = width, .height = height };
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    return error.GraphicsTransmissionFailed;
}

pub fn place(_: *Self, vx: *vaxis.Vaxis, writer: *std.Io.Writer, image: vaxis.Image, cols: u16, rows: u16) !void {
    var buf: [160]u8 = undefined;
    for (0..4) |_| {
        vx.graphics_ack.store(0, .release);
        try packet(writer, try std.fmt.bufPrint(&buf, "\x1b_Ga=p,U=1,i={d},p=1,c={d},r={d},q=0\x1b\\", .{ image.id, cols, rows }));
        try writer.flush();
        if (waitAck(vx, image.id)) return;
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    return error.GraphicsPlacementFailed;
}

pub fn freeImage(writer: *std.Io.Writer, image_id: u32) void {
    var buf: [96]u8 = undefined;
    packet(writer, std.fmt.bufPrint(&buf, "\x1b_Ga=d,d=I,i={d},q=2\x1b\\", .{image_id}) catch return) catch {};
}

pub fn draw(self: *Self, win: vaxis.Window, image_id: u32) !void {
    for (0..@min(win.height, diacritics.len)) |row| {
        for (0..@min(win.width, diacritics.len)) |col| {
            var buf: [20]u8 = undefined;
            var n: usize = 0;
            for ([_]u21{ 0x10eeee, diacritics[row], diacritics[col], diacritics[image_id >> 24] }) |cp| {
                n += try std.unicode.utf8Encode(cp, buf[n..][0..4]);
            }
            const key: u32 = (@as(u32, @intCast(row)) << 17) | (@as(u32, @intCast(col)) << 8) | (image_id >> 24);
            const entry = try self.glyphs.getOrPut(key);
            if (!entry.found_existing) entry.value_ptr.* = try self.allocator.dupe(u8, buf[0..n]);
            win.writeCell(@intCast(col), @intCast(row), .{
                .char = .{ .grapheme = entry.value_ptr.*, .width = 1 },
                .style = .{ .fg = .{ .index = @truncate(image_id) }, .ul = .{ .index = 1 } },
            });
        }
    }
}

pub fn refresh(allocator: std.mem.Allocator) void {
    // Ghostty <=1.3.1 needs a full client repaint, not an in-place pane update.
    // All ACKs must be received before requesting this (redraw drops DCS).
    const result = std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "tmux", "refresh-client" } }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

test "MuxSafe identifiers are nonzero and unique across the entire space" {
    var graphics = Self.init(std.testing.allocator);
    defer graphics.deinit();
    var seen = std.AutoHashMap(u32, void).init(std.testing.allocator);
    defer seen.deinit();
    for (0..65280) |_| {
        const image_id = graphics.allocateId();
        try std.testing.expect(image_id & 0xffffff >= 1 and image_id & 0xffffff <= 255);
        try std.testing.expect(!seen.contains(image_id));
        try seen.put(image_id, {});
    }
}

test "graphics parser requires OK and preserves IDs" {
    var parser: vaxis.Parser = .{};
    const positive = try parser.parse("\x1b_Gi=123,p=1;OK\x1b\\", null);
    try std.testing.expect(positive.event.?.graphics_response.ok);
    try std.testing.expectEqual(@as(u32, 123), positive.event.?.graphics_response.id);
    const negative = try parser.parse("\x1b_Gi=456;ENOENT: missing\x1b\\", null);
    try std.testing.expect(!negative.event.?.graphics_response.ok);
    try std.testing.expectEqual(@as(u32, 456), negative.event.?.graphics_response.id);
}

test "DCS doubles every ESC and preserves payload" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try packet(&out.writer, "\x1b_Ga=q;AAAA\x1b\\");
    try std.testing.expectEqualStrings("\x1bPtmux;\x1b\x1b_Ga=q;AAAA\x1b\x1b\\\x1b\\", out.written());
}
