const std = @import("std");

tag: Tag,
buffer_loc: BufferLoc,

pub const Tag = enum {
    eof,
    invalid,
    identifier,
    string_literal,
    int,
    float,
    open_paren,
    close_paren,
    open_brace,
    close_brace,
    open_bracket,
    close_bracket,
    plus,
    minus,
    forward_slash,
    star,
    double_star,
    percent,
    bang,
    plus_equal_sign,
    minus_equal_sign,
    forward_slash_equal_sign,
    star_equal_sign,
    double_star_equal_sign,
    percent_equal_sign,
    bang_equal_sign,
    equal_sign,
    double_equal_sign,
    greater_than,
    less_than,
    comma,
    colon,
    period,
    keyword_fn,
    keyword_return,
    keyword_while,
    keyword_break,
    keyword_continue,
    keyword_if,
    keyword_else,
    keyword_true,
    keyword_false,
    keyword_none,
};

pub const BufferLoc = struct {
    start: usize,
    end: usize,
};

pub const Keywords = std.StaticStringMap(Tag).initComptime(.{
    .{ "fn", .keyword_fn },
    .{ "return", .keyword_return },
    .{ "while", .keyword_while },
    .{ "break", .keyword_break },
    .{ "continue", .keyword_continue },
    .{ "if", .keyword_if },
    .{ "else", .keyword_else },
    .{ "true", .keyword_true },
    .{ "false", .keyword_false },
    .{ "none", .keyword_none },
});
