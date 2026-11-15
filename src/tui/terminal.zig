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

fn handleSigwinch(_: c_int) callconv(.c) void {
    sigwinch_flag.store(true, .release);
}

pub fn consumeResize() bool {
    return sigwinch_flag.swap(false, .acq_rel);
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buf: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(io, &buf);
    const out = &writer.interface;
    try out.writeAll(bytes);
    try out.flush();
}
