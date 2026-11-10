//! Slice helpers and iterators.
//! Includes zero-allocation in-place transforms, iterators, and allocating builders.

const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = mem.Allocator;

// === Equality Helper ===

/// Compares two values of type `T`.
/// Compares byte contents when `T` is `[]const u8` or `[]u8`, and uses `std.meta.eql` otherwise.
pub fn itemsEql(comptime T: type, a: T, b: T) bool {
    if (T == []const u8 or T == []u8) {
        return mem.eql(u8, a, b);
    }
    return std.meta.eql(a, b);
}

// === Element & Subslice Access ===

/// Returns the first element of `slice`, or `null` if empty.
pub fn first(comptime T: type, slice: []const T) ?T {
    if (slice.len == 0) return null;
    return slice[0];
}

/// Returns a mutable pointer to the first element of `slice`, or `null` if empty.
pub fn firstPtr(comptime T: type, slice: []T) ?*T {
    if (slice.len == 0) return null;
    return &slice[0];
}

/// Returns the last element of `slice`, or `null` if empty.
pub fn last(comptime T: type, slice: []const T) ?T {
    if (slice.len == 0) return null;
    return slice[slice.len - 1];
}

/// Returns a mutable pointer to the last element of `slice`, or `null` if empty.
pub fn lastPtr(comptime T: type, slice: []T) ?*T {
    if (slice.len == 0) return null;
    return &slice[slice.len - 1];
}

pub fn SplitResult(comptime T: type) type {
    return struct {
        head: T,
        tail: []const T,
    };
}

/// Returns the first element and the remaining slice, or `null` if empty.
pub fn splitFirst(comptime T: type, slice: []const T) ?SplitResult(T) {
    if (slice.len == 0) return null;
    return .{ .head = slice[0], .tail = slice[1..] };
}

/// Returns the last element and the preceding slice, or `null` if empty.
pub fn splitLast(comptime T: type, slice: []const T) ?SplitResult(T) {
    if (slice.len == 0) return null;
    return .{ .head = slice[slice.len - 1], .tail = slice[0 .. slice.len - 1] };
}

pub fn SplitAtResult(comptime T: type) type {
    return struct {
        left: []const T,
        right: []const T,
    };
}

/// Splits `slice` into two slices at `mid`. Asserts `mid <= slice.len`.
pub fn splitAt(comptime T: type, slice: []const T, mid: usize) SplitAtResult(T) {
    assert(mid <= slice.len);
    return .{
        .left = slice[0..mid],
        .right = slice[mid..],
    };
}

/// Takes up to `n` elements from the start of `slice` without panicking if `n > slice.len`.
pub fn takeFirst(comptime T: type, slice: []const T, n: usize) []const T {
    return slice[0..@min(n, slice.len)];
}

/// Takes up to `n` elements from the end of `slice` without panicking if `n > slice.len`.
pub fn takeLast(comptime T: type, slice: []const T, n: usize) []const T {
    const count = @min(n, slice.len);
    return slice[slice.len - count ..];
}

// === Prefix & Suffix Matching ===

/// Returns `true` if `slice` starts with `prefix`.
pub fn startsWith(comptime T: type, slice: []const T, prefix: []const T) bool {
    if (prefix.len > slice.len) return false;
    for (slice[0..prefix.len], prefix) |a, b| {
        if (!itemsEql(T, a, b)) return false;
    }
    return true;
}

/// Returns `true` if `slice` ends with `suffix`.
pub fn endsWith(comptime T: type, slice: []const T, suffix: []const T) bool {
    if (suffix.len > slice.len) return false;
    const start = slice.len - suffix.len;
    for (slice[start..], suffix) |a, b| {
        if (!itemsEql(T, a, b)) return false;
    }
    return true;
}

/// Removes `prefix` from the start of `slice` if present, or returns `null`.
pub fn stripPrefix(comptime T: type, slice: []const T, prefix: []const T) ?[]const T {
    if (startsWith(T, slice, prefix)) {
        return slice[prefix.len..];
    }
    return null;
}

/// Removes `suffix` from the end of `slice` if present, or returns `null`.
pub fn stripSuffix(comptime T: type, slice: []const T, suffix: []const T) ?[]const T {
    if (endsWith(T, slice, suffix)) {
        return slice[0 .. slice.len - suffix.len];
    }
    return null;
}

