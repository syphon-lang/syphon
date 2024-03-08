use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::instructions::Instruction;
use syphon_bytecode::value::{Function, Value};

use syphon_errors::SyphonError;
use syphon_location::Location;

use rustc_hash::FxHashMap;

#[derive(Clone)]
pub struct NameInfo {
    stack_index: usize,
    mutable: bool,
}

struct CallFrame {
    function: Function,
    names: FxHashMap<String, NameInfo>,
    ip: usize,
}

pub struct VirtualMachine {
    frames: Vec<CallFrame>,
    fp: usize,
    stack: Vec<Value>,
}

impl VirtualMachine {
    pub fn new() -> VirtualMachine {
        VirtualMachine {
            frames: Vec::new(),
            fp: 0,
            stack: Vec::new(),
        }
    }

    pub fn load_chunk(&mut self, chunk: Chunk) {
        if self.frames.is_empty() {
            self.frames.push(CallFrame {
                function: Function {
                    name: String::new(),
                    body: chunk,
                    parameters: Vec::new(),
                },

                names: FxHashMap::default(),
                ip: 0,
            });
        } else {
            self.frames[0].function.body = chunk;
            self.frames[0].ip = 0;
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        while self.frames[self.fp].ip < self.frames[self.fp].function.body.code.len() {
            println!("--");

            for value in self.stack.iter() {
                println!("{value}");
            }

            let instruction =
                self.frames[self.fp].function.body.code[self.frames[self.fp].ip].clone();

            self.frames[self.fp].ip += 1;

            match instruction {
                Instruction::Neg { location } => self.negative(location)?,

                Instruction::LogicalNot { location } => self.logical_not(location)?,

                Instruction::Add { location } => self.add(location)?,

                Instruction::Sub { location } => self.subtract(location)?,

                Instruction::Div { location } => self.divide(location)?,

                Instruction::Mult { location } => self.multiply(location)?,

                Instruction::Exponent { location } => self.exponent(location)?,

                Instruction::Modulo { location } => self.modulo(location)?,

                Instruction::LessThan { location } => self.less_than(location)?,

                Instruction::GreaterThan { location } => self.greater_than(location)?,

                Instruction::Equals { location } => self.equals(location)?,

                Instruction::NotEquals { location } => self.not_equals(location)?,

                Instruction::StoreName { name, mutable } => self.store_name(name, mutable),

                Instruction::LoadName { name, location } => self.load_name(name, location)?,

                Instruction::Assign { name, location } => self.assign(name, location)?,

                Instruction::LoadConstant { index } => self.stack.push(
                    self.frames[self.fp]
                        .function
                        .body
                        .get_constant(index)
                        .unwrap()
                        .clone(),
                ),

                Instruction::Call {
                    arguments_count,
                    location,
                } => self.call_function(arguments_count, location)?,

                Instruction::Return => {
                    if self.fp != 0 {
                        self.fp -= 1;

                        self.frames.pop().unwrap();
                    }

                    return Ok(match self.stack.pop() {
                        Some(value) => value,
                        None => Value::None,
                    });
                }

                Instruction::JumpIfFalse { offset, location } => {
                    self.jump_if_false(offset, location)?
                }

                Instruction::Jump { offset } => self.jump(offset),

                Instruction::Back { offset } => self.back(offset),
            }
        }

        Ok(Value::None)
    }

    fn negative(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match right {
            Value::Int(value) => Value::Int(-value),
            Value::Float(value) => Value::Float(-value),

            _ => return Err(SyphonError::unable_to(location, "apply '-' unary operator")),
        });

        Ok(())
    }

    fn logical_not(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match right {
            Value::Int(value) => Value::Bool(value == 0),
            Value::Float(value) => Value::Bool(value == 0.0),
            Value::Bool(value) => Value::Bool(!value),
            _ => Value::Bool(false),
        });

