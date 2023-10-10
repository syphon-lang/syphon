use derive_more::Display;

#[derive(Display, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    #[display(fmt = "none")]
    None,
}
