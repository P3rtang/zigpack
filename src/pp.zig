const std = @import("std");

const ppError = error{
    UnknownType,
};

pub fn pPrint(value: anytype) ![]const u8 {
    const format = switch (@typeInfo(@TypeOf(value))) {
        .Struct => {
            return "struct";
        },
        .Pointer => pPrint(value.*),
        else => return error.UnknownType,
    };

    return format;
}
