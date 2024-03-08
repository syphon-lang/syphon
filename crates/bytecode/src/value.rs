use crate::chunk::Chunk;

use derive_more::Display;

#[derive(Display, Clone, PartialEq)]
pub enum Value {
    #[display(fmt = "none")]
    None,

    String(String),

    Int(i64),

    Float(f64),

    Bool(bool),

    #[display(fmt = "<function '{}'>", name)]
    Function {
        name: String,
        parameters: Vec<String>,
        body: Chunk,
    },
}

impl Value {
    pub fn is_truthy(&self) -> bool {
        match self {
            Value::None => false,

            Value::String(value) => !value.is_empty(),

            &Value::Int(value) => value != 0,

            &Value::Float(value) => value != 0.0,

            &Value::Bool(value) => value == true,

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

            Value::Function {
                name,
                parameters,
                body,
            } => {
                bytes.push(6);

                bytes.extend(name.len().to_be_bytes());
                bytes.extend(name.as_bytes());

                bytes.extend(parameters.len().to_be_bytes());
                for parameter in parameters {
                    bytes.extend(parameter.len().to_be_bytes());
                    bytes.extend(parameter.as_bytes());
                }

                bytes.extend(body.to_bytes());
            }
        }

        bytes
    }
}
