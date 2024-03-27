use crate::chunk::Atom;
use crate::compiler::{Compiler, CompilerMode};
use crate::instruction::Instruction;
use crate::value::{Function as BytecodeFunction, Value};

use syphon_ast::*;
use syphon_errors::SyphonError;

impl<'a> Compiler<'a> {
    pub(crate) fn compile_stmt(&mut self, kind: StmtKind) -> Result<(), SyphonError> {
        match kind {
            StmtKind::VariableDeclaration(var) => {
                self.compile_variable_declaration(var);
                Ok(())
            }

            StmtKind::FunctionDeclaration(function) => self.compile_function_declaration(function),

            StmtKind::Conditional(conditional) => self.compile_conditional(conditional),

            StmtKind::While(while_stmt) => self.compile_while(while_stmt),

            StmtKind::Break(break_stmt) => self.compile_break(break_stmt),

            StmtKind::Continue(continue_stmt) => self.compile_continue(continue_stmt),

            StmtKind::Return(return_stmt) => self.compile_return(return_stmt),
        }
    }

    fn compile_variable_declaration(&mut self, var: Variable) {
        match var.value {
            Some(value) => self.compile_expr(value),
            None => {
                self.chunk.locations.push(var.location);

                let index = self.chunk.add_constant(Value::None);

                self.chunk
                    .instructions
                    .push(Instruction::LoadConstant { index });
            }
        };

        self.chunk.locations.push(var.location);

        self.chunk.instructions.push(Instruction::StoreName {
            atom: Atom::new(var.name),
        });

        if self.mode == CompilerMode::REPL {
            self.chunk.locations.push(var.location);

            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .instructions
                .push(Instruction::LoadConstant { index });
        }
    }

