//! Extra debug and input helpers built on top of the standard library.

const std = @import("std");
const builtin = @import("builtin");
pub const term = @import("debug/term.zig");

/// Cross-platform file handle. On Windows this is a HANDLE, elsewhere a POSIX fd.
/// Zig 0.18 removed POSIX support on Windows, so we cannot use std.posix.fd_t.
const Handle = std.Io.File.Handle;

pub const ReadError = error{
    EndOfStream,
    StreamTooLong,
    InvalidCharacter,
    Overflow,
};

/// Reads one line from stdin into `buf`.
/// Removes '\n' or '\r\n' from the end.
/// If the line is bigger than `buf.len`, it clears the rest of the line
/// from stdin and returns `error.StreamTooLong`.
pub fn readLine(buf: []u8) ReadError![]const u8 {
    return readLineFrom(stdinHandle(), buf);
}

/// Reads one line from stdin and turns it into type `T`.
/// Works with integers (base 10, 0x, 0b, 0o), floats, bools, and enums.
pub fn read(comptime T: type) ReadError!T {
    return readFrom(stdinHandle(), T);
}

/// Reads one line from any OS file handle.
/// This is useful when you want to test with pipes.
pub fn readLineFrom(handle: Handle, buf: []u8) ReadError![]const u8 {
    var index: usize = 0;

    while (true) {
        var byte: [1]u8 = undefined;
        const amt = readByte(handle, &byte) catch return error.EndOfStream;

        if (amt == 0) {
            if (index == 0) return error.EndOfStream;
            break;
        }

        if (byte[0] == '\n') break;

        if (index < buf.len) {
            buf[index] = byte[0];
            index += 1;
        } else {
            // Clear the rest of the line so the next read starts fresh.
            while (true) {
                const n = readByte(handle, &byte) catch break;
                if (n == 0 or byte[0] == '\n') break;
            }
            return error.StreamTooLong;
        }
    }

    // Strip '\r' if the input uses Windows CRLF line endings.
    if (index > 0 and buf[index - 1] == '\r') {
        index -= 1;
    }

    return buf[0..index];
}

/// Reads one line from an OS file handle and parses it into type `T`.
pub fn readFrom(handle: Handle, comptime T: type) ReadError!T {
    var stack_buf: [128]u8 = undefined;
    const raw = try readLineFrom(handle, &stack_buf);
    const trimmed = std.mem.trim(u8, raw, " \t\r");

    if (trimmed.len == 0) return error.InvalidCharacter;

    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, trimmed, 0),
        .float => std.fmt.parseFloat(T, trimmed),
        .bool => if (std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "1"))
            true
        else if (std.mem.eql(u8, trimmed, "false") or std.mem.eql(u8, trimmed, "0"))
            false
        else
            error.InvalidCharacter,
        .@"enum" => std.meta.stringToEnum(T, trimmed) orelse error.InvalidCharacter,
        else => @compileError("read(T) only supports ints, floats, bools, and enums. Use readLine(buf) for strings."),
    };
}

fn stdinHandle() Handle {
    return std.Io.File.stdin().handle;
}

fn readByte(handle: Handle, buf: *[1]u8) !usize {
    if (builtin.os.tag == .windows) {
        var n: std.os.windows.DWORD = 0;
        const ok = windows.ReadFile(handle, buf, 1, &n, null);
        if (ok == windows.BOOL.FALSE) {
            const err = std.os.windows.GetLastError();
            // ERROR_BROKEN_PIPE (109) means the write end was closed.
            if (err == .BROKEN_PIPE or err == .HANDLE_EOF) return 0;
            return error.EndOfStream;
        }
        return n;
    }
    return std.posix.read(handle, buf);
}

// Windows kernel32 declarations. Zig 0.18 does not expose CreatePipe/ReadFile/WriteFile
// as high-level wrappers the way older versions did.
const windows = struct {
    const w = std.os.windows;
    const HANDLE = w.HANDLE;
    const DWORD = w.DWORD;
    const BOOL = w.BOOL;
    const SECURITY_ATTRIBUTES = w.SECURITY_ATTRIBUTES;

    pub extern "kernel32" fn CreatePipe(
        hReadPipe: *HANDLE,
        hWritePipe: *HANDLE,
        lpPipeAttributes: ?*const SECURITY_ATTRIBUTES,
        nSize: DWORD,
    ) callconv(.winapi) BOOL;

    pub extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;

    pub extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;

    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
};

