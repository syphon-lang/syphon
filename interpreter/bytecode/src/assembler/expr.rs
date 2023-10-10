use crate::assembler::*;
use crate::instructions::Instruction;
use crate::values::Value;

impl Assembler {
    pub(crate) fn assemble_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { .. } => todo!(),
            ExprKind::Str { value, .. } => self.assemble_string(value),
            ExprKind::Int { value, .. } => self.assemble_integer(value),
            ExprKind::Float { value, .. } => self.assemble_float(value),
            ExprKind::Bool { value, .. } => self.assemble_boolean(value),
            ExprKind::UnaryOperation { operator, right, at } => self.assemble_unary_operation(operator, *right, at),
            ExprKind::BinaryOperation { left, operator, right, at } => self.assemble_binary_operation(*left, operator, *right, at),
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

    fn assemble_unary_operation(&mut self, operator: char, right: ExprKind, at: (usize, usize)) {
        self.assemble_expr(right);

        self.chunk.write_instruction(Instruction::UnaryOperation { operator, at });
    }

    fn assemble_binary_operation(&mut self, left: ExprKind, operator: String, right: ExprKind, at: (usize, usize)) {
        self.assemble_expr(right);
        self.assemble_expr(left);

        self.chunk.write_instruction(Instruction::BinaryOperation { operator, at });
    }
}
