mod expr;
mod stmt;

use crate::chunk::*;
use crate::instructions::Instruction;

use syphon_ast::*;
use syphon_errors::SyphonError;

use thin_vec::ThinVec;

#[derive(PartialEq)]
pub enum CompilerMode {
    Script,
    Function,
}

pub struct Compiler {
    chunk: Chunk,

    mode: CompilerMode,

    pub errors: ThinVec<SyphonError>,
}

impl Compiler {
    pub fn new(mode: CompilerMode) -> Compiler {
        Compiler {
            chunk: Chunk::new(),

            mode,

            errors: ThinVec::new(),
        }
    }

    pub fn compile(&mut self, module: Node) {
        self.compile_node(module);

        if self.mode == CompilerMode::Script {
            self.chunk.write_instruction(Instruction::Return);
        }
    }

    fn compile_node(&mut self, node: Node) {
        match node {
            Node::Module { body } => self.compile_nodes(body),
            Node::Stmt(kind) => self.compile_stmt(*kind),
            Node::Expr(kind) => self.compile_expr(*kind),
        }
    }

    fn compile_nodes(&mut self, nodes: ThinVec<Node>) {
        for node in nodes {
            self.compile_node(node)
        }
    }

    pub fn to_chunk(self) -> Chunk {
        self.chunk
    }
}
