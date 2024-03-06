use crate::chunk::Chunk;

use derive_more::Display;

use thin_vec::ThinVec;

#[derive(Display, Clone, PartialEq)]
pub enum Value {
    String(String),

    Int(i64),

    Float(f64),

    Bool(bool),

    #[display(fmt = "<function '{}'>", name)]
    Function {
        name: String,
        parameters: ThinVec<String>,
        body: Chunk,
    },

    #[display(fmt = "none")]
    None,
}
