const std = @import("std");

const Token = @import("Token.zig");

const Lexer = @This();

buffer: [:0]const u8,
index: usize,
state: State,

pub const State = enum {
    start,
    comment,
    identifier,
    string_literal,
    number,
    star,
    equal_sign,
};

pub fn init(buffer: [:0]const u8) Lexer {
    return Lexer{ .buffer = buffer, .index = 0, .state = .start };
}

pub fn next(self: *Lexer) Token {
    var result = Token{ .tag = .eof, .buffer_loc = .{ .start = self.index, .end = self.index } };

    while (self.buffer.len >= self.index) : (self.index += 1) {
        const current_char = self.buffer[self.index];

        switch (self.state) {
            .start => switch (current_char) {
                0 => break,

                ' ', '\r', '\n', '\t' => {},

                '#' => {
                    self.state = .comment;
                },

                'a'...'z', 'A'...'Z', '_' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .identifier;
                    self.state = .identifier;
                },

                '"' => {
                    result.buffer_loc.start = self.index + 1;
                    result.tag = .string_literal;
                    self.state = .string_literal;
                },

                '0'...'9' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .int;
                    self.state = .number;
                },

                '(' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .open_paren;
                    break;
                },

                ')' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .close_paren;
                    break;
                },

                '{' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .open_brace;
                    break;
                },

                '}' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .close_brace;
                    break;
                },

                '[' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .open_bracket;
                    break;
                },

                ']' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .close_bracket;
                    break;
                },

                '+' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .plus;
                    break;
                },

                '-' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .minus;
                    break;
                },

                '/' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .forward_slash;
                    break;
                },

                '*' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .star;
                    self.state = .star;
                },

                '!' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .bang;
                    break;
                },

                '>' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .greater_than;
                    break;
                },

                '<' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .less_than;
                    break;
                },

                '=' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .equal_sign;
                    self.state = .equal_sign;
                },

                ',' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .comma;
                    break;
                },

                else => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .invalid;
                    break;
                },
            },

            .comment => switch (current_char) {
                0 => {
                    result.buffer_loc.start = self.index;
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },

                '\n' => {
                    result.buffer_loc.start = self.index;
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                },

                else => {},
            },

            .identifier => switch (current_char) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => {},

                else => {
                    result.buffer_loc.end = self.index;
                    if (Token.Keywords.get(self.buffer[result.buffer_loc.start..result.buffer_loc.end])) |keyword_tag| {
                        result.tag = keyword_tag;
                    }
                    self.state = .start;
                    break;
                },
            },

            .string_literal => switch (current_char) {
                0 => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    result.tag = .invalid;
                    break;
                },

                '\n' => {
                    result.buffer_loc.end = self.index;
                    self.index += 1;
                    self.state = .start;
                    result.tag = .invalid;
                    break;
                },

                '"' => {
                    result.buffer_loc.end = self.index;
                    self.index += 1;
                    self.state = .start;
                    break;
                },

                else => {},
            },

            .number => switch (current_char) {
                '0'...'9' => {},

                '.' => {
                    result.tag = .float;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .star => switch (current_char) {
                '*' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .double_star;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .equal_sign => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .double_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },
        }
    }

    return result;
}

test "skip comment" {
    try testTokenize("# This is skipped by the lexer", &.{});
}

test "valid keywords" {
    try testTokenize("fn let return while if else true false none", &.{ .keyword_fn, .keyword_let, .keyword_return, .keyword_while, .keyword_if, .keyword_else, .keyword_true, .keyword_false, .keyword_none });
}

test "valid identifiers" {
    try testTokenize("identifier another_1d3ntifier AlsoIdentifier THIS_IS_AN_IDENTIFIER_BTW", &.{ .identifier, .identifier, .identifier, .identifier });
}

test "valid delimiters" {
    try testTokenize("= , () {} []", &.{ .equal_sign, .comma, .open_paren, .close_paren, .open_brace, .close_brace, .open_bracket, .close_bracket });
}

test "valid operators" {
    try testTokenize("+ - / * ** > < ==", &.{ .plus, .minus, .forward_slash, .star, .double_star, .greater_than, .less_than, .double_equal_sign });
}

test "valid ints" {
    try testTokenize("11 41 52 3 7", &.{ .int, .int, .int, .int, .int });
}

test "valid floats" {
    try testTokenize("1.0 2.0 0.5 55.0 6.0", &.{ .float, .float, .float, .float, .float });
}

test "valid string literals" {
    try testTokenize(
        \\"You can type anything you want"
    , &.{.string_literal});
}

test "invalid string literals" {
    try testTokenize(
        \\"invalid string
        \\"
    , &.{ .invalid, .invalid });
}

test "invalid tokens" {
    try testTokenize("@ & % $", &.{ .invalid, .invalid, .invalid, .invalid });
}

fn testTokenize(buffer: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var lexer = Lexer.init(buffer);

    for (expected_token_tags) |expected_token_tag| {
        const token = lexer.next();

        std.debug.print("\n{s}\n", .{buffer[token.buffer_loc.start..token.buffer_loc.end]});
        std.debug.print("\n{}\n", .{token});

        try std.testing.expectEqual(expected_token_tag, token.tag);
    }

    const eof_token = lexer.next();

    try std.testing.expectEqual(Token.Tag.eof, eof_token.tag);
    try std.testing.expectEqual(buffer.len, eof_token.buffer_loc.start);
    try std.testing.expectEqual(buffer.len, eof_token.buffer_loc.end);
}
