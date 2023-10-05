use crate::*;
use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_stmt(&mut self) -> Node {
        match self.peek() {
            Token::Identifier(symbol) => match symbol.as_str() {
                "const" => self.parse_variable_declaration(true),
                "let" => self.parse_variable_declaration(false),
                "def" => self.parse_function_definition(),
                "return" => self.parse_return(),
                _ => self.parse_expr(),
            },
            _ => self.parse_expr(),
        }
    }

    fn parse_variable_declaration(&mut self, is_constant: bool) -> Node {
        self.next_token();

        let name = match self.next_token() {
            Token::Identifier(name) => name,
            _ => {
                self.errors.push(EvaluateError::expected(
                    self.lexer.cursor.at,
                    "variable name",
                ));

                String::new()
            }
        };

        let value = match self.next_token() {
            Token::Delimiter(Delimiter::Assign) => Some(self.parse_expr_kind(Precedence::Lowest)),
            Token::Delimiter(Delimiter::Semicolon) => None,
            _ => {
                self.errors.push(EvaluateError::unexpected(
                    self.lexer.cursor.at,
                    "token",
                    self.peek().to_string().as_str(),
                ));

                None
            }
        };

        self.eat(Token::Delimiter(Delimiter::Semicolon));

        Node::Stmt(
            StmtKind::VariableDeclaration(Variable {
                is_constant,
                name,
                value,
                at: self.lexer.cursor.at,
            })
            .into(),
        )
    }

    fn parse_function_definition(&mut self) -> Node {
        self.next_token();

        let name = match self.next_token() {
            Token::Identifier(name) => name,
            _ => {
                self.errors.push(EvaluateError::expected(
                    self.lexer.cursor.at,
                    "function name",
                ));

                String::new()
            }
        };

        let parameters = self.parse_function_parameters();

        let body = self.parse_function_body();

        Node::Stmt(
            StmtKind::FunctionDefinition(Function {
                name,
                parameters,
                body,
                at: self.lexer.cursor.at,
            })
            .into(),
        )
    }

    fn parse_function_parameters(&mut self) -> ThinVec<FunctionParameter> {
        let mut parameters = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LParen)) {
            self.errors.push(EvaluateError::expected(
                self.lexer.cursor.at,
                "function parameters starts with '('",
            ));

            return parameters;
        }

        if !self.eat(Token::Delimiter(Delimiter::RParen)) {
            let mut parameter = self.parse_function_parameter();

            parameters.push(parameter);

            while self.eat(Token::Delimiter(Delimiter::Comma)) {
                if self.eat(Token::Delimiter(Delimiter::RParen)) {
                    break;
                }

                parameter = self.parse_function_parameter();

                parameters.push(parameter);
            }

            if !self.eat(Token::Delimiter(Delimiter::RParen)) {
                self.errors.push(EvaluateError::expected(
                    self.lexer.cursor.at,
                    "function parameters ends with ')'",
                ));

                return parameters;
            }
        }

        parameters
    }

    fn parse_function_parameter(&mut self) -> FunctionParameter {
        let name = match self.next_token() {
            Token::Identifier(name) => name,

            _ => {
                self.errors.push(EvaluateError::expected(
                    self.lexer.cursor.at,
                    "function parameter name",
                ));

                String::new()
            }
        };

        FunctionParameter {
            name,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_function_body(&mut self) -> ThinVec<Node> {
        let mut body = ThinVec::new();

        if !self.eat(Token::Delimiter(Delimiter::LBrace)) {
            self.errors.push(EvaluateError::expected(
                self.lexer.cursor.at,
                "function body starts with '{'",
            ));

            return body;
        }

        while self.peek() != Token::EOF && !self.eat(Token::Delimiter(Delimiter::RBrace)) {
            body.push(self.parse_stmt())
        }

        body
    }

    fn parse_return(&mut self) -> Node {
        let at = self.lexer.cursor.at;

        self.next_token();

        let value = match self.peek() {
            Token::Delimiter(Delimiter::Semicolon) => {
                self.next_token();

                None
            }

            _ => Some(self.parse_expr_kind(Precedence::Lowest)),
        };

        Node::Stmt(StmtKind::Return(Return { value, at }).into())
    }
}
