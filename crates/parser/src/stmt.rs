use crate::*;
use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_stmt(&mut self) -> Result<Node, SyphonError> {
        match self.peek_token().kind {
            TokenKind::Keyword(keyword) => match keyword {
                Keyword::Fn => self.parse_function_declaration(),
                Keyword::Let => self.parse_variable_declaration(true),
                Keyword::Const => self.parse_variable_declaration(false),
                Keyword::If => self.parse_conditional(),
                Keyword::While => self.parse_while_loop(),
                Keyword::Break => self.parse_break(),
                Keyword::Continue => self.parse_continue(),
                Keyword::Return => self.parse_return(),

                _ => self.parse_expr(),
            },

            TokenKind::Invalid => Err(SyphonError::invalid(
                self.token_location(&self.peek_token()),
                "token",
            )),

            _ => self.parse_expr(),
        }
    }

    fn parse_function_declaration(&mut self) -> Result<Node, SyphonError> {
        let fn_token = self.next_token();

        let name_token = self.next_token();

        if name_token.kind != TokenKind::Identifier {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "function name",
            ));
        };

        let name = self.token_value(&name_token).to_owned();

        let parameters = self.parse_function_parameters()?;

        let mut body = ThinVec::new();

        if !self.expect(TokenKind::Delimiter(Delimiter::LBrace)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "function body starts with '{'",
            ));
        }

        while !self.expect(TokenKind::Delimiter(Delimiter::RBrace)) {
            if self.peek_token().kind == TokenKind::EOF {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "function body ends with '}'",
                ));
            }

            body.push(self.parse_stmt()?);
        }

        Ok(Node::Stmt(
            StmtKind::FunctionDeclaration(Function {
                name,
                parameters,
                body,
                location: self.token_location(&fn_token),
            })
            .into(),
        ))
    }

    fn parse_function_parameters(&mut self) -> Result<Vec<FunctionParameter>, SyphonError> {
        let mut parameters = Vec::new();

        if !self.expect(TokenKind::Delimiter(Delimiter::LParen)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "function parameters starts with '('",
            ));
        }

        if !self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
            let mut parameter = self.parse_function_parameter()?;

            parameters.push(parameter);

            while self.expect(TokenKind::Delimiter(Delimiter::Comma)) {
                if self.peek_token().kind == TokenKind::Delimiter(Delimiter::RParen) {
                    break;
                }

                parameter = self.parse_function_parameter()?;

                parameters.push(parameter);
            }

            if !self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "function parameters ends with ')'",
                ));
            }
        }

        Ok(parameters)
    }

    fn parse_function_parameter(&mut self) -> Result<FunctionParameter, SyphonError> {
        let token = self.next_token();

        let location = self.token_location(&token);

        if token.kind != TokenKind::Identifier {
            return Err(SyphonError::expected(location, "function parameter name"));
        };

        let name = self.token_value(&token).to_owned();

        Ok(FunctionParameter { name, location })
    }

    fn parse_variable_declaration(&mut self, mutable: bool) -> Result<Node, SyphonError> {
        let let_token = self.next_token();

        let name_token = self.next_token();

        if name_token.kind != TokenKind::Identifier {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "variable name",
            ));
        };

        let name = self.token_value(&name_token).to_owned();

        let value = match self.peek_token().kind {
            TokenKind::Delimiter(Delimiter::Assign) => {
                self.next_token();

                Some(self.parse_expr_kind(Precedence::Lowest)?)
            }

            TokenKind::Delimiter(Delimiter::Semicolon) => {
                let token = self.next_token();

                if !mutable {
                    return Err(SyphonError::unable_to(
                        self.token_location(&token),
                        "none-initialize a constant",
                    ));
                }

                None
            }
            _ => {
                let token = self.next_token();

                return Err(SyphonError::unexpected(
                    self.token_location(&token),
                    "token",
                    self.token_value(&token),
                ));
            }
        };

        self.expect(TokenKind::Delimiter(Delimiter::Semicolon));

        Ok(Node::Stmt(
            StmtKind::VariableDeclaration(Variable {
                mutable,
                name,
                value,
                location: self.token_location(&let_token),
            })
            .into(),
        ))
    }

    fn parse_conditional(&mut self) -> Result<Node, SyphonError> {
        let mut conditions = ThinVec::new();
        let mut bodies = ThinVec::new();
        let mut fallback = None;

        loop {
            self.next_token();

            conditions.push(self.parse_expr_kind(Precedence::Lowest)?);

            if !self.expect(TokenKind::Delimiter(Delimiter::LBrace)) {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "conditional body starts with '{'",
                ));
            }

            let mut body = ThinVec::new();

            while !self.expect(TokenKind::Delimiter(Delimiter::RBrace)) {
                if self.peek_token().kind == TokenKind::EOF {
                    return Err(SyphonError::expected(
                        self.token_location(&self.peek_token()),
                        "conditional body ends with '}'",
                    ));
                }

                body.push(self.parse_stmt()?);
            }

            bodies.push(body);

            if self.expect(TokenKind::Keyword(Keyword::Else)) {
                if self.peek_token().kind == TokenKind::Keyword(Keyword::If) {
                    continue;
                }

                if !self.expect(TokenKind::Delimiter(Delimiter::LBrace)) {
                    return Err(SyphonError::expected(
                        self.token_location(&self.peek_token()),
                        "fallback body starts with '{'",
                    ));
                }

                let mut body = ThinVec::new();

                while !self.expect(TokenKind::Delimiter(Delimiter::RBrace)) {
                    if self.peek_token().kind == TokenKind::EOF {
                        return Err(SyphonError::expected(
                            self.token_location(&self.peek_token()),
                            "fallback body ends with '}'",
                        ));
                    }

                    body.push(self.parse_stmt()?);
                }

                fallback = Some(body);
            }

            break;
        }

        Ok(Node::Stmt(
            StmtKind::Conditional(Conditional {
                conditions,
                bodies,
                fallback,
                location: self.token_location(&self.peek_token()),
            })
            .into(),
        ))
    }

    fn parse_while_loop(&mut self) -> Result<Node, SyphonError> {
        self.next_token();

        let condition = self.parse_expr_kind(Precedence::Lowest)?;

        if !self.expect(TokenKind::Delimiter(Delimiter::LBrace)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "while loop body starts with '{'",
            ));
        }

        let mut body = ThinVec::new();

        while !self.expect(TokenKind::Delimiter(Delimiter::RBrace)) {
            if self.peek_token().kind == TokenKind::EOF {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "while loop body ends with '}'",
                ));
            }

            body.push(self.parse_stmt()?);
        }

        Ok(Node::Stmt(
            StmtKind::While(While {
                condition,
                body,
                location: self.token_location(&self.peek_token()),
            })
            .into(),
        ))
    }

    fn parse_break(&mut self) -> Result<Node, SyphonError> {
        let token = self.next_token();

        self.expect(TokenKind::Delimiter(Delimiter::Semicolon));

        Ok(Node::Stmt(
            StmtKind::Break(Break {
                location: self.token_location(&token),
            })
            .into(),
        ))
    }

    fn parse_continue(&mut self) -> Result<Node, SyphonError> {
        let token = self.next_token();

        self.expect(TokenKind::Delimiter(Delimiter::Semicolon));

        Ok(Node::Stmt(
            StmtKind::Continue(Continue {
                location: self.token_location(&token),
            })
            .into(),
        ))
    }

    fn parse_return(&mut self) -> Result<Node, SyphonError> {
        let token = self.next_token();

        let value = match self.peek_token().kind {
            TokenKind::Delimiter(Delimiter::Semicolon) => {
                self.next_token();

                None
            }

            _ => Some(self.parse_expr_kind(Precedence::Lowest)?),
        };

        Ok(Node::Stmt(
            StmtKind::Return(Return {
                value,
                location: self.token_location(&token),
            })
            .into(),
        ))
    }
}
