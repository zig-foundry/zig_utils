//! A contiguous, growable mathematical set backed by an array slice.
//! Preserves insertion order and guarantees that every element is unique.

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

/// A contiguous, growable set of unique items in memory.
/// Stores its own `Allocator` and keeps items in insertion order.
pub fn SetList(comptime T: type) type {
    return Aligned(T, null);
}

/// A contiguous, growable set of unique items with custom memory alignment.
/// If `alignment` is `null`, the natural `@alignOf(T)` is used.
pub fn Aligned(comptime T: type, comptime alignment: ?mem.Alignment) type {
    if (alignment) |a| {
        if (a.toByteUnits() == @alignOf(T)) {
            return Aligned(T, null);
        }
    }
    return struct {
        const Self = @This();

        /// Unique elements currently in the set.
        /// Read this slice directly, but do not write duplicate values into it.
        items: Slice,
        /// How many `T` values this set can hold without allocating more memory.
        capacity: usize,
        /// The allocator used by this set.
        allocator: Allocator,
        /// Safety lock used to catch pointer invalidation bugs.
        pointer_stability: debug.SafetyLock,

        pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;

        pub fn SentinelSlice(comptime s: T) type {
            return if (alignment) |a| ([:s]align(a.toByteUnits()) T) else [:s]T;
        }

        /// Creates an empty set using `gpa`.
        /// Free the memory with `deinit` or `toOwnedSlice`.
        pub fn init(gpa: Allocator) Self {
            return Self{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = gpa,
                .pointer_stability = .{},
            };
        }

        /// Creates an empty set with enough space for `num` elements.
        /// Free the memory with `deinit` or `toOwnedSlice`.
        pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self {
            var self = Self.init(gpa);
            try self.ensureTotalCapacityPrecise(num);
            return self;
        }

        /// Creates a set initialized with the unique items from `slice`.
        pub fn initSlice(gpa: Allocator, slice: []const T) Allocator.Error!Self {
            var self = try Self.initCapacity(gpa, slice.len);
            errdefer self.deinit();
            self.addSliceAssumeCapacity(slice);
            return self;
        }

        /// Frees all memory allocated by this set.
        pub fn deinit(self: Self) void {
            self.pointer_stability.assertUnlocked();
            if (@sizeOf(T) > 0) {
                self.allocator.free(self.allocatedSlice());
            }
        }

        /// Locks element pointers so any call that would invalidate them triggers an assertion.
        pub fn lockPointers(self: *Self) void {
            self.pointer_stability.lockShared();
        }

        /// Unlocks one call to `lockPointers`.
        pub fn unlockPointers(self: *Self) void {
            self.pointer_stability.unlockShared();
        }

        /// Takes ownership of `slice` allocated with `gpa` and removes any duplicate items in place.
        pub fn fromOwnedSlice(gpa: Allocator, slice: Slice) Self {
            var write_idx: usize = 0;
            for (slice) |item| {
                var exists = false;
                for (slice[0..write_idx]) |existing| {
                    if (itemsEql(existing, item)) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    slice[write_idx] = item;
                    write_idx += 1;
                }
            }
            @memset(slice[write_idx..], undefined);
            return Self{
                .items = slice[0..write_idx],
                .capacity = slice.len,
                .allocator = gpa,
                .pointer_stability = .{},
            };
        }

        /// Returns the set elements as an owned slice and resets this set to empty.
        /// The caller owns the returned slice and must free it with `gpa`.
        pub fn toOwnedSlice(self: *Self) Allocator.Error!Slice {
            self.pointer_stability.assertUnlocked();
            const allocator = self.allocator;

            const old_memory = self.allocatedSlice();
            if (allocator.remap(old_memory, self.items.len)) |new_items| {
                self.* = init(allocator);
                return new_items;
            }

            const new_memory = try allocator.alignedAlloc(T, alignment, self.items.len);
            @memcpy(new_memory, self.items);
            self.clearAndFree();
            return new_memory;
        }

        /// Returns the set elements as a sentinel-terminated slice and empties the set.
        pub fn toOwnedSliceSentinel(self: *Self, comptime sentinel: T) Allocator.Error!SentinelSlice(sentinel) {
            self.pointer_stability.assertUnlocked();
            try self.ensureTotalCapacityPrecise(self.items.len + 1);
            self.items.ptr[self.items.len] = sentinel;
            self.items.len += 1;
            errdefer self.items.len -= 1;
            const result = try self.toOwnedSlice();
            return result[0 .. result.len - 1 :sentinel];
        }

        /// Creates an independent copy of this set using the same allocator.
        pub fn clone(self: Self) Allocator.Error!Self {
            var cloned = try Self.initCapacity(self.allocator, self.items.len);
            @memcpy(cloned.allocatedSlice()[0..self.items.len], self.items);
            cloned.items.len = self.items.len;
            return cloned;
        }

        // Set Queries

        /// Returns the number of elements in the set ($|A|$).
        pub fn cardinality(self: Self) usize {
            return self.items.len;
        }

        /// Alias for `cardinality`. Returns the number of unique items.
        pub fn count(self: Self) usize {
            return self.items.len;
        }

        /// Returns `true` if the set has 0 elements ($A = \emptyset$).
        pub fn isEmpty(self: Self) bool {
            return self.items.len == 0;
        }

        /// Returns the index of `item` in the set, or `null` if it is not found.
        pub fn indexOf(self: Self, item: T) ?usize {
            for (self.items, 0..) |existing, i| {
                if (itemsEql(existing, item)) return i;
            }
            return null;
        }

        /// Returns `true` if `item` is in the set ($x \in A$).
        pub fn contains(self: Self, item: T) bool {
            return self.indexOf(item) != null;
        }

        /// Returns the last element in the set, or `null` if the set is empty.
        pub fn last(self: Self) ?T {
            if (self.items.len == 0) return null;
            return self.items[self.items.len - 1];
        }

        /// Returns a pointer to the last element, or `null` if the set is empty.
        pub fn lastPtr(self: Self) ?*T {
            if (self.items.len == 0) return null;
            return &self.items[self.items.len - 1];
        }

        // Adding & Removing Elements

        /// Adds `item` to the end of the set if it is not already present.
        /// Returns `true` if `item` was added, or `false` if it was already in the set.
        pub fn add(self: *Self, item: T) Allocator.Error!bool {
            if (self.contains(item)) return false;
            self.pointer_stability.assertUnlocked();
            try self.ensureUnusedCapacity(1);
            self.appendUniqueAssumeCapacity(item);
            return true;
        }

        /// Alias for `add` so code migrating from `ArrayList` feels familiar.
        pub fn append(self: *Self, item: T) Allocator.Error!void {
            _ = try self.add(item);
        }

        /// Adds `item` if it is not already present, assuming capacity is available.
        /// Returns `true` if added, or `false` if already present.
        pub fn addAssumeCapacity(self: *Self, item: T) bool {
            if (self.contains(item)) return false;
            self.pointer_stability.assertUnlocked();
            self.appendUniqueAssumeCapacity(item);
            return true;
        }

        /// Adds `item` if it is not already present.
        /// Returns `error.OutOfMemory` if the set is full and `item` is new.
        pub fn addBounded(self: *Self, item: T) error{OutOfMemory}!bool {
            if (self.contains(item)) return false;
            if (self.capacity - self.items.len == 0) return error.OutOfMemory;
            self.pointer_stability.assertUnlocked();
            self.appendUniqueAssumeCapacity(item);
            return true;
        }

        /// Inserts `item` at `index` if it is not already in the set.
        /// Returns `true` if inserted, or `false` if `item` already exists.
        pub fn insert(self: *Self, index: usize, item: T) Allocator.Error!bool {
            assert(index <= self.items.len);
            if (self.contains(item)) return false;
            self.pointer_stability.assertUnlocked();

            const new_len = try addOrOom(self.items.len, 1);
            try self.ensureTotalCapacity(new_len);

            self.items.len = new_len;
            @memmove(self.items[index + 1 .. self.items.len], self.items[index .. self.items.len - 1]);
            self.items[index] = item;
            return true;
        }

        /// Adds all unique items from `items` that are not already in the set.
        pub fn addSlice(self: *Self, items: []const T) Allocator.Error!void {
            for (items) |item| {
                _ = try self.add(item);
            }
        }

        /// Alias for `addSlice`.
        pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!void {
            try self.addSlice(items);
        }

        /// Adds all unique items from `items`, assuming enough capacity is already allocated.
        pub fn addSliceAssumeCapacity(self: *Self, items: []const T) void {
            for (items) |item| {
                _ = self.addAssumeCapacity(item);
            }
        }

        /// Removes `item` from the set while keeping insertion order ($O(N)$).
        /// Returns `true` if `item` was found and removed, or `false` otherwise.
        pub fn remove(self: *Self, item: T) bool {
            const idx = self.indexOf(item) orelse return false;
            _ = self.orderedRemove(idx);
            return true;
        }

        /// Removes `item` by swapping it with the last element ($O(1)$ after lookup).
        /// Does not keep insertion order. Returns `true` if found and removed.
        pub fn swapRemoveItem(self: *Self, item: T) bool {
            const idx = self.indexOf(item) orelse return false;
            _ = self.swapRemove(idx);
            return true;
        }

        /// Removes and returns the element at `index`, shifting following elements forward.
        pub fn orderedRemove(self: *Self, index: usize) T {
            self.pointer_stability.assertUnlocked();
            assert(index < self.items.len);
            const old_item = self.items[index];
            const tail = self.items[index + 1 ..];
            @memmove(self.items[index .. self.items.len - 1], tail);
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return old_item;
        }

        /// Removes and returns the element at `index` by filling the slot with the last element.
        pub fn swapRemove(self: *Self, index: usize) T {
            self.pointer_stability.assertUnlocked();
            assert(index < self.items.len);
            const val = self.items[index];
            self.items[index] = self.items[self.items.len - 1];
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return val;
        }

        /// Removes and returns the last element, or `null` if the set is empty.
        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;
            self.pointer_stability.assertUnlocked();
            const val = self.items[self.items.len - 1];
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return val;
        }

        // Mathematical Set Operations (In-Place & New Set)

        /// Union in-place ($A \gets A \cup B$).
        /// Adds all elements from `other` into `self`.
        pub fn unionWith(self: *Self, other: Self) Allocator.Error!void {
            try self.addSlice(other.items);
        }

        /// Returns a new set containing the union of `a` and `b` ($A \cup B$).
        /// Uses `a.allocator` for the new set.
        pub fn unionOf(a: Self, b: Self) Allocator.Error!Self {
            var result = try a.clone();
            errdefer result.deinit();
            try result.unionWith(b);
            return result;
        }

        /// Intersection in-place ($A \gets A \cap B$).
        /// Keeps only elements in `self` that are also present in `other`.
        /// Preserves order and never allocates memory.
        pub fn intersectWith(self: *Self, other: Self) void {
            self.pointer_stability.assertUnlocked();
            var write_idx: usize = 0;
            for (self.items) |item| {
                if (other.contains(item)) {
                    self.items[write_idx] = item;
                    write_idx += 1;
                }
            }
            @memset(self.items[write_idx..], undefined);
            self.items.len = write_idx;
        }

        /// Returns a new set containing the intersection of `a` and `b` ($A \cap B$).
        /// Uses `a.allocator` for the new set.
        pub fn intersectionOf(a: Self, b: Self) Allocator.Error!Self {
            const max_possible = @min(a.items.len, b.items.len);
            var result = try Self.initCapacity(a.allocator, max_possible);
            for (a.items) |item| {
                if (b.contains(item)) {
                    result.appendUniqueAssumeCapacity(item);
                }
            }
            return result;
        }

        /// Difference in-place ($A \gets A \setminus B$).
        /// Removes all elements from `self` that are present in `other`.
        /// Preserves order and never allocates memory.
        pub fn differenceWith(self: *Self, other: Self) void {
            self.pointer_stability.assertUnlocked();
            var write_idx: usize = 0;
            for (self.items) |item| {
                if (!other.contains(item)) {
                    self.items[write_idx] = item;
                    write_idx += 1;
                }
            }
            @memset(self.items[write_idx..], undefined);
            self.items.len = write_idx;
        }

        /// Returns a new set containing elements in `a` that are not in `b` ($A \setminus B$).
        /// Uses `a.allocator` for the new set.
        pub fn differenceOf(a: Self, b: Self) Allocator.Error!Self {
            var result = try Self.initCapacity(a.allocator, a.items.len);
            for (a.items) |item| {
                if (!b.contains(item)) {
                    result.appendUniqueAssumeCapacity(item);
                }
            }
            return result;
        }

        /// Symmetric difference in-place ($A \gets A \Delta B$).
        /// Keeps elements that are in `self` or `other`, but not in both.
        pub fn symmetricDifferenceWith(self: *Self, other: Self) Allocator.Error!void {
            for (other.items) |item| {
                if (!self.remove(item)) {
                    _ = try self.add(item);
                }
            }
        }

        /// Returns a new set with elements in `a` or `b`, but not both ($A \Delta B$).
        /// Uses `a.allocator` for the new set.
        pub fn symmetricDifferenceOf(a: Self, b: Self) Allocator.Error!Self {
            var result = try Self.initCapacity(a.allocator, a.items.len + b.items.len);
            errdefer result.deinit();
            for (a.items) |item| {
                if (!b.contains(item)) {
                    result.appendUniqueAssumeCapacity(item);
                }
            }
            for (b.items) |item| {
                if (!a.contains(item)) {
                    result.appendUniqueAssumeCapacity(item);
                }
            }
            return result;
        }

        // Mathematical Set Relations (Predicates)

        /// Returns `true` if every element in `self` is also in `other` ($A \subseteq B$).
        pub fn isSubsetOf(self: Self, other: Self) bool {
            if (self.items.len > other.items.len) return false;
            for (self.items) |item| {
                if (!other.contains(item)) return false;
            }
            return true;
        }

        /// Returns `true` if `self` is a subset of `other` and strictly smaller ($A \subset B$).
        pub fn isProperSubsetOf(self: Self, other: Self) bool {
            return self.items.len < other.items.len and self.isSubsetOf(other);
        }

        /// Returns `true` if `self` contains all elements of `other` ($A \supseteq B$).
        pub fn isSupersetOf(self: Self, other: Self) bool {
            return other.isSubsetOf(self);
        }

        /// Returns `true` if `self` is a superset of `other` and strictly larger ($A \supset B$).
        pub fn isProperSupersetOf(self: Self, other: Self) bool {
            return other.isProperSubsetOf(self);
        }

        /// Returns `true` if `self` and `other` have no elements in common ($A \cap B = \emptyset$).
        pub fn isDisjointWith(self: Self, other: Self) bool {
            const smaller = if (self.items.len <= other.items.len) self else other;
            const larger = if (self.items.len <= other.items.len) other else self;
            for (smaller.items) |item| {
                if (larger.contains(item)) return false;
            }
            return true;
        }

        /// Returns `true` if `self` and `other` contain the exact same elements ($A = B$),
        /// regardless of element order.
        pub fn eql(self: Self, other: Self) bool {
            if (self.items.len != other.items.len) return false;
            return self.isSubsetOf(other);
        }

        // Capacity & Memory Management

        /// Reduces length to `new_len` without freeing memory.
        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            self.pointer_stability.assertUnlocked();
            assert(new_len <= self.items.len);
            @memset(self.items[new_len..], undefined);
            self.items.len = new_len;
        }

        /// Reduces length and shrinks allocated capacity to `new_len`.
        pub fn shrinkAndFree(self: *Self, new_len: usize) void {
            self.shrinkAndFreePrecise(new_len) catch |e| switch (e) {
                error.OutOfMemory => {
                    self.shrinkRetainingCapacity(new_len);
                    return;
                },
            };
        }

        /// Shrinks allocated capacity to `new_len` exactly.
        pub fn shrinkAndFreePrecise(self: *Self, new_len: usize) Allocator.Error!void {
            self.pointer_stability.assertUnlocked();
            assert(new_len <= self.items.len);

            if (@sizeOf(T) == 0) {
                self.items.len = new_len;
                return;
            }

            const old_memory = self.allocatedSlice();
            if (self.allocator.remap(old_memory, new_len)) |new_items| {
                self.capacity = new_items.len;
                self.items = new_items;
                return;
            }

            const new_memory = try self.allocator.alignedAlloc(T, alignment, new_len);
            @memcpy(new_memory, self.items[0..new_len]);
            self.allocator.free(old_memory);
            self.items = new_memory;
            self.capacity = new_memory.len;
        }

        /// Clears all items from the set while keeping the allocated capacity.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.pointer_stability.assertUnlocked();
            @memset(self.items, undefined);
            self.items.len = 0;
        }

        /// Clears all items and frees the allocated memory.
        pub fn clearAndFree(self: *Self) void {
            self.pointer_stability.assertUnlocked();
            if (@sizeOf(T) > 0) {
                self.allocator.free(self.allocatedSlice());
            }
            self.items.len = 0;
            self.capacity = 0;
        }

        /// Ensures the set can hold at least `new_capacity` items.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }
            if (self.capacity >= new_capacity) return;
            return self.ensureTotalCapacityPrecise(growCapacity(new_capacity));
        }

        /// Ensures the set can hold `new_capacity` items without over-allocating.
        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }
            if (self.capacity >= new_capacity) return;
            self.pointer_stability.assertUnlocked();

            const old_memory = self.allocatedSlice();
            if (self.allocator.remap(old_memory, new_capacity)) |new_memory| {
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            } else {
                const new_memory = try self.allocator.alignedAlloc(T, alignment, new_capacity);
                @memcpy(new_memory[0..self.items.len], self.items);
                self.allocator.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        /// Ensures the set has room for `additional_count` more items.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void {
            return self.ensureTotalCapacity(try addOrOom(self.items.len, additional_count));
        }

        /// Returns the full allocated slice including unused capacity.
        pub fn allocatedSlice(self: Self) Slice {
            return self.items.ptr[0..self.capacity];
        }

        /// Returns the unused capacity slice after `self.items`.
        pub fn unusedCapacitySlice(self: Self) []T {
            return self.allocatedSlice()[self.items.len..];
        }

        /// Calculates a larger capacity for super-linear growth.
        pub fn growCapacity(minimum: usize) usize {
            if (@sizeOf(T) == 0) return math.maxInt(usize);
            const init_capacity: comptime_int = @max(1, std.atomic.cache_line / @sizeOf(T));
            return minimum +| (minimum / 2 + init_capacity);
        }

        fn appendUniqueAssumeCapacity(self: *Self, item: T) void {
            assert(self.items.len < self.capacity);
            self.items.len += 1;
            self.items[self.items.len - 1] = item;
        }

        /// Compares two values of type `T` for equality.
        /// Compares byte contents when `T` is `[]const u8` or `[]u8`, and uses `std.meta.eql` otherwise.
        fn itemsEql(a: T, b: T) bool {
            if (T == []const u8 or T == []u8) {
                return mem.eql(u8, a, b);
            }
            return std.meta.eql(a, b);
        }
    };
}

