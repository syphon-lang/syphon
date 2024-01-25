use crate::*;

#[derive(PartialEq, PartialOrd)]
pub enum Precedence {
    Lowest,
    Assign,
    Comparison,
    Sum,
    Product,
    Exponent,
    Prefix,
    Call,
}

impl From<&Token> for Precedence {
    fn from(value: &Token) -> Precedence {
        match value {
            Token::Operator(operator) => match operator {
                Operator::Equals => Precedence::Comparison,
                Operator::NotEquals => Precedence::Comparison,
                Operator::LessThan => Precedence::Comparison,
                Operator::GreaterThan => Precedence::Comparison,
                Operator::Plus => Precedence::Sum,
                Operator::Minus => Precedence::Sum,
                Operator::ForwardSlash => Precedence::Product,
                Operator::Star => Precedence::Product,
                Operator::Percent => Precedence::Product,
                Operator::DoubleStar => Precedence::Exponent,
                _ => Precedence::Lowest,
            },

            Token::Delimiter(Delimiter::LParen) => Precedence::Call,
            Token::Delimiter(Delimiter::Assign) => Precedence::Assign,

            _ => Precedence::Lowest,
        }
    }
}
