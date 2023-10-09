use syphon_bytecode::chunk::*;

pub struct VirtualMachine {
    chunk: Chunk,
}

impl VirtualMachine {
    pub fn new(chunk: Chunk) -> VirtualMachine {
        VirtualMachine { chunk }
    }
}
