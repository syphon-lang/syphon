use syphon_location::Location;

use thin_vec::ThinVec;

#[derive(Debug, Clone)]
pub enum Node {
    Module { body: ThinVec<Node> },

    Stmt(Box<StmtKind>),

    Expr(Box<ExprKind>),
}

#[derive(Debug, Clone)]
pub enum StmtKind {
    VariableDeclaration(Variable),

    FunctionDeclaration(Function),

    Conditional(Conditional),

    While(While),

    Return(Return),
}

#[derive(Debug, Clone)]
pub struct Variable {
    pub mutable: bool,
    pub name: String,
    pub value: Option<ExprKind>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Function {
    pub name: String,
    pub parameters: ThinVec<FunctionParameter>,
    pub body: ThinVec<Node>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct FunctionParameter {
    pub name: String,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Conditional {
    pub conditions: ThinVec<ExprKind>,
    pub bodies: ThinVec<ThinVec<Node>>,
    pub fallback: Option<ThinVec<Node>>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct While {
    pub condition: ExprKind,
    pub body: ThinVec<Node>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Return {
    pub value: Option<ExprKind>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub enum UnaryOperator {
    Minus,
    Bang,
}

impl From<char> for UnaryOperator {
    fn from(value: char) -> Self {
        match value {
            '-' => Self::Minus,
            '!' => Self::Bang,

            _ => unreachable!(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum BinaryOperator {
    Plus,
    Minus,
    ForwardSlash,
    Star,
    DoubleStar,
    Percent,

    LessThan,
    GreaterThan,
    Equals,
    NotEquals,
}

impl From<String> for BinaryOperator {
    fn from(value: String) -> Self {
        match value.as_str() {
            "+" => Self::Plus,
            "-" => Self::Minus,
            "/" => Self::ForwardSlash,
            "*" => Self::Star,
            "**" => Self::DoubleStar,
            "%" => Self::Percent,

            "<" => Self::LessThan,
            ">" => Self::GreaterThan,
            "==" => Self::Equals,
            "!=" => Self::NotEquals,

            _ => unreachable!(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum ExprKind {
    Identifier {
        symbol: String,
        location: Location,
    },

    String {
        value: String,
        location: Location,
    },

    Int {
        value: i64,
        location: Location,
    },

    Float {
        value: f64,
        location: Location,
    },

    Bool {
        value: bool,
        location: Location,
    },

    None {
        location: Location,
    },

    UnaryOperation {
        operator: UnaryOperator,
        right: Box<ExprKind>,
        location: Location,
    },

    BinaryOperation {
        left: Box<ExprKind>,
        operator: BinaryOperator,
        right: Box<ExprKind>,
        location: Location,
    },

    Assign {
        name: String,
        value: Box<ExprKind>,
        location: Location,
    },

    Call {
        callable: Box<ExprKind>,
        arguments: ThinVec<ExprKind>,
        location: Location,
    },
}
