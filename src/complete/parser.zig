const std = @import("std");
const Type = std.builtin.Type;
const Pointer = Type.Pointer;

pub const ParseError = error{Tag};

pub fn Item(comptime Input: type) type {
    return switch (@typeInfo(Input)) {
        .Pointer => |pointer| switch (pointer.size) {
            .Slice => pointer.child,
            .One => switch (@typeInfo(pointer.child)) {
                .Array => |array| array.child,
                else => @compileError("unsupported Input type"),
            },
            else => @compileError("unsupported Input type"),
        },
        else => @compileError("unsupported Input type"),
    };
}

pub fn Parser(comptime T: type, comptime Input: type) type {
    return struct {
        _parse: *const fn (self: *Self, input: Input) ParseResult,

        const Self = @This();
        pub const ParseResult = union(enum) {
            ok: Ok,
            err: Err,

            pub const Ok = struct {
                value: T,
                rest: []const Item(Input),
            };
            pub const Err = struct {
                input: Input,
                err: ParseError,
            };
        };

        pub fn parse(self: *Self, input: Input) ParseResult {
            return self._parse(self, input);
        }
    };
}
