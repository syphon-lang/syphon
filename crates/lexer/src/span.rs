use std::ops::Add;

#[derive(Debug, Clone, Copy)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn new(start: usize, end: usize) -> Span {
        Span { start, end }
    }

    pub fn to(&self, other: Span) -> Span {
        Span {
            start: self.start,
            end: other.end,
        }
    }
}

impl Add<usize> for Span {
    type Output = Span;

    fn add(self, rhs: usize) -> Self::Output {
        Span {
            start: self.start + rhs,
            end: self.end + rhs,
        }
    }
}
