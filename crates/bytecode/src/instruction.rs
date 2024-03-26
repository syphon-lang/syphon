use crate::chunk::Atom;

#[derive(Clone, Copy, PartialEq)]
pub enum Instruction {
    Neg,
    LogicalNot,

    Add,
    Sub,
    Div,
    Mult,
    Exponent,
    Modulo,

    Equals,
    NotEquals,
    LessThan,
    GreaterThan,

    StoreName { atom: Atom },
    LoadName { atom: Atom },

    Call { arguments_count: usize },

    LoadConstant { index: usize },

    Return,

    JumpIfFalse { offset: usize },
    Jump { offset: usize },
    Back { offset: usize },

    Pop,

    MakeArray { length: usize },
    LoadSubscript,
    StoreSubscript,
}

impl Instruction {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        match *self {
            Instruction::Neg => bytes.push(0),
            Instruction::LogicalNot => bytes.push(1),

            Instruction::Add => bytes.push(2),
            Instruction::Sub => bytes.push(3),
            Instruction::Div => bytes.push(4),
            Instruction::Mult => bytes.push(5),
            Instruction::Exponent => bytes.push(6),
            Instruction::Modulo => bytes.push(7),

            Instruction::Equals => bytes.push(8),
            Instruction::NotEquals => bytes.push(9),
            Instruction::LessThan => bytes.push(10),
            Instruction::GreaterThan => bytes.push(11),

            Instruction::StoreName { atom } => {
                bytes.push(12);

                bytes.extend(atom.to_be_bytes());
            }

            Instruction::LoadName { atom } => {
                bytes.push(13);

                bytes.extend(atom.to_be_bytes());
            }

            Instruction::Call { arguments_count } => {
                bytes.push(14);

                bytes.extend(arguments_count.to_be_bytes());
            }

            Instruction::LoadConstant { index } => {
                bytes.push(15);

                bytes.extend(index.to_be_bytes());
            }

            Instruction::Return => bytes.push(16),

            Instruction::JumpIfFalse { offset } => {
                bytes.push(17);

                bytes.extend(offset.to_be_bytes());
            }

            Instruction::Jump { offset } => {
                bytes.push(18);

                bytes.extend(offset.to_be_bytes());
            }

            Instruction::Back { offset } => {
                bytes.push(19);

                bytes.extend(offset.to_be_bytes());
            }

            Instruction::Pop => bytes.push(20),

            Instruction::MakeArray { length } => {
                bytes.push(21);

                bytes.extend(length.to_be_bytes());
            }

            Instruction::LoadSubscript => bytes.push(22),
            Instruction::StoreSubscript => bytes.push(23),
        }

        bytes
    }

    pub fn from_bytes(bytes: &mut impl Iterator<Item = u8>, tag: u8) -> Instruction {
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

        match tag {
            0 => Instruction::Neg,
            1 => Instruction::LogicalNot,

            2 => Instruction::Add,
            3 => Instruction::Sub,
            4 => Instruction::Div,
            5 => Instruction::Mult,
            6 => Instruction::Exponent,
            7 => Instruction::Modulo,

            8 => Instruction::Equals,
            9 => Instruction::NotEquals,
            10 => Instruction::LessThan,
            11 => Instruction::GreaterThan,

            12 => {
                let atom = Atom::from_be_bytes(get_8_bytes(bytes));

                Instruction::StoreName { atom }
            }

            13 => {
                let atom = Atom::from_be_bytes(get_8_bytes(bytes));

                Instruction::LoadName { atom }
            }

            14 => {
                let arguments_count = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::Call { arguments_count }
            }

            15 => {
                let index = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::LoadConstant { index }
            }

            16 => Instruction::Return,

            17 => {
                let offset = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::JumpIfFalse { offset }
            }

            18 => {
                let offset = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::Jump { offset }
            }

            19 => {
                let offset = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::Back { offset }
            }

            20 => Instruction::Pop,

            21 => {
                let length = usize::from_be_bytes(get_8_bytes(bytes));

                Instruction::MakeArray { length }
            }

            22 => Instruction::LoadSubscript,
            23 => Instruction::StoreSubscript,

            _ => unreachable!(),
        }
    }
}