/// Adds two integers or returns `error.OutOfMemory` on overflow.
fn addOrOom(a: usize, b: usize) error{OutOfMemory}!usize {
    const result, const overflow = @addWithOverflow(a, b);
    if (overflow != 0) return error.OutOfMemory;
    return result;
}

// Unit Tests

test "SetList: unique insertions and order preservation" {
    const a = testing.allocator;
    var set = SetList(i32).init(a);
    defer set.deinit();

    try testing.expect(set.isEmpty());
    try testing.expect(try set.add(10));
    try testing.expect(try set.add(20));
    try testing.expect(try set.add(30));

    // Duplicate additions return false and do not change length
    try testing.expect(!(try set.add(20)));
    try testing.expect(!(try set.add(10)));

    try testing.expectEqual(@as(usize, 3), set.cardinality());
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30 }, set.items);
    try testing.expect(set.contains(20));
    try testing.expect(!set.contains(99));
}

test "SetList: addSlice and fromOwnedSlice deduplication" {
    const a = testing.allocator;
    var set = SetList(i32).init(a);
    defer set.deinit();

    try set.addSlice(&.{ 1, 2, 2, 3, 1, 4, 3, 5 });
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4, 5 }, set.items);

    const raw = try a.dupe(i32, &.{ 9, 8, 9, 7, 8, 6 });
    var owned_set = SetList(i32).fromOwnedSlice(a, raw);
    defer owned_set.deinit();
    try testing.expectEqualSlices(i32, &.{ 9, 8, 7, 6 }, owned_set.items);
}

