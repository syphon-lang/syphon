mod expr;
mod stmt;

use crate::chunk::Chunk;
use crate::instruction::Instruction;

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
}

impl Compiler {
    pub fn new(mode: CompilerMode) -> Compiler {
        Compiler {
            chunk: Chunk::new(),

            mode,
        }
    }

    pub fn compile(&mut self, module: Node) -> Result<(), SyphonError> {
        self.compile_node(module)?;

        if self.mode == CompilerMode::Script {
            self.chunk.write_instruction(Instruction::Return);
        }

        Ok(())
    }

    fn compile_node(&mut self, node: Node) -> Result<(), SyphonError> {
        match node {
            Node::Module { body } => self.compile_nodes(body),
            Node::Stmt(kind) => self.compile_stmt(*kind),
            Node::Expr(kind) => {
                self.compile_expr(*kind);
                Ok(())
            }
        }
    }

    fn compile_nodes(&mut self, nodes: ThinVec<Node>) -> Result<(), SyphonError> {
        for node in nodes {
            self.compile_node(node)?;
        }

        Ok(())
    }

    pub fn get_chunk(self) -> Chunk {
        self.chunk
    }
}
