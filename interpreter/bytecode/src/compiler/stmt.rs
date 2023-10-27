use crate::compiler::*;
use crate::values::Value;

impl Compiler {
    pub(crate) fn compile_stmt(&mut self, kind: StmtKind) {
        match kind {
            StmtKind::VariableDeclaration(var) => self.declare_variable(var),
            StmtKind::FunctionDefinition(function) => self.compile_function(function),
            StmtKind::Return(return_stmt) => self.compiler_return(return_stmt),
            StmtKind::Unknown => (),
        }
    }

    fn declare_variable(&mut self, var: Variable) {
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
    }

    fn compile_function(&mut self, function: Function) {
        let index = self.chunk.add_constant(Value::Function {
            name: function.name.clone(),
            parameters: function.parameters.iter().map(|f| f.name.clone()).collect(),
            body: {
                let mut compiler = Compiler::new(CompilerMode::Function);

                for node in function.body {
                    compiler.compile(node);
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
    }

    fn compiler_return(&mut self, return_stmt: Return) {
        if self.mode != CompilerMode::Function {
            self.errors.push(SyphonError::unable_to(
                return_stmt.at,
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

        self.chunk.write_instruction(Instruction::Return)
    }
}
