const std = @import("std");
const zig_utils = @import("zig_utils");

const Mode = enum { fast, safe, debug };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // 1. Demo: SetList mathematical set operations
    var set_a = try zig_utils.SetList(i32).initSlice(gpa, &.{ 10, 20, 20, 30, 40 });
    defer set_a.deinit();

    var set_b = try zig_utils.SetList(i32).initSlice(gpa, &.{ 30, 40, 50, 60 });
    defer set_b.deinit();

    var union_set = try zig_utils.SetList(i32).unionOf(set_a, set_b);
    defer union_set.deinit();

    var inter_set = try zig_utils.SetList(i32).intersectionOf(set_a, set_b);
    defer inter_set.deinit();

    std.debug.print("--- SetList Demo ---\n", .{});
    std.debug.print("Set A        : {any}\n", .{set_a.items});
    std.debug.print("Set B        : {any}\n", .{set_b.items});
    std.debug.print("A union B    : {any}\n", .{union_set.items});
    std.debug.print("A intersect B: {any}\n\n", .{inter_set.items});

    // 2. Demo: Interactive debug input
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
