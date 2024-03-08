use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::instructions::Instruction;
use syphon_bytecode::value::Value;

use syphon_errors::SyphonError;
use syphon_location::Location;

use rustc_hash::FxHashMap;

#[derive(Clone)]
pub struct NameInfo {
    stack_index: usize,
    mutable: bool,
}

pub struct VirtualMachine {
    chunk: Chunk,
    stack: Vec<Value>,
    names: FxHashMap<String, NameInfo>,
    link: Option<usize>,
    ip: usize,
}

impl VirtualMachine {
    pub fn new() -> VirtualMachine {
        VirtualMachine {
            chunk: Chunk::new(),
            stack: Vec::new(),
            names: FxHashMap::default(),
            link: None,
            ip: 0,
        }
    }

    pub fn load_chunk(&mut self, chunk: Chunk) {
        self.ip = 0;
        self.chunk = chunk;
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        while self.ip < self.chunk.code.len() {
            let instruction = self.chunk.code[self.ip].clone();

            self.ip += 1;

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

                Instruction::LoadConstant { index } => self
                    .stack
                    .push(self.chunk.get_constant(index).unwrap().clone()),

                Instruction::Call {
                    arguments_count,
                    location,
                } => self.call_function(arguments_count, location)?,

                Instruction::Return => {
                    if let Some(link) = self.link {
                        self.ip = link;
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
        let stack_index = self.stack.len() - 1;

        self.names.insert(
            name,
            NameInfo {
                stack_index,
                mutable,
            },
        );
    }

    fn load_name(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let Some(name_info) = self.names.get(&name) else {
            return Err(SyphonError::undefined(location, "name", &name));
        };

        let value = self.stack.get(name_info.stack_index).unwrap().clone();

        self.stack.push(value);

        Ok(())
    }

    fn assign(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let Some(past_name_info) = self.names.get(&name) else {
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

        self.names.insert(
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
        let Some(callable) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "callable"));
        };

        let Value::Function {
            parameters, body, ..
        } = callable
        else {
            return Err(SyphonError::expected(location, "callable"));
        };

        if arguments_count != parameters.len() {
            return Err(SyphonError::expected(
                location,
                match parameters.len() {
                    1 => format!("{} argument", parameters.len()),
                    _ => format!("{} arguments", parameters.len()),
                }
                .as_str(),
            ));
        }

        let previous_names = self.names.clone();

        for i in 0..arguments_count {
            let argument_stack_index = self.stack.len() - 1 - i;

            self.names.insert(
                parameters[i].clone(),
                NameInfo {
                    stack_index: argument_stack_index,
                    mutable: true,
                },
            );
        }

        let previous_stack_len = self.stack.len();

        let previous_constants = self.chunk.constants.clone();

        let previous_link = self.link;

        self.chunk.constants = body.constants.clone();

        self.link = Some(self.ip);

        let body_instructions_len = body.code.len();

        self.chunk.extend(body);

        self.ip = self.chunk.code.len() - body_instructions_len;

        let return_value = self.run()?;

        self.link = previous_link;

        for _ in 0..self.stack.len() - previous_stack_len {
            self.stack.pop().unwrap();
        }

        for _ in 0..body_instructions_len {
            self.chunk.code.pop().unwrap();
        }

        self.names = previous_names;

        self.chunk.constants = previous_constants;

        self.stack.push(return_value);

        Ok(())
    }

    fn jump_if_false(&mut self, offset: usize, location: Location) -> Result<(), SyphonError> {
        let Some(value) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        if !value.is_truthy() {
            self.ip += offset;
        }

        Ok(())
    }

    fn jump(&mut self, offset: usize) {
        self.ip += offset;
    }

    fn back(&mut self, offset: usize) {
        self.ip -= offset + 1;
    }
}
