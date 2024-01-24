use crate::*;
use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_stmt(&mut self) -> Result<Node, SyphonError> {
        match self.peek() {
            Token::Identifier(symbol) => match symbol.as_str() {
                "const" => self.parse_variable_declaration(false),
                "let" => self.parse_variable_declaration(true),
                "def" => self.parse_function_definition(),
                "return" => self.parse_return(),
                _ => self.parse_expr(),
            },
            _ => self.parse_expr(),
        }
    }

    fn parse_variable_declaration(&mut self, mutable: bool) -> Result<Node, SyphonError> {
        self.next_token();

        let Token::Identifier(name) = self.next_token() else {
            return Err(SyphonError::expected(self.lexer.cursor.at, "variable name"));
        };

        let value = match self.next_token() {
            Token::Delimiter(Delimiter::Assign) => Some(self.parse_expr_kind(Precedence::Lowest)?),
            Token::Delimiter(Delimiter::Semicolon) => None,
            _ => {
                return Err(SyphonError::unexpected(
                    self.lexer.cursor.at,
                    "token",
                    self.peek().to_string().as_str(),
                ));
            }
        };

        self.eat(Token::Delimiter(Delimiter::Semicolon));

        Ok(Node::Stmt(
            StmtKind::VariableDeclaration(Variable {
                mutable,
                name,
                value,
                at: self.lexer.cursor.at,
            })
            .into(),
        ))
    }

    fn parse_function_definition(&mut self) -> Result<Node, SyphonError> {
        self.next_token();

        let Token::Identifier(name) = self.next_token() else {
            return Err(SyphonError::expected(self.lexer.cursor.at, "function name"));
        };

        let parameters = self.parse_function_parameters()?;

        let body = self.parse_function_body()?;

        Ok(Node::Stmt(
            StmtKind::FunctionDefinition(Function {
                name,
                parameters,
                body,
                at: self.lexer.cursor.at,
            })
            .into(),
        ))
    }

    fn parse_function_parameters(&mut self) -> Result<ThinVec<FunctionParameter>, SyphonError> {
        let mut parameters = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LParen)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.at,
                "function parameters starts with '('",
            ));
        }

        if !self.eat(Token::Delimiter(Delimiter::RParen)) {
            let mut parameter = self.parse_function_parameter()?;

            parameters.push(parameter);

            while self.eat(Token::Delimiter(Delimiter::Comma)) {
                if self.peek() == Token::Delimiter(Delimiter::RParen) {
                    break;
                }

                parameter = self.parse_function_parameter()?;

                parameters.push(parameter);
            }

            if !self.eat(Token::Delimiter(Delimiter::RParen)) {
                return Err(SyphonError::expected(
                    self.lexer.cursor.at,
                    "function parameters ends with ')'",
                ));
            }
        }

        Ok(parameters)
    }

    fn parse_function_parameter(&mut self) -> Result<FunctionParameter, SyphonError> {
        let name = match self.next_token() {
            Token::Identifier(name) => name,

            _ => {
                return Err(SyphonError::expected(
                    self.lexer.cursor.at,
                    "function parameter name",
                ));
            }
        };

        Ok(FunctionParameter {
            name,
            at: self.lexer.cursor.at,
        })
    }

    fn parse_function_body(&mut self) -> Result<ThinVec<Node>, SyphonError> {
        let mut body = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LBrace)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.at,
                "function body starts with '{'",
            ));
        }

        while self.peek() != Token::EOF && !self.eat(Token::Delimiter(Delimiter::RBrace)) {
            body.push(self.parse_stmt()?)
        }

        Ok(body)
    }

    fn parse_return(&mut self) -> Result<Node, SyphonError> {
        let at = self.lexer.cursor.at;

        self.next_token();

        let value = match self.peek() {
            Token::Delimiter(Delimiter::Semicolon) => {
                self.next_token();

                None
            }

            _ => Some(self.parse_expr_kind(Precedence::Lowest)?),
        };

        Ok(Node::Stmt(StmtKind::Return(Return { value, at }).into()))
    }
}
