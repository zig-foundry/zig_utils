//! Complete example and test suite for `zig_utils.slices`.
//! Run with `zig build run` or test with `zig build test`.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const zig_utils = @import("zig_utils");
const slices = zig_utils.slices;

// === Custom Types for Examples ===

const Point = struct {
    x: i32,
    y: i32,
};

fn isEven(n: i32) bool {
    return @mod(n, 2) == 0;
}

fn isPositive(n: i32) bool {
    return n > 0;
}

fn doubleVal(n: i32) i32 {
    return n * 2;
}

fn halfIfEven(n: i32) ?i32 {
    if (@mod(n, 2) == 0) return @divExact(n, 2);
    return null;
}

fn addAcc(acc: i32, n: i32) i32 {
    return acc + n;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    std.debug.print("=== zig_utils.slices Complete Example ===\n\n", .{});

    try demoElementAndSubsliceAccess();
    try demoPrefixSuffixAndSearch();
    try demoPredicatesAndFinding();
    try demoSortingAndBinarySearch();
    try demoInPlaceMutations();
    try demoFunctionalAndAllocating(gpa);
    try demoAggregations();
    try demoIterators();

    std.debug.print("=== All slices Demos Finished Successfully ===\n", .{});
}

// === 1. Element & Subslice Access ===

fn demoElementAndSubsliceAccess() !void {
    std.debug.print("--- 1. Element & Subslice Access ---\n", .{});

    const data = [_]i32{ 10, 20, 30, 40, 50 };

    // 1.1 `first` / `last` return the edge elements or null when empty
    std.debug.print("first() = {any}, last() = {any}\n", .{
        slices.first(i32, &data),
        slices.last(i32, &data),
    });

    // 1.2 `splitFirst` / `splitLast` peel off one element and return the rest
    const head = slices.splitFirst(i32, &data).?;
    const tail = slices.splitLast(i32, &data).?;
    std.debug.print("splitFirst: head = {d}, tail = {any}\n", .{ head.head, head.tail });
    std.debug.print("splitLast : head = {d}, tail = {any}\n", .{ tail.head, tail.tail });

    // 1.3 `splitAt` divides the slice at an index
    const parts = slices.splitAt(i32, &data, 2);
    std.debug.print("splitAt(2): left = {any}, right = {any}\n", .{ parts.left, parts.right });

    // 1.4 `takeFirst` / `takeLast` return a prefix or suffix of length n
    std.debug.print("takeFirst(3) = {any}, takeLast(2) = {any}\n\n", .{
        slices.takeFirst(i32, &data, 3),
        slices.takeLast(i32, &data, 2),
    });
}

// === 2. Prefix, Suffix & Searching ===

fn demoPrefixSuffixAndSearch() !void {
    std.debug.print("--- 2. Prefix, Suffix & Searching ---\n", .{});

    const data = [_]i32{ 1, 2, 3, 4, 5, 3, 2 };

    // 2.1 `startsWith` / `endsWith`
    std.debug.print("startsWith([1, 2]) = {}, endsWith([2]) = {}\n", .{
        slices.startsWith(i32, &data, &.{ 1, 2 }),
        slices.endsWith(i32, &data, &.{2}),
    });

    // 2.2 `stripPrefix` / `stripSuffix` remove a matching prefix or suffix
    const stripped = slices.stripPrefix(i32, &data, &.{ 1, 2 });
    std.debug.print("stripPrefix([1, 2]) = {any}\n", .{stripped});

    // 2.3 `contains`, `indexOf`, `lastIndexOf`
    std.debug.print("contains(3) = {}, indexOf(3) = {any}, lastIndexOf(3) = {any}\n\n", .{
        slices.contains(i32, &data, 3),
        slices.indexOf(i32, &data, 3),
        slices.lastIndexOf(i32, &data, 3),
    });
}

// === 3. Predicates & Finding ===

