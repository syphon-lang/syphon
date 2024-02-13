use derive_more::Display;

#[derive(Debug, Display, PartialEq, Clone, Copy)]
#[display(fmt = "{line}:{column}")]
pub struct Location {
    pub line: usize,
    pub column: usize,
}

impl Default for Location {
    fn default() -> Self {
        Self { line: 1, column: 0 }
    }
}