        Ok(())
    }

    fn add(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left + right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 + right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left + right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left + right),
            (Value::String(left), Value::String(right)) => Value::String(left + right.as_str()),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '+' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn subtract(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left - right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 - right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left - right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left - right),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '-' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn divide(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Float(left as f64 / right as f64),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 / right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left / right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left / right),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '/' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn multiply(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left * right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 * right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left * right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left * right),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '*' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn exponent(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Float((left as f64).powf(right as f64)),
            (Value::Int(left), Value::Float(right)) => Value::Float((left as f64).powf(right)),
            (Value::Float(left), Value::Int(right)) => Value::Float((left).powf(right as f64)),
            (Value::Float(left), Value::Float(right)) => Value::Float(left.powf(right)),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '**' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn modulo(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left.rem_euclid(right)),
            (Value::Int(left), Value::Float(right)) => {
                Value::Float((left as f64).rem_euclid(right))
            }
            (Value::Float(left), Value::Int(right)) => Value::Float(left.rem_euclid(right as f64)),
            (Value::Float(left), Value::Float(right)) => Value::Float(left.rem_euclid(right)),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '%' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn greater_than(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (right, left) {
            (Value::Int(left), Value::Int(right)) => Value::Bool(left > right),
            (Value::Int(left), Value::Float(right)) => Value::Bool(left as f64 > right),
            (Value::Float(left), Value::Int(right)) => Value::Bool(left > right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Bool(left > right),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '>' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn less_than(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (right, left) {
            (Value::Int(left), Value::Int(right)) => Value::Bool(left < right),
            (Value::Int(left), Value::Float(right)) => Value::Bool((left as f64) < right),
            (Value::Float(left), Value::Int(right)) => Value::Bool(left < right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Bool(left < right),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '<' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn equals(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Bool(left == right),
            (Value::Int(left), Value::Float(right)) => Value::Bool(left as f64 == right),
            (Value::Float(left), Value::Int(right)) => Value::Bool(left == right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Bool(left == right),
            (Value::String(left), Value::String(right)) => Value::Bool(left == right),
            (Value::None, Value::None) => Value::Bool(true),
            (Value::None, ..) => Value::Bool(false),
            (.., Value::None) => Value::Bool(false),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '==' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn not_equals(&mut self, location: Location) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Bool(left != right),
            (Value::Int(left), Value::Float(right)) => Value::Bool(left as f64 != right),
            (Value::Float(left), Value::Int(right)) => Value::Bool(left != right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Bool(left != right),
            (Value::String(left), Value::String(right)) => Value::Bool(left != right),
            (Value::None, Value::None) => Value::Bool(false),
            (Value::None, ..) => Value::Bool(true),
            (.., Value::None) => Value::Bool(true),

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '!=' binary operator",
                ));
            }
        });

        Ok(())
    }

    fn store_name(&mut self, name: String, mutable: bool) {
        let frame = &mut self.frames[self.fp];

        let stack_index = self.stack.len() - 1;

        frame.names.insert(
            name,
            NameInfo {
                stack_index,
                mutable,
            },
        );
    }

    fn load_name(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let frame = &self.frames[self.fp];

        let Some(name_info) = frame.names.get(&name) else {
            return Err(SyphonError::undefined(location, "name", &name));
        };

        let value = self.stack.get(name_info.stack_index).unwrap().clone();

        self.stack.push(value);

        Ok(())
    }

    fn assign(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let frame = &mut self.frames[self.fp];

        let Some(past_name_info) = frame.names.get(&name) else {
            return Err(SyphonError::undefined(location, "name", &name));
        };

        let Some(new_value) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a new value"));
        };

        if !past_name_info.mutable {
            return Err(SyphonError::unable_to(location, "assign to a constant"));
        }

        self.stack.remove(past_name_info.stack_index);

        self.stack.push(new_value);

        let stack_index = self.stack.len() - 1;

        frame.names.insert(
            name,
            NameInfo {
                stack_index,
                mutable: past_name_info.mutable,
            },
        );

        Ok(())
    }

    fn call_function(
        &mut self,
        arguments_count: usize,
        location: Location,
    ) -> Result<(), SyphonError> {
        let Some(callee) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a callable"));
        };

        let mut arguments = Vec::with_capacity(arguments_count);

        for _ in 0..arguments_count {
            arguments.push(self.stack.pop().unwrap());
        }

        match callee {
            Value::Function(function) => {
                if function.parameters.len() != arguments_count {
                    return Err(SyphonError::expected_got(
                        location,
                        format!(
                            "{} {}",
                            function.parameters.len(),
                            match function.parameters.len() == 1 {
                                true => "argument",
                                false => "arguments",
                            }
                        )
                        .as_str(),
                        arguments_count.to_string().as_str(),
                    ));
                }

                let previous_frame = &self.frames[self.fp];

                self.frames.push(CallFrame {
                    function,
                    names: previous_frame.names.clone(),
                    ip: 0,
                });

                self.fp += 1;

                let new_frame = &mut self.frames[self.fp];

                let previous_stack_len = self.stack.len();

                arguments.reverse();

                for parameter in new_frame.function.parameters.iter() {
                    self.stack.push(arguments.pop().unwrap());

                    let stack_index = self.stack.len() - 1;

                    new_frame.names.insert(
                        parameter.to_string(),
                        NameInfo {
                            stack_index,
                            mutable: true,
                        },
                    );
                }

                let return_value = self.run();

                for _ in 0..self.stack.len() - previous_stack_len {
                    self.stack.pop();
                }

                match return_value {
                    Ok(return_value) => self.stack.push(return_value),
                    Err(err) => {
                        self.fp -= 1;
                        self.frames.pop().unwrap();

                        return Err(err);
                    }
                }
            }

            _ => return Err(SyphonError::expected(location, "a callable")),
        }

        Ok(())
    }

    fn jump_if_false(&mut self, offset: usize, location: Location) -> Result<(), SyphonError> {
        let frame = &mut self.frames[self.fp];

        let Some(value) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        if !value.is_truthy() {
            frame.ip += offset;
        }

        Ok(())
    }

    fn jump(&mut self, offset: usize) {
        let frame = &mut self.frames[self.fp];

        frame.ip += offset;
    }

    fn back(&mut self, offset: usize) {
        let frame = &mut self.frames[self.fp];

        frame.ip -= offset + 1;
    }
}
