mod expr;
mod stmt;

use crate::chunk::*;
use crate::instructions::Instruction;

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

    pub fn assemble(&mut self, module: Node) {
        self.assemble_node(module);

        self.chunk.write_instruction(Instruction::Return);
    }

    fn assemble_node(&mut self, node: Node) {
        match node {
            Node::Module { body } => self.assemble_nodes(body),
            Node::Stmt(kind) => self.assemble_stmt(*kind),
            Node::Expr(kind) => self.assemble_expr(*kind),
        }
    }

    fn assemble_nodes(&mut self, nodes: ThinVec<Node>) {
        for node in nodes {
            self.assemble_node(node)
        }
    }

    pub fn to_chunk(self) -> Chunk {
        self.chunk
    }
}
