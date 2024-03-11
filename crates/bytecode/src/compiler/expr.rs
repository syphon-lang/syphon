use crate::chunk::Atom;
use crate::compiler::Compiler;
use crate::instruction::Instruction;
use crate::value::Value;

use syphon_ast::*;
use syphon_location::Location;

use thin_vec::ThinVec;

impl Compiler {
    pub(crate) fn compile_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { symbol, location } => self.compile_identifer(symbol, location),
            ExprKind::String { value, .. } => self.compile_string(value),
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
                callable,
                arguments,
                location,
            } => self.compile_call(*callable, arguments, location),
        }
    }

    fn compile_identifer(&mut self, symbol: String, location: Location) {
        self.chunk.write_instruction(Instruction::LoadName {
            atom: Atom::new(symbol),
            location,
        })
    }

    fn compile_string(&mut self, value: String) {
        let index = self.chunk.add_constant(Value::String(value.into()));

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

    fn compile_unary_operation(
        &mut self,
        operator: UnaryOperator,
        right: ExprKind,
        location: Location,
    ) {
        self.compile_expr(right);

        match operator {
            UnaryOperator::Minus => self.chunk.write_instruction(Instruction::Neg { location }),

            UnaryOperator::Bang => self.chunk.write_instruction(Instruction::LogicalNot),
        }
    }

    fn compile_binary_operation(
        &mut self,
        left: ExprKind,
        operator: BinaryOperator,
        right: ExprKind,
        location: Location,
    ) {
        self.compile_expr(left);
        self.compile_expr(right);

        match operator {
            BinaryOperator::Plus => self.chunk.write_instruction(Instruction::Add { location }),
            BinaryOperator::Minus => self.chunk.write_instruction(Instruction::Sub { location }),
            BinaryOperator::ForwardSlash => {
                self.chunk.write_instruction(Instruction::Div { location })
            }
            BinaryOperator::Star => self.chunk.write_instruction(Instruction::Mult { location }),
            BinaryOperator::DoubleStar => self
                .chunk
                .write_instruction(Instruction::Exponent { location }),
            BinaryOperator::Percent => self
                .chunk
                .write_instruction(Instruction::Modulo { location }),

            BinaryOperator::Equals => self
                .chunk
                .write_instruction(Instruction::Equals { location }),
            BinaryOperator::NotEquals => self
                .chunk
                .write_instruction(Instruction::NotEquals { location }),
            BinaryOperator::LessThan => self
                .chunk
                .write_instruction(Instruction::LessThan { location }),
            BinaryOperator::GreaterThan => self
                .chunk
                .write_instruction(Instruction::GreaterThan { location }),
        }
    }

    fn compile_assign(&mut self, name: String, value: ExprKind, location: Location) {
        self.compile_expr(value);

        let atom = Atom::new(name);

        self.chunk
            .write_instruction(Instruction::Assign { atom, location });

        self.chunk
            .write_instruction(Instruction::LoadName { atom, location });
    }

    fn compile_call(
        &mut self,
        callable: ExprKind,
        arguments: ThinVec<ExprKind>,
        location: Location,
    ) {
        for argument in arguments.clone() {
            self.compile_expr(argument);
        }

        self.compile_expr(callable);

        self.chunk.write_instruction(Instruction::Call {
            arguments_count: arguments.len(),
            location,
        });
    }
}
