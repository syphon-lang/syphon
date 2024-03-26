use crate::span::Span;

#[derive(Debug)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
}

impl Token {
    pub fn new(kind: TokenKind, span: Span) -> Token {
        Token { kind, span }
    }
}

#[derive(Debug, PartialEq)]
pub enum TokenKind {
    Identifier,
    String,
    Int,
    Float,
    Bool,

    Keyword(Keyword),

    Operator(Operator),

    Delimiter(Delimiter),

    Invalid,
    EOF,
}

#[derive(Debug, PartialEq)]
pub enum Keyword {
    Fn,
    Let,
    If,
    Else,
    While,
    Break,
    Continue,
    Return,
    None,
}

#[derive(Debug, PartialEq)]
pub enum Operator {
    // Arithmetic
    Plus,
    Minus,
    ForwardSlash,
    Star,
    DoubleStar,
    Percent,

    // Comparison
    LessThan,
    GreaterThan,
    Equals,
    NotEquals,

    // Logical
    Bang,
}

#[derive(Debug, PartialEq)]
pub enum Delimiter {
    // Arithmetic
    Assign,

    // Grouping
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,

    // Punctuation
    Comma,
    Colon,
    Semicolon,
    Period,
}