    fn compile_function_declaration(&mut self, function: Function) -> Result<(), SyphonError> {
        let bytecode_function = BytecodeFunction {
            name: Atom::new(function.name.clone()),
            parameters: function.parameters.iter().map(|f| f.name.clone()).collect(),
            body: {
                let mut compiler = Compiler::new(CompilerMode::Function, self.gc);

                compiler.compile_nodes(function.body)?;

                compiler.end_module();

                compiler.get_chunk()
            },
        };

        self.chunk.locations.push(function.location);

        let index = self
            .chunk
            .add_constant(Value::Function(self.gc.alloc(bytecode_function)));

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index });

        self.chunk.locations.push(function.location);

        self.chunk.instructions.push(Instruction::StoreName {
            atom: Atom::new(function.name),
        });

        if self.mode == CompilerMode::REPL {
            self.chunk.locations.push(function.location);

            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .instructions
                .push(Instruction::LoadConstant { index });
        }

        Ok(())
    }

    fn compile_conditional(&mut self, conditional: Conditional) -> Result<(), SyphonError> {
        struct BacktrackPoint {
            before_condition_point: usize,
            jump_if_false_point: usize,
            jump_point: usize,
        }

        let mut backtrack_points = Vec::new();

        let was_compiling_conditinal = self.context.compiling_conditional;

        self.context.compiling_conditional = true;

        for i in 0..conditional.conditions.len() {
            let before_condition_point = self.chunk.instructions.len() - 1;

            self.compile_expr(conditional.conditions[i].clone());

            self.chunk.locations.push(conditional.location);

            let jump_if_false_point = self.chunk.instructions.len();

            self.chunk
                .instructions
                .push(Instruction::JumpIfFalse { offset: 0 });

            self.compile_nodes(conditional.bodies[i].clone())?;

            self.chunk.locations.push(conditional.location);

            let jump_point = self.chunk.instructions.len();

            self.chunk
                .instructions
                .push(Instruction::Jump { offset: 0 });

            backtrack_points.push(BacktrackPoint {
                before_condition_point,
                jump_if_false_point,
                jump_point,
            });
        }

        let before_fallback_point = self.chunk.instructions.len() - 1;

        if let Some(fallback) = conditional.fallback {
            self.compile_nodes(fallback)?;
        }

        let after_fallback_point = self.chunk.instructions.len() - 1;

        if self.mode == CompilerMode::REPL {
            self.chunk.locations.push(conditional.location);

            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .instructions
                .push(Instruction::LoadConstant { index });
        }

        self.context.compiling_conditional = was_compiling_conditinal;

        let mut backtrack_points_iter = backtrack_points.iter();

        while backtrack_points_iter.len() > 0 {
            let point = backtrack_points_iter.next().unwrap();

            let default_point = BacktrackPoint {
                before_condition_point: before_fallback_point,
                jump_if_false_point: 0,
                jump_point: 0,
            };

            let next_point = backtrack_points_iter
                .clone()
                .next()
                .unwrap_or(&default_point);

            self.chunk.instructions[point.jump_if_false_point] = Instruction::JumpIfFalse {
                offset: next_point.before_condition_point - point.jump_if_false_point,
            };

            self.chunk.instructions[point.jump_point] = Instruction::Jump {
                offset: after_fallback_point - point.jump_point,
            }
        }

        Ok(())
    }

    fn compile_while(&mut self, while_stmt: While) -> Result<(), SyphonError> {
        let condition_point = self.chunk.instructions.len();

        self.compile_expr(while_stmt.condition);

        self.chunk.locations.push(while_stmt.location);

        self.chunk
            .instructions
            .push(Instruction::JumpIfFalse { offset: 0 });

        let jump_if_false_point = self.chunk.instructions.len() - 1;

        let previous_break_points_len = self.context.break_points.len();

        let previous_continue_points_len = self.context.continue_points.len();

        let was_compiling_loop = self.context.compiling_loop;

        self.context.compiling_loop = true;

        self.compile_nodes(while_stmt.body)?;

        self.chunk.instructions[jump_if_false_point] = Instruction::JumpIfFalse {
            offset: self.chunk.instructions.len() - jump_if_false_point,
        };

        self.chunk.locations.push(while_stmt.location);

        self.chunk.instructions.push(Instruction::Back {
            offset: self.chunk.instructions.len() - condition_point,
        });

        self.context
            .break_points
            .iter()
            .skip(previous_break_points_len)
            .for_each(|break_point| {
                self.chunk.instructions[*break_point] = Instruction::Jump {
                    offset: self.chunk.instructions.len() - break_point,
                }
            });

        self.context
            .continue_points
            .iter()
            .skip(previous_continue_points_len)
            .for_each(|continue_point| {
                self.chunk.instructions[*continue_point] = Instruction::Back {
                    offset: continue_point - condition_point,
                }
            });

        self.context.compiling_loop = was_compiling_loop;

        self.context
            .break_points
            .truncate(previous_break_points_len);

        self.context
            .continue_points
            .truncate(previous_continue_points_len);

        if self.mode == CompilerMode::REPL {
            self.chunk.locations.push(while_stmt.location);

            let index = self.chunk.add_constant(Value::None);

            self.chunk
                .instructions
                .push(Instruction::LoadConstant { index });
        }

        Ok(())
    }

    fn compile_break(&mut self, break_stmt: Break) -> Result<(), SyphonError> {
        if !self.context.compiling_loop {
            return Err(SyphonError::unable_to(
                break_stmt.location,
                "break outside a loop",
            ));
        }

        self.chunk.locations.push(break_stmt.location);

        self.chunk
            .instructions
            .push(Instruction::Jump { offset: 0 });

        self.context
            .break_points
            .push(self.chunk.instructions.len() - 1);

        Ok(())
    }

    fn compile_continue(&mut self, continue_stmt: Continue) -> Result<(), SyphonError> {
        if !self.context.compiling_loop {
            return Err(SyphonError::unable_to(
                continue_stmt.location,
                "continue outside a loop",
            ));
        }

        self.chunk.locations.push(continue_stmt.location);

        self.chunk
            .instructions
            .push(Instruction::Jump { offset: 0 });

        self.context
            .continue_points
            .push(self.chunk.instructions.len() - 1);

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
                self.chunk.locations.push(return_stmt.location);

                let index = self.chunk.add_constant(Value::None);

                self.chunk
                    .instructions
                    .push(Instruction::LoadConstant { index });
            }
        };

        self.chunk.locations.push(return_stmt.location);

        self.chunk.instructions.push(Instruction::Return);

        if !self.context.compiling_loop && !self.context.compiling_conditional {
            self.context.manual_return = true;
        }

        Ok(())
    }
}