// Test helpers. POSIX pipe/write/close were removed from std.posix in 0.18,
// and Windows has no POSIX at all.

fn testPipe() ![2]Handle {
    if (builtin.os.tag == .windows) {
        var read_h: windows.HANDLE = undefined;
        var write_h: windows.HANDLE = undefined;
        if (windows.CreatePipe(&read_h, &write_h, null, 0) == windows.BOOL.FALSE) return error.Unexpected;
        return .{ read_h, write_h };
    }

    var fds: [2]std.posix.fd_t = undefined;
    if (builtin.link_libc) {
        if (std.c.pipe(&fds) != 0) return error.Unexpected;
        return fds;
    }
    switch (builtin.os.tag) {
        .linux => {
            const rc = std.os.linux.pipe2(&fds, .{});
            if (rc != 0) return error.Unexpected;
            return fds;
        },
        else => @compileError("Add -lc to run pipe tests on non-Linux targets."),
    }
}

fn testWrite(fd: Handle, data: []const u8) !void {
    if (builtin.os.tag == .windows) {
        var written: windows.DWORD = 0;
        const ok = windows.WriteFile(fd, data.ptr, @intCast(data.len), &written, null);
        if (ok == windows.BOOL.FALSE or written != data.len) return error.Unexpected;
        return;
    }
    if (builtin.link_libc) {
        const rc = std.c.write(fd, data.ptr, data.len);
        if (rc < 0) return error.Unexpected;
        return;
    }
    switch (builtin.os.tag) {
        .linux => {
            const rc = std.os.linux.write(fd, data.ptr, data.len);
            if (@as(isize, @bitCast(rc)) < 0) return error.Unexpected;
        },
        else => @compileError("Add -lc to run pipe tests on non-Linux targets."),
    }
}

fn testClose(fd: Handle) void {
    if (builtin.os.tag == .windows) {
        _ = windows.CloseHandle(fd);
        return;
    }
    if (builtin.link_libc) {
        _ = std.c.close(fd);
        return;
    }
    switch (builtin.os.tag) {
        .linux => _ = std.os.linux.close(fd),
        else => {},
    }
}

// Unit Tests (Run with: zig build test)

test "readLineFrom basic and CRLF stripping" {
    const pipe = try testPipe();
    defer testClose(pipe[0]);

    {
        try testWrite(pipe[1], "hello zig\nworld\r\n");
        testClose(pipe[1]);
    }

    var buf: [32]u8 = undefined;

    const line1 = try readLineFrom(pipe[0], &buf);
    try std.testing.expectEqualStrings("hello zig", line1);

    const line2 = try readLineFrom(pipe[0], &buf);
    try std.testing.expectEqualStrings("world", line2);

    // Next read should return EndOfStream
    try std.testing.expectError(error.EndOfStream, readLineFrom(pipe[0], &buf));
}

test "readLineFrom flushes overflow properly" {
    const pipe = try testPipe();
    defer testClose(pipe[0]);

    {
        try testWrite(pipe[1], "this_line_is_way_too_long\nok\n");
        testClose(pipe[1]);
    }

    var small_buf: [4]u8 = undefined;

    // First line overflows our 4-byte buffer, but drains until '\n'
    try std.testing.expectError(error.StreamTooLong, readLineFrom(pipe[0], &small_buf));

    // Second line ("ok") is still read cleanly!
    const next_line = try readLineFrom(pipe[0], &small_buf);
    try std.testing.expectEqualStrings("ok", next_line);
}

test "readFrom parses ints, floats, bools, and enums" {
    const Color = enum { red, green, blue };

    const pipe = try testPipe();
    defer testClose(pipe[0]);

    {
        try testWrite(pipe[1], "42\n0xFF\n3.14\ntrue\ngreen\n");
        testClose(pipe[1]);
    }

    try std.testing.expectEqual(@as(i32, 42), try readFrom(pipe[0], i32));
    try std.testing.expectEqual(@as(u16, 255), try readFrom(pipe[0], u16));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), try readFrom(pipe[0], f64), 0.001);
    try std.testing.expectEqual(true, try readFrom(pipe[0], bool));
    try std.testing.expectEqual(Color.green, try readFrom(pipe[0], Color));
}