// === Predicates & Searching ===

/// Returns `true` if `slice` contains `needle`.
pub fn contains(comptime T: type, slice: []const T, needle: T) bool {
    return indexOf(T, slice, needle) != null;
}

/// Returns the first index of `needle` in `slice`, or `null` if not found.
pub fn indexOf(comptime T: type, slice: []const T, needle: T) ?usize {
    for (slice, 0..) |item, i| {
        if (itemsEql(T, item, needle)) return i;
    }
    return null;
}

/// Returns the last index of `needle` in `slice`, or `null` if not found.
pub fn lastIndexOf(comptime T: type, slice: []const T, needle: T) ?usize {
    var i: usize = slice.len;
    while (i > 0) {
        i -= 1;
        if (itemsEql(T, slice[i], needle)) return i;
    }
    return null;
}

/// Returns `true` if `pred(item)` returns `true` for at least one element.
pub fn any(comptime T: type, slice: []const T, pred: *const fn (T) bool) bool {
    for (slice) |item| {
        if (pred(item)) return true;
    }
    return false;
}

/// Returns `true` if `pred(item)` returns `true` for every element in `slice`.
/// Returns `true` if `slice` is empty.
pub fn all(comptime T: type, slice: []const T, pred: *const fn (T) bool) bool {
    for (slice) |item| {
        if (!pred(item)) return false;
    }
    return true;
}

/// Returns `true` if `pred(item)` returns `false` for every element in `slice`.
pub fn none(comptime T: type, slice: []const T, pred: *const fn (T) bool) bool {
    return !any(T, slice, pred);
}

/// Counts how many elements in `slice` satisfy `pred(item)`.
pub fn countIf(comptime T: type, slice: []const T, pred: *const fn (T) bool) usize {
    var total: usize = 0;
    for (slice) |item| {
        if (pred(item)) total += 1;
    }
    return total;
}

/// Counts how many times `needle` appears in `slice`.
pub fn countValue(comptime T: type, slice: []const T, needle: T) usize {
    var total: usize = 0;
    for (slice) |item| {
        if (itemsEql(T, item, needle)) total += 1;
    }
    return total;
}

/// Returns the first element that satisfies `pred(item)`, or `null`.
pub fn find(comptime T: type, slice: []const T, pred: *const fn (T) bool) ?T {
    for (slice) |item| {
        if (pred(item)) return item;
    }
    return null;
}

/// Returns the index of the first element that satisfies `pred(item)`, or `null`.
pub fn findIndex(comptime T: type, slice: []const T, pred: *const fn (T) bool) ?usize {
    for (slice, 0..) |item, i| {
        if (pred(item)) return i;
    }
    return null;
}

/// Returns the last element that satisfies `pred(item)`, or `null`.
pub fn rfind(comptime T: type, slice: []const T, pred: *const fn (T) bool) ?T {
    var i: usize = slice.len;
    while (i > 0) {
        i -= 1;
        if (pred(slice[i])) return slice[i];
    }
    return null;
}

/// Returns the index of the last element that satisfies `pred(item)`, or `null`.
pub fn rfindIndex(comptime T: type, slice: []const T, pred: *const fn (T) bool) ?usize {
    var i: usize = slice.len;
    while (i > 0) {
        i -= 1;
        if (pred(slice[i])) return i;
    }
    return null;
}

// === Sorting & Binary Search ===

/// Returns `true` if `slice` is sorted in ascending order (`a <= b`).
pub fn isSorted(comptime T: type, slice: []const T) bool {
    if (slice.len <= 1) return true;
    for (slice[0 .. slice.len - 1], slice[1..]) |a, b| {
        if (a > b) return false;
    }
    return true;
}

/// Returns `true` if `slice` is sorted according to `lessThan(a, b)`.
pub fn isSortedBy(comptime T: type, slice: []const T, lessThan: *const fn (T, T) bool) bool {
    if (slice.len <= 1) return true;
    for (slice[0 .. slice.len - 1], slice[1..]) |a, b| {
        if (lessThan(b, a)) return false;
    }
    return true;
}

