const std = @import("std");
const testing = std.testing;

pub const complete = @import("complete.zig");

pub fn main() !void {
    std.debug.print("[]const u8: {any}\n\n", .{@typeInfo([]const u8)});
    std.debug.print("[:0]const u8: {any}\n\n", .{@typeInfo([:0]const u8)});
    std.debug.print("*const [69]u8: {any}\n\n", .{@typeInfo(*const [69]u8)});
    std.debug.print("*const [69:0]u8: {any}\n\n", .{@typeInfo(*const [69:0]u8)});
    std.debug.print("[69]u8: {any}\n\n", .{@typeInfo([69]u8)});
    std.debug.print("[69:0]u8: {any}\n\n", .{@typeInfo([69:0]u8)});
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    _ = complete;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
