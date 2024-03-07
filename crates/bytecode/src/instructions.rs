use syphon_location::Location;

#[derive(Clone, PartialEq)]
#[repr(u8)]
pub enum Instruction {
    Neg {
        location: Location,
    },
    LogicalNot {
        location: Location,
    },

    Add {
        location: Location,
    },
    Sub {
        location: Location,
    },
    Div {
        location: Location,
    },
    Mult {
        location: Location,
    },
    Exponent {
        location: Location,
    },
    Modulo {
        location: Location,
    },

    Equals {
        location: Location,
    },
    NotEquals {
        location: Location,
    },
    LessThan {
        location: Location,
    },
    GreaterThan {
        location: Location,
    },

    StoreName {
        name: String,
        mutable: bool,
    },

    Assign {
        name: String,
        location: Location,
    },

    LoadName {
        name: String,
        location: Location,
    },

    Call {
        arguments_count: usize,
        location: Location,
    },

    LoadConstant {
        index: usize,
    },

    Return,

    JumpIfFalse {
        offset: usize,
        location: Location,
    },

    Jump {
        offset: usize,
    },
}

impl Instruction {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        match self {
            Instruction::Neg { location } => {
                bytes.push(0);
                bytes.extend(location.to_bytes());
            }

            Instruction::LogicalNot { location } => {
                bytes.push(1);
                bytes.extend(location.to_bytes());
            }

            Instruction::Add { location } => {
                bytes.push(2);
                bytes.extend(location.to_bytes());
            }

            Instruction::Sub { location } => {
                bytes.push(3);
                bytes.extend(location.to_bytes());
            }

            Instruction::Div { location } => {
                bytes.push(4);
                bytes.extend(location.to_bytes());
            }

            Instruction::Mult { location } => {
                bytes.push(5);
                bytes.extend(location.to_bytes());
            }

            Instruction::Exponent { location } => {
                bytes.push(6);
                bytes.extend(location.to_bytes());
            }

            Instruction::Modulo { location } => {
                bytes.push(7);
                bytes.extend(location.to_bytes());
            }

            Instruction::Equals { location } => {
                bytes.push(8);
                bytes.extend(location.to_bytes());
            }

            Instruction::NotEquals { location } => {
                bytes.push(9);
                bytes.extend(location.to_bytes());
            }

            Instruction::LessThan { location } => {
                bytes.push(10);
                bytes.extend(location.to_bytes());
            }

            Instruction::GreaterThan { location } => {
                bytes.push(11);
                bytes.extend(location.to_bytes());
            }

            Instruction::StoreName { name, mutable } => {
                bytes.push(12);

                bytes.extend(name.len().to_be_bytes());
                bytes.extend(name.as_bytes());

                if *mutable {
                    bytes.push(1);
                } else {
                    bytes.push(0);
                }
            }

            Instruction::Assign { name, location } => {
                bytes.push(13);

                bytes.extend(name.len().to_be_bytes());
                bytes.extend(name.as_bytes());

                bytes.extend(location.to_bytes());
            }

            Instruction::LoadName { name, location } => {
                bytes.push(14);

                bytes.extend(name.len().to_be_bytes());
                bytes.extend(name.as_bytes());

                bytes.extend(location.to_bytes());
            }

            Instruction::Call {
                arguments_count,
                location,
            } => {
                bytes.push(15);

                bytes.extend(arguments_count.to_be_bytes());

                bytes.extend(location.to_bytes());
            }

            Instruction::LoadConstant { index } => {
                bytes.push(16);

                bytes.extend(index.to_be_bytes());
            }

            Instruction::Return => {
                bytes.push(17);
            }

            Instruction::JumpIfFalse { offset, location } => {
                bytes.push(18);

                bytes.extend(offset.to_be_bytes());

                bytes.extend(location.to_bytes());
            }

            Instruction::Jump { offset } => {
                bytes.push(19);

                bytes.extend(offset.to_be_bytes());
            }
        }

        bytes
    }
}
