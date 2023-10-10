use crate::values::Value;

use thin_vec::ThinVec;

pub struct Chunk {
    pub code: ThinVec<Instruction>,
    constants: ThinVec<Value>,
}

#[repr(u8)]
pub enum Instruction {
    LoadConstant { index: usize, at: (usize, usize) },
    Return,
}

impl Chunk {
    pub fn new() -> Chunk {
        Chunk {
            code: ThinVec::new(),
            constants: ThinVec::new(),
        }
    }

    pub fn write_instruction(&mut self, instruction: Instruction) {
        self.code.push(instruction);
    }

    pub fn add_constant(&mut self, value: Value) -> usize {
        self.constants.push(value);
        self.constants.len() - 1
    }

    pub fn get_constant(&self, index: usize) -> Option<&Value> {
        self.constants.get(index)
    }
}