pub const BinarySearchResult = union(enum) {
    /// The item was found at this index.
    found: usize,
    /// The item was not found, but should be inserted at this index to keep sorted order.
    not_found: usize,
};

/// Searches a sorted ascending slice for `target` in $O(\log N)$ time.
/// Like Rust's `slice::binary_search`, returns either `.found = idx` or `.not_found = insert_idx`.
pub fn binarySearch(comptime T: type, slice: []const T, target: T) BinarySearchResult {
    var low: usize = 0;
    var high: usize = slice.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const item = slice[mid];
        if (item == target) {
            return .{ .found = mid };
        } else if (item < target) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return .{ .not_found = low };
}

// === In-Place Mutations (Zero Allocation) ===

/// Reverses `slice` in place.
pub fn reverse(comptime T: type, slice: []T) void {
    mem.reverse(T, slice);
}

/// Rotates `slice` left by `mid` positions in place so the element at `mid` becomes the first element.
pub fn rotateLeft(comptime T: type, slice: []T, mid: usize) void {
    if (slice.len == 0) return;
    const k = mid % slice.len;
    if (k == 0) return;
    mem.reverse(T, slice[0..k]);
    mem.reverse(T, slice[k..]);
    mem.reverse(T, slice);
}

/// Rotates `slice` right by `k` positions in place.
pub fn rotateRight(comptime T: type, slice: []T, k: usize) void {
    if (slice.len == 0) return;
    const shift = k % slice.len;
    if (shift == 0) return;
    rotateLeft(T, slice, slice.len - shift);
}

/// Fills all elements of `slice` with `value`.
pub fn fill(comptime T: type, slice: []T, value: T) void {
    @memset(slice, value);
}

/// Fills `slice` by calling `gen(index)` for each slot.
pub fn fillWith(comptime T: type, slice: []T, gen: *const fn (usize) T) void {
    for (slice, 0..) |*slot, i| {
        slot.* = gen(i);
    }
}

/// Swaps two elements at `i` and `j` in `slice`.
pub fn swap(comptime T: type, slice: []T, i: usize, j: usize) void {
    assert(i < slice.len and j < slice.len);
    if (i == j) return;
    mem.swap(T, &slice[i], &slice[j]);
}

/// Keeps only elements in `slice` that satisfy `pred(item)` in place, preserving order.
/// Returns the subslice of retained items (`slice[0..new_len]`).
pub fn retain(comptime T: type, slice: []T, pred: *const fn (T) bool) []T {
    var write_idx: usize = 0;
    for (slice) |item| {
        if (pred(item)) {
            slice[write_idx] = item;
            write_idx += 1;
        }
    }
    return slice[0..write_idx];
}

/// Removes consecutive duplicate elements in place (like Rust's `Vec::dedup`).
/// If `slice` is sorted, this removes all duplicates. Returns the deduplicated subslice.
pub fn dedup(comptime T: type, slice: []T) []T {
    if (slice.len <= 1) return slice;
    var write_idx: usize = 1;
    for (slice[1..]) |item| {
        if (!itemsEql(T, slice[write_idx - 1], item)) {
            slice[write_idx] = item;
            write_idx += 1;
        }
    }
    return slice[0..write_idx];
}

/// Removes all duplicate elements across the entire slice in place while keeping first-seen order.
/// Runs in $O(N^2)$ time with zero allocations. Returns the deduplicated subslice.
pub fn dedupAll(comptime T: type, slice: []T) []T {
    var write_idx: usize = 0;
    for (slice) |item| {
        if (!contains(T, slice[0..write_idx], item)) {
            slice[write_idx] = item;
            write_idx += 1;
        }
    }
    return slice[0..write_idx];
}

/// Reorders `slice` in place so all elements where `pred(item)` is `true` come before
/// all elements where `pred(item)` is `false`. Returns the index of the split point.
pub fn partitionInPlace(comptime T: type, slice: []T, pred: *const fn (T) bool) usize {
    var left: usize = 0;
    var right: usize = slice.len;

    while (left < right) {
        if (pred(slice[left])) {
            left += 1;
        } else {
            right -= 1;
            mem.swap(T, &slice[left], &slice[right]);
        }
    }
    return left;
}

// === Functional & Allocating Operations ===

