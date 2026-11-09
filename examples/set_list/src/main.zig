//! Complete example and test suite for `zig_utils.SetList` and `zig_utils.Set`.
//! Run with `zig build run` or test with `zig build test`.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const zig_utils = @import("zig_utils");
const SetList = zig_utils.SetList;
const Set = zig_utils.Set;
const AlignedSetList = zig_utils.set_list.Aligned;

// === Custom Types for Examples ===

const Role = enum {
    admin,
    developer,
    reviewer,
    guest,
};

const Point = struct {
    x: i32,
    y: i32,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("=== zig_utils.SetList Complete Example ===\n\n", .{});

    try demoInitializationAndSlices(gpa);
    try demoAddingAndQueries(gpa);
    try demoRemovingAndPopping(gpa);
    try demoMathOperationsNewSet(gpa);
    try demoMathOperationsInPlace(gpa);
    try demoMathRelations(gpa);
    try demoCapacityAndMemory(gpa);
    try demoStringsEnumsStructsAndAlignment(gpa);

    std.debug.print("=== All SetList Demos Finished Successfully ===\n", .{});
}

// === 1. Initialization, Cloning, and Slice Ownership ===

fn demoInitializationAndSlices(gpa: Allocator) !void {
    std.debug.print("--- 1. Initialization & Slice Ownership ---\n", .{});

    // 1.1 Basic empty initialization with `init`
    var basic_set = SetList(i32).init(gpa);
    defer basic_set.deinit();
    std.debug.print("init(): isEmpty = {}, count = {d}, capacity = {d}\n", .{
        basic_set.isEmpty(),
        basic_set.count(),
        basic_set.capacity,
    });

    // 1.2 Pre-allocated capacity with `initCapacity`
    var cap_set = try SetList(i32).initCapacity(gpa, 16);
    defer cap_set.deinit();
    std.debug.print("initCapacity(16): count = {d}, capacity = {d}\n", .{
        cap_set.cardinality(),
        cap_set.capacity,
    });

    // 1.3 Initialize directly from a slice (automatically removes duplicates)
    var slice_set = try SetList(i32).initSlice(gpa, &.{ 10, 20, 10, 30, 20, 40 });
    defer slice_set.deinit();
    std.debug.print("initSlice([10, 20, 10, 30, 20, 40]): items = {any}\n", .{slice_set.items});

    // 1.4 Clone an existing set into an independent copy
    var cloned_set = try slice_set.clone();
    defer cloned_set.deinit();
    _ = try cloned_set.add(50);
    std.debug.print("original after clone: {any}\n", .{slice_set.items});
    std.debug.print("cloned (+50)        : {any}\n", .{cloned_set.items});

    // 1.5 Take ownership of a heap slice with `fromOwnedSlice` (deduplicates in place)
    const raw_heap_slice = try gpa.dupe(i32, &.{ 5, 5, 10, 15, 10, 20 });
    var from_owned = SetList(i32).fromOwnedSlice(gpa, raw_heap_slice);
    std.debug.print("fromOwnedSlice([5, 5, 10, 15, 10, 20]): items = {any}, capacity = {d}\n", .{
        from_owned.items,
        from_owned.capacity,
    });

    // 1.6 Convert set back into a regular owned slice with `toOwnedSlice`
    // This empties `from_owned` so we free `owned_slice` directly.
    const owned_slice = try from_owned.toOwnedSlice();
    defer gpa.free(owned_slice);
    std.debug.print("toOwnedSlice(): slice = {any}, set isEmpty = {}\n", .{
        owned_slice,
        from_owned.isEmpty(),
    });

    // 1.7 Convert set into a sentinel-terminated slice with `toOwnedSliceSentinel`
    var char_set = try SetList(u8).initSlice(gpa, "abacab");
    defer char_set.deinit();
    const c_str = try char_set.toOwnedSliceSentinel(0);
    defer gpa.free(c_str);
    std.debug.print("toOwnedSliceSentinel(0) from \"abacab\": \"{s}\" (len = {d})\n\n", .{
        c_str,
        c_str.len,
    });
}

// === 2. Adding Elements and Querying the Set ===

