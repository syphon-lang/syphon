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

            StmtKind::Conditional(conditional) => self.compile_conditional(conditional),

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

        let index = self.chunk.add_constant(Value::None);

        self.chunk
            .write_instruction(Instruction::LoadConstant { index });
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

                compiler.get_chunk()
            },
        });

        self.chunk
            .write_instruction(Instruction::LoadConstant { index });

        self.chunk.write_instruction(Instruction::StoreName {
            name: function.name,
            mutable: false,
        });

        let index = self.chunk.add_constant(Value::None);

        self.chunk
            .write_instruction(Instruction::LoadConstant { index });

        Ok(())
    }

    fn compile_conditional(&mut self, conditional: Conditional) -> Result<(), SyphonError> {
        let mut backtrack_points = Vec::new();

        for i in 0..conditional.conditions.len() {
            self.compile_expr(conditional.conditions[i].clone());

            self.chunk.write_instruction(Instruction::JumpIfFalse {
                offset: 0,
                location: conditional.location,
            });

            backtrack_points.push(self.chunk.code.len() - 1);

            self.compile_nodes(conditional.bodies[i].clone())?;

            self.chunk
                .write_instruction(Instruction::Jump { offset: 0 });

            backtrack_points.push(self.chunk.code.len() - 1);
        }

        {
            let mut backtrack_points_iter = backtrack_points.iter();

            while backtrack_points_iter.len() > 0 {
                let first_point = backtrack_points_iter.next().unwrap();

                backtrack_points_iter.next();

                let next_first_point = if backtrack_points_iter.len() > 0 {
                    *backtrack_points_iter.clone().next().unwrap()
                } else {
                    self.chunk.code.len() + 1
                };

                self.chunk.code[*first_point] = Instruction::JumpIfFalse {
                    offset: next_first_point - first_point - 1,
                    location: conditional.location,
                };
            }
        }

        match conditional.fallback {
            Some(fallback) => {
                self.compile_nodes(fallback)?;

                let index = self.chunk.add_constant(Value::None);

                self.chunk
                    .write_instruction(Instruction::LoadConstant { index });
            }

            None => (),
        }

        {
            let mut backtrack_points_iter = backtrack_points.iter();

            while backtrack_points_iter.len() > 0 {
                backtrack_points_iter.next();

                let second_point = backtrack_points_iter.next().unwrap();

                self.chunk.code[*second_point] = Instruction::Jump {
                    offset: self.chunk.code.len() - second_point - 1,
                };
            }
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
