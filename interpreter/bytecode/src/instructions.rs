#[derive(Clone, PartialEq)]
#[repr(u8)]
pub enum Instruction {
    Neg {
        at: (usize, usize),
    },
    LogicalNot {
        at: (usize, usize),
    },

    Add {
        at: (usize, usize),
    },
    Sub {
        at: (usize, usize),
    },
    Div {
        at: (usize, usize),
    },
    Mult {
        at: (usize, usize),
    },
    Exponent {
        at: (usize, usize),
    },
    Modulo {
        at: (usize, usize),
    },

    Equals {
        at: (usize, usize),
    },
    NotEquals {
        at: (usize, usize),
    },
    LessThan {
        at: (usize, usize),
    },
    GreaterThan {
        at: (usize, usize),
    },

    StoreName {
        name: String,
        mutable: bool,
    },

    Assign {
        name: String,
        at: (usize, usize),
    },

    LoadName {
        name: String,
        at: (usize, usize),
    },

    Call {
        function_name: String,
        arguments_count: usize,
        at: (usize, usize),
    },

    LoadConstant {
        index: usize,
    },

    Return,
}