fn demoAddingAndQueries(gpa: Allocator) !void {
    std.debug.print("--- 2. Adding Elements & Queries ---\n", .{});

    // We can also use the `Set` alias, which is identical to `SetList`.
    var set = try Set(i32).initCapacity(gpa, 8);
    defer set.deinit();

    // 2.1 `add` returns true when the item is new, and false when it is a duplicate
    const added_10 = try set.add(10);
    const added_20 = try set.add(20);
    const added_10_again = try set.add(10);
    std.debug.print("add(10) = {}, add(20) = {}, add(10) again = {}\n", .{
        added_10,
        added_20,
        added_10_again,
    });

    // 2.2 `append` works like ArrayList.append but ignores duplicates
    try set.append(30);
    try set.append(20);

    // 2.3 `addAssumeCapacity` and `addSliceAssumeCapacity` when capacity is known
    _ = set.addAssumeCapacity(40);
    set.addSliceAssumeCapacity(&.{ 40, 50, 60 });

    // 2.4 `addBounded` returns `error.OutOfMemory` if capacity is full and item is new
    _ = try set.addBounded(70);
    _ = try set.addBounded(10); // Succeeds even if full when item is already in the set

    // 2.5 `insert` places a unique item at a specific index and shifts the rest
    const inserted_front = try set.insert(0, 5);
    const inserted_dup = try set.insert(0, 20); // Returns false because 20 already exists
    std.debug.print("insert(0, 5) = {}, insert(0, 20) = {}\n", .{ inserted_front, inserted_dup });

    // 2.6 `addSlice` and `appendSlice` add multiple items at once
    try set.addSlice(&.{ 70, 80, 90 });
    try set.appendSlice(&.{ 90, 100 });

    std.debug.print("Current set items: {any}\n", .{set.items});

    // 2.7 Queries: `cardinality`, `count`, `isEmpty`, `contains`, `indexOf`, `last`, `lastPtr`
    std.debug.print("cardinality() = {d}, count() = {d}, isEmpty() = {}\n", .{
        set.cardinality(),
        set.count(),
        set.isEmpty(),
    });
    std.debug.print("contains(30) = {}, contains(999) = {}\n", .{
        set.contains(30),
        set.contains(999),
    });
    std.debug.print("indexOf(40) = {any}, indexOf(999) = {any}\n", .{
        set.indexOf(40),
        set.indexOf(999),
    });
    std.debug.print("last() = {any}, lastPtr().* = {d}\n\n", .{
        set.last(),
        set.lastPtr().?.*,
    });
}

// === 3. Removing Elements and Popping ===

fn demoRemovingAndPopping(gpa: Allocator) !void {
    std.debug.print("--- 3. Removing Elements & Popping ---\n", .{});

    var set = try SetList(i32).initSlice(gpa, &.{ 10, 20, 30, 40, 50, 60, 70 });
    defer set.deinit();
    std.debug.print("Start items           : {any}\n", .{set.items});

    // 3.1 `remove` finds the value and shifts remaining items to keep order
    const removed_30 = set.remove(30);
    const removed_99 = set.remove(99);
    std.debug.print("remove(30) = {}, remove(99) = {} -> {any}\n", .{
        removed_30,
        removed_99,
        set.items,
    });

    // 3.2 `swapRemoveItem` finds the value and swaps it with the last item in O(1)
    const swap_removed_20 = set.swapRemoveItem(20);
    std.debug.print("swapRemoveItem(20) = {} -> {any}\n", .{ swap_removed_20, set.items });

    // 3.3 `orderedRemove` removes by index and preserves order
    const ord_val = set.orderedRemove(1);
    std.debug.print("orderedRemove(1) returned {d} -> {any}\n", .{ ord_val, set.items });

    // 3.4 `swapRemove` removes by index and fills the slot with the last element
    const swap_val = set.swapRemove(0);
    std.debug.print("swapRemove(0) returned {d} -> {any}\n", .{ swap_val, set.items });

    // 3.5 `pop` removes and returns the last item, or null when empty
    const popped = set.pop();
    std.debug.print("pop() returned {any} -> {any}\n\n", .{ popped, set.items });
}

// === 4. Mathematical Set Operations (Creating New Sets) ===

