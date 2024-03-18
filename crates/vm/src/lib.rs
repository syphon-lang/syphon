mod stack;

use stack::Stack;

use syphon_bytecode::chunk::{Atom, Chunk};
use syphon_bytecode::instruction::Instruction;
use syphon_bytecode::value::{Function, NativeFunction, Value};

use syphon_errors::SyphonError;
use syphon_gc::{GarbageCollector, Ref, Trace, TraceFormatter};
use syphon_location::Location;

use rustc_hash::FxHashMap;

use std::io::{stdout, BufWriter, Write};
use std::mem::MaybeUninit;
use std::time::Instant;

static mut START_TIME: MaybeUninit<Instant> = MaybeUninit::uninit();

#[derive(Clone)]
struct Local {
    stack_index: usize,
    mutable: bool,
}

struct Frame {
    function: Ref<Function>,
    ip: usize,

    locals: FxHashMap<Atom, Local>,

    stack_start: usize,
}

pub struct VirtualMachine<'a> {
    frames: Stack<Frame, { VirtualMachine::MAX_FRAMES }>,

    stack: Stack<Value, { VirtualMachine::STACK_SIZE }>,

    pub gc: &'a mut GarbageCollector,

    globals: FxHashMap<Atom, Value>,
}

impl<'a> VirtualMachine<'a> {
    const MAX_FRAMES: usize = 64;
    const STACK_SIZE: usize = VirtualMachine::MAX_FRAMES * (u8::MAX as usize + 1);

    pub fn new(gc: &mut GarbageCollector) -> VirtualMachine {
        unsafe { START_TIME.write(Instant::now()) };

        VirtualMachine {
            frames: Stack::new(),

            stack: Stack::new(),

            gc,

            globals: FxHashMap::default(),
        }
    }

    pub fn init_globals(&mut self) {
        let print_atom = Atom::new("print".to_owned());

        let print_fn = NativeFunction {
            name: print_atom,
            call: |gc, args| {
                let lock = stdout().lock();

                let mut writer = BufWriter::new(lock);

                args.iter().enumerate().for_each(|(i, value)| {
                    let _ = write!(writer, "{}", TraceFormatter::new(value.clone(), gc));

                    if i < args.len() - 1 {
                        let _ = write!(writer, " ");
                    }
                });

                Value::None
            },
        }
        .into();

        let println_atom = Atom::new("println".to_owned());

        let println_fn = NativeFunction {
            name: println_atom,
            call: |gc, args| {
                let lock = stdout().lock();

                let mut writer = BufWriter::new(lock);

                args.iter().for_each(|value| {
                    let _ = write!(writer, "{} ", TraceFormatter::new(value.clone(), gc));
                });

                let _ = writeln!(writer);

                Value::None
            },
        }
        .into();

        let time_atom = Atom::new("time".to_owned());

        let time_fn = NativeFunction {
            name: time_atom,
            call: |_, _| {
                let start_time = unsafe { START_TIME.assume_init() };

                Value::Int(start_time.elapsed().as_nanos() as i64)
            },
        }
        .into();

        self.globals
            .insert(print_atom, Value::NativeFunction(print_fn));

        self.globals
            .insert(println_atom, Value::NativeFunction(println_fn));

        self.globals
            .insert(time_atom, Value::NativeFunction(time_fn));
    }

    pub fn load_chunk(&mut self, chunk: Chunk) {
        if self.frames.len() == 0 {
            let function = self.gc.alloc(Function {
                name: Atom::new("script".to_owned()),
                body: chunk,
                parameters: Vec::new(),
            });

            self.frames.push(Frame {
                function,
                ip: 0,
                locals: FxHashMap::default(),
                stack_start: 0,
            });
        } else {
            self.gc.deref_mut(self.frames.top().function).body = chunk;
            self.frames.top_mut().ip = 0;
        }
    }

    fn mark_and_sweep(&mut self) {
        if self.gc.should_gc() {
            self.mark_roots();

            self.gc.collect_garbage();
        }
    }

    fn mark_roots(&mut self) {
        for i in 0..self.frames.len() {
            let frame = self.frames.get(i);

            self.gc.mark(frame.function);
        }

        for (_, value) in self.globals.iter() {
            value.trace(self.gc);
        }
    }

    pub fn run(&mut self) -> Result<Value, SyphonError> {
        while self.frames.top().ip < self.gc.deref(self.frames.top().function).body.code.len() {
            if self.frames.len() >= VirtualMachine::MAX_FRAMES
                || self.stack.len() >= VirtualMachine::STACK_SIZE
            {
                return Err(SyphonError::StackOverflow);
            }

            self.mark_and_sweep();

            self.frames.top_mut().ip += 1;

            let instruction = unsafe {
                self.gc
                    .deref(self.frames.top().function)
                    .body
                    .code
                    .get_unchecked(self.frames.top().ip - 1)
            };

            match *instruction {
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

                Instruction::LoadConstant { index } => {
                    let constant = *self
                        .gc
                        .deref(self.frames.top().function)
                        .body
                        .get_constant(index);

                    constant.trace(self.gc);

                    self.stack.push(constant);
                }

                Instruction::Call {
                    arguments_count,
                    location,
                } => self.call_function(arguments_count, location)?,

                Instruction::Return => {
                    let value = if self.stack.len() == 0 {
                        Value::None
                    } else {
                        self.stack.pop()
                    };

                    return Ok(value);
                }

                Instruction::JumpIfFalse { offset } => self.jump_if_false(offset)?,

                Instruction::Jump { offset } => self.jump(offset),

                Instruction::Back { offset } => self.back(offset),

                Instruction::Pop => {
                    self.stack.pop();
                }
            }
        }

        Ok(Value::None)
    }

