use derive_more::Display;

#[derive(Display, Clone)]
pub enum Value {
    #[display(fmt = "{}", _0)]
    Int(u64),
    #[display(fmt = "{}", _0)]
    Float(f64),
    #[display(fmt = "none")]
    None,
}