fn demoMathOperationsNewSet(gpa: Allocator) !void {
    std.debug.print("--- 4. Math Operations (New Sets) ---\n", .{});

    var a = try SetList(i32).initSlice(gpa, &.{ 1, 2, 3, 4 });
    defer a.deinit();

    var b = try SetList(i32).initSlice(gpa, &.{ 3, 4, 5, 6 });
    defer b.deinit();

    // 4.1 Union (A ∪ B): Elements in A or B
    var union_set = try SetList(i32).unionOf(a, b);
    defer union_set.deinit();

    // 4.2 Intersection (A ∩ B): Elements in both A and B
    var inter_set = try SetList(i32).intersectionOf(a, b);
    defer inter_set.deinit();

    // 4.3 Difference (A \ B): Elements in A that are not in B
    var diff_ab = try SetList(i32).differenceOf(a, b);
    defer diff_ab.deinit();

    // 4.4 Difference (B \ A): Elements in B that are not in A
    var diff_ba = try SetList(i32).differenceOf(b, a);
    defer diff_ba.deinit();

    // 4.5 Symmetric Difference (A Δ B): Elements in A or B, but not both
    var sym_diff = try SetList(i32).symmetricDifferenceOf(a, b);
    defer sym_diff.deinit();

    std.debug.print("Set A                      : {any}\n", .{a.items});
    std.debug.print("Set B                      : {any}\n", .{b.items});
    std.debug.print("Union (A ∪ B)              : {any}\n", .{union_set.items});
    std.debug.print("Intersection (A ∩ B)       : {any}\n", .{inter_set.items});
    std.debug.print("Difference (A \\ B)         : {any}\n", .{diff_ab.items});
    std.debug.print("Difference (B \\ A)         : {any}\n", .{diff_ba.items});
    std.debug.print("Symmetric Diff (A Δ B)     : {any}\n\n", .{sym_diff.items});
}

// === 5. Mathematical Set Operations (In-Place Mutation) ===

fn demoMathOperationsInPlace(gpa: Allocator) !void {
    std.debug.print("--- 5. Math Operations (In-Place) ---\n", .{});

    var other = try SetList(i32).initSlice(gpa, &.{ 30, 40, 50 });
    defer other.deinit();

    // 5.1 `unionWith` (A <- A ∪ B)
    var s1 = try SetList(i32).initSlice(gpa, &.{ 10, 20, 30 });
    defer s1.deinit();
    try s1.unionWith(other);
    std.debug.print("unionWith([30, 40, 50])              : {any}\n", .{s1.items});

    // 5.2 `intersectWith` (A <- A ∩ B) - runs in place with zero allocations
    var s2 = try SetList(i32).initSlice(gpa, &.{ 10, 20, 30, 40 });
    defer s2.deinit();
    s2.intersectWith(other);
    std.debug.print("intersectWith([30, 40, 50])          : {any}\n", .{s2.items});

    // 5.3 `differenceWith` (A <- A \ B) - runs in place with zero allocations
    var s3 = try SetList(i32).initSlice(gpa, &.{ 10, 20, 30, 40 });
    defer s3.deinit();
    s3.differenceWith(other);
    std.debug.print("differenceWith([30, 40, 50])         : {any}\n", .{s3.items});

    // 5.4 `symmetricDifferenceWith` (A <- A Δ B)
    var s4 = try SetList(i32).initSlice(gpa, &.{ 10, 20, 30 });
    defer s4.deinit();
    try s4.symmetricDifferenceWith(other);
    std.debug.print("symmetricDifferenceWith([30, 40, 50]): {any}\n\n", .{s4.items});
}

// === 6. Mathematical Set Relations (Predicates) ===

