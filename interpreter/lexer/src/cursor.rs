use std::str::Chars;

#[derive(Clone)]
pub struct Cursor<'a> {
    chars: Chars<'a>,
    pub at: (usize, usize),
}

impl<'a> Cursor<'a> {
    pub fn new(chars: Chars) -> Cursor {
        Cursor { chars, at: (1, 0) }
    }

    pub fn consume(&mut self) -> Option<char> {
        let ch = self.chars.next();

        if ch.is_some_and(|ch| ch == '\n') {
            self.at.0 += 1
        } else if ch.is_some() {
            self.at.1 += 1
        }

        ch
    }

    pub fn peek(&self) -> Option<char> {
        self.chars.clone().next()
    }
}
