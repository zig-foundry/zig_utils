//! This file Stores original termios globally so endwin() can be called
//! from defer or a custom Zig panic handler without needing arguments.

const std = @import("std");
const posix = std.posix;

pub const Size = struct {
    cols: u16,
    rows: u16,
};

var saved_active = std.atomic.Value(bool).init(false);
var saved_fd: posix.fd_t = 0;
var saved_termios: posix.termios = undefined;
var sigwinch_flag = std.atomic.Value(bool).init(false);

fn handleSigwinch(_: posix.SIG) callconv(.c) void {
    sigwinch_flag.store(true, .release);
}

pub fn consumeResize() bool {
    return sigwinch_flag.swap(false, .acq_rel);
}

pub fn enterRawMode(io: std.Io) !posix.fd_t {
    const fd = std.Io.File.stdin().handle;
    const orig = try posix.tcgetattr(fd);
    var raw = orig;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.oflag.OPOST = false;

    raw.cc[@backingInt(posix.V.MIN)] = 0;
    raw.cc[@backingInt(posix.V.TIME)] = 0;

    try posix.tcsetattr(fd, .FLUSH, raw);

    saved_fd = fd;
    saved_termios = orig;
    saved_active.store(true, .release);

    // Register SIGWINCH for live terminal resize detection
    const sa = posix.Sigaction{
        .handler = .{ .handler = handleSigwinch },
        .mask = std.mem.zeroes(posix.sigset_t),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);

    // Enter alternate screen, hide cursor, clear screen
    try writeStdout(io, "\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H");
    return fd;
}

/// Safe to call from both normal cleanup and custom panic handlers.
pub fn leaveRawMode() void {
    if (!saved_active.swap(false, .acq_rel)) return;

    const stdout_fd = std.Io.File.stdout().handle;
    const reset_seq = "\x1b[0m\x1b[?25h\x1b[?1049l";
    _ = posix.system.write(stdout_fd, reset_seq.ptr, reset_seq.len);
    posix.tcsetattr(saved_fd, .FLUSH, saved_termios) catch {};
}

pub fn getSize(fd: posix.fd_t) !Size {
    var ws: posix.winsize = undefined;
    const rc = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(rc) != .SUCCESS) return error.IoctlFailed;
    return .{
        .cols = if (ws.col > 0) ws.col else 80,
        .rows = if (ws.row > 0) ws.row else 24,
    };
}

pub fn setCursorVisible(io: std.Io, visible: bool) !void {
    try writeStdout(io, if (visible) "\x1b[?25h" else "\x1b[?25l");
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buf: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(io, &buf);
    const out = &writer.interface;
    try out.writeAll(bytes);
    try out.flush();
}