fn demoMathRelations(gpa: Allocator) !void {
    std.debug.print("--- 6. Mathematical Set Relations ---\n", .{});

    var small = try SetList(i32).initSlice(gpa, &.{ 2, 4 });
    defer small.deinit();

    var big = try SetList(i32).initSlice(gpa, &.{ 1, 2, 3, 4 });
    defer big.deinit();

    var same_reordered = try SetList(i32).initSlice(gpa, &.{ 4, 2 });
    defer same_reordered.deinit();

    var disjoint = try SetList(i32).initSlice(gpa, &.{ 10, 20 });
    defer disjoint.deinit();

    std.debug.print("small = {any}, big = {any}, reordered = {any}, disjoint = {any}\n", .{
        small.items,
        big.items,
        same_reordered.items,
        disjoint.items,
    });
    std.debug.print("small.isSubsetOf(big)               : {}\n", .{small.isSubsetOf(big)});
    std.debug.print("small.isProperSubsetOf(big)         : {}\n", .{small.isProperSubsetOf(big)});
    std.debug.print("small.isProperSubsetOf(reordered)   : {}\n", .{small.isProperSubsetOf(same_reordered)});
    std.debug.print("big.isSupersetOf(small)             : {}\n", .{big.isSupersetOf(small)});
    std.debug.print("big.isProperSupersetOf(small)       : {}\n", .{big.isProperSupersetOf(small)});
    std.debug.print("small.eql(reordered) (order-free)   : {}\n", .{small.eql(same_reordered)});
    std.debug.print("small.isDisjointWith(disjoint)      : {}\n", .{small.isDisjointWith(disjoint)});
    std.debug.print("small.isDisjointWith(big)           : {}\n\n", .{small.isDisjointWith(big)});
}

// === 7. Capacity, Memory Management, and Pointer Locking ===

fn demoCapacityAndMemory(gpa: Allocator) !void {
    std.debug.print("--- 7. Capacity, Memory & Pointer Stability ---\n", .{});

    var set = SetList(i32).init(gpa);
    defer set.deinit();

    // 7.1 `ensureTotalCapacityPrecise` and `ensureUnusedCapacity`
    try set.ensureTotalCapacityPrecise(10);
    std.debug.print("After ensureTotalCapacityPrecise(10): cap = {d}\n", .{set.capacity});

    try set.addSlice(&.{ 1, 2, 3, 4, 5, 6 });
    try set.ensureUnusedCapacity(10);
    std.debug.print("After adding 6 items + ensureUnusedCapacity(10): len = {d}, cap = {d}\n", .{
        set.cardinality(),
        set.capacity,
    });

    // 7.2 Inspect `allocatedSlice` and `unusedCapacitySlice`
    std.debug.print("allocatedSlice().len = {d}, unusedCapacitySlice().len = {d}\n", .{
        set.allocatedSlice().len,
        set.unusedCapacitySlice().len,
    });

    // 7.3 `lockPointers` and `unlockPointers` protect active element references
    set.lockPointers();
    const first_ptr = &set.items[0];
    std.debug.print("Locked pointer to first element: {d}\n", .{first_ptr.*});
    set.unlockPointers();

    // 7.4 `shrinkRetainingCapacity` drops items from the end without freeing memory
    set.shrinkRetainingCapacity(4);
    std.debug.print("After shrinkRetainingCapacity(4): items = {any}, cap = {d}\n", .{
        set.items,
        set.capacity,
    });

    // 7.5 `shrinkAndFreePrecise` and `shrinkAndFree` shrink the buffer down
    try set.shrinkAndFreePrecise(3);
    std.debug.print("After shrinkAndFreePrecise(3)   : items = {any}, cap = {d}\n", .{
        set.items,
        set.capacity,
    });

    set.shrinkAndFree(2);
    std.debug.print("After shrinkAndFree(2)          : items = {any}, cap = {d}\n", .{
        set.items,
        set.capacity,
    });

    // 7.6 `clearRetainingCapacity` vs `clearAndFree`
    set.clearRetainingCapacity();
    std.debug.print("After clearRetainingCapacity()  : len = {d}, cap = {d}\n", .{
        set.cardinality(),
        set.capacity,
    });

    set.clearAndFree();
    std.debug.print("After clearAndFree()            : len = {d}, cap = {d}\n\n", .{
        set.cardinality(),
        set.capacity,
    });
}

// === 8. Strings, Enums, Structs, and Custom Alignment ===

