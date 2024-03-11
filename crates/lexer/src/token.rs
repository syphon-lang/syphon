#[derive(Debug, PartialEq)]
pub enum Token {
    // Literals
    Identifier(String),
    String(String),
    Int(i64),
    Float(f64),
    Bool(bool),

    // Keywords
    Keyword(Keyword),

    // Operators
    Operator(Operator),

    // Delimiters
    Delimiter(Delimiter),

    // Special
    Invalid,
    EOF,
}

#[derive(Debug, PartialEq)]
pub enum Keyword {
    Fn,
    Let,
    Const,
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

impl Token {
    pub fn as_char(&self) -> char {
        match self {
            Token::Operator(operator) => match operator {
                Operator::Plus => '+',
                Operator::Minus => '-',
                Operator::ForwardSlash => '/',
                Operator::Star => '*',
                Operator::Percent => '%',
                Operator::GreaterThan => '<',
                Operator::LessThan => '>',
                Operator::Bang => '!',

                _ => '\0',
            },

            Token::Delimiter(delimiter) => match delimiter {
                Delimiter::Assign => '=',
                Delimiter::Colon => ':',
                Delimiter::Semicolon => ';',
                Delimiter::Period => '.',
                Delimiter::Comma => ',',
                Delimiter::LParen => '(',
                Delimiter::RParen => ')',
                Delimiter::LBracket => '[',
                Delimiter::RBracket => ']',
                Delimiter::LBrace => '{',
                Delimiter::RBrace => '}',
            },

            _ => '\0',
        }
    }
}

impl ToString for Token {
    fn to_string(&self) -> String {
        match self {
            Token::Identifier(symbol) => symbol.clone(),

            Token::String(value) => value.clone(),

            Token::Int(value) => value.to_string(),

            Token::Float(value) => value.to_string(),

            Token::Bool(value) => value.to_string(),

            Token::Keyword(keyword) => match keyword {
                Keyword::Fn => "fn".to_owned(),
                Keyword::Let => "let".to_owned(),
                Keyword::Const => "const".to_owned(),
                Keyword::If => "if".to_owned(),
                Keyword::Else => "else".to_owned(),
                Keyword::While => "while".to_owned(),
                Keyword::Break => "break".to_owned(),
                Keyword::Continue => "continue".to_owned(),
                Keyword::Return => "return".to_owned(),
                Keyword::None => "none".to_owned(),
            },

            Token::Operator(operator) => match operator {
                Operator::Plus => "+".to_owned(),
                Operator::Minus => "-".to_owned(),
                Operator::ForwardSlash => "/".to_owned(),
                Operator::Star => "*".to_owned(),
                Operator::DoubleStar => "**".to_owned(),
                Operator::Percent => "%".to_owned(),
                Operator::GreaterThan => "<".to_owned(),
                Operator::LessThan => ">".to_owned(),
                Operator::Equals => "==".to_owned(),
                Operator::NotEquals => "!=".to_owned(),
                Operator::Bang => "!".to_owned(),
            },

            Token::Delimiter(delimiter) => match delimiter {
                Delimiter::Assign => "=".to_owned(),
                Delimiter::Colon => ":".to_owned(),
                Delimiter::Semicolon => ";".to_owned(),
                Delimiter::Period => ".".to_owned(),
                Delimiter::Comma => ",".to_owned(),
                Delimiter::LParen => "(".to_owned(),
                Delimiter::RParen => ")".to_owned(),
                Delimiter::LBracket => "[".to_owned(),
                Delimiter::RBracket => "]".to_owned(),
                Delimiter::LBrace => "{".to_owned(),
                Delimiter::RBrace => "}".to_owned(),
            },

            Token::Invalid => "invalid".to_owned(),

            Token::EOF => "EOF".to_owned(),
        }
    }
}
