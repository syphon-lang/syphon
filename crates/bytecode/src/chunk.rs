use crate::instruction::Instruction;
use crate::value::{Function, Value};

use syphon_location::Location;

use derive_more::Display;

use once_cell::sync::Lazy;

use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display)]
pub struct Atom(usize);

static ATOMS: Lazy<Mutex<HashMap<String, Atom>>> = Lazy::new(|| Mutex::new(HashMap::new()));

impl Atom {
    pub fn new(name: String) -> Atom {
        let mut atoms_lock = ATOMS.lock().unwrap();

        if let Some(atom) = atoms_lock.get(&name) {
            return *atom;
        }

        let atom = Atom(atoms_lock.len());

        atoms_lock.insert(name.to_owned(), atom);

        atom
    }

    pub fn get(name: &str) -> Atom {
        let atoms_lock = ATOMS.lock().unwrap();

        unsafe { *atoms_lock.get(name).unwrap_unchecked() }
    }

    pub fn get_name(&self) -> String {
        let atoms_lock = ATOMS.lock().unwrap();

        unsafe {
            atoms_lock
                .iter()
                .find_map(|(k, v)| if v == self { Some(k) } else { None })
                .unwrap_unchecked()
                .to_owned()
        }
    }

    pub fn from_be_bytes(bytes: [u8; std::mem::size_of::<usize>()]) -> Atom {
        Atom(usize::from_be_bytes(bytes))
    }

    pub fn to_be_bytes(&self) -> [u8; std::mem::size_of::<usize>()] {
        self.0.to_be_bytes()
    }
}

#[derive(Clone, PartialEq)]
pub struct Chunk {
    pub code: Vec<Instruction>,
    pub constants: Vec<Value>,
}

impl Chunk {
    pub fn new() -> Chunk {
        Chunk {
            code: Vec::new(),
            constants: Vec::new(),
        }
    }

    pub fn write_instruction(&mut self, instruction: Instruction) {
        self.code.push(instruction);
    }

    pub fn add_constant(&mut self, value: Value) -> usize {
        self.constants.iter().position(|c| c == &value).unwrap_or({
            self.constants.push(value);
            self.constants.len() - 1
        })
    }

    pub fn get_constant(&self, index: usize) -> &Value {
        &self.constants[index]
    }

    pub fn extend(&mut self, other: Chunk) {
        self.constants.extend(other.constants);
        self.code.extend(other.code);
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        bytes.extend(self.constants.len().to_be_bytes());
        for constant in self.constants.iter() {
            bytes.extend(constant.to_bytes());
        }

        let atoms_lock = ATOMS.lock().unwrap();

        bytes.extend(atoms_lock.len().to_be_bytes());
        atoms_lock.iter().for_each(|(name, atom)| {
            bytes.extend(name.len().to_be_bytes());
            bytes.extend(name.as_bytes());

            bytes.extend(atom.to_be_bytes());
        });

        bytes.extend(self.code.len().to_be_bytes());
        self.code.iter().for_each(|instruction| {
            bytes.extend(instruction.to_bytes());
        });

        bytes
    }