fn demoStringsEnumsStructsAndAlignment(gpa: Allocator) !void {
    std.debug.print("--- 8. Strings, Enums, Structs & Custom Alignment ---\n", .{});

    // 8.1 Strings (`[]const u8`) compare character bytes, not slice pointers
    var tags = SetList([]const u8).init(gpa);
    defer tags.deinit();

    const dynamic_zig = try gpa.dupe(u8, "zig");
    defer gpa.free(dynamic_zig);

    _ = try tags.add("zig");
    _ = try tags.add("systems");
    _ = try tags.add(dynamic_zig); // Recognized as a duplicate of "zig"!

    std.debug.print("String SetList: ", .{});
    printStringSlice(tags.items);
    std.debug.print(" (count = {d})\n", .{tags.cardinality()});

    // 8.2 Enums
    var roles = try SetList(Role).initSlice(gpa, &.{ .admin, .developer, .admin, .reviewer });
    defer roles.deinit();
    std.debug.print("Enum SetList  : {any}\n", .{roles.items});

    // 8.3 Structs
    var points = SetList(Point).init(gpa);
    defer points.deinit();
    _ = try points.add(.{ .x = 0, .y = 0 });
    _ = try points.add(.{ .x = 10, .y = 20 });
    _ = try points.add(.{ .x = 0, .y = 0 }); // Duplicate struct ignored
    std.debug.print("Struct SetList: {any}\n", .{points.items});

    // 8.4 Custom SIMD / Page Alignment with `set_list.Aligned`
    var aligned_set = AlignedSetList(u32, .@"64").init(gpa);
    defer aligned_set.deinit();
    try aligned_set.addSlice(&.{ 100, 200, 300, 100 });
    const addr = @intFromPtr(aligned_set.items.ptr);
    std.debug.print("64-byte AlignedSetList: items = {any}, aligned to 64 bytes = {}\n\n", .{
        aligned_set.items,
        addr % 64 == 0,
    });
}

fn printStringSlice(strings: []const []const u8) void {
    std.debug.print("{{ ", .{});
    for (strings, 0..) |s, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("\"{s}\"", .{s});
    }
    std.debug.print(" }}", .{});
}

// === Comprehensive Unit Tests (`zig build test`) ===

test "SetList: init, initCapacity, initSlice, and clone" {
    const a = testing.allocator;

    var s1 = SetList(i32).init(a);
    defer s1.deinit();
    try testing.expect(s1.isEmpty());
    try testing.expectEqual(@as(usize, 0), s1.cardinality());
    try testing.expectEqual(@as(usize, 0), s1.count());
    try testing.expectEqual(@as(?i32, null), s1.last());
    try testing.expectEqual(@as(?*i32, null), s1.lastPtr());

    var s2 = try SetList(i32).initCapacity(a, 32);
    defer s2.deinit();
    try testing.expectEqual(@as(usize, 32), s2.capacity);

    var s3 = try SetList(i32).initSlice(a, &.{ 5, 1, 5, 2, 1, 3 });
    defer s3.deinit();
    try testing.expectEqualSlices(i32, &.{ 5, 1, 2, 3 }, s3.items);

    var s4 = try s3.clone();
    defer s4.deinit();
    try testing.expect(s3.eql(s4));
    try testing.expectEqualSlices(i32, s3.items, s4.items);
}

test "SetList: add, append, addAssumeCapacity, addBounded, and insert" {
    const a = testing.allocator;

    var set = try Set(i32).initCapacity(a, 4);
    defer set.deinit();

    // `addAssumeCapacity`
    try testing.expect(set.addAssumeCapacity(10));
    try testing.expect(!set.addAssumeCapacity(10));

    // `addBounded`
    try testing.expect(try set.addBounded(20));
    try testing.expect(try set.addBounded(30));
    try testing.expect(try set.addBounded(40));

    // Set is now at capacity (4). Adding a duplicate with `addBounded` still returns false without error.
    try testing.expect(!(try set.addBounded(20)));
    // Adding a new element when full returns `error.OutOfMemory`.
    try testing.expectError(error.OutOfMemory, set.addBounded(50));

    // `insert` grows capacity automatically when needed
    try testing.expect(try set.insert(0, 5));
    try testing.expect(!(try set.insert(2, 20))); // Duplicate
    try testing.expect(try set.insert(2, 15));
    try testing.expectEqualSlices(i32, &.{ 5, 10, 15, 20, 30, 40 }, set.items);

    // `last` and `lastPtr`
    try testing.expectEqual(@as(?i32, 40), set.last());
    try testing.expectEqual(@as(i32, 40), set.lastPtr().?.*);
}

