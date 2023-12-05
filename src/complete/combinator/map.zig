const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const Item = @import("../parser.zig").Item;
const ParseError = @import("../parser.zig").ParseError;
// const ParseResult = @import("../parser.zig").ParseResult;

pub fn Value(comptime T: type, comptime U: type, comptime Input: type) type {
    return struct {
        parser: Parser(U, Input) = .{
            ._parse = &_parse,
        },
        child_parser: Parser(T, Input),
        value: U,

        const Self = @This();
        const ValueCombinator = Parser(U, Input);

        pub fn init(value: U, child_parser: Parser(T, Input)) Self {
            return .{
                .value = value,
                .child_parser = child_parser,
            };
        }

        fn _parse(parser: *ValueCombinator, input: Input) ValueCombinator.ParseResult {
            const self = @fieldParentPtr(Self, "parser", parser);
            return self.parse(input);
        }

        pub fn parse(self: *Self, input: Input) ValueCombinator.ParseResult {
            const result = self.child_parser.parse(input);
            std.debug.print("{}\n", .{result});
            return switch (result) {
                .ok => |ok| .{ .ok = .{ .value = self.value, .rest = ok.rest } },
                .err => |err| .{ .err = .{ .input = err.input, .err = err.err } },
            };
        }
    };
}

const testing = std.testing;

test "value 1 from \"one\"" {
    const input = "one";

    const Tag = @import("../tag.zig").Tag;
    var tag_parser = Tag(@TypeOf(input)).init("one");
    var value_parser = Value([]const u8, u8, @TypeOf(input)).init(1, tag_parser.parser);
    const result = value_parser.parse(input);
    std.debug.print("{}\n", .{result});
    try testing.expectEqual(@as(u8, 1), result.ok.value);
    try testing.expectEqualStrings("", result.ok.rest);
}
