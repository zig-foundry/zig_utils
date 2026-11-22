const std = @import("std");
const tui = @import("root.zig");
const cell = tui.cell;
const window = tui.window;

const TestWindow = struct {
    win: window.Window,
    rend: *tui.renderer.Renderer,
    pairs: cell.PairTable,
    gpa: std.mem.Allocator,

    pub fn deinit(self: *TestWindow) void {
        self.win.deinit(self.gpa);
        self.rend.deinit(self.gpa);
        self.gpa.destroy(self.rend);
    }
};

fn makeTestWindow(gpa: std.mem.Allocator, w: u16, h: u16) !TestWindow {
    const rend = try gpa.create(tui.renderer.Renderer);
    rend.* = try tui.renderer.Renderer.init(gpa, w, h);
    var pairs = cell.PairTable{};
    const win = try window.Window.init(gpa, 0, 0, w, h, rend, &pairs, 0);
    return .{
        .win = win,
        .rend = rend,
        .pairs = pairs,
        .gpa = gpa,
    };
}

test "Attr merge and remove" {
    var a = cell.Attr{ .bold = true, .underline = true };
    const b = cell.Attr{ .italic = true, .blink = true };
    a = a.merge(b);
    try std.testing.expect(a.bold and a.underline and a.italic and a.blink);
    a = a.remove(cell.Attr{ .bold = true });
    try std.testing.expect(!a.bold and a.underline);
}

test "ACS constants are non-zero" {
    try std.testing.expect(cell.ACS.ulcorner != 0);
    try std.testing.expect(cell.ACS.hline != 0);
    try std.testing.expect(cell.ACS.vline != 0);
}

test "getyx / getmaxyx / getbegyx" {
    const gpa = std.testing.allocator;
    var tw = try makeTestWindow(gpa, 20, 10);
    defer tw.deinit();
    const win = &tw.win;

    const yx = win.getyx();
    try std.testing.expectEqual(@as(u16, 0), yx.x);
    try std.testing.expectEqual(@as(u16, 0), yx.y);

    win.move(5, 3);
    const yx2 = win.getyx();
    try std.testing.expectEqual(@as(u16, 5), yx2.x);
    try std.testing.expectEqual(@as(u16, 3), yx2.y);

    const max = win.getmaxyx();
    try std.testing.expectEqual(@as(u16, 20), max.x);
    try std.testing.expectEqual(@as(u16, 10), max.y);
}

test "inch and mvinch" {
    const gpa = std.testing.allocator;
    var tw = try makeTestWindow(gpa, 10, 5);
    defer tw.deinit();
    const win = &tw.win;

    win.mvAddChar(2, 1, 'A');
    const c = win.mvinch(2, 1);
    try std.testing.expect(c != null);
    try std.testing.expectEqual(@as(u21, 'A'), c.?.char);
}

test "border writes corners and sides" {
    const gpa = std.testing.allocator;
    var tw = try makeTestWindow(gpa, 5, 4);
    defer tw.deinit();

    const win = &tw.win;

    win.border(0, 0, 0, 0, 0, 0, 0, 0);

    const tl = win.mvinch(0, 0);
    const tr = win.mvinch(4, 0);
    const bl = win.mvinch(0, 3);
    const br = win.mvinch(4, 3);
    try std.testing.expectEqual(cell.ACS.ulcorner, tl.?.char);
    try std.testing.expectEqual(cell.ACS.urcorner, tr.?.char);
    try std.testing.expectEqual(cell.ACS.llcorner, bl.?.char);
    try std.testing.expectEqual(cell.ACS.lrcorner, br.?.char);
}

test "touch flag starts true and untouch works" {
    const gpa = std.testing.allocator;
    var tw = try makeTestWindow(gpa, 5, 5);
    defer tw.deinit();

    const win = &tw.win;

    try std.testing.expect(win.touched);
    win.untouch();
    try std.testing.expect(!win.touched);
    win.touch();
    try std.testing.expect(win.touched);
}

test "erase uses background after bkgdset" {
    const gpa = std.testing.allocator;
    var tw = try makeTestWindow(gpa, 4, 3);
    defer tw.deinit();

    const win = &tw.win;

    win.bkgdset('#', .{ .bold = true }, 0);
    win.erase();

    const c = win.mvinch(1, 1);
    try std.testing.expectEqual(@as(u21, '#'), c.?.char);
    try std.testing.expect(c.?.attr.bold);
}
