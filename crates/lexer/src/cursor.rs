use crate::span::Span;

use std::str::Chars;

#[derive(Clone)]
pub struct Cursor<'a> {
    chars: Chars<'a>,
    pub pos: usize,
}

impl<'a> Cursor<'a> {
    pub const fn new(chars: Chars) -> Cursor {
        Cursor { chars, pos: 0 }
    }

    #[inline]
    pub fn consume(&mut self) -> Option<char> {
        self.pos += 1;

        self.chars.next()
    }

    #[inline]
    pub fn peek(&self) -> Option<char> {
        self.chars.clone().next()
    }

    #[inline]
    pub fn span(&self) -> Span {
        Span::new(self.pos, self.pos)
    }
}