fn demoPredicatesAndFinding() !void {
    std.debug.print("--- 3. Predicates & Finding ---\n", .{});

    const data = [_]i32{ 1, 2, 3, 4, 5, 6 };

    // 3.1 `any` / `all` / `none`
    std.debug.print("any(isEven) = {}, all(isEven) = {}, none(isEven) = {}\n", .{
        slices.any(i32, &data, isEven),
        slices.all(i32, &data, isEven),
        slices.none(i32, &data, isEven),
    });

    // 3.2 `countIf` / `countValue`
    std.debug.print("countIf(isEven) = {d}, countValue(3) = {d}\n", .{
        slices.countIf(i32, &data, isEven),
        slices.countValue(i32, &data, 3),
    });

    // 3.3 `find` / `findIndex` / `rfind` / `rfindIndex`
    std.debug.print("find(isEven) = {any}, findIndex(isEven) = {any}\n", .{
        slices.find(i32, &data, isEven),
        slices.findIndex(i32, &data, isEven),
    });
    std.debug.print("rfind(isEven) = {any}, rfindIndex(isEven) = {any}\n\n", .{
        slices.rfind(i32, &data, isEven),
        slices.rfindIndex(i32, &data, isEven),
    });
}

// === 4. Sorting & Binary Search ===

fn demoSortingAndBinarySearch() !void {
    std.debug.print("--- 4. Sorting & Binary Search ---\n", .{});

    const sorted = [_]i32{ 1, 3, 5, 7, 9 };
    const unsorted = [_]i32{ 3, 1, 4, 1, 5 };

    // 4.1 `isSorted` / `isSortedBy`
    std.debug.print("isSorted(sorted) = {}, isSorted(unsorted) = {}\n", .{
        slices.isSorted(i32, &sorted),
        slices.isSorted(i32, &unsorted),
    });

    // 4.2 `binarySearch` returns `.found` or `.not_found` with an insertion index
    const found = slices.binarySearch(i32, &sorted, 5);
    const missing = slices.binarySearch(i32, &sorted, 4);
    std.debug.print("binarySearch(5) = {any}, binarySearch(4) = {any}\n\n", .{ found, missing });
}

// === 5. In-Place Mutations (Zero Allocation) ===

fn demoInPlaceMutations() !void {
    std.debug.print("--- 5. In-Place Mutations ---\n", .{});

    var data = [_]i32{ 1, 2, 3, 4, 5, 6 };

    // 5.1 `reverse`
    slices.reverse(i32, &data);
    std.debug.print("after reverse()          : {any}\n", .{data});

    // 5.2 `rotateLeft` / `rotateRight`
    slices.rotateLeft(i32, &data, 2);
    std.debug.print("after rotateLeft(2)      : {any}\n", .{data});

    // 5.3 `fill` / `fillWith`
    var fill_buf = [_]i32{ 0, 0, 0, 0 };
    slices.fill(i32, &fill_buf, 7);
    std.debug.print("fill(7)                  : {any}\n", .{fill_buf});

    // 5.4 `retain` keeps elements where the predicate is true
    var retain_buf = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const kept = slices.retain(i32, &retain_buf, isEven);
    std.debug.print("retain(isEven)           : {any}\n", .{kept});

    // 5.5 `dedup` removes consecutive duplicates
    var dedup_buf = [_]i32{ 1, 1, 2, 2, 2, 3, 3 };
    const deduped = slices.dedup(i32, &dedup_buf);
    std.debug.print("dedup()                  : {any}\n", .{deduped});

    // 5.6 `partitionInPlace` moves matching elements to the front
    var part_buf = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const split = slices.partitionInPlace(i32, &part_buf, isEven);
    std.debug.print("partitionInPlace(isEven): matching = {any}, rest = {any}\n\n", .{
        part_buf[0..split],
        part_buf[split..],
    });
}

// === 6. Functional & Allocating Operations ===

