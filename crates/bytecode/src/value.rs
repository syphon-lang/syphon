use crate::chunk::{Atom, Chunk};

use syphon_gc::{GarbageCollector, Ref, Trace};

#[derive(Clone, Copy, PartialEq)]
pub enum Value {
    None,

    String(Ref<String>),

    Int(i64),

    Float(f64),

    Bool(bool),

    Function(Ref<Function>),

    NativeFunction(NativeFunction),
}

#[derive(Clone, PartialEq)]
pub struct Function {
    pub name: Atom,
    pub parameters: Vec<String>,
    pub body: Chunk,
}

#[derive(Clone, Copy, PartialEq)]
pub struct NativeFunction {
    pub name: Atom,
    pub call: fn(&mut GarbageCollector, Vec<Value>) -> Value,
}

impl Value {
    #[inline]
    pub fn is_truthy(&self, gc: &GarbageCollector) -> bool {
        match self {
            Value::None => false,

            Value::String(value) => {
                let value = gc.deref(*value);

                !value.is_empty()
            }

            &Value::Int(value) => value != 0,

            &Value::Float(value) => value != 0.0,

            &Value::Bool(value) => value,

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

            _ => unreachable!(),
        }

        bytes
    }
}

impl Trace for Value {
    fn format(&self, gc: &GarbageCollector, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Value::None => write!(f, "none"),

            Value::String(reference) => {
                let value = gc.deref(*reference);

                value.format(gc, f)
            }

            Value::Int(value) => write!(f, "{}", value),
            Value::Float(value) => write!(f, "{}", value),
            Value::Bool(value) => write!(f, "{}", value),

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
