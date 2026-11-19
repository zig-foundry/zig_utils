//! This module provides ncurses-style cursor movement, attribute toggling (attrOn/attrOff/colorSet), clipped text
//! output (mvAddStr, mvPrint), Unicode box(), erase(), clear(), noutrefresh(), and refresh()

const std = @import("std");
const posix = std.posix;
const cell_mod = @import("cell.zig");
const renderer_mod = @import("renderer.zig");
const input_mod = @import("input.zig");

pub const Window = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    cur_x: u16 = 0,
    cur_y: u16 = 0,
    attr: cell_mod.Attr = .{},
    pair_id: u8 = 0,
    bkgd_char: u21 = ' ',
    bkgd_attr: cell_mod.Attr = .{},
    bkgd_pair: u8 = 0,
    timeout_ms: i32 = -1, // -1 = blocking (default ncurses), 0 = nodelay
    cells: []cell_mod.Cell,
    renderer: *renderer_mod.Renderer,
    pairs: *const cell_mod.PairTable,
    tty_fd: posix.fd_t,

    pub fn init(
        gpa: std.mem.Allocator,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        renderer: *renderer_mod.Renderer,
        pairs: *const cell_mod.PairTable,
        tty_fd: posix.fd_t,
    ) !Window {
        const cells = try gpa.alloc(cell_mod.Cell, @as(usize, width) * @as(usize, height));
        @memset(cells, cell_mod.Cell{});
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .cells = cells,
            .renderer = renderer,
            .pairs = pairs,
            .tty_fd = tty_fd,
        };
    }

    pub fn deinit(self: *Window, gpa: std.mem.Allocator) void {
        gpa.free(self.cells);
    }

    pub fn resize(self: *Window, gpa: std.mem.Allocator, width: u16, height: u16) !void {
        const new_cells = try gpa.alloc(cell_mod.Cell, @as(usize, width) * @as(usize, height));
        @memset(new_cells, cell_mod.Cell{});
        gpa.free(self.cells);
        self.cells = new_cells;
        self.width = width;
        self.height = height;
        self.cur_x = 0;
        self.cur_y = 0;
    }

    pub fn move(self: *Window, x: u16, y: u16) void {
        self.cur_x = x;
        self.cur_y = y;
    }

    pub fn attrOn(self: *Window, a: cell_mod.Attr) void {
        self.attr = self.attr.merge(a);
    }

    pub fn attrOff(self: *Window, a: cell_mod.Attr) void {
        self.attr = self.attr.remove(a);
    }

    pub fn attrSet(self: *Window, a: cell_mod.Attr, pair_id: u8) void {
        self.attr = a;
        self.pair_id = pair_id;
    }

    pub fn colorSet(self: *Window, pair_id: u8) void {
        self.pair_id = pair_id;
    }

    /// Sets the background character, attributes, and color pair used by erase/clear.
    /// Does not modify existing cells. Equivalent to ncurses bkgdset().
    pub fn bkgdset(self: *Window, ch: u21, attr: cell_mod.Attr, pair_id: u8) void {
        self.bkgd_char = ch;
        self.bkgd_attr = attr;
        self.bkgd_pair = pair_id;
    }

    /// Sets the background and applies it to the whole window (like ncurses bkgd).
    pub fn bkgd(self: *Window, ch: u21, attr: cell_mod.Attr, pair_id: u8) void {
        self.bkgdset(ch, attr, pair_id);
        self.erase();
    }

    pub fn nodelay(self: *Window, enabled: bool) void {
        self.timeout_ms = if (enabled) 0 else -1;
    }

    pub fn timeout(self: *Window, ms: i32) void {
        self.timeout_ms = ms;
    }

    pub fn getch(self: *Window) !input_mod.Key {
        return input_mod.readKey(self.tty_fd, self.timeout_ms);
    }

    /// Fills window with the current background character/attribute/pair.
    pub fn erase(self: *Window) void {
        const cp = self.pairs.get(self.bkgd_pair);
        @memset(self.cells, cell_mod.Cell{
            .char = self.bkgd_char,
            .fg = cp.fg,
            .bg = cp.bg,
            .attr = self.bkgd_attr,
        });
        self.cur_x = 0;
        self.cur_y = 0;
    }

    /// Same as erase(), plus forces a full terminal repaint on next doupdate().
    pub fn clear(self: *Window) void {
        self.erase();
        self.renderer.force_redraw = true;
    }

    pub fn addChar(self: *Window, ch: u21) void {
        if (ch == '\n') {
            self.cur_x = 0;
            self.cur_y +|= 1;
            return;
        }
        if (self.cur_x >= self.width or self.cur_y >= self.height) return;

        const cp = self.pairs.get(self.pair_id);
        const idx = @as(usize, self.cur_y) * @as(usize, self.width) + @as(usize, self.cur_x);
        self.cells[idx] = .{
            .char = ch,
            .fg = cp.fg,
            .bg = cp.bg,
            .attr = self.attr,
        };
        self.cur_x += 1;
    }

    pub fn mvAddChar(self: *Window, x: u16, y: u16, ch: u21) void {
        self.move(x, y);
        self.addChar(ch);
    }

    pub fn addStr(self: *Window, text: []const u8) void {
        var it = std.unicode.Utf8View.initUnchecked(text).iterator();
        while (it.nextCodepoint()) |cp| {
            if (self.cur_x >= self.width and cp != '\n') break;
            self.addChar(cp);
        }
    }

    pub fn mvAddStr(self: *Window, x: u16, y: u16, text: []const u8) void {
        self.move(x, y);
        self.addStr(text);
    }

    pub fn print(self: *Window, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.addStr(slice);
    }

    pub fn mvPrint(self: *Window, x: u16, y: u16, comptime fmt: []const u8, args: anytype) void {
        self.move(x, y);
        self.print(fmt, args);
    }

    pub fn box(self: *Window) void {
        if (self.width < 2 or self.height < 2) return;

        const ACS = cell_mod.ACS;

        self.mvAddChar(0, 0, ACS.ulcorner);
        self.mvAddChar(self.width - 1, 0, ACS.urcorner);
        self.mvAddChar(0, self.height - 1, ACS.llcorner);
        self.mvAddChar(self.width - 1, self.height - 1, ACS.lrcorner);

        var x: u16 = 1;
        while (x < self.width - 1) : (x += 1) {
            self.mvAddChar(x, 0, ACS.hline);
            self.mvAddChar(x, self.height - 1, ACS.hline);
        }

        var y: u16 = 1;
        while (y < self.height - 1) : (y += 1) {
            self.mvAddChar(0, y, ACS.vline);
            self.mvAddChar(self.width - 1, y, ACS.vline);
        }
    }

    /// Stage this window into the virtual screen without flushing to stdout yet.
    pub fn noutrefresh(self: *const Window) void {
        var wy: u16 = 0;
        while (wy < self.height) : (wy += 1) {
            const sy = self.y + wy;
            if (sy >= self.renderer.height) break;

            var wx: u16 = 0;
            while (wx < self.width) : (wx += 1) {
                const sx = self.x + wx;
                if (sx >= self.renderer.width) break;

                const w_idx = @as(usize, wy) * @as(usize, self.width) + @as(usize, wx);
                const s_idx = @as(usize, sy) * @as(usize, self.renderer.width) + @as(usize, sx);
                self.renderer.virtual[s_idx] = self.cells[w_idx];
            }
        }
    }

    /// Stage and immediately flush to the terminal (equivalent to wrefresh).
    pub fn refresh(self: *const Window, io: std.Io) !void {
        self.noutrefresh();
        try self.renderer.doupdate(io);
    }
};