fn demoFunctionalAndAllocating(gpa: Allocator) !void {
    std.debug.print("--- 6. Functional & Allocating Operations ---\n", .{});

    const data = [_]i32{ 1, 2, 3, 4, 5 };

    // 6.1 `map` transforms every element into a new allocated slice
    const mapped = try slices.map(gpa, i32, i32, &data, doubleVal);
    defer gpa.free(mapped);
    std.debug.print("map(doubleVal)           : {any}\n", .{mapped});

    // 6.2 `filter` keeps only elements where the predicate is true
    const filtered = try slices.filter(gpa, i32, &data, isEven);
    defer gpa.free(filtered);
    std.debug.print("filter(isEven)           : {any}\n", .{filtered});

    // 6.3 `filterMap` maps and drops null results
    const fmapped = try slices.filterMap(gpa, i32, i32, &data, halfIfEven);
    defer gpa.free(fmapped);
    std.debug.print("filterMap(halfIfEven)    : {any}\n", .{fmapped});

    // 6.4 `fold` / `reduce`
    const folded = slices.fold(i32, i32, &data, 0, addAcc);
    const reduced = slices.reduce(i32, &data, addAcc);
    std.debug.print("fold(addAcc) = {d}, reduce(addAcc) = {any}\n", .{ folded, reduced });

    // 6.5 `repeat` and `join`
    const repeated = try slices.repeat(gpa, i32, &.{ 7, 8 }, 3);
    defer gpa.free(repeated);
    std.debug.print("repeat([7, 8], 3)        : {any}\n", .{repeated});

    const nested = [_][]const i32{ &.{ 1, 2 }, &.{ 3, 4 } };
    const joined = try slices.join(gpa, i32, &nested, &.{0});
    defer gpa.free(joined);
    std.debug.print("join([[1,2],[3,4]], [0]) : {any}\n\n", .{joined});
}

// === 7. Aggregations ===

fn demoAggregations() !void {
    std.debug.print("--- 7. Aggregations ---\n", .{});

    const data = [_]i32{ 2, 4, 6, 8 };

    // 7.1 `sum` / `product`
    std.debug.print("sum() = {d}, product() = {d}\n", .{
        slices.sum(i32, &data),
        slices.product(i32, &data),
    });

    // 7.2 `min` / `max` / `minMax`
    const mm = slices.minMax(i32, &data).?;
    std.debug.print("min() = {any}, max() = {any}, minMax = {{ .min = {d}, .max = {d} }}\n\n", .{
        slices.min(i32, &data),
        slices.max(i32, &data),
        mm.min,
        mm.max,
    });
}

// === 8. Zero-Allocation Iterators ===

fn demoIterators() !void {
    std.debug.print("--- 8. Zero-Allocation Iterators ---\n", .{});

    const data = [_]i32{ 1, 2, 3, 4, 5 };

    // 8.1 `chunks` yields non-overlapping chunks (last may be shorter)
    std.debug.print("chunks(2): ", .{});
    var ch = slices.chunks(i32, &data, 2);
    while (ch.next()) |chunk| {
        std.debug.print("{any} ", .{chunk});
    }
    std.debug.print("\n", .{});

    // 8.2 `chunksExact` + `.remainder()`
    var ce = slices.chunksExact(i32, &data, 2);
    std.debug.print("chunksExact(2) remainder = {any}\n", .{ce.remainder()});

    // 8.3 `windows` yields overlapping windows
    std.debug.print("windows(3): ", .{});
    var win = slices.windows(i32, &data, 3);
    while (win.next()) |window| {
        std.debug.print("{any} ", .{window});
    }
    std.debug.print("\n", .{});

    // 8.4 `splitBy` splits where the predicate is true
    std.debug.print("splitBy(isEven): ", .{});
    var sb = slices.splitBy(i32, &data, isEven);
    while (sb.next()) |part| {
        std.debug.print("{any} ", .{part});
    }
    std.debug.print("\n\n", .{});
}

// === Comprehensive Unit Tests (`zig build test`) ===

test "slices: first, last, split, take" {
    const data = [_]i32{ 10, 20, 30, 40 };

    try testing.expectEqual(@as(?i32, 10), slices.first(i32, &data));
    try testing.expectEqual(@as(?i32, 40), slices.last(i32, &data));
    try testing.expectEqual(@as(?i32, null), slices.first(i32, &.{}));

    const head = slices.splitFirst(i32, &data).?;
    try testing.expectEqual(@as(i32, 10), head.head);
    try testing.expectEqualSlices(i32, &.{ 20, 30, 40 }, head.tail);

    const parts = slices.splitAt(i32, &data, 2);
    try testing.expectEqualSlices(i32, &.{ 10, 20 }, parts.left);
    try testing.expectEqualSlices(i32, &.{ 30, 40 }, parts.right);

    try testing.expectEqualSlices(i32, &.{ 10, 20 }, slices.takeFirst(i32, &data, 2));
    try testing.expectEqualSlices(i32, &.{ 30, 40 }, slices.takeLast(i32, &data, 2));
}

