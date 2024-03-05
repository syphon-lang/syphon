use syphon_location::Location;

use std::str::Chars;

#[derive(Clone)]
pub struct Cursor<'a> {
    chars: Chars<'a>,
    pub location: Location,
}

impl<'a> Cursor<'a> {
    pub fn new(chars: Chars) -> Cursor {
        Cursor {
            chars,
            location: Location::default(),
        }
    }

    pub fn consume(&mut self) -> Option<char> {
        let ch = self.chars.next();

        if ch.is_some_and(|ch| ch == '\n') {
            self.location.line += 1;
            self.location.column = 1;
        } else if ch.is_some() {
            self.location.column += 1;
        }

        ch
    }

    pub fn peek(&self) -> Option<char> {
        self.chars.clone().next()
    }
}