test "SetList: remove, swapRemoveItem, orderedRemove, swapRemove, and pop" {
    const a = testing.allocator;

    var set = try SetList(i32).initSlice(a, &.{ 10, 20, 30, 40, 50, 60 });
    defer set.deinit();

    // `remove` preserves order
    try testing.expect(set.remove(20));
    try testing.expect(!set.remove(999));
    try testing.expectEqualSlices(i32, &.{ 10, 30, 40, 50, 60 }, set.items);

    // `swapRemoveItem` swaps with the end
    try testing.expect(set.swapRemoveItem(30));
    try testing.expect(!set.swapRemoveItem(30));
    try testing.expectEqualSlices(i32, &.{ 10, 60, 40, 50 }, set.items);

    // `orderedRemove` by index
    try testing.expectEqual(@as(i32, 60), set.orderedRemove(1));
    try testing.expectEqualSlices(i32, &.{ 10, 40, 50 }, set.items);

    // `swapRemove` by index
    try testing.expectEqual(@as(i32, 10), set.swapRemove(0));
    try testing.expectEqualSlices(i32, &.{ 50, 40 }, set.items);

    // `pop`
    try testing.expectEqual(@as(?i32, 40), set.pop());
    try testing.expectEqual(@as(?i32, 50), set.pop());
    try testing.expectEqual(@as(?i32, null), set.pop());
}

test "SetList: fromOwnedSlice, toOwnedSlice, and toOwnedSliceSentinel" {
    const a = testing.allocator;

    const raw = try a.dupe(u8, "banana");
    var set = SetList(u8).fromOwnedSlice(a, raw);
    defer set.deinit();
    try testing.expectEqualStrings("ban", set.items);

    var clone_for_sentinel = try set.clone();
    defer clone_for_sentinel.deinit();

    const owned = try set.toOwnedSlice();
    defer a.free(owned);
    try testing.expectEqualStrings("ban", owned);
    try testing.expect(set.isEmpty());

    const sentinel_slice = try clone_for_sentinel.toOwnedSliceSentinel(0);
    defer a.free(sentinel_slice);
    try testing.expectEqualStrings("ban", sentinel_slice);
    try testing.expectEqual(@as(u8, 0), sentinel_slice[sentinel_slice.len]);
}

test "SetList: all mathematical set operations and laws" {
    const a = testing.allocator;

    var set_a = try SetList(i32).initSlice(a, &.{ 1, 2, 3, 4 });
    defer set_a.deinit();

    var set_b = try SetList(i32).initSlice(a, &.{ 3, 4, 5, 6 });
    defer set_b.deinit();

    // New set operations
    var u = try SetList(i32).unionOf(set_a, set_b);
    defer u.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4, 5, 6 }, u.items);

    var inter = try SetList(i32).intersectionOf(set_a, set_b);
    defer inter.deinit();
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, inter.items);

    var diff = try SetList(i32).differenceOf(set_a, set_b);
    defer diff.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, diff.items);

    var sym = try SetList(i32).symmetricDifferenceOf(set_a, set_b);
    defer sym.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2, 5, 6 }, sym.items);

    // Verify identity: (A ∪ B) \ (A ∩ B) == (A Δ B)
    var u_minus_inter = try SetList(i32).differenceOf(u, inter);
    defer u_minus_inter.deinit();
    try testing.expect(u_minus_inter.eql(sym));

    // In-place operations
    var inplace = try set_a.clone();
    defer inplace.deinit();

    try inplace.unionWith(set_b);
    try testing.expect(inplace.eql(u));

    inplace.intersectWith(set_b);
    try testing.expect(inplace.eql(set_b));

    inplace.differenceWith(set_a);
    try testing.expectEqualSlices(i32, &.{ 5, 6 }, inplace.items);

    try inplace.symmetricDifferenceWith(set_b);
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, inplace.items);
}