/// Combines all elements into a single accumulator value by calling `folder(acc, item)`.
pub fn fold(
    comptime T: type,
    comptime Acc: type,
    slice: []const T,
    init_val: Acc,
    folder: *const fn (Acc, T) Acc,
) Acc {
    var acc = init_val;
    for (slice) |item| {
        acc = folder(acc, item);
    }
    return acc;
}

/// Reduces a non-empty slice to a single value of type `T` using `reducer(acc, item)`.
/// Returns `null` if `slice` is empty.
pub fn reduce(comptime T: type, slice: []const T, reducer: *const fn (T, T) T) ?T {
    if (slice.len == 0) return null;
    var acc = slice[0];
    for (slice[1..]) |item| {
        acc = reducer(acc, item);
    }
    return acc;
}

/// Allocates a new slice containing the result of calling `mapper(item)` on every element.
/// Caller owns the returned memory and must free it with `gpa`.
pub fn map(
    gpa: Allocator,
    comptime In: type,
    comptime Out: type,
    slice: []const In,
    mapper: *const fn (In) Out,
) Allocator.Error![]Out {
    const out = try gpa.alloc(Out, slice.len);
    for (slice, 0..) |item, i| {
        out[i] = mapper(item);
    }
    return out;
}

/// Allocates a new slice containing only elements where `pred(item)` returns `true`.
/// Caller owns the returned memory and must free it with `gpa`.
pub fn filter(
    gpa: Allocator,
    comptime T: type,
    slice: []const T,
    pred: *const fn (T) bool,
) Allocator.Error![]T {
    const count = countIf(T, slice, pred);
    const out = try gpa.alloc(T, count);
    var idx: usize = 0;
    for (slice) |item| {
        if (pred(item)) {
            out[idx] = item;
            idx += 1;
        }
    }
    return out;
}

/// Filters and maps simultaneously. Calls `mapper(item)` and keeps non-null results.
/// Caller owns the returned memory and must free it with `gpa`.
pub fn filterMap(
    gpa: Allocator,
    comptime In: type,
    comptime Out: type,
    slice: []const In,
    mapper: *const fn (In) ?Out,
) Allocator.Error![]Out {
    var list: std.ArrayList(Out) = .empty;
    errdefer list.deinit(gpa);

    for (slice) |item| {
        if (mapper(item)) |val| {
            try list.append(gpa, val);
        }
    }
    return list.toOwnedSlice(gpa);
}

pub fn PartitionResult(comptime T: type) type {
    return struct {
        matching: []T,
        non_matching: []T,

        pub fn deinit(self: @This(), gpa: Allocator) void {
            gpa.free(self.matching);
            gpa.free(self.non_matching);
        }
    };
}

/// Splits `slice` into two newly allocated slices: `matching` (where `pred` is true)
/// and `non_matching` (where `pred` is false). Free both with `result.deinit(gpa)`.
pub fn partition(
    gpa: Allocator,
    comptime T: type,
    slice: []const T,
    pred: *const fn (T) bool,
) Allocator.Error!PartitionResult(T) {
    const match_count = countIf(T, slice, pred);
    const matching = try gpa.alloc(T, match_count);
    errdefer gpa.free(matching);

    const non_matching = try gpa.alloc(T, slice.len - match_count);

    var m_idx: usize = 0;
    var nm_idx: usize = 0;
    for (slice) |item| {
        if (pred(item)) {
            matching[m_idx] = item;
            m_idx += 1;
        } else {
            non_matching[nm_idx] = item;
            nm_idx += 1;
        }
    }
    return .{ .matching = matching, .non_matching = non_matching };
}

/// Flattens a slice of slices (`[]const []const T`) into a single allocated `[]T`.
pub fn flatten(gpa: Allocator, comptime T: type, nested: []const []const T) Allocator.Error![]T {
    var total_len: usize = 0;
    for (nested) |sub| {
        total_len += sub.len;
    }
    const out = try gpa.alloc(T, total_len);
    var offset: usize = 0;
    for (nested) |sub| {
        @memcpy(out[offset..][0..sub.len], sub);
        offset += sub.len;
    }
    return out;
}

