use syphon_bytecode::chunk::*;
use syphon_bytecode::values::Value;

use syphon_errors::SyphonError;

use thin_vec::ThinVec;

pub struct VirtualMachine {
    chunk: Chunk,
    stack: ThinVec<Value>,
}

impl VirtualMachine {
    pub fn new(chunk: Chunk) -> VirtualMachine {
        VirtualMachine {
            chunk,
            stack: ThinVec::new(),
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        for instruction in self.chunk.code.iter() {
            match instruction {
                Instruction::LoadConstant { index } => self.stack.push(self.chunk.get_constant(*index).unwrap().clone()),

                Instruction::Return => match self.stack.pop() {
                    Some(value) => return Ok(value),
                    None => return Ok(Value::None),
                },
            }
        }

        Ok(Value::None)
    }
}