test "slices: startsWith, endsWith, strip, contains, indexOf" {
    const data = [_]i32{ 1, 2, 3, 4, 5, 3 };

    try testing.expect(slices.startsWith(i32, &data, &.{ 1, 2 }));
    try testing.expect(slices.endsWith(i32, &data, &.{ 5, 3 }));
    try testing.expectEqualSlices(i32, &.{ 3, 4, 5, 3 }, slices.stripPrefix(i32, &data, &.{ 1, 2 }).?);

    try testing.expect(slices.contains(i32, &data, 3));
    try testing.expectEqual(@as(?usize, 2), slices.indexOf(i32, &data, 3));
    try testing.expectEqual(@as(?usize, 5), slices.lastIndexOf(i32, &data, 3));
}

test "slices: any, all, none, countIf, find" {
    const data = [_]i32{ 1, 2, 3, 4, 5, 6 };

    try testing.expect(slices.any(i32, &data, isEven));
    try testing.expect(!slices.all(i32, &data, isEven));
    try testing.expect(!slices.none(i32, &data, isEven));
    try testing.expectEqual(@as(usize, 3), slices.countIf(i32, &data, isEven));
    try testing.expectEqual(@as(?i32, 2), slices.find(i32, &data, isEven));
    try testing.expectEqual(@as(?i32, 6), slices.rfind(i32, &data, isEven));
}

test "slices: isSorted, binarySearch, reverse, retain, dedup" {
    const sorted = [_]i32{ 1, 3, 5, 7 };
    try testing.expect(slices.isSorted(i32, &sorted));

    const found = slices.binarySearch(i32, &sorted, 5);
    try testing.expectEqual(@as(usize, 2), found.found);

    var buf = [_]i32{ 1, 2, 3, 4 };
    slices.reverse(i32, &buf);
    try testing.expectEqualSlices(i32, &.{ 4, 3, 2, 1 }, &buf);

    var retain_buf = [_]i32{ 1, 2, 3, 4, 5, 6 };
    const kept = slices.retain(i32, &retain_buf, isEven);
    try testing.expectEqualSlices(i32, &.{ 2, 4, 6 }, kept);

    var dedup_buf = [_]i32{ 1, 1, 2, 2, 3 };
    const deduped = slices.dedup(i32, &dedup_buf);
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3 }, deduped);
}

test "slices: map, filter, filterMap, fold, sum, product, minMax" {
    const a = testing.allocator;
    const data = [_]i32{ 1, 2, 3, 4 };

    const mapped = try slices.map(a, i32, i32, &data, doubleVal);
    defer a.free(mapped);
    try testing.expectEqualSlices(i32, &.{ 2, 4, 6, 8 }, mapped);

    const filtered = try slices.filter(a, i32, &data, isEven);
    defer a.free(filtered);
    try testing.expectEqualSlices(i32, &.{ 2, 4 }, filtered);

    const fmapped = try slices.filterMap(a, i32, i32, &data, halfIfEven);
    defer a.free(fmapped);
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, fmapped);

    try testing.expectEqual(@as(i32, 10), slices.fold(i32, i32, &data, 0, addAcc));
    try testing.expectEqual(@as(i32, 10), slices.sum(i32, &data));
    try testing.expectEqual(@as(i32, 24), slices.product(i32, &data));

    const mm = slices.minMax(i32, &data).?;
    try testing.expectEqual(@as(i32, 1), mm.min);
    try testing.expectEqual(@as(i32, 4), mm.max);
}

test "slices: chunks, windows, and splitBy" {
    const data = [_]i32{ 1, 2, 3, 4, 5 };

    var ch = slices.chunks(i32, &data, 2);
    try testing.expectEqualSlices(i32, &.{ 1, 2 }, ch.next().?);
    try testing.expectEqualSlices(i32, &.{ 3, 4 }, ch.next().?);
    try testing.expectEqualSlices(i32, &.{5}, ch.next().?);
    try testing.expectEqual(@as(?[]const i32, null), ch.next());

    var win = slices.windows(i32, &data, 3);
    try testing.expectEqualSlices(i32, &.{ 1, 2, 3 }, win.next().?);
    try testing.expectEqualSlices(i32, &.{ 2, 3, 4 }, win.next().?);
    try testing.expectEqualSlices(i32, &.{ 3, 4, 5 }, win.next().?);
    try testing.expectEqual(@as(?[]const i32, null), win.next());
}
