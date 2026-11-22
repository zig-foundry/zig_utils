//! Cell module
//! Just like ncurses, foreground and
//! background colors are registered
//! into numbered ColorPair slots (1..
//! 255), while slot 0 is always terminal default.

const std = @import("std");

pub const Color = union(enum) {
    default,
    ansi: u8,
    rgb: struct { r: u8, g: u8, b: u8 },

    // Classic ncurses 8-color constants
    pub const black: Color = .{ .ansi = 0 };
    pub const red: Color = .{ .ansi = 1 };
    pub const green: Color = .{ .ansi = 2 };
    pub const yellow: Color = .{ .ansi = 3 };
    pub const blue: Color = .{ .ansi = 4 };
    pub const magenta: Color = .{ .ansi = 5 };
    pub const cyan: Color = .{ .ansi = 6 };
    pub const white: Color = .{ .ansi = 7 };
};

pub const Attr = bitpack struct(u16) {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    blink: bool = false,
    standout: bool = false,
    invisible: bool = false,
    protect: bool = false,
    altcharset: bool = false,
    _pad: u6 = 0,

    const Self = @This();

    pub const normal: Self = .{};

    pub fn merge(self: Self, other: Self) Self {
        return @bitCast(@as(u16, @bitCast(self)) | @as(u16, @bitCast(other)));
    }

    pub fn remove(self: Self, other: Self) Self {
        return @bitCast(@as(u16, @bitCast(self)) & ~@as(u16, @bitCast(other)));
    }
};

pub const ColorPair = struct {
    fg: Color = .default,
    bg: Color = .default,
};

pub const PairTable = struct {
    pairs: [256]ColorPair = @splat(.{}),

    /// Equivalent to ncurses init_pair(pair, fg, bg). Slot 0 is reserved for default.
    pub fn initPair(self: *PairTable, id: u8, fg: Color, bg: Color) void {
        if (id == 0) return;
        self.pairs[id] = .{ .fg = fg, .bg = bg };
    }

    pub fn get(self: *const PairTable, id: u8) ColorPair {
        return self.pairs[id];
    }
};

pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    attr: Attr = .{},

    pub fn eql(a: Cell, b: Cell) bool {
        return a.char == b.char and
            a.attr == b.attr and
            std.meta.eql(a.fg, b.fg) and
            std.meta.eql(a.bg, b.bg);
    }
};

/// Unicode box-drawing characters (preferred over classic ACS on modern terminals).
/// Names follow the common ACS / ncurses naming where practical.
pub const ACS = struct {
    pub const ulcorner: u21 = '┌';
    pub const urcorner: u21 = '┐';
    pub const llcorner: u21 = '└';
    pub const lrcorner: u21 = '┘';
    pub const hline: u21 = '─';
    pub const vline: u21 = '│';
    pub const ltee: u21 = '├';
    pub const rtee: u21 = '┤';
    pub const ttee: u21 = '┬';
    pub const btee: u21 = '┴';
    pub const plus: u21 = '┼';
    pub const diamond: u21 = '◆';
    pub const ckboard: u21 = '░';
    pub const degree: u21 = '°';
    pub const bullet: u21 = '•';
    pub const arrow_right: u21 = '→';
    pub const arrow_left: u21 = '←';
    pub const arrow_up: u21 = '↑';
    pub const arrow_down: u21 = '↓';
};