/// Creates a new slice by repeating `slice` `n` times (like Rust's `slice::repeat`).
pub fn repeat(gpa: Allocator, comptime T: type, slice: []const T, n: usize) Allocator.Error![]T {
    const total_len = math.mul(usize, slice.len, n) catch return error.OutOfMemory;
    const out = try gpa.alloc(T, total_len);
    var offset: usize = 0;
    for (0..n) |_| {
        @memcpy(out[offset..][0..slice.len], slice);
        offset += slice.len;
    }
    return out;
}

/// Joins a slice of slices with `sep` placed between each slice.
pub fn join(
    gpa: Allocator,
    comptime T: type,
    nested: []const []const T,
    sep: []const T,
) Allocator.Error![]T {
    if (nested.len == 0) return gpa.alloc(T, 0);

    var total_len: usize = sep.len * (nested.len - 1);
    for (nested) |sub| {
        total_len += sub.len;
    }

    const out = try gpa.alloc(T, total_len);
    var offset: usize = 0;
    for (nested, 0..) |sub, i| {
        if (i > 0 and sep.len > 0) {
            @memcpy(out[offset..][0..sep.len], sep);
            offset += sep.len;
        }
        @memcpy(out[offset..][0..sub.len], sub);
        offset += sub.len;
    }
    return out;
}

// === Math & Aggregations ===

/// Returns the sum of all elements in `slice` (`0` if empty).
pub fn sum(comptime T: type, slice: []const T) T {
    var total: T = 0;
    for (slice) |item| {
        total += item;
    }
    return total;
}

/// Returns the product of all elements in `slice` (`1` if empty).
pub fn product(comptime T: type, slice: []const T) T {
    var total: T = 1;
    for (slice) |item| {
        total *= item;
    }
    return total;
}

/// Returns the minimum value in `slice`, or `null` if empty.
pub fn min(comptime T: type, slice: []const T) ?T {
    if (slice.len == 0) return null;
    return mem.min(T, slice);
}

/// Returns the maximum value in `slice`, or `null` if empty.
pub fn max(comptime T: type, slice: []const T) ?T {
    if (slice.len == 0) return null;
    return mem.max(T, slice);
}

pub fn MinMaxResult(comptime T: type) type {
    return struct { min: T, max: T };
}

/// Returns both minimum and maximum values in a single pass, or `null` if empty.
pub fn minMax(comptime T: type, slice: []const T) ?MinMaxResult(T) {
    if (slice.len == 0) return null;
    var min_val = slice[0];
    var max_val = slice[0];
    for (slice[1..]) |item| {
        if (item < min_val) min_val = item;
        if (item > max_val) max_val = item;
    }
    return .{ .min = min_val, .max = max_val };
}

// === Zero-Allocation Iterators (Chunks, Windows, Split) ===

pub fn ChunksIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        chunk_size: usize,
        index: usize = 0,

        pub fn next(self: *@This()) ?[]const T {
            if (self.index >= self.slice.len) return null;
            const end = @min(self.index + self.chunk_size, self.slice.len);
            const chunk = self.slice[self.index..end];
            self.index = end;
            return chunk;
        }
    };
}

/// Yields non-overlapping chunks of `chunk_size`. The last chunk may be shorter.
pub fn chunks(comptime T: type, slice: []const T, chunk_size: usize) ChunksIterator(T) {
    assert(chunk_size > 0);
    return .{ .slice = slice, .chunk_size = chunk_size };
}

pub fn ChunksExactIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        rem: []const T,
        chunk_size: usize,
        index: usize = 0,

        pub fn next(self: *@This()) ?[]const T {
            if (self.index >= self.slice.len) return null;
            const chunk = self.slice[self.index .. self.index + self.chunk_size];
            self.index += self.chunk_size;
            return chunk;
        }

        /// Returns the leftover tail slice that was smaller than `chunk_size`.
        pub fn remainder(self: @This()) []const T {
            return self.rem;
        }
    };
}

/// Yields exact chunks of `chunk_size`. Any leftover items can be read via `.remainder()`.
pub fn chunksExact(comptime T: type, slice: []const T, chunk_size: usize) ChunksExactIterator(T) {
    assert(chunk_size > 0);
    const rem_len = slice.len % chunk_size;
    const exact_len = slice.len - rem_len;
    return .{
        .slice = slice[0..exact_len],
        .rem = slice[exact_len..],
        .chunk_size = chunk_size,
    };
}

