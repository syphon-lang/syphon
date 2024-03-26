use crate::chunk::{Atom, Chunk};

use syphon_gc::{GarbageCollector, Ref, Trace};

use thin_vec::ThinVec;

#[derive(Clone, Copy, PartialEq)]
pub enum Value {
    None,

    String(Ref<String>),

    Int(i64),

    Float(f64),

    Bool(bool),

    Array(Ref<Array>),

    Function(Ref<Function>),

    NativeFunction(NativeFunction),
}

#[derive(PartialEq)]
pub struct Array {
    pub values: ThinVec<Value>,
}

#[derive(PartialEq)]
pub struct Function {
    pub name: Atom,
    pub parameters: Vec<String>,
    pub body: Chunk,
}

#[derive(Clone, Copy, PartialEq)]
pub struct NativeFunction {
    pub name: Atom,
    pub parameters_count: Option<usize>,
    pub call: NativeFunctionCall,
}

pub type NativeFunctionCall = fn(&mut GarbageCollector, Vec<Value>) -> Value;
impl Value {
    #[inline]
    pub fn is_truthy(&self, gc: &GarbageCollector) -> bool {
        match self {
            Value::None => false,

            Value::String(reference) => {
                let value = gc.deref(*reference);

                !value.is_empty()
            }

            &Value::Int(value) => value != 0,

            &Value::Float(value) => value != 0.0,

            &Value::Bool(value) => value,

            Value::Array(reference) => {
                let value = gc.deref(*reference);

                !value.values.is_empty()
            }

            _ => true,
        }
    }

    pub fn to_bytes(&self, gc: &GarbageCollector) -> Vec<u8> {
        let mut bytes = Vec::new();

        match self {
            Value::None => {
                bytes.push(0);
            }

            Value::String(reference) => {
                let value = gc.deref(*reference);

                bytes.push(1);

                bytes.extend(value.len().to_be_bytes());
                bytes.extend(value.as_bytes());
            }

            Value::Int(value) => {
                bytes.push(2);
                bytes.extend(value.to_be_bytes());
            }

            Value::Float(value) => {
                bytes.push(3);
                bytes.extend(value.to_be_bytes());
            }

            Value::Bool(value) => match value {
                true => bytes.push(4),
                false => bytes.push(5),
            },

            Value::Function(reference) => {
                let function = gc.deref(*reference);

                bytes.push(6);

                bytes.extend(function.name.to_be_bytes());

                bytes.extend(function.parameters.len().to_be_bytes());
                function.parameters.iter().for_each(|parameter| {
                    bytes.extend(parameter.len().to_be_bytes());
                    bytes.extend(parameter.as_bytes());
                });

                bytes.extend(function.body.to_bytes(gc));
            }

            Value::Array(reference) => {
                let array = gc.deref(*reference);

                bytes.push(7);

                bytes.extend(array.values.len().to_be_bytes());
                for value in array.values.iter() {
                    if value == self {
                        bytes.push(8);
                    } else {
                        bytes.extend(value.to_bytes(gc));
                    }
                }
            }

            _ => unreachable!(),
        }

        bytes
    }

