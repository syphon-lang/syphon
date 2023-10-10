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
                Instruction::Neg { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match right {
                        Value::Int(value) => Value::Int(-value),
                        Value::Float(value) => Value::Float(-value),

                        _ => return Err(SyphonError::unable_to(*at, "apply '-' unary operator")),
                    })
                }

                Instruction::LogicalNot { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match right {
                        Value::Int(value) => Value::Bool(value == 0),
                        Value::Float(value) => Value::Bool(value == 0.0),
                        Value::Bool(value) => Value::Bool(!value),
                        _ => Value::Bool(false),
                    })
                }

                Instruction::Add { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Int(left + right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float(left as f64 + right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float(left + right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left + right),
                        (Value::Str(left), Value::Str(right)) => Value::Str(left + right.as_str()),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '+' binary operator"));
                        }
                    })
                }

                Instruction::Sub { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Int(left - right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float(left as f64 - right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float(left - right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left - right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '-' binary operator"));
                        }
                    })
                }

                Instruction::Div { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => {
                            Value::Float(left as f64 / right as f64)
                        }
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float(left as f64 / right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float(left / right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left / right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '/' binary operator"));
                        }
                    })
                }

                Instruction::Mult { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Int(left * right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float(left as f64 * right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float(left * right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left * right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '*' binary operator"));
                        }
                    })
                }

                Instruction::Exponent { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => {
                            Value::Float((left as f64).powf(right as f64))
                        }
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float((left as f64).powf(right))
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float((left).powf(right as f64))
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left.powf(right)),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '**' binary operator"));
                        }
                    })
                }

                Instruction::Modulo { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Int(left % right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Float(left as f64 % right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Float(left % right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Float(left % right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '%' binary operator"));
                        }
                    })
                }

                Instruction::LessThan { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (right, left) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left < right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Bool((left as f64) < right)
                        }
                        (Value::Float(left), Value::Int(right)) => Value::Bool(left < right as f64),
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left < right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '<' binary operator"));
                        }
                    })
                }

                Instruction::GreaterThan { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (right, left) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left > right),
                        (Value::Int(left), Value::Float(right)) => Value::Bool(left as f64 > right),
                        (Value::Float(left), Value::Int(right)) => Value::Bool(left > right as f64),
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left > right),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '>' binary operator"));
                        }
                    })
                }

                Instruction::Equals { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left == right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Bool(left as f64 == right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Bool(left == right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left == right),
                        (Value::Str(left), Value::Str(right)) => Value::Bool(left == right),
                        (Value::None, Value::None) => Value::Bool(true),
                        (Value::None, ..) => Value::Bool(false),
                        (.., Value::None) => Value::Bool(false),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '==' binary operator"));
                        }
                    })
                }

                Instruction::NotEquals { at } => {
                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(*at, "a value"));
                    };

                    self.stack.push(match (left, right) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left != right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Bool(left as f64 != right)
                        }
                        (Value::Float(left), Value::Int(right)) => {
                            Value::Bool(left != right as f64)
                        }
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left != right),
                        (Value::Str(left), Value::Str(right)) => Value::Bool(left != right),
                        (Value::None, Value::None) => Value::Bool(false),
                        (Value::None, ..) => Value::Bool(true),
                        (.., Value::None) => Value::Bool(true),

                        _ => {
                            return Err(SyphonError::unable_to(*at, "apply '!=' binary operator"));
                        }
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