pub fn RChunksIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        chunk_size: usize,
        end: usize,

        pub fn next(self: *@This()) ?[]const T {
            if (self.end == 0) return null;
            const start = self.end -| self.chunk_size;
            const chunk = self.slice[start..self.end];
            self.end = start;
            return chunk;
        }
    };
}

/// Yields chunks of `chunk_size` starting from the end of `slice` moving backwards.
pub fn rchunks(comptime T: type, slice: []const T, chunk_size: usize) RChunksIterator(T) {
    assert(chunk_size > 0);
    return .{ .slice = slice, .chunk_size = chunk_size, .end = slice.len };
}

pub fn WindowsIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        window_size: usize,
        index: usize = 0,

        pub fn next(self: *@This()) ?[]const T {
            if (self.index + self.window_size > self.slice.len) return null;
            const win = self.slice[self.index .. self.index + self.window_size];
            self.index += 1;
            return win;
        }
    };
}

/// Yields overlapping sliding windows of `window_size`.
pub fn windows(comptime T: type, slice: []const T, window_size: usize) WindowsIterator(T) {
    assert(window_size > 0);
    return .{ .slice = slice, .window_size = window_size };
}

pub fn SplitByIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        pred: *const fn (T) bool,
        index: usize = 0,
        done: bool = false,

        pub fn next(self: *@This()) ?[]const T {
            if (self.done) return null;
            const start = self.index;
            while (self.index < self.slice.len) : (self.index += 1) {
                if (self.pred(self.slice[self.index])) {
                    const part = self.slice[start..self.index];
                    self.index += 1;
                    return part;
                }
            }
            self.done = true;
            return self.slice[start..self.slice.len];
        }
    };
}

/// Splits `slice` into subslices separated by elements where `pred(item)` is `true`.
pub fn splitBy(comptime T: type, slice: []const T, pred: *const fn (T) bool) SplitByIterator(T) {
    return .{ .slice = slice, .pred = pred };
}

// === Unit Tests ===

fn isEven(x: i32) bool {
    return @rem(x, 2) == 0;
}

fn doubleVal(x: i32) i32 {
    return x * 2;
}

fn halfIfEven(x: i32) ?i32 {
    return if (@rem(x, 2) == 0) @divTrunc(x, 2) else null;
}

fn addAcc(acc: i32, x: i32) i32 {
    return acc + x;
}

test "slices: element access, splitFirst, splitLast, splitAt, prefix/suffix" {
    const data = [_]i32{ 10, 20, 30, 40, 50 };

    try testing.expectEqual(@as(?i32, 10), first(i32, &data));
    try testing.expectEqual(@as(?i32, 50), last(i32, &data));
    try testing.expectEqual(@as(?i32, null), first(i32, &[_]i32{}));

    const sf = splitFirst(i32, &data).?;
    try testing.expectEqual(@as(i32, 10), sf.head);
    try testing.expectEqualSlices(i32, &.{ 20, 30, 40, 50 }, sf.tail);

    const sl = splitLast(i32, &data).?;
    try testing.expectEqual(@as(i32, 50), sl.head);
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30, 40 }, sl.tail);

    const sp = splitAt(i32, &data, 2);
    try testing.expectEqualSlices(i32, &.{ 10, 20 }, sp.left);
    try testing.expectEqualSlices(i32, &.{ 30, 40, 50 }, sp.right);

    try testing.expect(startsWith(i32, &data, &.{ 10, 20 }));
    try testing.expect(endsWith(i32, &data, &.{ 40, 50 }));
    try testing.expectEqualSlices(i32, &.{ 30, 40, 50 }, stripPrefix(i32, &data, &.{ 10, 20 }).?);
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30 }, stripSuffix(i32, &data, &.{ 40, 50 }).?);
}

test "slices: predicates, search, binarySearch, and sorting checks" {
    const data = [_]i32{ 2, 4, 6, 8, 10 };

    try testing.expect(contains(i32, &data, 6));
    try testing.expect(!contains(i32, &data, 5));
    try testing.expect(all(i32, &data, isEven));
    try testing.expect(any(i32, &data, isEven));
    try testing.expectEqual(@as(usize, 5), countIf(i32, &data, isEven));

    try testing.expect(isSorted(i32, &data));
    try testing.expect(!isSorted(i32, &[_]i32{ 1, 3, 2 }));

    try testing.expectEqual(BinarySearchResult{ .found = 2 }, binarySearch(i32, &data, 6));
    try testing.expectEqual(BinarySearchResult{ .not_found = 2 }, binarySearch(i32, &data, 5));
}

