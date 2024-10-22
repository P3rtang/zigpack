const std = @import("std");
const utils = @import("utils");
const Iterator = utils.Iterator;

test "map" {
    const Iter = struct {
        const Self = @This();

        iterator: Iterator(usize) = .{ .nextFn = next },
        items: *const [4]usize = &.{ 2, 5, 8, 1000 },

        fn next(iter: *Iterator(usize)) ?usize {
            defer iter.index += 1;
            const self = iter.cast(Self);
            if (self.items.len <= iter.index) {
                return null;
            } else {
                return self.items[iter.index];
            }
        }
    };

    var iter = Iter{};
    try std.testing.expectEqual(2, iter.iterator.next());
    try std.testing.expectEqual(5, iter.iterator.next());
    try std.testing.expectEqual(8, iter.iterator.next());
    try std.testing.expectEqual(1000, iter.iterator.next());
    iter.iterator.reset();

    var map_iter = iter.iterator.map(usize, struct {
        fn call(in: usize) usize {
            return in * 2;
        }
    }.call);
    try std.testing.expectEqual(4, map_iter.iterator.next());
    try std.testing.expectEqual(10, map_iter.iterator.next());
    try std.testing.expectEqual(16, map_iter.iterator.next());
    try std.testing.expectEqual(2000, map_iter.iterator.next());
}

test "collect" {
    const Iter = struct {
        const Self = @This();

        iterator: Iterator(usize) = .{ .nextFn = next },
        items: *const [4]usize = &.{ 2, 5, 8, 1000 },

        fn next(iter: *Iterator(usize)) ?usize {
            defer iter.index += 1;
            const self = iter.cast(Self);
            if (self.items.len <= iter.index) {
                return null;
            } else {
                return self.items[iter.index];
            }
        }
    };

    var iter = Iter{};
    const list = try iter.iterator.collect(std.testing.allocator);
    defer list.deinit();

    var expected: [4]usize = .{ 2, 5, 8, 1000 };
    try std.testing.expectEqualDeep(&expected, list.items[0..4]);

    iter.iterator.reset();
    try std.testing.expectEqual(2, iter.iterator.next());
    try std.testing.expectEqual(5, iter.iterator.next());
    try std.testing.expectEqual(8, iter.iterator.next());
    try std.testing.expectEqual(1000, iter.iterator.next());
}

test "filter" {
    const Iter = struct {
        const Self = @This();

        iterator: Iterator(usize) = .{ .nextFn = next },
        items: *const [4]usize = &.{ 2, 5, 8, 1000 },

        fn next(iter: *Iterator(usize)) ?usize {
            defer iter.index += 1;
            const self = iter.cast(Self);
            if (self.items.len <= iter.index) {
                return null;
            } else {
                return self.items[iter.index];
            }
        }
    };

    var iter = Iter{};
    var filtered = iter.iterator.filter(struct {
        fn call(item: *const usize) bool {
            return item.* % 2 == 0;
        }
    }.call);

    try std.testing.expectEqual(2, filtered.iterator.next());
    try std.testing.expectEqual(8, filtered.iterator.next());
    try std.testing.expectEqual(1000, filtered.iterator.next());
}

test "overload" {
    const Iter = struct {
        const Self = @This();

        iterator: Iterator(usize) = .{ .nextFn = next, .methods = .{ .lenFn = len, .collectFn = collect } },
        items: *const [4]usize = &.{ 2, 5, 8, 1000 },

        fn next(iter: *Iterator(usize)) ?usize {
            defer iter.index += 1;
            const self = iter.cast(Self);
            if (self.items.len <= iter.index) {
                return null;
            } else {
                return self.items[iter.index];
            }
        }

        fn len(_: *Iterator(usize)) usize {
            return 8;
        }

        fn collect(_: *Iterator(usize), alloc: std.mem.Allocator) !std.ArrayList(usize) {
            var list = std.ArrayList(usize).init(alloc);
            try list.appendSlice(&.{ 10, 20, 42 });
            return list;
        }
    };

    var iter = Iter{};

    try std.testing.expectEqual(8, iter.iterator.len());
    {
        const expected: [3]usize = .{ 10, 20, 42 };
        const list = try iter.iterator.collect(std.testing.allocator);
        defer list.deinit();
        try std.testing.expectEqualDeep(&expected, list.items[0..3]);
    }
}
