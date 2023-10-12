#[derive(Clone)]
#[repr(u8)]
pub enum Instruction {
    Neg { at: (usize, usize) },
    LogicalNot { at: (usize, usize) },

    Add { at: (usize, usize) },
    Sub { at: (usize, usize) },
    Div { at: (usize, usize) },
    Mult { at: (usize, usize) },
    Exponent { at: (usize, usize) },
    Modulo { at: (usize, usize) },

    Equals { at: (usize, usize) },
    NotEquals { at: (usize, usize) },
    LessThan { at: (usize, usize) },
    GreaterThan { at: (usize, usize) },

    StoreAs { name: String },

    LoadVariable { name: String, at: (usize, usize) },

    LoadConstant { index: usize },

    Return,
}