    pub fn from_bytes(
        bytes: &mut impl Iterator<Item = u8>,
        gc: &mut GarbageCollector,
        tag: u8,
    ) -> Value {
        fn get_8_bytes(bytes: &mut impl Iterator<Item = u8>) -> [u8; 8] {
            [
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
            ]
        }

        fn get_multiple(bytes: &mut impl Iterator<Item = u8>, len: usize) -> Vec<u8> {
            let mut data = Vec::with_capacity(len);

            for _ in 0..len {
                data.push(bytes.next().unwrap());
            }

            data
        }

        match tag {
            0 => Value::None,

            1 => {
                let string_len = usize::from_be_bytes(get_8_bytes(bytes));
                let string = String::from_utf8(get_multiple(bytes, string_len)).unwrap();

                Value::String(gc.intern(string))
            }

            2 => Value::Int(i64::from_be_bytes(get_8_bytes(bytes))),

            3 => Value::Float(f64::from_be_bytes(get_8_bytes(bytes))),

            4 => Value::Bool(true),

            5 => Value::Bool(false),

            6 => {
                let name = Atom::from_be_bytes(get_8_bytes(bytes));

                let parameters_len = usize::from_be_bytes(get_8_bytes(bytes));
                let mut parameters = Vec::with_capacity(parameters_len);

                for _ in 0..parameters_len {
                    let parameter_len = usize::from_be_bytes(get_8_bytes(bytes));
                    let parameter = String::from_utf8(get_multiple(bytes, parameter_len)).unwrap();

                    parameters.push(parameter);
                }

                let body = Chunk::parse(bytes, gc);

                Value::Function(gc.alloc(Function {
                    name,
                    parameters,
                    body,
                }))
            }

            7 => {
                let array_len = usize::from_be_bytes(get_8_bytes(bytes));

                let array_reference = gc.alloc(Array {
                    values: ThinVec::with_capacity(array_len),
                });

                for _ in 0..array_len {
                    let tag = bytes.next().unwrap();

                    let value = if tag == 8 {
                        Value::Array(array_reference)
                    } else {
                        Value::from_bytes(bytes, gc, tag)
                    };

                    gc.deref_mut(array_reference).values.push(value);
                }

                Value::Array(array_reference)
            }

            _ => unreachable!(),
        }
    }
}

impl Trace for Value {
    fn format(&self, gc: &GarbageCollector, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Value::None => write!(f, "none"),

            Value::String(reference) => {
                let string = gc.deref(*reference);

                string.format(gc, f)
            }

            Value::Int(value) => write!(f, "{}", value),
            Value::Float(value) => write!(f, "{}", value),
            Value::Bool(value) => write!(f, "{}", value),

            Value::Array(reference) => {
                let array = gc.deref(*reference);

                write!(f, "[")?;

                for (i, value) in array.values.iter().enumerate() {
                    if value == self {
                        write!(f, "[...]")?;
                    } else {
                        value.format(gc, f)?;
                    }

                    if i < array.values.len() - 1 {
                        write!(f, ", ")?;
                    }
                }

                write!(f, "]")?;

                Ok(())
            }

            Value::Function(reference) => {
                let function = gc.deref(*reference);

                function.format(gc, f)
            }

            Value::NativeFunction(function) => {
                write!(f, "<native function '{}'>", function.name.get_name())
            }
        }
    }

    fn trace(&self, gc: &mut GarbageCollector) {
        match self {
            Value::String(reference) => gc.mark(*reference),

            Value::Array(reference) => gc.mark(*reference),

            Value::Function(reference) => gc.mark(*reference),

            _ => (),
        }
    }

    fn as_any(&self) -> &dyn std::any::Any {
        unreachable!()
    }

    fn as_any_mut(&mut self) -> &mut dyn std::any::Any {
        unreachable!()
    }
}

impl Trace for Function {
    fn format(&self, _: &GarbageCollector, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "<function '{}'>", self.name.get_name())
    }

    fn trace(&self, gc: &mut GarbageCollector) {
        for constant in self.body.constants.iter() {
            constant.trace(gc);
        }
    }

    #[inline]
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    #[inline]
    fn as_any_mut(&mut self) -> &mut dyn std::any::Any {
        self
    }
}

impl Trace for Array {
    fn format(&self, _: &GarbageCollector, _: &mut std::fmt::Formatter) -> std::fmt::Result {
        unreachable!()
    }

    fn trace(&self, gc: &mut GarbageCollector) {
        for value in self.values.iter() {
            value.trace(gc);
        }
    }

    #[inline]
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    #[inline]
    fn as_any_mut(&mut self) -> &mut dyn std::any::Any {
        self
    }
}
