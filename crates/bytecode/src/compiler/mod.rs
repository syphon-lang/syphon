mod expr;
mod stmt;

use crate::chunk::Chunk;
use crate::instruction::Instruction;

use syphon_ast::*;
use syphon_errors::SyphonError;
use syphon_gc::GarbageCollector;

use thin_vec::ThinVec;

#[derive(Default)]
pub struct CompilerContext {
    looping: bool,
    break_points: Vec<usize>,
    continue_points: Vec<usize>,
}

#[derive(PartialEq)]
pub enum CompilerMode {
    REPL,
    Script,
    Function,
}

pub struct Compiler<'a> {
    chunk: Chunk,

    gc: &'a mut GarbageCollector,

    context: CompilerContext,
    mode: CompilerMode,
}

impl<'a> Compiler<'a> {
    pub fn new(mode: CompilerMode, gc: &mut GarbageCollector) -> Compiler {
        Compiler {
            chunk: Chunk::new(),

            gc,

            context: CompilerContext::default(),
            mode,
        }
    }

    pub fn compile(&mut self, module: Node) -> Result<(), SyphonError> {
        self.compile_node(module)?;

        if self.mode == CompilerMode::REPL {
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

                if self.mode != CompilerMode::REPL {
                    self.chunk.write_instruction(Instruction::Pop);
                }

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
