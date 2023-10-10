use derive_more::Display;

#[derive(Display, Clone)]
pub enum Value {
    #[display(fmt = "{}", _0)]
    Str(String),
    #[display(fmt = "{}", _0)]
    Int(i64),
    #[display(fmt = "{}", _0)]
    Float(f64),
    #[display(fmt = "{}", _0)]
    Bool(bool),
    #[display(fmt = "none")]
    None,
}
