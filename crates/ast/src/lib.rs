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
pub struct Return {
    pub value: Option<ExprKind>,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub enum ExprKind {
    Identifier {
        symbol: String,
        location: Location,
    },

    Str {
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
        operator: char,
        right: Box<ExprKind>,
        location: Location,
    },

    BinaryOperation {
        left: Box<ExprKind>,
        operator: String,
        right: Box<ExprKind>,
        location: Location,
    },

    Assign {
        name: String,
        value: Box<ExprKind>,
        location: Location,
    },

    Call {
        function_name: String,
        arguments: ThinVec<ExprKind>,
        location: Location,
    },
}