    fn negative(&mut self, location: Location) -> Result<(), SyphonError> {
        let right = self.stack.pop();

        self.stack.push(match right {
            Value::Int(value) => Value::Int(-value),
            Value::Float(value) => Value::Float(-value),

            _ => return Err(SyphonError::unable_to(location, "apply '-' unary operator")),
        });

        Ok(())
    }

    #[inline]
    fn logical_not(&mut self) -> Result<(), SyphonError> {
        let right = self.stack.pop();

        self.stack.push(Value::Bool(!right.is_truthy(self.gc)));

        Ok(())
    }

    fn add(&mut self, location: Location) -> Result<(), SyphonError> {
        let right = self.stack.pop();

        let left = self.stack.pop();

        let value = match (left, right) {
            (Value::Int(left), Value::Int(right)) => Value::Int(left + right),
            (Value::Int(left), Value::Float(right)) => Value::Float(left as f64 + right),
            (Value::Float(left), Value::Int(right)) => Value::Float(left + right as f64),
            (Value::Float(left), Value::Float(right)) => Value::Float(left + right),
            (Value::String(left_reference), Value::String(right_reference)) => {
                let left = self.gc.deref(left_reference);
                let right = self.gc.deref(right_reference);

                let mut string = String::with_capacity(left.len() + right.len());

                string.push_str(left);
                string.push_str(right);

                let value = self.gc.alloc(string);

                self.gc.mark(value);

                Value::String(value)
            }

            _ => {
                return Err(SyphonError::unable_to(
                    location,
                    "apply '+' binary operator",
                ));
            }
        };

        self.stack.push(value);

        Ok(())
    }

    fn subtract(&mut self, location: Location) -> Result<(), SyphonError> {
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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
        let right = self.stack.pop();

        let left = self.stack.pop();

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

    #[inline]
    fn store_name(&mut self, atom: Atom, mutable: bool) {
        let frame = self.frames.top_mut();

        if let Some(past_local) = frame.locals.get_mut(&atom) {
            if past_local.stack_index >= frame.stack_start {
                let new_value = self.stack.pop();

                *self.stack.get_mut(past_local.stack_index) = new_value;
                past_local.mutable = mutable;

                return;
            }
        }

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
        let value = match self.frames.top().locals.get(&atom) {
            Some(name_info) => Some(self.stack.get(name_info.stack_index)),

            None => self.globals.get(&atom),
        };

        match value {
            Some(value) => {
                value.trace(self.gc);

                self.stack.push(*value);

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
        let Some(past_local) = self.frames.top().locals.get(&atom) else {
            return Err(SyphonError::undefined(
                location,
                "name",
                atom.get_name().as_str(),
            ));
        };

        if !past_local.mutable {
            return Err(SyphonError::unable_to(location, "assign to a constant"));
        }

        let new_value = self.stack.pop();

        *self.stack.get_mut(past_local.stack_index) = new_value;

        Ok(())
    }

    fn call_function(
        &mut self,
        arguments_count: usize,
        location: Location,
    ) -> Result<(), SyphonError> {
        let callee = self.stack.pop();

        let arguments = self.stack.pop_multiple(arguments_count).to_vec();

        match callee {
            Value::Function(reference) => {
                let function = self.gc.deref(reference);

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

                self.frames.push(Frame {
                    function: reference,
                    locals: self.frames.top().locals.clone(),
                    ip: 0,
                    stack_start: self.stack.len(),
                });

                function
                    .parameters
                    .iter()
                    .enumerate()
                    .for_each(|(i, parameter)| {
                        self.stack.push(arguments[arguments.len() - 1 - i]);

                        let stack_index = self.stack.len() - 1;

                        self.frames.top_mut().locals.insert(
                            Atom::get(parameter),
                            Local {
                                stack_index,
                                mutable: true,
                            },
                        );
                    });

                let return_value = self.run();

                self.stack.truncate(self.frames.top().stack_start);

                self.frames.pop();

                let return_value = return_value?;

                return_value.trace(self.gc);

                self.stack.push(return_value);
            }

            Value::NativeFunction(function) => {
                let return_value = (function.call)(self.gc, arguments);

                return_value.trace(self.gc);

                self.stack.push(return_value);
            }

            _ => return Err(SyphonError::expected(location, "a callable")),
        }

        Ok(())
    }

    #[inline]
    fn jump_if_false(&mut self, offset: usize) -> Result<(), SyphonError> {
        let value = self.stack.pop();

        if !value.is_truthy(self.gc) {
            self.frames.top_mut().ip += offset;
        }

        Ok(())
    }

    #[inline]
    fn jump(&mut self, offset: usize) {
        self.frames.top_mut().ip += offset;
    }

    #[inline]
    fn back(&mut self, offset: usize) {
        self.frames.top_mut().ip -= offset + 1;
    }
}
