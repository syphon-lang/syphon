use crate::assembler::*;
use crate::values::Value;

impl Assembler {
    pub(crate) fn assemble_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { .. } => todo!(),
            ExprKind::Str { value, .. } => self.assemble_string(value),
            ExprKind::Int { value, .. } => self.assemble_integer(value),
            ExprKind::Float { value, .. } => self.assemble_float(value),
            ExprKind::Bool { value, .. } => self.assemble_boolean(value),
            ExprKind::UnaryOperation { .. } => todo!(),
            ExprKind::BinaryOperation { .. } => todo!(),
            ExprKind::Call { .. } => todo!(),
            ExprKind::Unknown => (),
        }
    }

    fn assemble_string(&mut self, value: String) {
        let index = self.chunk.add_constant(Value::Str(value));

        self.chunk.write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_integer(&mut self, value: i64) {
        let index = self.chunk.add_constant(Value::Int(value));

        self.chunk.write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_float(&mut self, value: f64) {
        let index = self.chunk.add_constant(Value::Float(value));

        self.chunk.write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_boolean(&mut self, value: bool) {
        let index = self.chunk.add_constant(Value::Bool(value));

        self.chunk.write_instruction(Instruction::LoadConstant { index })
    }
}
