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
    Subscript,
}

impl From<&Token> for Precedence {
    fn from(value: &Token) -> Precedence {
        match &value.kind {
            TokenKind::Operator(operator) => match operator {
                Operator::Equals
                | Operator::NotEquals
                | Operator::LessThan
                | Operator::GreaterThan => Precedence::Comparison,
                Operator::Plus | Operator::Minus => Precedence::Sum,
                Operator::ForwardSlash | Operator::Star => Precedence::Product,
                Operator::Percent | Operator::DoubleStar => Precedence::Exponent,
                _ => Precedence::Lowest,
            },

            TokenKind::Delimiter(Delimiter::LParen) => Precedence::Call,
            TokenKind::Delimiter(Delimiter::LBracket) => Precedence::Subscript,
            TokenKind::Delimiter(Delimiter::Assign) => Precedence::Assign,

            _ => Precedence::Lowest,
        }
    }
}