test "slices: in-place reverse, rotate, retain, dedup, dedupAll, partitionInPlace" {
    var rot = [_]i32{ 1, 2, 3, 4, 5 };
    rotateLeft(i32, &rot, 2);
    try testing.expectEqualSlices(i32, &.{ 3, 4, 5, 1, 2 }, &rot);
    rotateRight(i32, &rot, 2);
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4, 5 }, &rot);

    var nums = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const evens = retain(i32, &nums, isEven);
    try testing.expectEqualSlices(i32, &.{ 2, 4, 6 }, evens);

    var consec = [_]i32{ 1, 1, 2, 2, 2, 3, 1, 1 };
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3, 1 }, dedup(i32, &consec));

    var all_dups = [_]i32{ 3, 1, 3, 2, 1, 4 };
    try testing.expectEqualSlices(i32, &.{ 3, 1, 2, 4 }, dedupAll(i32, &all_dups));

    var part = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const split_idx = partitionInPlace(i32, &part, isEven);
    try testing.expectEqual(@as(usize, 3), split_idx);
    try testing.expect(all(i32, part[0..split_idx], isEven));
}

test "slices: map, filter, filterMap, fold, reduce, flatten, repeat, join" {
    const a = testing.allocator;
    const data = [_]i32{ 1, 2, 3, 4 };

    const mapped = try map(a, i32, i32, &data, doubleVal);
    defer a.free(mapped);
    try testing.expectEqualSlices(i32, &.{ 2, 4, 6, 8 }, mapped);

    const filtered = try filter(a, i32, &data, isEven);
    defer a.free(filtered);
    try testing.expectEqualSlices(i32, &.{ 2, 4 }, filtered);

    const fmapped = try filterMap(a, i32, i32, &data, halfIfEven);
    defer a.free(fmapped);
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, fmapped);

    try testing.expectEqual(@as(i32, 10), fold(i32, i32, &data, 0, addAcc));
    try testing.expectEqual(@as(?i32, 10), reduce(i32, &data, addAcc));
    try testing.expectEqual(@as(i32, 10), sum(i32, &data));
    try testing.expectEqual(@as(i32, 24), product(i32, &data));

    const mm = minMax(i32, &data).?;
    try testing.expectEqual(@as(i32, 1), mm.min);
    try testing.expectEqual(@as(i32, 4), mm.max);

    const rep = try repeat(a, i32, &.{ 7, 8 }, 3);
    defer a.free(rep);
    try testing.expectEqualSlices(i32, &.{ 7, 8, 7, 8, 7, 8 }, rep);

    const nested = [_][]const i32{ &.{ 1, 2 }, &.{ 3, 4 } };
    const joined = try join(a, i32, &nested, &.{0});
    defer a.free(joined);
    try testing.expectEqualSlices(i32, &.{ 1, 2, 0, 3, 4 }, joined);
}

test "slices: chunks, chunksExact, rchunks, windows, and splitBy" {
    const data = [_]i32{ 1, 2, 3, 4, 5 };

    var ch = chunks(i32, &data, 2);
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, ch.next().?);
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, ch.next().?);
    try testing.expectEqualSlices(i32, &.{5}, ch.next().?);
    try testing.expectEqual(@as(?[]const i32, null), ch.next());

    var ce = chunksExact(i32, &data, 2);
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, ce.next().?);
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, ce.next().?);
    try testing.expectEqual(@as(?[]const i32, null), ce.next());
    try testing.expectEqualSlices(i32, &.{5}, ce.remainder());

    var win = windows(i32, &data, 3);
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3 }, win.next().?);
    try testing.expectEqualSlices(i32, &.{ 2, 3, 4 }, win.next().?);
    try testing.expectEqualSlices(i32, &.{ 3, 4, 5 }, win.next().?);
    try testing.expectEqual(@as(?[]const i32, null), win.next());
}
