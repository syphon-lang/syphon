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
}

impl<'a> Parser<'a> {
    pub fn new(lexer: Lexer) -> Parser {
        Parser { lexer }
    }

    pub fn parse(&mut self) -> Result<Node, SyphonError> {
        let mut body = ThinVec::new();

        while self.peek() != Token::EOF {
            body.push(self.parse_stmt()?);
        }

        Ok(Node::Module { body })
    }

    fn next_token(&mut self) -> Token {
        self.lexer.next_token()
    }

    fn peek(&self) -> Token {
        self.lexer.clone().next_token()
    }

    fn eat(&mut self, expects: Token) -> bool {
        if self.peek() == expects {
            self.next_token();
            true
        } else {
            false
        }
    }
}
