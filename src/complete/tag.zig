const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Item = @import("parser.zig").Item;
const ParseError = @import("parser.zig").ParseError;
const ziglyph = @import("ziglyph");

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

pub const TagNoCase = struct {
    parser: TagParser = .{
        ._parse = &_parse,
    },
    tag: []const u8,

    const Self = @This();
    const TagParser = Parser([]const u8, []const u8);

    pub fn init(tag: []const u8) Self {
        return .{ .tag = tag };
    }

    fn _parse(parser: *TagParser, input: []const u8) TagParser.ParseResult {
        const self = @fieldParentPtr(Self, "parser", parser);
        return self.parse(input);
    }

    pub fn parse(self: *const Self, input: []const u8) TagParser.ParseResult {
        var tag_utf8 = blk: {
            const view = std.unicode.Utf8View.init(self.tag) catch return .{ .err = .{ .input = input, .err = ParseError.Tag } };
            break :blk view.iterator();
        };
        var input_utf8 = blk: {
            const view = std.unicode.Utf8View.init(input) catch return .{ .err = .{ .input = input, .err = ParseError.Tag } };
            break :blk view.iterator();
        };
        while (tag_utf8.nextCodepoint()) |tag_codepoint| {
            if (input_utf8.nextCodepoint()) |input_codepoint| {
                if (ziglyph.toLower(tag_codepoint) != ziglyph.toLower(input_codepoint)) {
                    return .{ .err = .{ .input = input, .err = ParseError.Tag } };
                }
            } else {
                return .{ .err = .{ .input = input, .err = ParseError.Tag } };
            }
        }

        return .{ .ok = .{
            .value = input[0..input_utf8.i],
            .rest = input[input_utf8.i..],
        } };
    }
};

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

test "tag no case \"abc\" from \"abcde\"" {
    const input = "abcde";
    const parser = TagNoCase.init("abc");
    const result = parser.parse(input).ok;
    try testing.expectEqualStrings("abc", result.value);
    try testing.expectEqualStrings("de", result.rest);
    try testing.expectEqual(@intFromPtr(input), @intFromPtr(result.value.ptr));
    try testing.expectEqual(@intFromPtr(input) + 3, @intFromPtr(result.rest.ptr));
}

test "tag no case \"абвгґ\" from \"абвгґде\"" {
    const input = "абвгґде";
    const parser = TagNoCase.init("абвгґ");
    const result = parser.parse(input).ok;
    try testing.expectEqualStrings("абвгґ", result.value);
    try testing.expectEqualStrings("де", result.rest);
    try testing.expectEqual(@intFromPtr(input), @intFromPtr(result.value.ptr));
    try testing.expectEqual(@intFromPtr(input) + 10, @intFromPtr(result.rest.ptr));
}

test "tag no case \"abc\" from \"ab\"" {
    const input = "ab";
    const parser = TagNoCase.init("abc");
    const result = parser.parse(input).err;
    try testing.expectEqualStrings("ab", result.input);
    try testing.expectEqual(ParseError.Tag, result.err);
}

test "tag no case \"абвгґ\" from \"абвг\"" {
    const input = "абвг";
    const parser = TagNoCase.init("абвгґ");
    const result = parser.parse(input).err;
    try testing.expectEqualStrings("абвг", result.input);
    try testing.expectEqual(ParseError.Tag, result.err);
}
