mod expr;
mod precedence;

mod stmt;

use syphon_ast::*;
use syphon_errors::SyphonError;
use syphon_lexer::token::*;
use syphon_lexer::Lexer;

use thin_vec::ThinVec;

pub struct Parser<'a> {
    pub lexer: Lexer<'a>,
    input: &'a str,
}

impl<'a> Parser<'a> {
    pub fn new(input: &str) -> Parser {
        Parser {
            lexer: Lexer::new(input),
            input,
        }
    }

    pub fn parse(&mut self) -> Result<Node, SyphonError> {
        let mut body = ThinVec::new();

        while self.peek_token().kind != TokenKind::EOF {
            body.push(self.parse_stmt()?);
        }

        Ok(Node::Module { body })
    }

    #[inline]
    fn next_token(&mut self) -> Token {
        self.lexer.next_token()
    }

    #[inline]
    fn peek_token(&self) -> Token {
        self.lexer.clone().next_token()
    }

    #[inline]
    fn token_value(&self, token: &Token) -> &str {
        &self.input[token.span.start..token.span.end]
    }

    fn token_location(&self, token: &Token) -> Location {
        let mut location = Location { line: 1, column: 1 };

        let start = if token.kind == TokenKind::EOF {
            self.input.len()
        } else {
            token.span.start
        };

        for i in 0..start {
            let ch = self.input.chars().nth(i).unwrap();

            if ch == '\n' {
                location.line += 1;
                location.column = 1;
            } else {
                location.column += 1;
            }
        }

        location
    }

    #[inline]
    fn expect(&mut self, expected: TokenKind) -> bool {
        if self.peek_token().kind == expected {
            self.next_token();

            true
        } else {
            false
        }
    }
}
