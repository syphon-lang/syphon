use crate::chunk::Atom;
use crate::compiler::Compiler;
use crate::instruction::Instruction;
use crate::value::Value;

use syphon_ast::*;

use thin_vec::ThinVec;

impl<'a> Compiler<'a> {
    pub(crate) fn compile_expr(&mut self, kind: ExprKind) {
        match kind {
            ExprKind::Identifier { name, location } => self.compile_identifer(name, location),

            ExprKind::String { value, location } => self.compile_string(value, location),

            ExprKind::Int { value, location } => self.compile_integer(value, location),

            ExprKind::Float { value, location } => self.compile_float(value, location),

            ExprKind::Bool { value, location } => self.compile_boolean(value, location),

            ExprKind::Array { values, location } => self.compile_array(values, location),

            ExprKind::None { location } => self.compile_none(location),

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

            ExprKind::AssignSubscript {
                array,
                index,
                value,
                location,
            } => self.compile_assign_subscript(*array, *index, *value, location),

            ExprKind::Call {
                callable,
                arguments,
                location,
            } => self.compile_call(*callable, arguments, location),

            ExprKind::ArraySubscript {
                array,
                index,
                location,
            } => self.compile_array_subscript(*array, *index, location),
        }
    }

    fn compile_identifer(&mut self, name: String, location: Location) {
        self.chunk.locations.push(location);

        self.chunk.instructions.push(Instruction::LoadName {
            atom: Atom::new(name),
        })
    }

    fn compile_string(&mut self, value: String, location: Location) {
        self.chunk.locations.push(location);

        let index = self
            .chunk
            .add_constant(Value::String(self.gc.intern(value)));

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index })
    }

    fn compile_integer(&mut self, value: i64, location: Location) {
        self.chunk.locations.push(location);

        let index = self.chunk.add_constant(Value::Int(value));

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index })
    }

    fn compile_float(&mut self, value: f64, location: Location) {
        self.chunk.locations.push(location);

        let index = self.chunk.add_constant(Value::Float(value));

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index })
    }

    fn compile_boolean(&mut self, value: bool, location: Location) {
        self.chunk.locations.push(location);

        let index = self.chunk.add_constant(Value::Bool(value));

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index })
    }

    fn compile_array(&mut self, values: ThinVec<ExprKind>, location: Location) {
        let length = values.len();

        for value in values {
            self.compile_expr(value);
        }

        self.chunk.locations.push(location);

        self.chunk
            .instructions
            .push(Instruction::MakeArray { length })
    }

    fn compile_none(&mut self, location: Location) {
        self.chunk.locations.push(location);

        let index = self.chunk.add_constant(Value::None);

        self.chunk
            .instructions
            .push(Instruction::LoadConstant { index })
    }

    fn compile_unary_operation(
        &mut self,
        operator: UnaryOperator,
        right: ExprKind,
        location: Location,
    ) {
        self.compile_expr(right);

        self.chunk.locations.push(location);

        match operator {
            UnaryOperator::Minus => self.chunk.instructions.push(Instruction::Neg),

            UnaryOperator::Bang => self.chunk.instructions.push(Instruction::LogicalNot),
        }
    }

    fn compile_binary_operation(
        &mut self,
        left: ExprKind,
        operator: BinaryOperator,
        right: ExprKind,
        location: Location,
    ) {
        macro_rules! constant_folding {
            ($operator: tt, $default: expr) => {
                match (left, right) {
                    (ExprKind::Int { value: left, .. }, ExprKind::Int { value: right, .. }) => {
                        let index = self.chunk.add_constant(
                            if stringify!($operator) == "/" {
                                Value::Float((left as f64) $operator (right as f64))
                            } else {
                                Value::Int((left) $operator (right))
                            }
                        );

                        self.chunk.instructions.push(Instruction::LoadConstant { index });
                    }

                    (ExprKind::Float { value: left, .. }, ExprKind::Int { value: right, .. }) => {
                        let index = self.chunk.add_constant(Value::Float((left) $operator (right as f64)));

                        self.chunk.instructions.push(Instruction::LoadConstant { index });
                    }

                    (ExprKind::Int { value: left, .. }, ExprKind::Float { value: right, .. }) => {
                        let index = self.chunk.add_constant(Value::Float((left as f64) $operator (right)));

                        self.chunk.instructions.push(Instruction::LoadConstant { index });
                    }

                    (ExprKind::Float { value: left, .. }, ExprKind::Float { value: right, .. }) => {
                        let index = self.chunk.add_constant(Value::Float((left) $operator (right)));

                        self.chunk.instructions.push(Instruction::LoadConstant { index });
                    }

                    (left, right) => {
                        self.compile_expr(left);
                        self.compile_expr(right);

                        $default;
                    }
                }
            };
        }

        match operator {
            BinaryOperator::Plus => {
                constant_folding!(+, {
                    self.chunk.locations.push(location);

                    self.chunk.instructions.push(Instruction::Add)
                })
            }

            BinaryOperator::Minus => {
                constant_folding!(-, {
                    self.chunk.locations.push(location);

                    self.chunk.instructions.push(Instruction::Sub)
                })
            }

            BinaryOperator::ForwardSlash => {
                constant_folding!(/, {
                    self.chunk.locations.push(location);

                    self.chunk.instructions.push(Instruction::Div)
                })
            }

            BinaryOperator::Star => {
                constant_folding!(*, {
                    self.chunk.locations.push(location);

                    self.chunk.instructions.push(Instruction::Mult)
                })
            }

            _ => {
                self.compile_expr(left);
                self.compile_expr(right);
            }
        }

        self.chunk.locations.push(location);

        match operator {
            BinaryOperator::DoubleStar => self.chunk.instructions.push(Instruction::Exponent),

            BinaryOperator::Percent => self.chunk.instructions.push(Instruction::Modulo),

            BinaryOperator::Equals => self.chunk.instructions.push(Instruction::Equals),

            BinaryOperator::NotEquals => self.chunk.instructions.push(Instruction::NotEquals),

            BinaryOperator::LessThan => self.chunk.instructions.push(Instruction::LessThan),

            BinaryOperator::GreaterThan => self.chunk.instructions.push(Instruction::GreaterThan),

            _ => (),
        }
    }

    fn compile_assign(&mut self, name: String, value: ExprKind, location: Location) {
        self.compile_expr(value.clone());

        self.chunk.locations.push(location);

        self.chunk.instructions.push(Instruction::StoreName {
            atom: Atom::new(name),
        });

        self.compile_expr(value);
    }

    fn compile_assign_subscript(
        &mut self,
        array: ExprKind,
        index: ExprKind,
        value: ExprKind,
        location: Location,
    ) {
        self.compile_expr(array);

        self.compile_expr(index);

        self.compile_expr(value.clone());

        self.chunk.locations.push(location);

        self.chunk.instructions.push(Instruction::StoreSubscript);

        self.compile_expr(value);
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

        self.chunk.locations.push(location);

        self.chunk.instructions.push(Instruction::Call {
            arguments_count: arguments.len(),
        });
    }

    fn compile_array_subscript(&mut self, array: ExprKind, index: ExprKind, location: Location) {
        self.compile_expr(array);

        self.compile_expr(index);

        self.chunk.locations.push(location);

        self.chunk.instructions.push(Instruction::LoadSubscript);
    }
}
