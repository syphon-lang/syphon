#[derive(Debug, PartialEq)]
pub enum Token {
    // Literals
    Identifier(String),
    Str(String),
    Int(u64),
    Flaot(f64),
    Bool(bool),

    // Operators
    Operator(Operator),

    // Delimiters
    Delimiter(Delimiter),

    // Special
    Unknown,
    EOF,
}

#[derive(Debug, PartialEq)]
pub enum Operator {
    // Arithmetic
    Plus,
    Minus,
    ForwradSlash,
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
