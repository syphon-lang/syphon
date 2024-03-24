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

        while !self.expect(TokenKind::Delimiter(Delimiter::Semicolon))
            && precedence < Precedence::from(&self.peek_token())
        {
            left = self.parse_binary_expression(left)?;
        }

        Ok(left)
    }

    fn parse_unary_expression(&mut self) -> Result<ExprKind, SyphonError> {
        Ok(match self.peek_token().kind {
            TokenKind::Operator(Operator::Minus) => self.parse_unary_operation()?,
            TokenKind::Operator(Operator::Bang) => self.parse_unary_operation()?,

            TokenKind::Delimiter(Delimiter::LParen) => self.parse_parentheses_expression()?,

            TokenKind::Delimiter(Delimiter::LBracket) => self.parse_array()?,

            TokenKind::Identifier => self.parse_identifier(),

            TokenKind::String => self.parse_string(),

            TokenKind::Int => self.parse_integer()?,

            TokenKind::Float => self.parse_float()?,

            TokenKind::Bool => self.parse_bool(),

            TokenKind::Keyword(Keyword::None) => self.parse_none(),

            _ => {
                return Err(SyphonError::unexpected(
                    self.token_location(&self.peek_token()),
                    "token",
                    self.token_value(&self.peek_token()),
                ))
            }
        })
    }

    fn parse_unary_operation(&mut self) -> Result<ExprKind, SyphonError> {
        let operator = self.next_token();

        let right = self.parse_expr_kind(Precedence::Prefix)?;

        Ok(ExprKind::UnaryOperation {
            operator: UnaryOperator::from(self.token_value(&operator).chars().next().unwrap()),
            right: right.into(),
            location: self.token_location(&self.peek_token()),
        })
    }

    fn parse_parentheses_expression(&mut self) -> Result<ExprKind, SyphonError> {
        self.next_token();

        if self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "expression inside '()'",
            ));
        }

        let value = self.parse_expr_kind(Precedence::Lowest)?;

        if !self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "to close '(' with ')'",
            ));
        }

        Ok(value)
    }

    fn parse_array(&mut self) -> Result<ExprKind, SyphonError> {
        self.next_token();

        let mut values = ThinVec::new();

        if !self.expect(TokenKind::Delimiter(Delimiter::RBracket)) {
            let mut value = self.parse_expr_kind(Precedence::Lowest)?;
            values.push(value);

            while self.expect(TokenKind::Delimiter(Delimiter::Comma)) {
                if self.peek_token().kind == TokenKind::Delimiter(Delimiter::RBracket) {
                    break;
                }

                value = self.parse_expr_kind(Precedence::Lowest)?;
                values.push(value);
            }

            if !self.expect(TokenKind::Delimiter(Delimiter::RBracket)) {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "array expression ends with ']'",
                ));
            }
        }

        self.expect(TokenKind::Delimiter(Delimiter::Semicolon));

        Ok(ExprKind::Array {
            values,
            location: self.token_location(&self.peek_token()),
        })
    }

    fn parse_identifier(&mut self) -> ExprKind {
        let token = self.next_token();

        ExprKind::Identifier {
            name: self.token_value(&token).to_owned(),
            location: self.token_location(&token),
        }
    }

    fn parse_string(&mut self) -> ExprKind {
        let token = self.next_token();

        ExprKind::String {
            value: self.token_value(&token).to_owned(),
            location: self.token_location(&token),
        }
    }

    fn parse_integer(&mut self) -> Result<ExprKind, SyphonError> {
        let token = self.next_token();

        let location = self.token_location(&token);

        let Ok(value) = self.token_value(&token).parse() else {
            return Err(SyphonError::invalid(location, "integer"));
        };

        Ok(ExprKind::Int { value, location })
    }

    fn parse_float(&mut self) -> Result<ExprKind, SyphonError> {
        let token = self.next_token();

        let location = self.token_location(&token);

        let Ok(value) = self.token_value(&token).parse() else {
            return Err(SyphonError::invalid(location, "float"));
        };

        Ok(ExprKind::Float { value, location })
    }

    fn parse_bool(&mut self) -> ExprKind {
        let token = self.next_token();

        ExprKind::Bool {
            value: self.token_value(&token).parse().unwrap(),
            location: self.token_location(&token),
        }
    }

    fn parse_none(&mut self) -> ExprKind {
        let token = self.next_token();

        ExprKind::None {
            location: self.token_location(&token),
        }
    }

    fn parse_binary_expression(&mut self, left: ExprKind) -> Result<ExprKind, SyphonError> {
        match self.peek_token().kind {
            TokenKind::Operator(operator) => match operator {
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

            TokenKind::Delimiter(Delimiter::Assign) => self.parse_assign(left),

            TokenKind::Delimiter(Delimiter::LParen) => self.parse_function_call(left),

            TokenKind::Delimiter(Delimiter::LBracket) => self.parse_array_subscript(left),

            _ => Ok(left),
        }
    }

    fn parse_binary_operation(&mut self, left: ExprKind) -> Result<ExprKind, SyphonError> {
        let operator = self.next_token();
        let precedence = Precedence::from(&operator);

        let right = self.parse_expr_kind(precedence)?;

        Ok(ExprKind::BinaryOperation {
            left: left.into(),
            operator: BinaryOperator::from(self.token_value(&operator)),
            right: right.into(),
            location: self.token_location(&self.peek_token()),
        })
    }

    fn parse_assign(&mut self, expr: ExprKind) -> Result<ExprKind, SyphonError> {
        match expr {
            ExprKind::Identifier { name, .. } => {
                self.next_token();

                let value = self.parse_expr_kind(Precedence::Lowest)?;

                Ok(ExprKind::Assign {
                    name,
                    value: value.into(),
                    location: self.token_location(&self.peek_token()),
                })
            }

            ExprKind::ArraySubscript { array, index, .. } => {
                self.next_token();

                let value = self.parse_expr_kind(Precedence::Lowest)?;

                Ok(ExprKind::AssignSubscript {
                    array,
                    index,
                    value: value.into(),
                    location: self.token_location(&self.peek_token()),
                })
            }

            _ => Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "a name or subscript",
            )),
        }
    }

    fn parse_function_call(&mut self, callable: ExprKind) -> Result<ExprKind, SyphonError> {
        let arguments = self.parse_function_call_arguments()?;

        Ok(ExprKind::Call {
            callable: callable.into(),
            arguments,
            location: self.token_location(&self.peek_token()),
        })
    }

    fn parse_array_subscript(&mut self, array: ExprKind) -> Result<ExprKind, SyphonError> {
        self.next_token();

        if self.peek_token().kind == TokenKind::Delimiter(Delimiter::RBracket) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "an index",
            ));
        }

        let index = self.parse_expr_kind(Precedence::Lowest)?;

        if !self.expect(TokenKind::Delimiter(Delimiter::RBracket)) {
            return Err(SyphonError::expected(
                self.token_location(&self.peek_token()),
                "a ']'",
            ));
        };

        Ok(ExprKind::ArraySubscript {
            array: array.into(),
            index: index.into(),
            location: self.token_location(&self.peek_token()),
        })
    }

    fn parse_function_call_arguments(&mut self) -> Result<ThinVec<ExprKind>, SyphonError> {
        let mut arguments = ThinVec::new();

        self.expect(TokenKind::Delimiter(Delimiter::LParen));

        if !self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
            let mut argument = self.parse_expr_kind(Precedence::Lowest)?;
            arguments.push(argument);

            while self.expect(TokenKind::Delimiter(Delimiter::Comma)) {
                if self.peek_token().kind == TokenKind::Delimiter(Delimiter::RParen) {
                    break;
                }

                argument = self.parse_expr_kind(Precedence::Lowest)?;
                arguments.push(argument);
            }

            if !self.expect(TokenKind::Delimiter(Delimiter::RParen)) {
                return Err(SyphonError::expected(
                    self.token_location(&self.peek_token()),
                    "function call ends with ')'",
                ));
            }
        }

        self.expect(TokenKind::Delimiter(Delimiter::Semicolon));

        Ok(arguments)
    }
}
