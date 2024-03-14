use syphon_bytecode::chunk::{Atom, Chunk};
use syphon_bytecode::instruction::Instruction;
use syphon_bytecode::value::{Function, NativeFunction, Value};

use syphon_errors::SyphonError;
use syphon_location::Location;

use rustc_hash::FxHashMap;

use std::io::{stdout, BufWriter, Write};
use std::sync::Arc;

#[derive(Clone)]
pub struct Local {
    stack_index: usize,
    mutable: bool,
}

struct CallFrame {
    function: Arc<Function>,
    ip: usize,

    locals: FxHashMap<Atom, Local>,
}

pub struct VirtualMachine {
    frames: Vec<CallFrame>,
    fp: usize,

    stack: Vec<Value>,

    globals: FxHashMap<Atom, Value>,
}

impl VirtualMachine {
    pub fn new() -> VirtualMachine {
        VirtualMachine {
            frames: Vec::new(),
            fp: 0,

            stack: Vec::with_capacity(256),

            globals: FxHashMap::default(),
        }
    }

    pub fn init_globals(&mut self) {
        let print_atom = Atom::new("print".to_owned());

        let println_atom = Atom::new("println".to_owned());

        let print_fn = NativeFunction {
            name: print_atom.get_name(),
            call: |args| {
                let lock = stdout().lock();

                let mut writer = BufWriter::new(lock);

                if args.len() == 1 {
                    let _ = write!(writer, "{}", args[0]);
                } else {
                    for value in args {
                        let _ = write!(writer, "{} ", value);
                    }
                }

                Value::None
            },
        };

        let println_fn = NativeFunction {
            name: println_atom.get_name(),
            call: |args| {
                let lock = stdout().lock();

                let mut writer = BufWriter::new(lock);

                for value in args {
                    let _ = write!(writer, "{} ", value);
                }

                let _ = writeln!(writer);

                Value::None
            },
        };

        self.globals
            .insert(print_atom, Value::NativeFunction(print_fn.into()));

        self.globals
            .insert(println_atom, Value::NativeFunction(println_fn.into()));
    }

