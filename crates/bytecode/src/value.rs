use crate::chunk::Chunk;

use derive_more::Display;

use std::sync::Arc;

#[derive(Display, Clone, PartialEq)]
pub enum Value {
    #[display(fmt = "none")]
    None,

    String(Arc<String>),

    Int(i64),

    Float(f64),

    Bool(bool),

    Function(Arc<Function>),

    NativeFunction(Arc<NativeFunction>),
}

#[derive(Display, Clone, PartialEq)]
#[display(fmt = "<function '{}'>", name)]
pub struct Function {
    pub name: String,
    pub parameters: Vec<String>,
    pub body: Chunk,
}

#[derive(Display, Clone, PartialEq)]
#[display(fmt = "<native function '{}'>", name)]
pub struct NativeFunction {
    pub name: String,
    pub call: fn(Vec<Value>) -> Value,
}

impl Value {
    #[inline]
    pub fn is_truthy(&self) -> bool {
        match self {
            Value::None => false,

            Value::String(value) => !value.is_empty(),

            &Value::Int(value) => value != 0,

            &Value::Float(value) => value != 0.0,

            &Value::Bool(value) => value,

            _ => true,
        }
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        match self {
            Value::None => {
                bytes.push(0);
            }

            Value::String(value) => {
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

            Value::Function(function) => {
                bytes.push(6);

                bytes.extend(function.name.len().to_be_bytes());
                bytes.extend(function.name.as_bytes());

                bytes.extend(function.name.len().to_be_bytes());
                for parameter in function.parameters.iter() {
                    bytes.extend(parameter.len().to_be_bytes());
                    bytes.extend(parameter.as_bytes());
                }

                bytes.extend(function.body.to_bytes());
            }

            _ => unreachable!(),
        }

        bytes
    }
}
