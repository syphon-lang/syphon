use crate::*;
use precedence::Precedence;

impl<'a> Parser<'a> {
    pub(crate) fn parse_expr(&mut self) -> Node {
        Node::Expr(self.parse_expr_kind(Precedence::Lowest).into())
    }

    pub(crate) fn parse_expr_kind(&mut self, precedence: Precedence) -> ExprKind {
        let mut left = self.parse_unary_expression();

        while !self.eat(Token::Delimiter(Delimiter::Semicolon))
            && precedence < Precedence::from(&self.peek())
        {
            left = self.parse_binary_expression(left);
        }

        left
    }

    fn parse_unary_expression(&mut self) -> ExprKind {
        match self.peek() {
            Token::Operator(Operator::Minus) => self.parse_unary_operation(),
            Token::Operator(Operator::Bang) => self.parse_unary_operation(),
            Token::Identifier(symbol) => self.parse_identifier(symbol),
            Token::Str(value) => self.parse_string(value),
            Token::Int(value) => self.parse_integer(value),
            Token::Float(value) => self.parse_float(value),
            Token::Bool(value) => self.parse_boolean(value),

            _ => {
                self.next_token();

                ExprKind::Unknown
            }
        }
    }

    fn parse_unary_operation(&mut self) -> ExprKind {
        let operator = self.next_token();

        let right = self.parse_expr_kind(Precedence::Prefix);

        ExprKind::UnaryOperation {
            operator: operator.as_char(),
            right: right.into(),
            at: self.lexer.cursor.at,
        }
    }

    fn parse_identifier(&mut self, symbol: String) -> ExprKind {
        self.next_token();

        ExprKind::Identifier {
            symbol,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_string(&mut self, value: String) -> ExprKind {
        self.next_token();

        ExprKind::Str {
            value,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_integer(&mut self, value: i64) -> ExprKind {
        self.next_token();

        ExprKind::Int {
            value,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_float(&mut self, value: f64) -> ExprKind {
        self.next_token();

        ExprKind::Float {
            value,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_boolean(&mut self, value: bool) -> ExprKind {
        self.next_token();

        ExprKind::Bool {
            value,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_binary_expression(&mut self, left: ExprKind) -> ExprKind {
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

                _ => left,
            },

            Token::Delimiter(Delimiter::LParen) => self.parse_function_call(left),

            _ => left,
        }
    }

    fn parse_binary_operation(&mut self, left: ExprKind) -> ExprKind {
        let operator = self.next_token();
        let precedence = Precedence::from(&operator);

        let right = self.parse_expr_kind(precedence);

        ExprKind::BinaryOperation {
            left: left.into(),
            operator: operator.to_string(),
            right: right.into(),
            at: self.lexer.cursor.at,
        }
    }

    fn parse_function_call(&mut self, function_name: ExprKind) -> ExprKind {
        let function_name = match function_name {
            ExprKind::Identifier { symbol, .. } => symbol,
            _ => "".to_string(),
        };

        let arguments = self.parse_function_call_arguments();

        ExprKind::Call {
            function_name,
            arguments,
            at: self.lexer.cursor.at,
        }
    }

    fn parse_function_call_arguments(&mut self) -> ThinVec<ExprKind> {
        let mut arguments = ThinVec::new();

        self.eat(Token::Delimiter(Delimiter::LParen));

        if !self.eat(Token::Delimiter(Delimiter::RParen)) {
            let mut argument = self.parse_expr_kind(Precedence::Lowest);
            arguments.push(argument);

            while self.eat(Token::Delimiter(Delimiter::Comma)) {
                if self.peek() == Token::Delimiter(Delimiter::RParen) {
                    break;
                }

                argument = self.parse_expr_kind(Precedence::Lowest);
                arguments.push(argument);
            }

            if !self.eat(Token::Delimiter(Delimiter::RParen)) {
                self.errors.push(SyphonError::expected(
                    self.lexer.cursor.at,
                    "function call ends with ')'",
                ));
            }
        }

        self.eat(Token::Delimiter(Delimiter::Semicolon));

        arguments
    }
}
