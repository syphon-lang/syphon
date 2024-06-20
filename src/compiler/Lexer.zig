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
    string_literal_back_slash,
    number,
    bang,
    equal_sign,
    plus,
    minus,
    forward_slash,
    percent,
    star,
};

pub fn init(buffer: [:0]const u8) Lexer {
    return Lexer{
        .buffer = buffer,
        .index = 0,
        .state = .start,
    };
}

pub fn next(self: *Lexer) Token {
    var result = Token{ .tag = .eof, .buffer_loc = .{ .start = self.index, .end = self.index } };

    while (self.buffer.len >= self.index) : (self.index += 1) {
        const current_char = self.buffer[self.index];

        switch (self.state) {
            .start => switch (current_char) {
                0 => break,

                ' ', '\r', '\n', '\t', ';' => {},

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
                    result.tag = .plus;
                    self.state = .plus;
                },

                '-' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .minus;
                    self.state = .minus;
                },

                '/' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .forward_slash;
                    self.state = .forward_slash;
                },

                '%' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .percent;
                    self.state = .percent;
                },

                '*' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .star;
                    self.state = .star;
                },

                '!' => {
                    result.buffer_loc.start = self.index;
                    result.tag = .bang;
                    self.state = .bang;
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

                ':' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .colon;
                    break;
                },

                '.' => {
                    result.buffer_loc.start = self.index;
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .period;
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

                '\\' => {
                    self.state = .string_literal_back_slash;
                },

                '"' => {
                    result.buffer_loc.end = self.index;
                    self.index += 1;
                    self.state = .start;
                    break;
                },

                else => {},
            },

            .string_literal_back_slash => switch (current_char) {
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

                else => {
                    self.state = .string_literal;
                },
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

            .bang => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .bang_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .plus => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .plus_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .minus => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .minus_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .forward_slash => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .forward_slash_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .percent => switch (current_char) {
                '=' => {
                    self.index += 1;
                    result.buffer_loc.end = self.index;
                    result.tag = .percent_equal_sign;
                    self.state = .start;
                    break;
                },

                else => {
                    result.buffer_loc.end = self.index;
                    self.state = .start;
                    break;
                },
            },

            .star => switch (current_char) {
                '*' => {
                    result.tag = .double_star;
                },

                '=' => {
                    if (result.tag == .star) {
                        result.tag = .star_equal_sign;
                    } else {
                        result.tag = .double_star_equal_sign;
                    }
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
