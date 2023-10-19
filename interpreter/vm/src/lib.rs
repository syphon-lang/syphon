use syphon_bytecode::chunk::*;
use syphon_bytecode::instructions::Instruction;
use syphon_bytecode::values::*;

use syphon_errors::SyphonError;

use rustc_hash::FxHashMap;

use thin_vec::ThinVec;

pub struct VirtualMachine<'a> {
    chunk: Chunk,
    stack: ThinVec<Value>,
    names: &'a mut FxHashMap<String, ValueInfo>,
}

impl<'a> VirtualMachine<'a> {
    pub fn new(chunk: Chunk, globals: &mut FxHashMap<String, ValueInfo>) -> VirtualMachine {
        VirtualMachine {
            chunk,
            stack: ThinVec::new(),
            names: globals,
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        for instruction in self.chunk.code.clone() {
            match instruction {
                Instruction::Neg { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    self.stack.push(match right {
                        Value::Int(value) => Value::Int(-value),
                        Value::Float(value) => Value::Float(-value),

                        _ => return Err(SyphonError::unable_to(at, "apply '-' unary operator")),
                    })
                }

                Instruction::LogicalNot { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    self.stack.push(match right {
                        Value::Int(value) => Value::Bool(value == 0),
                        Value::Float(value) => Value::Bool(value == 0.0),
                        Value::Bool(value) => Value::Bool(!value),
                        _ => Value::Bool(false),
                    })
                }

                Instruction::Add { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '+' binary operator"));
                        }
                    })
                }

                Instruction::Sub { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '-' binary operator"));
                        }
                    })
                }

                Instruction::Div { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '/' binary operator"));
                        }
                    })
                }

                Instruction::Mult { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '*' binary operator"));
                        }
                    })
                }

                Instruction::Exponent { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '**' binary operator"));
                        }
                    })
                }

                Instruction::Modulo { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '%' binary operator"));
                        }
                    })
                }

                Instruction::LessThan { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    self.stack.push(match (right, left) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left < right),
                        (Value::Int(left), Value::Float(right)) => {
                            Value::Bool((left as f64) < right)
                        }
                        (Value::Float(left), Value::Int(right)) => Value::Bool(left < right as f64),
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left < right),

                        _ => {
                            return Err(SyphonError::unable_to(at, "apply '<' binary operator"));
                        }
                    })
                }

                Instruction::GreaterThan { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    self.stack.push(match (right, left) {
                        (Value::Int(left), Value::Int(right)) => Value::Bool(left > right),
                        (Value::Int(left), Value::Float(right)) => Value::Bool(left as f64 > right),
                        (Value::Float(left), Value::Int(right)) => Value::Bool(left > right as f64),
                        (Value::Float(left), Value::Float(right)) => Value::Bool(left > right),

                        _ => {
                            return Err(SyphonError::unable_to(at, "apply '>' binary operator"));
                        }
                    })
                }

                Instruction::Equals { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '==' binary operator"));
                        }
                    })
                }

                Instruction::NotEquals { at } => {
                    let Some(right) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    let Some(left) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
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
                            return Err(SyphonError::unable_to(at, "apply '!=' binary operator"));
                        }
                    })
                }

                Instruction::StoreName { name, mutable } => {
                    let value = self.stack.pop().unwrap();

                    self.names.insert(name, ValueInfo { value, mutable });
                }

                Instruction::LoadName { name, at } => {
                    let Some(value_info) = self.names.get(&name) else {
                        return Err(SyphonError::undefined(at, "name", &name));
                    };

                    self.stack.push(value_info.value.clone());
                }

                Instruction::Assign { name, at } => {
                    let Some(past_value_info) = self.names.get(&name) else {
                        return Err(SyphonError::undefined(at, "name", &name));
                    };

                    let Some(value) = self.stack.pop() else {
                        return Err(SyphonError::expected(at, "a value"));
                    };

                    if !past_value_info.mutable {
                        return Err(SyphonError::unable_to(at, "assign to a constant"));
                    }

                    self.stack.push(value.clone());

                    self.names.insert(
                        name,
                        ValueInfo {
                            value,
                            mutable: past_value_info.mutable,
                        },
                    );
                }

                Instruction::LoadConstant { index } => self
                    .stack
                    .push(self.chunk.get_constant(index).unwrap().clone()),

                Instruction::Call {
                    function_name,
                    arguments_count,
                    at,
                } => {
                    let Some(value_info) = self.names.get(&function_name) else {
                        return Err(SyphonError::undefined(at, "name", &function_name));
                    };

                    let Value::Function {
                        parameters, body, ..
                    } = value_info.value.clone()
                    else {
                        return Err(SyphonError::expected(at, "function"));
                    };

                    if arguments_count != parameters.len() {
                        return Err(SyphonError::expected(
                            at,
                            match parameters.len() {
                                1 => format!("{} argument", parameters.len()),
                                _ => format!("{} arguments", parameters.len()),
                            }
                            .as_str(),
                        ));
                    }

                    let mut arguments = ThinVec::new();

                    for _ in 0..arguments_count {
                        arguments.push(self.stack.pop().unwrap());
                    }

                    let mut names = self.names.clone();

                    for (index, value) in arguments.iter().enumerate() {
                        names.insert(
                            parameters[index].clone(),
                            ValueInfo {
                                value: value.clone(),
                                mutable: true,
                            },
                        );
                    }

                    let mut vm = VirtualMachine::new(body, &mut names);

                    match vm.run() {
                        Ok(value) => self.stack.push(value),
                        Err(err) => return Err(err),
                    }
                }

                Instruction::Return => match self.stack.pop() {
                    Some(value) => return Ok(value),
                    None => return Ok(Value::None),
                },
            }
        }

        Ok(Value::None)
    }
}
