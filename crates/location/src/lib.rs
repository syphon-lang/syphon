use derive_more::Display;

#[derive(Debug, Display, PartialEq, Clone, Copy)]
#[display(fmt = "{line}:{column}")]
pub struct Location {
    pub line: usize,
    pub column: usize,
}

impl Location {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();

        bytes.extend(self.line.to_be_bytes());
        bytes.extend(self.column.to_be_bytes());

        bytes
    }

    pub fn from_bytes(bytes: &mut impl Iterator<Item = u8>) -> Location {
        fn get_8_bytes(bytes: &mut impl Iterator<Item = u8>) -> [u8; 8] {
            [
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
                bytes.next().unwrap(),
            ]
        }

        let line = usize::from_be_bytes(get_8_bytes(bytes));
        let column = usize::from_be_bytes(get_8_bytes(bytes));

        Location { line, column }
    }
}

impl Default for Location {
    fn default() -> Self {
        Self { line: 1, column: 1 }
    }
}
