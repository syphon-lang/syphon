use crate::*;
use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_stmt(&mut self) -> Result<Node, SyphonError> {
        match self.peek() {
            Token::Keyword(keyword) => match keyword {
                Keyword::Def => self.parse_function_definition(),
                Keyword::Let => self.parse_variable_declaration(true),
                Keyword::Const => self.parse_variable_declaration(false),
                Keyword::If => self.parse_conditional(),
                Keyword::Return => self.parse_return(),

                _ => self.parse_expr(),
            },

            Token::Invalid => Err(SyphonError::invalid(self.lexer.cursor.location, "token")),

            _ => self.parse_expr(),
        }
    }

    fn parse_function_definition(&mut self) -> Result<Node, SyphonError> {
        self.next_token();

        let Token::Identifier(name) = self.next_token() else {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
                "function name",
            ));
        };

        let parameters = self.parse_function_parameters()?;

        let body = self.parse_function_body()?;

        Ok(Node::Stmt(
            StmtKind::FunctionDeclaration(Function {
                name,
                parameters,
                body,
                location: self.lexer.cursor.location,
            })
            .into(),
        ))
    }

    fn parse_function_parameters(&mut self) -> Result<ThinVec<FunctionParameter>, SyphonError> {
        let mut parameters = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LParen)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
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
                    self.lexer.cursor.location,
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
                    self.lexer.cursor.location,
                    "function parameter name",
                ));
            }
        };

        Ok(FunctionParameter {
            name,
            location: self.lexer.cursor.location,
        })
    }

    fn parse_function_body(&mut self) -> Result<ThinVec<Node>, SyphonError> {
        let mut body = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LBrace)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
                "function body starts with '{'",
            ));
        }

        while self.peek() != Token::EOF && !self.eat(Token::Delimiter(Delimiter::RBrace)) {
            body.push(self.parse_stmt()?)
        }

        Ok(body)
    }

    fn parse_variable_declaration(&mut self, mutable: bool) -> Result<Node, SyphonError> {
        self.next_token();

        let Token::Identifier(name) = self.next_token() else {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
                "variable name",
            ));
        };

        let value = match self.next_token() {
            Token::Delimiter(Delimiter::Assign) => Some(self.parse_expr_kind(Precedence::Lowest)?),
            Token::Delimiter(Delimiter::Semicolon) => None,
            _ => {
                return Err(SyphonError::unexpected(
                    self.lexer.cursor.location,
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
                location: self.lexer.cursor.location,
            })
            .into(),
        ))
    }

    fn parse_conditional(&mut self) -> Result<Node, SyphonError> {
        let location = self.lexer.cursor.location;

        let mut conditions = ThinVec::new();
        let mut bodies = ThinVec::new();
        let mut fallback = None;

        loop {
            self.next_token();

            conditions.push(self.parse_expr_kind(Precedence::Lowest)?);

            if !self.eat(Token::Delimiter(Delimiter::LBrace)) {
                return Err(SyphonError::expected(self.lexer.cursor.location, "a '{'"));
            }

            let mut body = ThinVec::new();

            while self.peek() != Token::EOF && !self.eat(Token::Delimiter(Delimiter::RBrace)) {
                body.push(self.parse_stmt()?);
            }

            bodies.push(body);

            if self.eat(Token::Keyword(Keyword::Else)) {
                if self.peek() == Token::Keyword(Keyword::If) {
                    continue;
                }

                if !self.eat(Token::Delimiter(Delimiter::LBrace)) {
                    return Err(SyphonError::expected(self.lexer.cursor.location, "a '{'"));
                }

                let mut body = ThinVec::new();

                while self.peek() != Token::EOF && !self.eat(Token::Delimiter(Delimiter::RBrace)) {
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
                location,
            })
            .into(),
        ))
    }

    fn parse_return(&mut self) -> Result<Node, SyphonError> {
        let location = self.lexer.cursor.location;

        self.next_token();

        let value = match self.peek() {
            Token::Delimiter(Delimiter::Semicolon) => {
                self.next_token();

                None
            }

            _ => Some(self.parse_expr_kind(Precedence::Lowest)?),
        };

        Ok(Node::Stmt(
            StmtKind::Return(Return { value, location }).into(),
        ))
    }
}
