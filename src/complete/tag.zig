const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Item = @import("parser.zig").Item;
const ParseError = @import("parser.zig").ParseError;
// const ParseResult = @import("parser.zig").ParseResult;

pub fn Tag(comptime Input: type) type {
    return struct {
        parser: TagParser = .{
            ._parse = &_parse,
        },
        tag: []const Item(Input),

        const Self = @This();
        const TagParser = Parser([]const Item(Input), Input);

        pub fn init(tag: []const Item(Input)) Self {
            return .{ .tag = tag };
        }

        fn _parse(parser: *TagParser, input: Input) TagParser.ParseResult {
            const self = @fieldParentPtr(Self, "parser", parser);
            return self.parse(input);
        }

        pub fn parse(self: *const Self, input: Input) TagParser.ParseResult {
            if (std.mem.startsWith(Item(Input), input, self.tag)) {
                return .{ .ok = .{
                    .value = input[0..self.tag.len],
                    .rest = input[self.tag.len..],
                } };
            }

            return .{ .err = .{ .input = input, .err = ParseError.Tag } };
        }
    };
}

const testing = std.testing;

test "tag \"abc\" from \"abcde\"" {
    const input = "abcde";
    const parser = Tag(@TypeOf(input)).init("abc");
    const result = parser.parse(input).ok;
    try testing.expectEqualStrings("abc", result.value);
    try testing.expectEqualStrings("de", result.rest);
    try testing.expectEqual(@intFromPtr(input), @intFromPtr(result.value.ptr));
    try testing.expectEqual(@intFromPtr(input) + 3, @intFromPtr(result.rest.ptr));
}

test "tag \"abc\" from \"ab\"" {
    const input = "ab";
    const parser = Tag(@TypeOf(input)).init("abc");
    const result = parser.parse(input).err;
    try testing.expectEqualStrings("ab", result.input);
    try testing.expectEqual(ParseError.Tag, result.err);
}
