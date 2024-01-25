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
    FunctionDefinition(Function),
    Return(Return),
    Unknown,
}

#[derive(Debug, Clone)]
pub struct Variable {
    pub mutable: bool,
    pub name: String,
    pub value: Option<ExprKind>,
    pub at: (usize, usize),
}

#[derive(Debug, Clone)]
pub struct Function {
    pub name: String,
    pub parameters: ThinVec<FunctionParameter>,
    pub body: ThinVec<Node>,
    pub at: (usize, usize),
}

#[derive(Debug, Clone)]
pub struct FunctionParameter {
    pub name: String,
    pub at: (usize, usize),
}

#[derive(Debug, Clone)]
pub struct Return {
    pub value: Option<ExprKind>,
    pub at: (usize, usize),
}

#[derive(Debug, Clone)]
pub enum ExprKind {
    Identifier {
        symbol: String,
        at: (usize, usize),
    },
    Str {
        value: String,
        at: (usize, usize),
    },
    Int {
        value: i64,
        at: (usize, usize),
    },
    Float {
        value: f64,
        at: (usize, usize),
    },
    Bool {
        value: bool,
        at: (usize, usize),
    },

    UnaryOperation {
        operator: char,
        right: Box<ExprKind>,
        at: (usize, usize),
    },
    BinaryOperation {
        left: Box<ExprKind>,
        operator: String,
        right: Box<ExprKind>,
        at: (usize, usize),
    },

    Assign {
        name: String,
        value: Box<ExprKind>,
        at: (usize, usize),
    },

    Call {
        function_name: String,
        arguments: ThinVec<ExprKind>,
        at: (usize, usize),
    },

    Unknown,
}