    pub fn load_chunk(&mut self, chunk: Chunk) {
        let function = Function {
            name: String::new(),
            body: chunk,
            parameters: Vec::new(),
        }
        .into();

        if self.frames.is_empty() {
            self.frames.push(CallFrame {
                function,
                locals: FxHashMap::default(),
                ip: 0,
            });
        } else {
            self.frames[0].function = function;
            self.frames[0].ip = 0;
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        while self.frames[self.fp].ip < self.frames[self.fp].function.body.code.len() {
            self.frames[self.fp].ip += 1;

            match self.frames[self.fp].function.body.code[self.frames[self.fp].ip - 1] {
                Instruction::Neg { location } => self.negative(location)?,

                Instruction::LogicalNot => self.logical_not()?,

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

                Instruction::StoreName { atom, mutable } => self.store_name(atom, mutable),

                Instruction::LoadName { atom, location } => self.load_name(atom, location)?,

                Instruction::Assign { atom, location } => self.assign(atom, location)?,

                Instruction::LoadConstant { index } => self.stack.push(
                    self.frames[self.fp]
                        .function
                        .body
                        .get_constant(index)
                        .clone(),
                ),

                Instruction::Call {
                    arguments_count,
                    location,
                } => self.call_function(arguments_count, location)?,

                Instruction::Return => {
                    return Ok(match self.stack.pop() {
                        Some(value) => value,
                        None => Value::None,
                    });
                }

                Instruction::JumpIfFalse { offset } => self.jump_if_false(offset)?,

                Instruction::Jump { offset } => self.jump(offset),

                Instruction::Back { offset } => self.back(offset),
            }
        }

        Ok(Value::None)
    }

    fn negative(&mut self, location: Location) -> Result<(), SyphonError> {
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        self.stack.push(match right {
            Value::Int(value) => Value::Int(-value),
            Value::Float(value) => Value::Float(-value),

            _ => return Err(SyphonError::unable_to(location, "apply '-' unary operator")),
        });

        Ok(())
    }

    fn logical_not(&mut self) -> Result<(), SyphonError> {
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        self.stack.push(match right {
            Value::Int(value) => Value::Bool(value == 0),
            Value::Float(value) => Value::Bool(value == 0.0),
            Value::Bool(value) => Value::Bool(!value),
            _ => Value::Bool(false),
        });

        Ok(())
    }

    fn add(&mut self, location: Location) -> Result<(), SyphonError> {
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

        self.stack.push(match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left + right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 + right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left + right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left + right),
            (Value::String(left), Value::String(right)) => {
                let mut string = String::with_capacity(left.len() + right.len());

                string.push_str(left.as_str());
                string.push_str(right.as_str());

                Value::String(string.into())
            }

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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
        let right = unsafe { self.stack.pop().unwrap_unchecked() };

        let left = unsafe { self.stack.pop().unwrap_unchecked() };

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

    fn store_name(&mut self, atom: Atom, mutable: bool) {
        let frame = &mut self.frames[self.fp];

        let stack_index = self.stack.len() - 1;

        frame.locals.insert(
            atom,
            Local {
                stack_index,
                mutable,
            },
        );
    }

    fn load_name(&mut self, atom: Atom, location: Location) -> Result<(), SyphonError> {
        let frame = &self.frames[self.fp];

        let value = match frame.locals.get(&atom) {
            Some(name_info) => self.stack.get(name_info.stack_index),

            None => self.globals.get(&atom),
        };

        match value {
            Some(value) => {
                self.stack.push(value.clone());

                Ok(())
            }

            None => Err(SyphonError::undefined(
                location,
                "name",
                atom.get_name().as_str(),
            )),
        }
    }

    fn assign(&mut self, atom: Atom, location: Location) -> Result<(), SyphonError> {
        let frame = &mut self.frames[self.fp];

        let Some(past_name_info) = frame.locals.get(&atom) else {
            return Err(SyphonError::undefined(
                location,
                "name",
                atom.get_name().as_str(),
            ));
        };

        let new_value = unsafe { self.stack.last().unwrap_unchecked() };

        if !past_name_info.mutable {
            return Err(SyphonError::unable_to(location, "assign to a constant"));
        }

        self.stack[past_name_info.stack_index] = new_value.clone();

        Ok(())
    }

    fn call_function(
        &mut self,
        arguments_count: usize,
        location: Location,
    ) -> Result<(), SyphonError> {
        let callee = unsafe { self.stack.pop().unwrap_unchecked() };

        let mut arguments = self.stack.split_off(self.stack.len() - arguments_count);
    
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
                    locals: previous_frame.locals.clone(),
                    ip: 0,
                });

                self.fp += 1;

                let new_frame = &mut self.frames[self.fp];

                let previous_stack_len = self.stack.len();

                for parameter in new_frame.function.parameters.iter() {
                    self.stack
                        .push(unsafe { arguments.pop().unwrap_unchecked() });

                    let stack_index = self.stack.len() - 1;

                    new_frame.locals.insert(
                        Atom::get(parameter),
                        Local {
                            stack_index,
                            mutable: true,
                        },
                    );
                }

                let return_value = self.run();

                self.stack.truncate(previous_stack_len);

                self.fp -= 1;

                self.frames.pop();

                self.stack.push(return_value?);
            }

            Value::NativeFunction(function) => {
                let return_value = (function.call)(arguments);

                self.stack.push(return_value);
            }

            _ => return Err(SyphonError::expected(location, "a callable")),
        }

        Ok(())
    }

    fn jump_if_false(&mut self, offset: usize) -> Result<(), SyphonError> {
        let frame = &mut self.frames[self.fp];

        let value = unsafe { self.stack.pop().unwrap_unchecked() };

        if !value.is_truthy() {
            frame.ip += offset;
        }

        Ok(())
    }

    #[inline]
    fn jump(&mut self, offset: usize) {
        let frame = &mut self.frames[self.fp];

        frame.ip += offset;
    }

    #[inline]
    fn back(&mut self, offset: usize) {
        let frame = &mut self.frames[self.fp];

        frame.ip -= offset + 1;
    }
}
