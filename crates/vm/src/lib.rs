mod stack;

use stack::Stack;

use syphon_bytecode::chunk::{Atom, Chunk};
use syphon_bytecode::instruction::Instruction;
use syphon_bytecode::value::{Array, Function, NativeFunction, NativeFunctionCall, Value};

use syphon_ast::Location;
use syphon_errors::SyphonError;
use syphon_gc::{GarbageCollector, Ref, Trace, TraceFormatter};

use rustc_hash::FxHashMap;

use rand::{thread_rng, Rng};
use thin_vec::ThinVec;

use std::io::{stdout, BufWriter, Write};
use std::mem::MaybeUninit;
use std::process::exit;
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

    fn add_global_native(
        &mut self,
        name: &str,
        parameters_count: Option<usize>,
        call: NativeFunctionCall,
    ) {
        let atom = Atom::new(name.to_owned());

        self.globals.insert(
            atom,
            Value::NativeFunction(NativeFunction {
                name: atom,
                parameters_count,
                call,
            }),
        );
    }

    pub fn init_globals(&mut self) {
        self.add_global_native("print", None, |gc, args| {
            let lock = stdout().lock();

            let mut writer = BufWriter::new(lock);

            args.iter().enumerate().for_each(|(i, value)| {
                let _ = write!(writer, "{}", TraceFormatter::new(*value, gc));

                if i < args.len() - 1 {
                    let _ = write!(writer, " ");
                }
            });

            Value::None
        });

        self.add_global_native("println", None, |gc, args| {
            let lock = stdout().lock();

            let mut writer = BufWriter::new(lock);

            args.iter().for_each(|value| {
                let _ = write!(writer, "{} ", TraceFormatter::new(*value, gc));
            });

            let _ = writeln!(writer);

            Value::None
        });

        self.add_global_native("time", Some(0), |_, _| {
            let start_time = unsafe { START_TIME.assume_init() };

            Value::Int(start_time.elapsed().as_nanos() as i64)
        });

        self.add_global_native("random", Some(2), |_, args| {
            let mut rng = thread_rng();

            match (args[0], args[1]) {
                (Value::Int(min), Value::Int(max)) => {
                    let min = min as f64;
                    let max = max as f64;

                    if min == max {
                        return Value::Float(min);
                    }

                    Value::Float(rng.gen_range(if min > max { max..min } else { min..max }))
                }

                (Value::Int(min), Value::Float(max)) => {
                    let min = min as f64;

                    if min == max {
                        return Value::Float(min);
                    }

                    Value::Float(rng.gen_range(if min > max { max..min } else { min..max }))
                }

                (Value::Float(min), Value::Int(max)) => {
                    let max = max as f64;

                    if min == max {
                        return Value::Float(min);
                    }

                    Value::Float(rng.gen_range(if min > max { max..min } else { min..max }))
                }

                (Value::Float(min), Value::Float(max)) => {
                    if min == max {
                        return Value::Float(min);
                    }

                    Value::Float(rng.gen_range(if min > max { max..min } else { min..max }))
                }

                (_, _) => Value::None,
            }
        });

        self.add_global_native("exit", Some(1), |_, args| match args[0] {
            Value::Int(status_code) => exit(status_code.rem_euclid(256) as i32),

            _ => exit(1),
        });

        self.add_global_native("typeof", Some(1), |gc, args| match args[0] {
            Value::None => Value::String(gc.intern("none".to_owned())),

            Value::String(_) => Value::String(gc.intern("string".to_owned())),

            Value::Int(_) => Value::String(gc.intern("int".to_owned())),

            Value::Float(_) => Value::String(gc.intern("float".to_owned())),

            Value::Bool(_) => Value::String(gc.intern("bool".to_owned())),

            Value::Array(_) => Value::String(gc.intern("array".to_owned())),

            Value::Function(_) | Value::NativeFunction(_) => {
                Value::String(gc.intern("function".to_owned()))
            }
        })
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
        loop {
            if self.frames.len() >= VirtualMachine::MAX_FRAMES
                || self.stack.len() >= VirtualMachine::STACK_SIZE
            {
                return Err(SyphonError::StackOverflow);
            }

            self.mark_and_sweep();

            let frame = self.frames.top_mut();
            let function = self.gc.deref(frame.function);

            assert!(frame.ip < function.body.instructions.len());
            assert!(frame.ip < function.body.locations.len());

            let instruction = function.body.instructions[frame.ip];
            let instruction_location = function.body.locations[frame.ip];

            frame.ip += 1;

            match instruction {
                Instruction::Neg => self.negative(instruction_location)?,

                Instruction::LogicalNot => self.logical_not()?,

                Instruction::Add => self.add(instruction_location)?,

                Instruction::Sub => self.subtract(instruction_location)?,

                Instruction::Div => self.divide(instruction_location)?,

                Instruction::Mult => self.multiply(instruction_location)?,

                Instruction::Exponent => self.exponent(instruction_location)?,

                Instruction::Modulo => self.modulo(instruction_location)?,

                Instruction::LessThan => self.less_than(instruction_location)?,

                Instruction::GreaterThan => self.greater_than(instruction_location)?,

                Instruction::Equals => self.equals(instruction_location)?,

                Instruction::NotEquals => self.not_equals(instruction_location)?,

                Instruction::StoreName { atom, mutable } => self.store_name(atom, mutable),

                Instruction::LoadName { atom } => self.load_name(atom, instruction_location)?,

                Instruction::Assign { atom } => self.assign(atom, instruction_location)?,

                Instruction::LoadConstant { index } => {
                    let constant = *function.body.get_constant(index);

                    constant.trace(self.gc);

                    self.stack.push(constant);
                }

                Instruction::Call { arguments_count } => {
                    self.call_function(arguments_count, instruction_location)?
                }

                Instruction::Return => {
                    return Ok(self.stack.pop());
                }

                Instruction::JumpIfFalse { offset } => {
                    let value = self.stack.pop();

                    if !value.is_truthy(self.gc) {
                        frame.ip += offset;
                    }
                }

                Instruction::Jump { offset } => {
                    frame.ip += offset;
                }

                Instruction::Back { offset } => {
                    frame.ip -= offset + 1;
                }

                Instruction::Pop => {
                    self.stack.pop();
                }

                Instruction::MakeArray { length } => self.make_array(length),

                Instruction::LoadSubscript => self.load_subscript(instruction_location)?,

                Instruction::StoreSubscript => self.store_subscript(instruction_location)?,
            }
        }
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

                let value = self.gc.intern(string);

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

        self.stack.push(match (left, right) {
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

        self.stack.push(match (left, right) {
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

    fn check_arguments_count(
        &self,
        location: Location,
        parameters_count: usize,
        arguments_count: usize,
    ) -> Result<(), SyphonError> {
        if parameters_count != arguments_count {
            Err(SyphonError::expected_got(
                location,
                format!(
                    "{} {}",
                    parameters_count,
                    match parameters_count == 1 {
                        true => "argument",
                        false => "arguments",
                    }
                )
                .as_str(),
                arguments_count.to_string().as_str(),
            ))
        } else {
            Ok(())
        }
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

                self.check_arguments_count(location, function.parameters.len(), arguments_count)?;

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
                        self.stack.push(arguments[i]);

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
                if let Some(parameters_count) = function.parameters_count {
                    self.check_arguments_count(location, parameters_count, arguments_count)?;
                }

                let return_value = (function.call)(self.gc, arguments);

                return_value.trace(self.gc);

                self.stack.push(return_value);
            }

            _ => return Err(SyphonError::expected(location, "a callable")),
        }

        Ok(())
    }

    fn make_array(&mut self, length: usize) {
        let values = ThinVec::from(self.stack.pop_multiple(length));

        self.stack
            .push(Value::Array(self.gc.alloc(Array { values })));
    }

    fn load_subscript(&mut self, location: Location) -> Result<(), SyphonError> {
        let mut index = match self.stack.pop() {
            Value::Int(index) => index,

            _ => return Err(SyphonError::expected(location, "an index of type 'int'")),
        };

        let array = match self.stack.pop() {
            Value::Array(reference) => self.gc.deref(reference),

            _ => return Err(SyphonError::expected(location, "an array")),
        };

        if index.is_negative() {
            index += array.values.len() as i64;
        }

        if index.is_negative() || index >= array.values.len() as i64 {
            return Err(SyphonError::unable_to(
                location,
                "subscript the array, index out of bounds",
            ));
        }

        let result = array.values[index as usize];

        result.trace(self.gc);

        self.stack.push(result);

        Ok(())
    }

    fn store_subscript(&mut self, location: Location) -> Result<(), SyphonError> {
        let value = self.stack.pop();

        let mut index = match self.stack.pop() {
            Value::Int(index) => index,

            _ => return Err(SyphonError::expected(location, "an index of type 'int'")),
        };

        let array = match self.stack.pop() {
            Value::Array(reference) => self.gc.deref_mut(reference),

            _ => return Err(SyphonError::expected(location, "an array")),
        };

        if index.is_negative() {
            index += array.values.len() as i64;
        }

        if index.is_negative() || index >= array.values.len() as i64 {
            return Err(SyphonError::unable_to(
                location,
                "subscript the array, index out of bounds",
            ));
        }

        array.values[index as usize] = value;

        Ok(())
    }
}
