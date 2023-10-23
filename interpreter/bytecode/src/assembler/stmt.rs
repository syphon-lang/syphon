use crate::assembler::*;
use crate::values::Value;

impl Assembler {
    pub(crate) fn assemble_stmt(&mut self, kind: StmtKind) {
        match kind {
            StmtKind::VariableDeclaration(var) => self.assemble_variable(var),
            StmtKind::FunctionDefinition(function) => self.assemble_function(function),
            StmtKind::Return(_) => todo!(),
            StmtKind::Unknown => (),
        }
    }

    fn assemble_variable(&mut self, var: Variable) {
        match var.value {
            Some(value) => self.assemble_expr(value),
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

    fn assemble_function(&mut self, function: Function) {
        let index = self.chunk.add_constant(Value::Function {
            name: function.name.clone(),
            parameters: function.parameters.iter().map(|f| f.name.clone()).collect(),
            body: {
                let mut assembler = Assembler::new();

                for node in function.body {
                    assembler.assemble(node);
                }

                assembler.to_chunk()
            },
        });

        self.chunk
            .write_instruction(Instruction::LoadConstant { index });

        self.chunk.write_instruction(Instruction::StoreName {
            name: function.name,
            mutable: false,
        });
    }
}
