const std = @import("std");
const Io = std.Io;

const zig_utils = @import("zig_utils");

const Mode = enum { fast, safe, debug };

pub fn main(init: std.process.Init) !void {
    _ = init;
    var name_buf: [64]u8 = undefined;
    std.debug.print("Enter your name: ", .{});
    const name = try zig_utils.debug.readLine(&name_buf);
    std.debug.print("Enter a number (decimal or 0x hex): ", .{});
    const num = try zig_utils.debug.read(i64);
    std.debug.print("Pick a mode (fast / safe / debug): ", .{});
    const mode = try zig_utils.debug.read(Mode);

    std.debug.print("\n--- Result ---\n", .{});
    std.debug.print("Name : {s}\n", .{name});
    std.debug.print("Num  : {d}\n", .{num});
    std.debug.print("Mode : {s}\n", .{@tagName(mode)});
}
