const std = @import("std");

pub fn Iterator(comptime T: type) type {
    return struct {
        const Self = @This();

        index: usize = 0,
        nextFn: *const fn (self: *Self) ?T = next,

        /// This field is used to overload the default methods of iterator
        /// It can be useful to just overload the reset method with your own
        ///
        /// methods able to be overloaded are:
        ///   - len
        ///   - reset
        ///   - collect
        methods: IteratorMethods = .{},

        pub const IteratorMethods = struct {
            lenFn: *const fn (*Self) usize = _len,
            resetFn: *const fn (*Self) void = _reset,
            collectFn: *const fn (*Self, std.mem.Allocator) std.mem.Allocator.Error!std.ArrayList(T) = _collect,
            filterFn: *const fn (*Self, *const fn (*const T) bool) FilteredIterator = _filter,
        };

        const FilteredIterator = struct {
            parent_ptr: *Self,
            iterator: Self = .{ .nextFn = call },
            filterFn: *const fn (*const T) bool,

            fn call(iter: *Self) ?T {
                const self = iter.cast(@This());

                while (self.parent_ptr.next()) |t| {
                    var _t = t;
                    if (self.filterFn(&_t)) {
                        return t;
                    }
                }

                return null;
            }
        };

        pub fn cast(self: *Self, comptime U: type) *U {
            const parent: *U = @fieldParentPtr("iterator", self);
            return parent;
        }

        pub fn next(self: *Self) ?T {
            return self.nextFn(self);
        }

        pub fn peek(self: *Self) ?T {
            const old_index = self.index;
            defer self.index = old_index;
            return self.next();
        }

        fn _len(self: *Self) usize {
            var count: usize = 0;
            while (self.next()) |_| {
                count += 1;
            }

            self.reset();
            return count;
        }

        pub fn len(self: *Self) usize {
            return self.methods.lenFn(self);
        }

        pub fn map(self: *Self, comptime U: type, callback: *const fn (T) U) MappedIterator(T, U) {
            return MappedIterator(T, U){ .parent_ptr = self, .mapFn = callback };
        }

        pub fn collect(self: *Self, alloc: std.mem.Allocator) !std.ArrayList(T) {
            return self.methods.collectFn(self, alloc);
        }

        fn _collect(self: *Self, alloc: std.mem.Allocator) !std.ArrayList(T) {
            var list = std.ArrayList(T).init(alloc);
            while (self.next()) |item| {
                try list.append(item);
            }

            return list;
        }

        fn _reset(self: *Self) void {
            self.index = 0;
        }

        pub fn reset(self: *Self) void {
            self.methods.resetFn(self);
        }

        fn _filter(self: *Self, callback: *const fn (*const T) bool) FilteredIterator {
            return FilteredIterator{
                .parent_ptr = self,
                .filterFn = callback,
            };
        }

        pub fn filter(self: *Self, callback: *const fn (*const T) bool) FilteredIterator {
            return self.methods.filterFn(self, callback);
        }
    };
}

fn MappedIterator(comptime T: type, comptime U: type) type {
    return struct {
        parent_ptr: *Iterator(T),
        iterator: Iterator(U) = .{ .nextFn = call },
        mapFn: *const fn (T) U,

        fn call(iter: *Iterator(U)) ?U {
            const self = iter.cast(@This());

            if (self.parent_ptr.next()) |i| {
                return self.mapFn(i);
            } else {
                return null;
            }
        }
    };
}
