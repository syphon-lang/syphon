mod cursor;
pub mod token;

use cursor::Cursor;
use token::*;

use syphon_errors::EvaluateError;

use thin_vec::ThinVec;

pub struct Lexer<'a> {
    cursor: Cursor<'a>,
    errors: ThinVec<EvaluateError>,
}

impl<'a> Lexer<'a> {
    pub fn new(source_code: &'a str) -> Lexer {
        Lexer {
            cursor: Cursor::new(source_code.chars()),
            errors: ThinVec::new(),
        }
    }

    pub fn next_token(&mut self) -> Token {
        macro_rules! mini_condition {
            ($next: expr, $if: expr, $else: expr) => {
                if self.cursor.peek().is_some_and(|c| c == $next) {
                    self.cursor.consume();
                    $if
                } else {
                    $else
                }
            };
        }

        self.skip_whitespace();

        let ch = match self.cursor.consume() {
            Some(ch) => ch,
            None => return Token::EOF,
        };

        match ch {
            '=' => mini_condition!(
                '=',
                Token::Operator(Operator::Equals),
                Token::Delimiter(Delimiter::Assign)
            ),
            '!' => mini_condition!(
                '=',
                Token::Operator(Operator::NotEquals),
                Token::Operator(Operator::Bang)
            ),

            '+' => Token::Operator(Operator::Plus),
            '-' => Token::Operator(Operator::Minus),
            '/' => Token::Operator(Operator::ForwradSlash),
            '*' => mini_condition!(
                '*',
                Token::Operator(Operator::DoubleStar),
                Token::Operator(Operator::Star)
            ),
            '%' => Token::Operator(Operator::Percent),

            '<' => Token::Operator(Operator::LessThan),
            '>' => Token::Operator(Operator::GreaterThan),

            ',' => Token::Delimiter(Delimiter::Comma),
            ':' => Token::Delimiter(Delimiter::Colon),
            ';' => Token::Delimiter(Delimiter::Semicolon),
            '.' => Token::Delimiter(Delimiter::Period),
            '(' => Token::Delimiter(Delimiter::LParen),
            ')' => Token::Delimiter(Delimiter::RParen),
            '[' => Token::Delimiter(Delimiter::LBracket),
            ']' => Token::Delimiter(Delimiter::RBracket),
            '{' => Token::Delimiter(Delimiter::LBrace),
            '}' => Token::Delimiter(Delimiter::RBrace),

            '"' | '\'' => self.read_string(),
            'a'..='z' | 'A'..='Z' | '_' => self.read_identifier(ch),
            '0'..='9' => self.read_number(ch),
            _ => {
                self.errors.push(EvaluateError::unexpected(
                    self.cursor.at,
                    "character",
                    ch.to_string().as_str(),
                ));

                Token::Unknown
            }
        }
    }

    fn skip_whitespace(&mut self) {
        while self.cursor.peek().is_some_and(|ch| ch.is_whitespace()) {
            self.cursor.consume();
        }
    }

    fn read_string(&mut self) -> Token {
        let mut literal = String::new();

        while let Some(ch) = self.cursor.consume() {
            match ch {
                '"' | '\'' => break,
                _ => literal.push(ch),
            }
        }

        Token::Str(literal)
    }

    fn read_identifier(&mut self, ch: char) -> Token {
        let mut literal = String::from(ch);

        while let Some(ch) = self.cursor.peek() {
            match ch {
                'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => literal.push(ch),
                _ => break,
            }

            self.cursor.consume();
        }

        if &literal == "true" || &literal == "false" {
            return Token::Bool(literal.parse().unwrap());
        }

        Token::Identifier(literal)
    }

    fn read_number(&mut self, ch: char) -> Token {
        let mut literal = String::from(ch);

        while let Some(ch) = self.cursor.peek() {
            match ch {
                '0'..='9' | '.' => literal.push(ch),
                _ => break,
            }

            self.cursor.consume();
        }

        if let Ok(integer) = literal.parse::<u64>() {
            Token::Int(integer)
        } else if let Ok(float) = literal.parse::<f64>() {
            Token::Flaot(float)
        } else {
            self.errors.push(EvaluateError::unable_to(
                self.cursor.at,
                "parse integer or float",
            ));

            Token::Int(0)
        }
    }
}
