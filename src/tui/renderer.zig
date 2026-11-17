//! This module Mirrors ncurses's newscr (virtual) and curscr (physical) buffers, emitting minimal cursor moves
//! and SGR style updates in a single flush() per doupdate()

const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;
const Color = cell_mod.Color;
const Attr = cell_mod.Attr;

pub const Renderer = struct {
    width: u16,
    height: u16,
    virtual: []Cell,
    physical: []Cell,
    force_redraw: bool = true,

    pub fn init(gpa: std.mem.Allocator, width: u16, height: u16) !Renderer {
        const len = @as(usize, width) * @as(usize, height);
        const virt = try gpa.alloc(Cell, len);
        errdefer gpa.free(virt);
        const phys = try gpa.alloc(Cell, len);

        @memset(virt, Cell{});
        @memset(phys, Cell{});

        return .{
            .width = width,
            .height = height,
            .virtual = virt,
            .physical = phys,
            .force_redraw = true,
        };
    }

    pub fn deinit(self: *Renderer, gpa: std.mem.Allocator) void {
        gpa.free(self.virtual);
        gpa.free(self.physical);
    }

    pub fn resize(self: *Renderer, gpa: std.mem.Allocator, width: u16, height: u16) !void {
        const len = @as(usize, width) * @as(usize, height);
        const new_virt = try gpa.alloc(Cell, len);
        errdefer gpa.free(new_virt);
        const new_phys = try gpa.alloc(Cell, len);

        @memset(new_virt, Cell{});
        @memset(new_phys, Cell{});

        gpa.free(self.virtual);
        gpa.free(self.physical);

        self.width = width;
        self.height = height;
        self.virtual = new_virt;
        self.physical = new_phys;
        self.force_redraw = true;
    }

    /// Equivalent to ncurses doupdate(): diffs virtual against physical and flushes ANSI.
    pub fn doupdate(self: *Renderer, io: std.Io) !void {
        var out_buf: [16384]u8 = undefined;
        var file_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
        const out = &file_writer.interface;

        // Begin synchronized frame update to eliminate flicker
        try out.writeAll("\x1b[?2026h");

        var last_x: ?u16 = null;
        var last_y: ?u16 = null;
        var last_fg: ?Color = null;
        var last_bg: ?Color = null;
        var last_attr: ?Attr = null;

        var y: u16 = 0;
        while (y < self.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.width) : (x += 1) {
                const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
                const cell = self.virtual[idx];

                if (!self.force_redraw and cell.eql(self.physical[idx])) {
                    continue;
                }

                if (last_y != y or last_x != x) {
                    try out.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });
                }

                if (last_attr == null or last_attr.? != cell.attr) {
                    try writeAttr(out, cell.attr);
                    last_attr = cell.attr;
                    // Resetting attributes clears colors, so force re-emit
                    last_fg = null;
                    last_bg = null;
                }

                if (last_fg == null or !std.meta.eql(last_fg.?, cell.fg)) {
                    try writeFg(out, cell.fg);
                    last_fg = cell.fg;
                }

                if (last_bg == null or !std.meta.eql(last_bg.?, cell.bg)) {
                    try writeBg(out, cell.bg);
                    last_bg = cell.bg;
                }

                var utf8_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch blk: {
                    utf8_buf[0] = '?';
                    break :blk 1;
                };
                try out.writeAll(utf8_buf[0..utf8_len]);

                self.physical[idx] = cell;
                last_x = x + 1;
                last_y = y;
            }
        }

        try out.writeAll("\x1b[0m\x1b[?2026l");
        try out.flush();
        self.force_redraw = false;
    }
};

fn writeAttr(out: *std.Io.Writer, attr: Attr) !void {
    try out.writeAll("\x1b[0");
    if (attr.bold) try out.writeAll(";1");
    if (attr.dim) try out.writeAll(";2");
    if (attr.italic) try out.writeAll(";3");
    if (attr.underline) try out.writeAll(";4");
    if (attr.reverse) try out.writeAll(";7");
    try out.writeAll("m");
}

fn writeFg(out: *std.Io.Writer, fg: Color) !void {
    switch (fg) {
        .default => try out.writeAll("\x1b[39m"),
        .ansi => |code| try out.print("\x1b[38;5;{d}m", .{code}),
        .rgb => |c| try out.print("\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
    }
}

fn writeBg(out: *std.Io.Writer, bg: Color) !void {
    switch (bg) {
        .default => try out.writeAll("\x1b[49m"),
        .ansi => |code| try out.print("\x1b[48;5;{d}m", .{code}),
        .rgb => |c| try out.print("\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
    }
}
