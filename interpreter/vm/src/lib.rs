use syphon_bytecode::chunk::*;
use syphon_bytecode::instructions::Instruction;
use syphon_bytecode::values::Value;

use syphon_errors::SyphonError;

use thin_vec::ThinVec;

pub struct VirtualMachine {
    chunk: Chunk,
    stack: ThinVec<Value>,
}

impl VirtualMachine {
    pub fn new(chunk: Chunk) -> VirtualMachine {
        VirtualMachine {
            chunk,
            stack: ThinVec::new(),
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        for instruction in self.chunk.code.iter() {
            match instruction {
                Instruction::UnaryOperation { operator, at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match operator {
                        '!' => match right {
                            Value::Int(value) => Value::Bool(value == 0),
                            Value::Float(value) => Value::Bool(value == 0.0),
                            Value::Bool(value) => Value::Bool(!value),
                            _ => Value::Bool(false),
                        },

                        '-' => match right {
                            Value::Int(value) => Value::Int(-value),
                            Value::Float(value) => Value::Float(-value),

                            _ => {
                                return Err(SyphonError::unable_to(*at, "apply '-' unary operator"))
                            }
                        },

                        _ => unreachable!(),
                    })
                }

                Instruction::BinaryOperation { operator, at } => {
                    let Some(lhs) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(rhs) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match operator.as_str() {
                        "+" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs + rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 + rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Float(lhs + rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs + rhs),
                            (Value::Str(lhs), Value::Str(rhs)) => Value::Str(lhs + rhs.as_str()),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '+' binary operator",
                                ));
                            }
                        },

                        "-" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs - rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 - rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Float(lhs - rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs - rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '-' binary operator",
                                ));
                            }
                        },

                        "/" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => {
                                Value::Float(lhs as f64 / rhs as f64)
                            }
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 / rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Float(lhs / rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs / rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '/' binary operator",
                                ));
                            }
                        },

                        "*" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs * rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 * rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Float(lhs * rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs * rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '*' binary operator",
                                ));
                            }
                        },

                        "**" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => {
                                Value::Float((lhs as f64).powf(rhs as f64))
                            }
                            (Value::Int(lhs), Value::Float(rhs)) => {
                                Value::Float((lhs as f64).powf(rhs))
                            }
                            (Value::Float(lhs), Value::Int(rhs)) => {
                                Value::Float((lhs).powf(rhs as f64))
                            }
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs.powf(rhs)),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '**' binary operator",
                                ));
                            }
                        },

                        "%" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs % rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 % rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Float(lhs % rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs % rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '%' binary operator",
                                ));
                            }
                        },

                        ">" => match (rhs, lhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs > rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 > rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Bool(lhs > rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs > rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '>' binary operator",
                                ));
                            }
                        },

                        "<" => match (rhs, lhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs < rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Bool((lhs as f64) < rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Bool(lhs < rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs < rhs),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '<' binary operator",
                                ));
                            }
                        },

                        "==" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs == rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 == rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Bool(lhs == rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs == rhs),
                            (Value::Str(lhs), Value::Str(rhs)) => Value::Bool(lhs == rhs),
                            (Value::None, Value::None) => Value::Bool(true),
                            (Value::None, ..) => Value::Bool(false),
                            (.., Value::None) => Value::Bool(false),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '==' binary operator",
                                ));
                            }
                        },

                        "!=" => match (lhs, rhs) {
                            (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs != rhs),
                            (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 != rhs),
                            (Value::Float(lhs), Value::Int(rhs)) => Value::Bool(lhs != rhs as f64),
                            (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs != rhs),
                            (Value::Str(lhs), Value::Str(rhs)) => Value::Bool(lhs != rhs),
                            (Value::None, Value::None) => Value::Bool(false),
                            (Value::None, ..) => Value::Bool(true),
                            (.., Value::None) => Value::Bool(true),

                            _ => {
                                return Err(SyphonError::unable_to(
                                    *at,
                                    "apply '!=' binary operator",
                                ));
                            }
                        },

                        _ => unreachable!(),
                    })
                }

                Instruction::LoadConstant { index } => self
                    .stack
                    .push(self.chunk.get_constant(*index).unwrap().clone()),

                Instruction::Return => match self.stack.pop() {
                    Some(value) => return Ok(value),
                    None => return Ok(Value::None),
                },
            }
        }

        Ok(Value::None)
    }
}