test "SetList: union, intersection, difference, symmetric difference" {
    const a = testing.allocator;

    var set_a = try SetList(i32).initSlice(a, &.{ 1, 2, 3, 4 });
    defer set_a.deinit();

    var set_b = try SetList(i32).initSlice(a, &.{ 3, 4, 5, 6 });
    defer set_b.deinit();

    // Union: {1, 2, 3, 4, 5, 6}
    var u = try SetList(i32).unionOf(set_a, set_b);
    defer u.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4, 5, 6 }, u.items);

    // Intersection: {3, 4}
    var inter = try SetList(i32).intersectionOf(set_a, set_b);
    defer inter.deinit();
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, inter.items);

    // Difference (A \ B): {1, 2}
    var diff = try SetList(i32).differenceOf(set_a, set_b);
    defer diff.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, diff.items);

    // Symmetric Difference (A Δ B): {1, 2, 5, 6}
    var sym = try SetList(i32).symmetricDifferenceOf(set_a, set_b);
    defer sym.deinit();
    try testing.expectEqualSlices(i32, &.{ 1, 2, 5, 6 }, sym.items);
}

test "SetList: subset, superset, disjoint, and equality" {
    const a = testing.allocator;

    var sub = try SetList(i32).initSlice(a, &.{ 2, 4 });
    defer sub.deinit();

    var full = try SetList(i32).initSlice(a, &.{ 1, 2, 3, 4 });
    defer full.deinit();

    var reordered = try SetList(i32).initSlice(a, &.{ 4, 2 });
    defer reordered.deinit();

    var other = try SetList(i32).initSlice(a, &.{ 9, 10 });
    defer other.deinit();

    try testing.expect(sub.isSubsetOf(full));
    try testing.expect(sub.isProperSubsetOf(full));
    try testing.expect(full.isSupersetOf(sub));
    try testing.expect(full.isProperSupersetOf(sub));

    // Set equality ignores element order
    try testing.expect(sub.eql(reordered));
    try testing.expect(!sub.isProperSubsetOf(reordered));

    // Disjoint sets share no elements
    try testing.expect(sub.isDisjointWith(other));
    try testing.expect(!sub.isDisjointWith(full));
}

test "SetList: string slices support" {
    const a = testing.allocator;
    var tags = SetList([]const u8).init(a);
    defer tags.deinit();

    try testing.expect(try tags.add("zig"));
    try testing.expect(try tags.add("systems"));
    try testing.expect(!(try tags.add("zig")));

    try testing.expectEqual(@as(usize, 2), tags.cardinality());
    try testing.expect(tags.contains("systems"));
    try testing.expect(tags.remove("zig"));
    try testing.expectEqual(@as(usize, 1), tags.cardinality());
}
