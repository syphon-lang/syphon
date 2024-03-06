use crate::*;

use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_expr(&mut self) -> Result<Node, SyphonError> {
        Ok(Node::Expr(self.parse_expr_kind(Precedence::Lowest)?.into()))
    }

    pub(crate) fn parse_expr_kind(
        &mut self,
        precedence: Precedence,
    ) -> Result<ExprKind, SyphonError> {
        let mut left = self.parse_unary_expression()?;

        while !self.eat(Token::Delimiter(Delimiter::Semicolon))
            && precedence < Precedence::from(&self.peek())
        {
            left = self.parse_binary_expression(left)?;
        }

        Ok(left)
    }

    fn parse_unary_expression(&mut self) -> Result<ExprKind, SyphonError> {
        Ok(match self.peek() {
            Token::Operator(Operator::Minus) => self.parse_unary_operation()?,
            Token::Operator(Operator::Bang) => self.parse_unary_operation()?,
            Token::Delimiter(Delimiter::LParen) => self.parse_parentheses_expression()?,
            Token::Identifier(symbol) => self.parse_identifier(symbol),
            Token::String(value) => self.parse_string(value),
            Token::Int(value) => self.parse_integer(value),
            Token::Float(value) => self.parse_float(value),
            Token::Bool(value) => self.parse_boolean(value),

            Token::Keyword(Keyword::None) => self.parse_none(),

            _ => {
                return Err(SyphonError::unexpected(
                    self.lexer.cursor.location,
                    "token",
                    self.peek().to_string().as_str(),
                ))
            }
        })
    }

    fn parse_unary_operation(&mut self) -> Result<ExprKind, SyphonError> {
        let operator = self.next_token();

        let right = self.parse_expr_kind(Precedence::Prefix)?;

        Ok(ExprKind::UnaryOperation {
            operator: operator.as_char(),
            right: right.into(),
            location: self.lexer.cursor.location,
        })
    }

    fn parse_parentheses_expression(&mut self) -> Result<ExprKind, SyphonError> {
        self.next_token();

        if self.eat(Token::Delimiter(Delimiter::RParen)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
                "expression inside '()'",
            ));
        }

        let value = self.parse_expr_kind(Precedence::Lowest)?;

        if !self.eat(Token::Delimiter(Delimiter::RParen)) {
            return Err(SyphonError::expected(
                self.lexer.cursor.location,
                "to close '(' with ')'",
            ));
        }

        Ok(value)
    }

    fn parse_identifier(&mut self, symbol: String) -> ExprKind {
        self.next_token();

        ExprKind::Identifier {
            symbol,
            location: self.lexer.cursor.location,
        }
    }

    fn parse_string(&mut self, value: String) -> ExprKind {
        self.next_token();

        ExprKind::String {
            value,
            location: self.lexer.cursor.location,
        }
    }

    fn parse_integer(&mut self, value: i64) -> ExprKind {
        self.next_token();

        ExprKind::Int {
            value,
            location: self.lexer.cursor.location,
        }
    }

    fn parse_float(&mut self, value: f64) -> ExprKind {
        self.next_token();

        ExprKind::Float {
            value,
            location: self.lexer.cursor.location,
        }
    }

    fn parse_boolean(&mut self, value: bool) -> ExprKind {
        self.next_token();

        ExprKind::Bool {
            value,
            location: self.lexer.cursor.location,
        }
    }

    fn parse_none(&mut self) -> ExprKind {
        self.next_token();

        ExprKind::None {
            location: self.lexer.cursor.location,
        }
    }

    fn parse_binary_expression(&mut self, left: ExprKind) -> Result<ExprKind, SyphonError> {
        match self.peek() {
            Token::Operator(operator) => match operator {
                Operator::Equals => self.parse_binary_operation(left),
                Operator::NotEquals => self.parse_binary_operation(left),
                Operator::LessThan => self.parse_binary_operation(left),
                Operator::GreaterThan => self.parse_binary_operation(left),
                Operator::Plus => self.parse_binary_operation(left),
                Operator::Minus => self.parse_binary_operation(left),
                Operator::ForwardSlash => self.parse_binary_operation(left),
                Operator::Star => self.parse_binary_operation(left),
                Operator::DoubleStar => self.parse_binary_operation(left),
                Operator::Percent => self.parse_binary_operation(left),

                _ => Ok(left),
            },

            Token::Delimiter(Delimiter::Assign) => self.parse_assign(left),

            Token::Delimiter(Delimiter::LParen) => self.parse_function_call(left),

            _ => Ok(left),
        }
    }

    fn parse_binary_operation(&mut self, left: ExprKind) -> Result<ExprKind, SyphonError> {
        let operator = self.next_token();
        let precedence = Precedence::from(&operator);

        let right = self.parse_expr_kind(precedence)?;

        Ok(ExprKind::BinaryOperation {
            left: left.into(),
            operator: operator.to_string(),
            right: right.into(),
            location: self.lexer.cursor.location,
        })
    }

    fn parse_assign(&mut self, expr: ExprKind) -> Result<ExprKind, SyphonError> {
        let name = match expr {
            ExprKind::Identifier { symbol, .. } => symbol,
            _ => return Err(SyphonError::expected(self.lexer.cursor.location, "a name")),
        };

        self.eat(Token::Delimiter(Delimiter::Assign));

        let value = self.parse_expr_kind(Precedence::Lowest)?;

        Ok(ExprKind::Assign {
            name,
            value: value.into(),
            location: self.lexer.cursor.location,
        })
    }

    fn parse_function_call(&mut self, expr: ExprKind) -> Result<ExprKind, SyphonError> {
        let function_name = match expr {
            ExprKind::Identifier { symbol, .. } => symbol,
            _ => {
                return Err(SyphonError::expected(
                    self.lexer.cursor.location,
                    "a function name",
                ))
            }
        };

        let arguments = self.parse_function_call_arguments()?;

        Ok(ExprKind::Call {
            function_name,
            arguments,
            location: self.lexer.cursor.location,
        })
    }

    fn parse_function_call_arguments(&mut self) -> Result<ThinVec<ExprKind>, SyphonError> {
        let mut arguments = ThinVec::new();

        self.eat(Token::Delimiter(Delimiter::LParen));

        if !self.eat(Token::Delimiter(Delimiter::RParen)) {
            let mut argument = self.parse_expr_kind(Precedence::Lowest)?;
            arguments.push(argument);

            while self.eat(Token::Delimiter(Delimiter::Comma)) {
                if self.peek() == Token::Delimiter(Delimiter::RParen) {
                    break;
                }

                argument = self.parse_expr_kind(Precedence::Lowest)?;
                arguments.push(argument);
            }

            if !self.eat(Token::Delimiter(Delimiter::RParen)) {
                return Err(SyphonError::expected(
                    self.lexer.cursor.location,
                    "function call ends with ')'",
                ));
            }
        }

        self.eat(Token::Delimiter(Delimiter::Semicolon));

        Ok(arguments)
    }
}
