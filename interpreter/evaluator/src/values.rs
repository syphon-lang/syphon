use crate::*;

use std::fmt::Display;

#[derive(Clone)]
pub enum Value {
    Str(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    Return(Box<Value>),
    Function {
        name: String,
        parameters: ThinVec<FunctionParameter>,
        body: ThinVec<Node>,
        env: Environment,
    },
    None,
}

impl Display for Value {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Value::Str(content) => write!(f, "{}", content),
            Value::Int(value) => write!(f, "{}", value),
            Value::Float(value) => write!(f, "{}", value),
            Value::Bool(value) => write!(f, "{}", value),
            Value::Return(value) => write!(f, "{}", *value),
            Value::Function { name, .. } => write!(f, "<function '{}'>", name),
            Value::None => write!(f, "none"),
        }
    }
}
