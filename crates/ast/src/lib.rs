use derive_more::Display;

use thin_vec::ThinVec;

#[derive(Debug, Display, PartialEq, Clone, Copy)]
#[display(fmt = "{line}:{column}")]
pub struct Location {
    pub line: usize,
    pub column: usize,
}

impl Location {
    pub const fn dummy() -> Location {
        Location { line: 0, column: 0 }
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        bytes.extend(self.line.to_be_bytes());
        bytes.extend(self.column.to_be_bytes());

        bytes
    }

    pub fn from_bytes(bytes: &mut impl Iterator<Item = u8>) -> Location {
        fn get_8_bytes(bytes: &mut impl Iterator<Item = u8>) -> [u8; 8] {
            [
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
            ]
        }

        let line = usize::from_be_bytes(get_8_bytes(bytes));
        let column = usize::from_be_bytes(get_8_bytes(bytes));

        Location { line, column }
    }
}

impl Default for Location {
    fn default() -> Self {
        Self { line: 1, column: 1 }
    }
}

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

    Break(Break),

    Continue(Continue),

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
    pub parameters: Vec<FunctionParameter>,
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
pub struct Break {
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Continue {
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

impl From<&str> for BinaryOperator {
    fn from(value: &str) -> Self {
        match value {
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
        name: String,
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

    Array {
        values: ThinVec<ExprKind>,
        location: Location,
    },

    ArraySubscript {
        array: Box<ExprKind>,
        index: Box<ExprKind>,
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

    AssignSubscript {
        array: Box<ExprKind>,
        index: Box<ExprKind>,
        value: Box<ExprKind>,
        location: Location,
    },

    Call {
        callable: Box<ExprKind>,
        arguments: ThinVec<ExprKind>,
        location: Location,
    },
}
