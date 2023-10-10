#[repr(u8)]
pub enum Instruction {
    UnaryOperation {
        operator: char,
        at: (usize, usize),
    },
    BinaryOperation {
        operator: String,
        at: (usize, usize),
    },

    LoadConstant {
        index: usize,
    },
    Return,
}
