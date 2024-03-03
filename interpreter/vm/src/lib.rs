use syphon_bytecode::chunk::*;
use syphon_bytecode::instructions::Instruction;
use syphon_bytecode::values::*;

use syphon_errors::SyphonError;
use syphon_location::Location;

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
                    function_name,
                    arguments_count,
                    location,
                } => self.call_function(function_name, arguments_count, location)?,

                Instruction::Return => return Ok(self.stack_top()),
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
            (Value::Str(left), Value::Str(right)) => Value::Str(left + right.as_str()),

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
            (Value::Str(left), Value::Str(right)) => Value::Bool(left == right),
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
            (Value::Str(left), Value::Str(right)) => Value::Bool(left != right),
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
        let value = self.stack.pop().unwrap();

        self.names.insert(name, ValueInfo { value, mutable });
    }

    fn load_name(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let Some(value_info) = self.names.get(&name) else {
            return Err(SyphonError::undefined(location, "name", &name));
        };

        self.stack.push(value_info.value.clone());

        Ok(())
    }

    fn assign(&mut self, name: String, location: Location) -> Result<(), SyphonError> {
        let Some(past_value_info) = self.names.get(&name) else {
            return Err(SyphonError::undefined(location, "name", &name));
        };

        let Some(value) = self.stack.pop() else {
            return Err(SyphonError::expected(location, "a value"));
        };

        if !past_value_info.mutable {
            return Err(SyphonError::unable_to(location, "assign to a constant"));
        }

        self.stack.push(value.clone());

        self.names.insert(
            name,
            ValueInfo {
                value,
                mutable: past_value_info.mutable,
            },
        );

        Ok(())
    }

    fn call_function(
        &mut self,
        function_name: String,
        arguments_count: usize,
        location: Location,
    ) -> Result<(), SyphonError> {
        let Some(value_info) = self.names.get(&function_name) else {
            return Err(SyphonError::undefined(location, "name", &function_name));
        };

        let Value::Function {
            parameters, body, ..
        } = value_info.value.clone()
        else {
            return Err(SyphonError::expected(location, "function"));
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

        Ok(())
    }

    fn stack_top(&mut self) -> Value {
        match self.stack.pop() {
            Some(value) => value,
            None => Value::None,
        }
    }
}