test "SetList: subset, proper subset, superset, disjoint, and equality" {
    const a = testing.allocator;

    var empty = SetList(i32).init(a);
    defer empty.deinit();

    var s1 = try SetList(i32).initSlice(a, &.{ 1, 2 });
    defer s1.deinit();

    var s2 = try SetList(i32).initSlice(a, &.{ 2, 1 });
    defer s2.deinit();

    var s3 = try SetList(i32).initSlice(a, &.{ 1, 2, 3 });
    defer s3.deinit();

    var s4 = try SetList(i32).initSlice(a, &.{ 8, 9 });
    defer s4.deinit();

    // Empty set is a proper subset of any non-empty set and disjoint with everything
    try testing.expect(empty.isSubsetOf(s1));
    try testing.expect(empty.isProperSubsetOf(s1));
    try testing.expect(empty.isDisjointWith(s1));
    try testing.expect(empty.isDisjointWith(empty));

    // Equality is independent of insertion order
    try testing.expect(s1.eql(s2));
    try testing.expect(s1.isSubsetOf(s2));
    try testing.expect(!s1.isProperSubsetOf(s2));
    try testing.expect(s1.isSupersetOf(s2));
    try testing.expect(!s1.isProperSupersetOf(s2));

    // Proper subset & superset
    try testing.expect(s1.isSubsetOf(s3));
    try testing.expect(s1.isProperSubsetOf(s3));
    try testing.expect(s3.isSupersetOf(s1));
    try testing.expect(s3.isProperSupersetOf(s1));

    // Disjoint check
    try testing.expect(s1.isDisjointWith(s4));
    try testing.expect(!s1.isDisjointWith(s3));
}

test "SetList: capacity management, shrinking, clearing, and zero-sized types" {
    const a = testing.allocator;

    var set = SetList(u32).init(a);
    defer set.deinit();

    try set.ensureTotalCapacity(20);
    try testing.expect(set.capacity >= 20);

    try set.addSlice(&.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    try testing.expectEqual(@as(usize, 8), set.cardinality());
    try testing.expectEqual(set.capacity, set.allocatedSlice().len);
    try testing.expectEqual(set.capacity - 8, set.unusedCapacitySlice().len);

    set.shrinkRetainingCapacity(5);
    try testing.expectEqualSlices(u32, &.{ 1, 2, 3, 4, 5 }, set.items);

    try set.shrinkAndFreePrecise(4);
    try testing.expectEqual(@as(usize, 4), set.capacity);
    try testing.expectEqualSlices(u32, &.{ 1, 2, 3, 4 }, set.items);

    set.shrinkAndFree(2);
    try testing.expectEqual(@as(usize, 2), set.capacity);
    try testing.expectEqualSlices(u32, &.{ 1, 2 }, set.items);

    set.clearRetainingCapacity();
    try testing.expect(set.isEmpty());
    try testing.expectEqual(@as(usize, 2), set.capacity);

    set.clearAndFree();
    try testing.expectEqual(@as(usize, 0), set.capacity);

    // Zero-sized types (`u0` / `void`) never allocate memory
    var zst_set = SetList(u0).init(testing.failing_allocator);
    defer zst_set.deinit();
    try testing.expect(try zst_set.add(0));
    try testing.expect(!(try zst_set.add(0)));
    try testing.expectEqual(@as(usize, 1), zst_set.cardinality());
}

test "SetList: strings, enums, structs, and custom alignment" {
    const a = testing.allocator;

    // Strings
    var words = SetList([]const u8).init(a);
    defer words.deinit();
    const heap_hello = try a.dupe(u8, "hello");
    defer a.free(heap_hello);

    try testing.expect(try words.add("hello"));
    try testing.expect(!(try words.add(heap_hello)));
    try testing.expect(try words.add("world"));
    try testing.expectEqual(@as(usize, 2), words.cardinality());

    // Enums
    var roles = try SetList(Role).initSlice(a, &.{ .admin, .guest, .admin });
    defer roles.deinit();
    try testing.expectEqual(@as(usize, 2), roles.cardinality());
    try testing.expect(roles.contains(.guest));

    // Structs
    var pts = SetList(Point).init(a);
    defer pts.deinit();
    try testing.expect(try pts.add(.{ .x = 1, .y = 2 }));
    try testing.expect(!(try pts.add(.{ .x = 1, .y = 2 })));
    try testing.expect(pts.contains(.{ .x = 1, .y = 2 }));

    // Custom Alignment
    var aligned = AlignedSetList(u64, .@"64").init(a);
    defer aligned.deinit();
    try aligned.addSlice(&.{ 11, 22, 33, 11 });
    try testing.expectEqual(@as(usize, 0), @intFromPtr(aligned.items.ptr) % 64);
    try testing.expectEqualSlices(u64, &.{ 11, 22, 33 }, aligned.items);
}
