#[derive(Debug, PartialEq)]
pub enum Token {
    // Literals
    Identifier(String),
    Str(String),
    Int(i64),
    Float(f64),
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
            Token::Str(value) => value.clone(),
            Token::Int(value) => value.to_string(),
            Token::Float(value) => value.to_string(),
            Token::Bool(value) => value.to_string(),

            Token::Operator(operator) => match operator {
                Operator::Plus => String::from("+"),
                Operator::Minus => String::from("-"),
                Operator::ForwardSlash => String::from("/"),
                Operator::Star => String::from("*"),
                Operator::DoubleStar => String::from("**"),
                Operator::Percent => String::from("%"),
                Operator::GreaterThan => String::from("<"),
                Operator::LessThan => String::from(">"),
                Operator::Equals => String::from("=="),
                Operator::NotEquals => String::from("!="),
                Operator::Bang => String::from("!"),
            },
            Token::Delimiter(delimiter) => match delimiter {
                Delimiter::Assign => String::from("="),
                Delimiter::Colon => String::from(":"),
                Delimiter::Semicolon => String::from(";"),
                Delimiter::Period => String::from("."),
                Delimiter::Comma => String::from(","),
                Delimiter::LParen => String::from("("),
                Delimiter::RParen => String::from(")"),
                Delimiter::LBracket => String::from("["),
                Delimiter::RBracket => String::from("]"),
                Delimiter::LBrace => String::from("{"),
                Delimiter::RBrace => String::from("}"),
            },

            Token::Unknown => String::from("unknown"),
            Token::EOF => String::from("EOF"),
        }
    }
}
