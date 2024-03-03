use crate::instructions::Instruction;
use crate::values::Value;

use thin_vec::ThinVec;

#[derive(Clone, PartialEq)]
pub struct Chunk {
    pub code: ThinVec<Instruction>,
    pub constants: ThinVec<Value>,
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
        self.constants.iter().position(|c| c == &value).unwrap_or({
            self.constants.push(value);
            self.constants.len() - 1
        })
    }

    pub fn get_constant(&self, index: usize) -> Option<&Value> {
        self.constants.get(index)
    }

    pub fn extend(&mut self, other: Chunk) {
        self.constants.extend(other.constants);
        self.code.extend(other.code);
    }
}
