const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const Item = @import("../parser.zig").Item;
const ParseError = @import("../parser.zig").ParseError;
// const ParseResult = @import("../parser.zig").ParseResult;

fn isValidMapFn(comptime T: type, comptime Fn: std.builtin.Type.Fn) bool {
    return Fn.params.len == 1 and Fn.params[0].type == T and Fn.return_type != null;
}

fn isValidClosure(comptime T: type, comptime Closure: type) bool {
    const Fn = @typeInfo(@TypeOf(@field(Closure, "call"))).Fn;
    return Fn.params.len == 2 and switch (@typeInfo(Fn.params[0].type.?)) {
        .Pointer => |Pointer| Pointer.size == .One and Pointer.child == Closure,
        else => Fn.params[0].type == Closure,
    } and Fn.params[1].type == T and Fn.return_type != null;
}

/// `Mapper` can be a function (`fn(T) U`), a function pointer (`*const fn(T) U`) or a closure.
/// It it's a closure, it must have a public method named `call` that takes two arguments,
/// the first of which is of type `Self`, `*const Self`, or `*Self`, and the second of
/// which is of type `T`, and returns a value of type `U`
/// (where `U` is infered from the return type of the function):
///
/// ```zig
/// struct { pub fn call(self: @This(), value: T) U }        // FnOnce (kind of)
/// struct { pub fn call(self: *const @This(), value: T) U } // Fn
/// struct { pub fn call(self: *@This(), value: T) U }       // FnMut
/// ```
///
/// If `Mapper` is a function, the `init` constructor will take one argument, the parser to map from.
/// If `Mapper` is a closure, the `init` constructor will take two arguments, the closure and the
/// parser to map from.
///
/// # Examples
/// ```zig
/// const testing = @import("std").testing;
/// const Tag = @import("../tag.zig").Tag;
/// fn len(value: []const u8) usize {
///     return value.len;
/// }
/// ```
///
/// - Mapping with a function:
/// ```zig
/// const input = "one";
/// var tag_parser = Tag(@TypeOf(input)).init("one");
/// var value_parser = Map([]const u8, len, @TypeOf(input)).init(&tag_parser.parser);
/// const result = value_parser.parse(input);
/// try testing.expectEqual(@as(usize, 3), result.ok.value);
/// try testing.expectEqualStrings("", result.ok.rest);
/// ```
/// - Mapping with a function pointer
/// ```zig
/// const input = "one";
/// var tag_parser = Tag(@TypeOf(input)).init("one");
/// var value_parser = Map([]const u8, *const fn ([]const u8) usize, @TypeOf(input)).init(&len, &tag_parser.parser);
/// const result = value_parser.parse(input);
/// try testing.expectEqual(@as(usize, 3), result.ok.value);
/// try testing.expectEqualStrings("", result.ok.rest);
/// ```
/// - Mapping with a closure
/// ```zig
/// const input = "one";
/// var tag_parser = Tag(@TypeOf(input)).init("one");
/// var value_parser = Map([]const u8, struct {
///     pub fn call(self: @This(), value: []const u8) usize {
///         _ = self;
///         return value.len;
///     }
/// }, @TypeOf(input)).init(.{}, &tag_parser.parser);
/// const result = value_parser.parse(input);
/// try testing.expectEqual(@as(usize, 3), result.ok.value);
/// try testing.expectEqualStrings("", result.ok.rest);
/// ```
pub fn Map(comptime T: type, comptime Mapper: anytype, comptime Input: type) type {
    switch (@typeInfo(@TypeOf(Mapper))) {
        .Type => switch (@typeInfo(Mapper)) {
            .Pointer => |Pointer| if (Pointer.size != .One or @typeInfo(Pointer.child) != .Fn or !isValidMapFn(T, @typeInfo(Pointer.child).Fn)) {
                @compileError("unsupported Mapper");
            },
            else => if (!isValidClosure(T, Mapper)) {
                @compileError("unsupported Mapper");
            },
        },
        .Fn => |Fn| return struct {
            parser: Parser(Fn.return_type.?, Input) = .{
                ._parse = &_parse,
            },
            child_parser: *Parser(T, Input),

            const Self = @This();
            const MapCombinator = Parser(Fn.return_type.?, Input);

            pub fn init(child_parser: *Parser(T, Input)) Self {
                return .{
                    .child_parser = child_parser,
                };
            }

            fn _parse(parser: *MapCombinator, input: Input) MapCombinator.ParseResult {
                const self = @fieldParentPtr(Self, "parser", parser);
                return self.parse(input);
            }

            pub fn parse(self: *Self, input: Input) MapCombinator.ParseResult {
                const result = self.child_parser.parse(input);
                return switch (result) {
                    .ok => |ok| .{ .ok = .{
                        .value = Mapper(ok.value),
                        .rest = ok.rest,
                    } },
                    .err => |err| .{ .err = .{ .input = err.input, .err = err.err } },
                };
            }
        },
        else => @compileError("unsupported Mapper"),
    }

    const U = switch (@typeInfo(Mapper)) {
        .Fn => |Fn| Fn.return_type.?,
        .Pointer => |Pointer| @typeInfo(Pointer.child).Fn.return_type.?,
        else => @typeInfo(@TypeOf(@field(Mapper, "call"))).Fn.return_type.?,
    };

    const StoredMapper = switch (@typeInfo(Mapper)) {
        .Fn, .Pointer => Mapper,
        else => @typeInfo(@TypeOf(@field(Mapper, "call"))).Fn.params[0].type.?,
    };

    return struct {
        parser: Parser(U, Input) = .{
            ._parse = &_parse,
        },
        mapper: StoredMapper,
        child_parser: *Parser(T, Input),

        const Self = @This();
        const MapCombinator = Parser(U, Input);

        pub fn init(mapper: StoredMapper, child_parser: *Parser(T, Input)) Self {
            return .{
                .mapper = mapper,
                .child_parser = child_parser,
            };
        }

        fn _parse(parser: *MapCombinator, input: Input) MapCombinator.ParseResult {
            const self = @fieldParentPtr(Self, "parser", parser);
            return self.parse(input);
        }

        pub fn parse(self: *Self, input: Input) MapCombinator.ParseResult {
            const result = self.child_parser.parse(input);
            return switch (result) {
                .ok => |ok| .{ .ok = .{
                    .value = map(self.mapper, ok.value),
                    .rest = ok.rest,
                } },
                .err => |err| .{ .err = .{ .input = err.input, .err = err.err } },
            };
        }

        fn map(mapper: StoredMapper, value: T) U {
            return switch (@typeInfo(Mapper)) {
                .Pointer => mapper(value),
                else => mapper.call(value),
            };
        }
    };
}

