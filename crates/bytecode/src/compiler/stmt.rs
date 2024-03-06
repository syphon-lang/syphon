use crate::compiler::{Compiler, CompilerMode};
use crate::instructions::Instruction;
use crate::value::Value;

use syphon_ast::*;
use syphon_errors::SyphonError;

impl Compiler {
    pub(crate) fn compile_stmt(&mut self, kind: StmtKind) -> Result<(), SyphonError> {
        match kind {
            StmtKind::VariableDeclaration(var) => {
                self.compile_variable_declaration(var);
                Ok(())
            }
            StmtKind::FunctionDeclaration(function) => self.compile_function_definition(function),
            StmtKind::Return(return_stmt) => self.compile_return(return_stmt),
        }
    }

    fn compile_variable_declaration(&mut self, var: Variable) {
        match var.value {
            Some(value) => self.compile_expr(value),
            None => {
                let index = self.chunk.add_constant(Value::None);

                self.chunk
                    .write_instruction(Instruction::LoadConstant { index });
            }
        };

        self.chunk.write_instruction(Instruction::StoreName {
            name: var.name,
            mutable: var.mutable,
        });

        if self.mode == CompilerMode::Script {
            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .write_instruction(Instruction::LoadConstant { index });
        }
    }

    fn compile_function_definition(&mut self, function: Function) -> Result<(), SyphonError> {
        let index = self.chunk.add_constant(Value::Function {
            name: function.name.clone(),
            parameters: function.parameters.iter().map(|f| f.name.clone()).collect(),
            body: {
                let mut compiler = Compiler::new(CompilerMode::Function);

                for node in function.body {
                    compiler.compile(node)?;
                }

                compiler.to_chunk()
            },
        });

        self.chunk
            .write_instruction(Instruction::LoadConstant { index });

        self.chunk.write_instruction(Instruction::StoreName {
            name: function.name,
            mutable: false,
        });

        if self.mode == CompilerMode::Script {
            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .write_instruction(Instruction::LoadConstant { index });
        }

        Ok(())
    }

    fn compile_return(&mut self, return_stmt: Return) -> Result<(), SyphonError> {
        if self.mode != CompilerMode::Function {
            return Err(SyphonError::unable_to(
                return_stmt.location,
                "return outside a function",
            ));
        }

        match return_stmt.value {
            Some(value) => self.compile_expr(value),
            None => {
                let index = self.chunk.add_constant(Value::None);

                self.chunk
                    .write_instruction(Instruction::LoadConstant { index });
            }
        };

        self.chunk.write_instruction(Instruction::Return);

        Ok(())
    }
}
