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
                Instruction::Neg { at } => self.negative(at)?,

                Instruction::LogicalNot { at } => self.logical_not(at)?,

                Instruction::Add { at } => self.add(at)?,

                Instruction::Sub { at } => self.subtract(at)?,

                Instruction::Div { at } => self.divide(at)?,

                Instruction::Mult { at } => self.multiply(at)?,

                Instruction::Exponent { at } => self.exponent(at)?,

                Instruction::Modulo { at } => self.modulo(at)?,

                Instruction::LessThan { at } => self.less_than(at)?,

                Instruction::GreaterThan { at } => self.greater_than(at)?,

                Instruction::Equals { at } => self.equals(at)?,

                Instruction::NotEquals { at } => self.not_equals(at)?,

                Instruction::StoreName { name, mutable } => self.store_name(name, mutable),

                Instruction::LoadName { name, at } => self.load_name(name, at)?,

                Instruction::Assign { name, at } => self.assign(name, at)?,

                Instruction::LoadConstant { index } => self
                    .stack
                    .push(self.chunk.get_constant(index).unwrap().clone()),

                Instruction::Call {
                    function_name,
                    arguments_count,
                    at,
                } => self.call_function(function_name, arguments_count, at)?,

                Instruction::Return => return Ok(self.stack_top()),
            }
        }

        Ok(Value::None)
    }

    fn negative(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match right {
            Value::Int(value) => Value::Int(-value),
            Value::Float(value) => Value::Float(-value),

            _ => return Err(SyphonError::unable_to(at, "apply '-' unary operator")),
        });

        Ok(())
    }

    fn logical_not(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match right {
            Value::Int(value) => Value::Bool(value == 0),
            Value::Float(value) => Value::Bool(value == 0.0),
            Value::Bool(value) => Value::Bool(!value),
            _ => Value::Bool(false),
        });

        Ok(())
    }

    fn add(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left + right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 + right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left + right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left + right),
            (Value::Str(left), Value::Str(right)) => Value::Str(left + right.as_str()),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '+' binary operator"));
            }
        });

        Ok(())
    }

    fn subtract(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left - right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 - right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left - right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left - right),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '-' binary operator"));
            }
        });

        Ok(())
    }

    fn divide(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Float(left as f64 / right as f64),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 / right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left / right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left / right),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '/' binary operator"));
            }
        });

        Ok(())
    }

    fn multiply(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left * right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 * right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left * right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left * right),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '*' binary operator"));
            }
        });

        Ok(())
    }

    fn exponent(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Float((left as f64).powf(right as f64)),
            (Value::Int(left), Value::Float(right)) => Value::Float((left as f64).powf(right)),
            (Value::Float(left), Value::Int(right)) => Value::Float((left).powf(right as f64)),
            (Value::Float(left), Value::Float(right)) => Value::Float(left.powf(right)),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '**' binary operator"));
            }
        });

        Ok(())
    }

    fn modulo(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left % right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 % right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left % right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left % right),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '%' binary operator"));
            }
        });

        Ok(())
    }

    fn greater_than(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
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
        });

        Ok(())
    }

    fn less_than(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        self.stack.push(match (right, left) {
            (Value::Int(left), Value::Int(right)) => Value::Bool(left < right),
            (Value::Int(left), Value::Float(right)) => Value::Bool((left as f64) < right),
            (Value::Float(left), Value::Int(right)) => Value::Bool(left < right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Bool(left < right),

            _ => {
                return Err(SyphonError::unable_to(at, "apply '<' binary operator"));
            }
        });

        Ok(())
    }

    fn equals(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
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
                return Err(SyphonError::unable_to(at, "apply '==' binary operator"));
            }
        });

        Ok(())
    }

    fn not_equals(&mut self, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(right) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
        };

        let Some(left) = self.stack.pop() else {
            return Err(SyphonError::expected(at, "a value"));
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
                return Err(SyphonError::unable_to(at, "apply '!=' binary operator"));
            }
        });

        Ok(())
    }

    fn store_name(&mut self, name: String, mutable: bool) {
        let value = self.stack.pop().unwrap();

        self.names.insert(name, ValueInfo { value, mutable });
    }

    fn load_name(&mut self, name: String, at: (usize, usize)) -> Result<(), SyphonError> {
        let Some(value_info) = self.names.get(&name) else {
            return Err(SyphonError::undefined(at, "name", &name));
        };

        self.stack.push(value_info.value.clone());

        Ok(())
    }

    fn assign(&mut self, name: String, at: (usize, usize)) -> Result<(), SyphonError> {
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

        Ok(())
    }

    fn call_function(
        &mut self,
        function_name: String,
        arguments_count: usize,
        at: (usize, usize),
    ) -> Result<(), SyphonError> {
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

        Ok(())
    }

    fn stack_top(&mut self) -> Value {
        match self.stack.pop() {
            Some(value) => value,
            None => Value::None,
        }
    }
}
