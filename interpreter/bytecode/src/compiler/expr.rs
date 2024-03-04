use crate::compiler::*;
use crate::instructions::Instruction;
use crate::values::Value;

use syphon_location::Location;

use thin_vec::ThinVec;

impl Compiler {
    pub(crate) fn compile_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { symbol, location } => self.compile_identifer(symbol, location),
            ExprKind::Str { value, .. } => self.compile_string(value),
            ExprKind::Int { value, .. } => self.compile_integer(value),
            ExprKind::Float { value, .. } => self.compile_float(value),
            ExprKind::Bool { value, .. } => self.compile_boolean(value),
            ExprKind::None { .. } => self.compile_none(),

            ExprKind::UnaryOperation {
                operator,
                right,
                location,
            } => self.compile_unary_operation(operator, *right, location),

            ExprKind::BinaryOperation {
                left,
                operator,
                right,
                location,
            } => self.compile_binary_operation(*left, operator, *right, location),

            ExprKind::Assign {
                name,
                value,
                location,
            } => self.compile_assign(name, *value, location),

            ExprKind::Call {
                function_name,
                arguments,
                location,
            } => self.compile_call(function_name, arguments, location),

            ExprKind::Unknown => (),
        }
    }

    fn compile_identifer(&mut self, symbol: String, location: Location) {
        self.chunk.write_instruction(Instruction::LoadName {
            name: symbol,
            location,
        })
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

    fn compile_none(&mut self) {
        let index = self.chunk.add_constant(Value::None);

        self.chunk
            .write_instruction(Instruction::LoadConstant { index })
    }

    fn compile_unary_operation(&mut self, operator: char, right: ExprKind, location: Location) {
        self.compile_expr(right);

        match operator {
            '-' => self.chunk.write_instruction(Instruction::Neg { location }),
            '!' => self
                .chunk
                .write_instruction(Instruction::LogicalNot { location }),
            _ => unreachable!(),
        }
    }

    fn compile_binary_operation(
        &mut self,
        left: ExprKind,
        operator: String,
        right: ExprKind,
        location: Location,
    ) {
        self.compile_expr(left);
        self.compile_expr(right);

        match operator.as_str() {
            "+" => self.chunk.write_instruction(Instruction::Add { location }),
            "-" => self.chunk.write_instruction(Instruction::Sub { location }),
            "/" => self.chunk.write_instruction(Instruction::Div { location }),
            "*" => self.chunk.write_instruction(Instruction::Mult { location }),
            "**" => self
                .chunk
                .write_instruction(Instruction::Exponent { location }),
            "%" => self
                .chunk
                .write_instruction(Instruction::Modulo { location }),

            "==" => self
                .chunk
                .write_instruction(Instruction::Equals { location }),
            "!=" => self
                .chunk
                .write_instruction(Instruction::NotEquals { location }),
            "<" => self
                .chunk
                .write_instruction(Instruction::LessThan { location }),
            ">" => self
                .chunk
                .write_instruction(Instruction::GreaterThan { location }),
            _ => unreachable!(),
        }
    }

    fn compile_assign(&mut self, name: String, value: ExprKind, location: Location) {
        self.compile_expr(value);

        self.chunk.write_instruction(Instruction::Assign {
            name: name.clone(),
            location,
        });

        self.chunk
            .write_instruction(Instruction::LoadName { name, location });
    }

    fn compile_call(
        &mut self,
        function_name: String,
        arguments: ThinVec<ExprKind>,
        location: Location,
    ) {
        for argument in arguments.clone() {
            self.compile_expr(argument);
        }

        self.chunk.write_instruction(Instruction::Call {
            function_name,
            arguments_count: arguments.len(),
            location,
        });
    }
}
