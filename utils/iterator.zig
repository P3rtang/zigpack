pub fn Iterator(comptime Output: type) type {
    return struct {
        const Self = @This();
        var index = 0;

        nextFn: *const fn (*Self) Output,

        pub fn next(self: *Self) Output {
            return self.nextFn(self);
        }

        pub fn peek(self: *Self) Output {
            const old_index = index;
            defer index = old_index;
            return self.next();
        }

        pub fn map(self: *Self, comptime Map: type, callback: *const fn (Output) Map) Iterator(Map) {
            const mapper = struct {
                fn call() Map {
                    callback(self.next());
                }
            }.call;

            .{ .index = 0, .next = mapper };
        }

        pub fn cast(self: *Self, comptime T: type) *T {
            const parent: *T = @fieldParentPtr("iterator", self);
            return parent;
        }
    };
}
