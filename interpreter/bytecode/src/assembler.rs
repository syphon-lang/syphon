use crate::chunk::*;

use syphon_ast::*;
use syphon_errors::SyphonError;

use thin_vec::ThinVec;

pub struct Assembler {
    chunk: Chunk,

    pub errors: ThinVec<SyphonError>,
}

impl Assembler {
    pub fn new() -> Assembler {
        Assembler {
            chunk: Chunk::new(),

            errors: ThinVec::new(),
        }
    }

    pub fn assemble(&mut self, node: Node) {
        match node {
            _ => todo!(),
        }
    }

    pub fn to_chunk(self) -> Chunk {
        self.chunk
    }
}
