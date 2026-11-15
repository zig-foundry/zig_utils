//! This module Handles blocking (timeout_ms = -1), non-blocking (
//! timeout_ms = 0, matching nodelay(win, true)), and timed polling (timeout_ms > 0), decoding UTF-8, control keys,
//! CSI sequences, and SIGWINCH.

const std = @import("std");
const posix = std.posix;
const terminal = @import("terminal.zig");

pub const Key = union(enum) {
    char: u21,
    ctrl: u8,
    enter,
    esc,
    backspace,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    delete,
    resize,
    none,
};

pub fn readKey(fd: posix.fd_t, timeout_ms: i32) !Key {
    if (terminal.consumeResize()) return .resize;

    var fds = [_]posix.pollfd{
        .{ .fd = fd, .events = posix.POLL.IN, .revents = 0 },
    };

    const ready = posix.poll(&fds, timeout_ms) catch |err| switch (err) {
        error.Interrupted => return if (terminal.consumeResize()) .resize else .none,
        else => return err,
    };

    if (ready == 0) {
        return if (terminal.consumeResize()) .resize else .none;
    }

    var buf: [32]u8 = undefined;
    const n = posix.read(fd, &buf) catch |err| switch (err) {
        error.WouldBlock, error.Interrupted => return if (terminal.consumeResize()) .resize else .none,
        else => return err,
    };
    if (n == 0) return .none;

    // Escape or ANSI CSI/SS3 sequence
    if (buf[0] == 0x1B) {
        if (n == 1) {
            // Short follow-up poll to distinguish standalone Esc from multi-byte sequence
            const esc_ready = posix.poll(&fds, 15) catch 0;
            if (esc_ready == 0) return .esc;
            const extra = posix.read(fd, buf[1..]) catch 0;
            if (extra == 0) return .esc;
            return parseEscape(buf[0 .. 1 + extra]);
        }
        return parseEscape(buf[0..n]);
    }

    return switch (buf[0]) {
        0x0D, 0x0A => .enter,
        0x09 => .tab,
        0x7F, 0x08 => .backspace,
        0x01...0x1A => .{ .ctrl = 'a' + (buf[0] - 1) },
        else => decodeUtf8(buf[0..n]),
    };
}

fn parseEscape(seq: []const u8) Key {
    if (seq.len < 3) return .esc;

    // SS3 sequences (\x1bO...)
    if (seq[1] == 'O') {
        return switch (seq[2]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            'H' => .home,
            'F' => .end,
            else => .esc,
        };
    }

    // CSI sequences (\x1b[...)
    if (seq[1] == '[') {
        const final = seq[seq.len - 1];
        return switch (final) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            'H' => .home,
            'F' => .end,
            '~' => parseTildeCode(seq[2 .. seq.len - 1]),
            else => .esc,
        };
    }

    return .esc;
}

fn parseTildeCode(param: []const u8) Key {
    if (std.mem.eql(u8, param, "1") or std.mem.eql(u8, param, "7")) return .home;
    if (std.mem.eql(u8, param, "3")) return .delete;
    if (std.mem.eql(u8, param, "4") or std.mem.eql(u8, param, "8")) return .end;
    if (std.mem.eql(u8, param, "5")) return .page_up;
    if (std.mem.eql(u8, param, "6")) return .page_down;
    return .esc;
}

fn decodeUtf8(bytes: []const u8) Key {
    const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return .none;
    if (bytes.len < len) return .none;
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch return .none;
    return .{ .char = cp };
}
