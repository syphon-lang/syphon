use crate::assembler::*;
use crate::values::Value;

impl Assembler {
    pub(crate) fn assemble_stmt(&mut self, kind: StmtKind) {
        match kind {
            StmtKind::VariableDeclaration(var) => self.assemble_variable(var),
            _ => todo!(),
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

        self.chunk
            .write_instruction(Instruction::StoreAs { name: var.name });
    }
}
