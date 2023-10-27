use crate::compiler::*;
use crate::instructions::Instruction;
use crate::values::Value;

impl Compiler {
    pub(crate) fn compile_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { symbol, at } => self.compile_identifer(symbol, at),
            ExprKind::Str { value, .. } => self.compile_string(value),
            ExprKind::Int { value, .. } => self.compile_integer(value),
            ExprKind::Float { value, .. } => self.compile_float(value),
            ExprKind::Bool { value, .. } => self.compile_boolean(value),
            ExprKind::UnaryOperation {
                operator,
                right,
                at,
            } => self.compile_unary_operation(operator, *right, at),
            ExprKind::BinaryOperation {
                left,
                operator,
                right,
                at,
            } => self.compile_binary_operation(*left, operator, *right, at),

            ExprKind::Assign { name, value, at } => self.compile_assign(name, *value, at),

            ExprKind::Call {
                function_name,
                arguments,
                at,
            } => self.compile_call(function_name, arguments, at),

            ExprKind::Unknown => (),
        }
    }

    fn compile_identifer(&mut self, symbol: String, at: (usize, usize)) {
        self.chunk
            .write_instruction(Instruction::LoadName { name: symbol, at })
    }

    fn compile_string(&mut self, value: String) {
        let index = self.chunk.add_constant(Value::Str(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn compile_integer(&mut self, value: i64) {
        let index = self.chunk.add_constant(Value::Int(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn compile_float(&mut self, value: f64) {
        let index = self.chunk.add_constant(Value::Float(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn compile_boolean(&mut self, value: bool) {
        let index = self.chunk.add_constant(Value::Bool(value));

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn compile_unary_operation(&mut self, operator: char, right: ExprKind, at: (usize, usize)) {
        self.compile_expr(right);

        match operator {
            '-' => self.chunk.write_instruction(Instruction::Neg { at }),
            '!' => self.chunk.write_instruction(Instruction::LogicalNot { at }),
            _ => unreachable!(),
        }
    }

    fn compile_binary_operation(
        &mut self,
        left: ExprKind,
        operator: String,
        right: ExprKind,
        at: (usize, usize),
    ) {
        self.compile_expr(left);
        self.compile_expr(right);

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

    fn compile_assign(&mut self, name: String, value: ExprKind, at: (usize, usize)) {
        self.compile_expr(value);

        self.chunk
            .write_instruction(Instruction::Assign { name, at })
    }

    fn compile_call(
        &mut self,
        function_name: String,
        arguments: ThinVec<ExprKind>,
        at: (usize, usize),
    ) {
        for argument in arguments.clone() {
            self.compile_expr(argument);
        }

        self.chunk.write_instruction(Instruction::Call {
            function_name,
            arguments_count: arguments.len(),
            at,
        });
    }
}
