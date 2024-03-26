mod cursor;
pub mod span;
pub mod token;

use cursor::Cursor;
use span::Span;
use token::*;

#[derive(Clone)]
pub struct Lexer<'a> {
    pub cursor: Cursor<'a>,
}

impl<'a> Lexer<'a> {
    pub fn new(source_code: &'a str) -> Lexer {
        Lexer {
            cursor: Cursor::new(source_code.chars()),
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

        let start = self.cursor.span();

        let Some(ch) = self.cursor.consume() else {
            return Token::new(TokenKind::EOF, start);
        };

        let kind = match ch {
            '=' => mini_condition!(
                '=',
                TokenKind::Operator(Operator::Equals),
                TokenKind::Delimiter(Delimiter::Assign)
            ),
            '!' => mini_condition!(
                '=',
                TokenKind::Operator(Operator::NotEquals),
                TokenKind::Operator(Operator::Bang)
            ),

            '+' => TokenKind::Operator(Operator::Plus),
            '-' => TokenKind::Operator(Operator::Minus),
            '/' => TokenKind::Operator(Operator::ForwardSlash),
            '*' => mini_condition!(
                '*',
                TokenKind::Operator(Operator::DoubleStar),
                TokenKind::Operator(Operator::Star)
            ),
            '%' => TokenKind::Operator(Operator::Percent),

            '<' => TokenKind::Operator(Operator::LessThan),
            '>' => TokenKind::Operator(Operator::GreaterThan),

            ',' => TokenKind::Delimiter(Delimiter::Comma),
            ':' => TokenKind::Delimiter(Delimiter::Colon),
            ';' => TokenKind::Delimiter(Delimiter::Semicolon),
            '.' => TokenKind::Delimiter(Delimiter::Period),
            '(' => TokenKind::Delimiter(Delimiter::LParen),
            ')' => TokenKind::Delimiter(Delimiter::RParen),
            '[' => TokenKind::Delimiter(Delimiter::LBracket),
            ']' => TokenKind::Delimiter(Delimiter::RBracket),
            '{' => TokenKind::Delimiter(Delimiter::LBrace),
            '}' => TokenKind::Delimiter(Delimiter::RBrace),

            '#' => return self.skip_comment(),

            '"' | '\'' => return self.read_string(start + 1),

            'a'..='z' | 'A'..='Z' | '_' => return self.read_identifier(start, ch),

            '0'..='9' => return self.read_number(start),

            _ => TokenKind::Invalid,
        };

        Token::new(kind, start.to(self.cursor.span()))
    }

    #[inline]
    fn skip_whitespace(&mut self) {
        while self.cursor.peek().is_some_and(|ch| ch.is_whitespace()) {
            self.cursor.consume();
        }
    }

    fn skip_comment(&mut self) -> Token {
        while self.cursor.peek().is_some_and(|ch| ch != '\n') {
            self.cursor.consume();
        }

        self.next_token()
    }

    fn read_string(&mut self, start: Span) -> Token {
        let mut end = self.cursor.span();

        while let Some(ch) = self.cursor.consume() {
            match ch {
                '"' | '\'' => break,

                _ => end = self.cursor.span(),
            }
        }

        Token::new(TokenKind::String, start.to(end))
    }

    fn read_identifier(&mut self, start: Span, ch: char) -> Token {
        let mut literal = String::from(ch);

        while let Some(ch) = self.cursor.peek() {
            match ch {
                'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => literal.push(ch),

                _ => break,
            }

            self.cursor.consume();
        }

        let kind = match literal.as_str() {
            "true" | "false" => TokenKind::Bool,

            "fn" => TokenKind::Keyword(Keyword::Fn),
            "let" => TokenKind::Keyword(Keyword::Let),
            "if" => TokenKind::Keyword(Keyword::If),
            "else" => TokenKind::Keyword(Keyword::Else),
            "while" => TokenKind::Keyword(Keyword::While),
            "break" => TokenKind::Keyword(Keyword::Break),
            "continue" => TokenKind::Keyword(Keyword::Continue),
            "return" => TokenKind::Keyword(Keyword::Return),
            "none" => TokenKind::Keyword(Keyword::None),

            _ => TokenKind::Identifier,
        };

        Token::new(kind, start.to(self.cursor.span()))
    }

    fn read_number(&mut self, start: Span) -> Token {
        let mut is_float = false;

        while let Some(ch) = self.cursor.peek() {
            match ch {
                '0'..='9' => (),
                '.' => is_float = true,
                _ => break,
            }

            self.cursor.consume();
        }

        let kind = if is_float {
            TokenKind::Float
        } else {
            TokenKind::Int
        };

        Token::new(kind, start.to(self.cursor.span()))
    }
}
