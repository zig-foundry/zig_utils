//! TUI Module
//! Reference: ncurses.h for c

const std = @import("std");
const posix = std.posix;

pub const terminal = @import("terminal.zig");
pub const cell = @import("cell.zig");
pub const renderer = @import("renderer.zig");
pub const window = @import("window.zig");
pub const input = @import("input.zig");

pub const Color = cell.Color;
pub const Attr = cell.Attr;
pub const Window = window.Window;
pub const Key = input.Key;
pub const ACS = cell.ACS;

pub const Screen = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    tty_fd: posix.fd_t,
    rend: renderer.Renderer,
    pairs: cell.PairTable = .{},
    stdscr: Window,

    pub fn deinit(self: *Screen) void {
        endwin();
        self.stdscr.deinit(self.gpa);
        self.rend.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    pub fn initPair(self: *Screen, id: u8, fg: Color, bg: Color) void {
        self.pairs.initPair(id, fg, bg);
    }

    pub fn cursSet(self: *Screen, visible: bool) !void {
        try terminal.setCursorVisible(self.io, visible);
    }

    pub fn newwin(self: *Screen, x: u16, y: u16, width: u16, height: u16) !Window {
        return Window.init(
            self.gpa,
            x,
            y,
            width,
            height,
            &self.rend,
            &self.pairs,
            self.tty_fd,
        );
    }

    pub fn delwin(self: *Screen, win: *Window) void {
        win.deinit(self.gpa);
    }

    pub fn doupdate(self: *Screen) !void {
        try self.rend.doupdate(self.io);
    }

    pub fn handleResize(self: *Screen) !void {
        const sz = try terminal.getSize(self.tty_fd);
        try self.rend.resize(self.gpa, sz.cols, sz.rows);
        try self.stdscr.resize(self.gpa, sz.cols, sz.rows);
    }
};

/// Initialize the terminal in raw mode and allocate stdscr.
pub fn initscr(gpa: std.mem.Allocator, io: std.Io) !*Screen {
    const fd = try terminal.enterRawMode(io);
    errdefer terminal.leaveRawMode();

    const sz = try terminal.getSize(fd);
    const scr = try gpa.create(Screen);
    errdefer gpa.destroy(scr);

    scr.* = .{
        .gpa = gpa,
        .io = io,
        .tty_fd = fd,
        .rend = try renderer.Renderer.init(gpa, sz.cols, sz.rows),
        .pairs = .{},
        .stdscr = undefined,
    };
    errdefer scr.rend.deinit(gpa);

    scr.stdscr = try Window.init(
        gpa,
        0,
        0,
        sz.cols,
        sz.rows,
        &scr.rend,
        &scr.pairs,
        fd,
    );

    return scr;
}

/// Restore terminal state immediately. Safe to call in custom panic handlers.
pub fn endwin() void {
    terminal.leaveRawMode();
}
