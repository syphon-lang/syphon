use std::fmt::Display;

pub enum Value {
    Int(u64),
    Float(f64),
    None,
}

impl Display for Value {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Value::Int(value) => write!(f, "{}", value),
            Value::Float(value) => write!(f, "{}", value),
            Value::None => write!(f, "None"),
        }
    }
}
