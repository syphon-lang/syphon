use thin_vec::ThinVec;

#[derive(Debug)]
pub enum Node {
    Module { body: ThinVec<Node> },

    Stmt(Box<StmtKind>),
    Expr(Box<ExprKind>),
}

#[derive(Debug)]
pub enum StmtKind {
    VariableDeclaration(Variable),
    FunctionDefinition(Function),
    Return(Return),
    Unknown,
}

#[derive(Debug)]
pub struct Variable {
    pub is_constant: bool,
    pub name: String,
    pub value: Option<ExprKind>,
    pub at: (usize, usize),
}

#[derive(Debug)]
pub struct Function {
    pub name: String,
    pub parameters: ThinVec<FunctionParameter>,
    pub body: ThinVec<Node>,
    pub at: (usize, usize),
}

#[derive(Debug)]
pub struct FunctionParameter {
    pub name: String,
    pub at: (usize, usize),
}

#[derive(Debug)]
pub struct Return {
    pub value: Option<ExprKind>,
    pub at: (usize, usize),
}

#[derive(Debug)]
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
        value: u64,
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
        operator: char,
        right: Box<ExprKind>,
        at: (usize, usize),
    },

    Call {
        function_name: String,
        arguments: ThinVec<ExprKind>,
        at: (usize, usize),
    },

    Unknown,
}
