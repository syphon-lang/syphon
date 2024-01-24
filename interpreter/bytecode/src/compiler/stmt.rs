use crate::compiler::*;
use crate::values::Value;

impl Compiler {
    pub(crate) fn compile_stmt(&mut self, kind: StmtKind) -> Result<(), SyphonError> {
        match kind {
            StmtKind::VariableDeclaration(var) => Ok(self.compile_variable_declaration(var)),
            StmtKind::FunctionDefinition(function) => self.compile_function_definition(function),
            StmtKind::Return(return_stmt) => self.compile_return(return_stmt),
            StmtKind::Unknown => Ok(()),
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
        
        Ok(())
    }

    fn compile_return(&mut self, return_stmt: Return) -> Result<(), SyphonError> {
        if self.mode != CompilerMode::Function {
            return Err(SyphonError::unable_to(
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

        self.chunk.write_instruction(Instruction::Return);

        Ok(())
    }
}
