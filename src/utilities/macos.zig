const std = @import("std");
pub const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
});

pub fn getDPI() ?f32 {
    const display = getDisplay();

    if (c.CGDisplayCopyDisplayMode(display)) |mode| {
        defer c.CGDisplayModeRelease(mode);
        const width_px = @as(f32, @floatFromInt(c.CGDisplayModeGetPixelWidth(mode)));
        const width_mm = @as(f32, @floatCast(c.CGDisplayScreenSize(display).width));
        if (width_mm != 0) return std.math.round(width_px / width_mm * 25.4);
    }
    return null;
}

fn getDisplay() c.CGDirectDisplayID {
    const main_display = c.CGMainDisplayID();

    var disp_count: u32 = 0;
    if (c.CGGetActiveDisplayList(0, null, &disp_count) != c.kCGErrorSuccess or disp_count <= 1) return main_display;

    const win_list = c.CGWindowListCopyWindowInfo(c.kCGWindowListOptionOnScreenOnly | c.kCGWindowListExcludeDesktopElements, c.kCGNullWindowID) orelse return main_display;
    defer c.CFRelease(win_list);
    if (c.CFArrayGetCount(win_list) == 0) return main_display;

    const win = @as(c.CFDictionaryRef, @ptrCast(c.CFArrayGetValueAtIndex(win_list, 0)));
    const win_bounds = c.CFDictionaryGetValue(win, c.kCGWindowBounds) orelse return main_display;
    var win_rect: c.CGRect = undefined;
    if (!c.CGRectMakeWithDictionaryRepresentation(@as(c.CFDictionaryRef, @ptrCast(win_bounds)), &win_rect)) return main_display;

    var display: c.CGDirectDisplayID = 0;
    if (c.CGGetDisplaysWithRect(win_rect, 1, &display, &disp_count) == c.kCGErrorSuccess and disp_count > 0) return display;

    return main_display;
}