    pub fn parse(bytes: &mut impl Iterator<Item = u8>) -> Option<Chunk> {
        let mut chunk = Chunk::new();

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

        fn get_multiple(bytes: &mut impl Iterator<Item = u8>, len: usize) -> Vec<u8> {
            let mut data = Vec::with_capacity(len);

            for _ in 0..len {
                data.push(bytes.next().unwrap());
            }

            data
        }

        let constants_len = usize::from_be_bytes(get_8_bytes(bytes));

        for _ in 0..constants_len {
            let constant_tag = bytes.next().unwrap();

            match constant_tag {
                0 => {
                    chunk.add_constant(Value::None);
                }

                1 => {
                    let string_len = usize::from_be_bytes(get_8_bytes(bytes));

                    let string = String::from_utf8(get_multiple(bytes, string_len)).unwrap();

                    chunk.add_constant(Value::String(string.into()));
                }

                2 => {
                    chunk.add_constant(Value::Int(i64::from_be_bytes(get_8_bytes(bytes))));
                }

                3 => {
                    chunk.add_constant(Value::Float(f64::from_be_bytes(get_8_bytes(bytes))));
                }

                4 => {
                    chunk.add_constant(Value::Bool(true));
                }

                5 => {
                    chunk.add_constant(Value::Bool(false));
                }

                6 => {
                    let name_len = usize::from_be_bytes(get_8_bytes(bytes));

                    let name = String::from_utf8(get_multiple(bytes, name_len)).unwrap();

                    let parameters_len = usize::from_be_bytes(get_8_bytes(bytes));

                    let mut parameters = Vec::with_capacity(parameters_len);

                    for _ in 0..parameters_len {
                        let parameter_len = usize::from_be_bytes(get_8_bytes(bytes));

                        let parameter =
                            String::from_utf8(get_multiple(bytes, parameter_len)).unwrap();

                        parameters.push(parameter);
                    }

                    let body = Chunk::parse(bytes)?;

                    chunk.add_constant(Value::Function(
                        Function {
                            name,
                            parameters,
                            body,
                        }
                        .into(),
                    ));
                }

                _ => {
                    eprintln!("invalid syc file: invalid constant tag: {}", constant_tag);

                    return None;
                }
            };
        }

        let mut atoms_lock = ATOMS.lock().unwrap();

        let atoms_len = usize::from_be_bytes(get_8_bytes(bytes));

        for _ in 0..atoms_len {
            let name_len = usize::from_be_bytes(get_8_bytes(bytes));

            let name = String::from_utf8(get_multiple(bytes, name_len)).unwrap();

            let atom = Atom::from_be_bytes(get_8_bytes(bytes));

            atoms_lock.insert(name, atom);
        }

        let code_len = usize::from_be_bytes(get_8_bytes(bytes));

        for _ in 0..code_len {
            let code_tag = bytes.next().unwrap();

            match code_tag {
                0 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Neg { location });
                }

                1 => {
                    chunk.write_instruction(Instruction::LogicalNot);
                }

                2 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Add { location });
                }

                3 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Sub { location });
                }

                4 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Div { location });
                }

                5 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Mult { location });
                }

                6 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Exponent { location });
                }

                7 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Modulo { location });
                }

                8 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Equals { location });
                }

                9 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::NotEquals { location });
                }

                10 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::LessThan { location });
                }

                11 => {
                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::GreaterThan { location });
                }

                12 => {
                    let atom = Atom::from_be_bytes(get_8_bytes(bytes));

                    let mutable = bytes.next().unwrap() == 1;

                    chunk.write_instruction(Instruction::StoreName { atom, mutable });
                }

                13 => {
                    let atom = Atom::from_be_bytes(get_8_bytes(bytes));

                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Assign { atom, location });
                }

                14 => {
                    let atom = Atom::from_be_bytes(get_8_bytes(bytes));

                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::LoadName { atom, location });
                }

                15 => {
                    let arguments_count = usize::from_be_bytes(get_8_bytes(bytes));

                    let location = Location::from_bytes(bytes);

                    chunk.write_instruction(Instruction::Call {
                        arguments_count,
                        location,
                    });
                }

                16 => {
                    let index = usize::from_be_bytes(get_8_bytes(bytes));

                    chunk.write_instruction(Instruction::LoadConstant { index });
                }

                17 => {
                    chunk.write_instruction(Instruction::Return);
                }

                18 => {
                    let offset = usize::from_be_bytes(get_8_bytes(bytes));

                    chunk.write_instruction(Instruction::JumpIfFalse { offset });
                }

                19 => {
                    let offset = usize::from_be_bytes(get_8_bytes(bytes));

                    chunk.write_instruction(Instruction::Jump { offset });
                }

                20 => {
                    let offset = usize::from_be_bytes(get_8_bytes(bytes));

                    chunk.write_instruction(Instruction::Back { offset });
                }

                _ => {
                    eprintln!("invalid syc file: invalid code tag: {}", code_tag);

                    return None;
                }
            }
        }

        Some(chunk)
    }
}