const testing = std.testing;

test "map len from tag (fn)" {
    const Tag = @import("../tag.zig").Tag;

    const input = "one";
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Map([]const u8, len, @TypeOf(input)).init(&tag_parser.parser);
    const result = value_parser.parse(input);
    try testing.expectEqual(@as(usize, 3), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}

test "map len from tag (*const fn)" {
    const Tag = @import("../tag.zig").Tag;

    const input = "one";
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Map([]const u8, *const fn ([]const u8) usize, @TypeOf(input)).init(&len, &tag_parser.parser);
    const result = value_parser.parse(input);
    try testing.expectEqual(@as(usize, 3), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}

test "map len-1 from tag (FnMut closure)" {
    const Tag = @import("../tag.zig").Tag;

    const input = "one";
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Map([]const u8, struct {
        pub fn call(self: *@This(), value: []const u8) usize {
            _ = self;
            return value.len;
        }
    }, @TypeOf(input)).init(&.{}, &tag_parser.parser);
    const result = value_parser.parse(input);
    try testing.expectEqual(@as(usize, 3), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}

test "map len-1 from tag (Fn closure)" {
    const Tag = @import("../tag.zig").Tag;

    const input = "one";
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Map([]const u8, struct {
        pub fn call(self: *const @This(), value: []const u8) usize {
            _ = self;
            return value.len;
        }
    }, @TypeOf(input)).init(&.{}, &tag_parser.parser);
    const result = value_parser.parse(input);
    try testing.expectEqual(@as(usize, 3), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}

test "map len-1 from tag (FnOnce closure)" {
    const Tag = @import("../tag.zig").Tag;

    const input = "one";
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Map([]const u8, struct {
        pub fn call(self: @This(), value: []const u8) usize {
            _ = self;
            return value.len;
        }
    }, @TypeOf(input)).init(.{}, &tag_parser.parser);
    const result = value_parser.parse(input);
    try testing.expectEqual(@as(usize, 3), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}

fn len(value: []const u8) usize {
    return value.len;
}
