use crate::assembler::*;
use crate::instructions::Instruction;
use crate::values::Value;

impl Assembler {
    pub(crate) fn assemble_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { symbol, at } => self.assemble_identifer(symbol, at),
            ExprKind::Str { value, .. } => self.assemble_string(value),
            ExprKind::Int { value, .. } => self.assemble_integer(value),
            ExprKind::Float { value, .. } => self.assemble_float(value),
            ExprKind::Bool { value, .. } => self.assemble_boolean(value),
            ExprKind::UnaryOperation {
                operator,
                right,
                at,
            } => self.assemble_unary_operation(operator, *right, at),
            ExprKind::BinaryOperation {
                left,
                operator,
                right,
                at,
            } => self.assemble_binary_operation(*left, operator, *right, at),

            ExprKind::Assign { name, value, at } => self.assemble_assign(name, *value, at),

            ExprKind::Call { function_name, arguments, at} => self.assemble_call(function_name, arguments, at),

            ExprKind::Unknown => (),
        }
    }

    fn assemble_identifer(&mut self, symbol: String, at: (usize, usize)) {
        self.chunk
            .write_instruction(Instruction::LoadName { name: symbol, at })
    }

    fn assemble_string(&mut self, value: String) {
        let index = self.chunk.add_constant(Value::Str(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_integer(&mut self, value: i64) {
        let index = self.chunk.add_constant(Value::Int(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_float(&mut self, value: f64) {
        let index = self.chunk.add_constant(Value::Float(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_boolean(&mut self, value: bool) {
        let index = self.chunk.add_constant(Value::Bool(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn assemble_unary_operation(&mut self, operator: char, right: ExprKind, at: (usize, usize)) {
        self.assemble_expr(right);

        match operator {
            '-' => self.chunk.write_instruction(Instruction::Neg { at }),
            '!' => self.chunk.write_instruction(Instruction::LogicalNot { at }),
            _ => unreachable!(),
        }
    }

    fn assemble_binary_operation(
        &mut self,
        left: ExprKind,
        operator: String,
        right: ExprKind,
        at: (usize, usize),
    ) {
        self.assemble_expr(left);
        self.assemble_expr(right);

        match operator.as_str() {
            "+" => self.chunk.write_instruction(Instruction::Add { at }),
            "-" => self.chunk.write_instruction(Instruction::Sub { at }),
            "/" => self.chunk.write_instruction(Instruction::Div { at }),
            "*" => self.chunk.write_instruction(Instruction::Mult { at }),
            "**" => self.chunk.write_instruction(Instruction::Exponent { at }),
            "%" => self.chunk.write_instruction(Instruction::Modulo { at }),

            "==" => self.chunk.write_instruction(Instruction::Equals { at }),
            "!=" => self.chunk.write_instruction(Instruction::NotEquals { at }),
            "<" => self.chunk.write_instruction(Instruction::LessThan { at }),
            ">" => self
                .chunk
                .write_instruction(Instruction::GreaterThan { at }),
            _ => unreachable!(),
        }
    }

    fn assemble_assign(&mut self, name: String, value: ExprKind, at: (usize, usize)) {
        self.assemble_expr(value);

        self.chunk
            .write_instruction(Instruction::Assign { name, at })
    }

    fn assemble_call(&mut self, function_name: String, arguments: ThinVec<ExprKind>, at: (usize, usize)) {
        for argument in arguments.clone() {
            self.assemble_expr(argument);
        }

        self.chunk.write_instruction(Instruction::Call { function_name, arguments_count: arguments.len(), at });
    }
}
