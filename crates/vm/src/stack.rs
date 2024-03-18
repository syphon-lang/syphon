use std::mem::MaybeUninit;

pub struct Stack<T, const N: usize> {
    data: [MaybeUninit<T>; N],

    index: usize,
}

impl<T, const N: usize> Stack<T, N> {
    const INIT: MaybeUninit<T> = MaybeUninit::uninit();

    pub fn new() -> Self {
        Stack {
            data: [Self::INIT; N],

            index: 0,
        }
    }

    pub fn push(&mut self, value: T) {
        unsafe {
            *self.data.get_unchecked_mut(self.index) = MaybeUninit::new(value);

            self.index += 1;
        }
    }

    pub fn pop(&mut self) -> T {
        unsafe {
            self.index -= 1;

            (self.data.get_unchecked_mut(self.index).as_ptr()).read()
        }
    }

    #[inline]
    pub fn get(&self, index: usize) -> &T {
        unsafe { self.data.get_unchecked(index).assume_init_ref() }
    }

    #[inline]
    pub fn get_mut(&mut self, index: usize) -> &mut T {
        unsafe { self.data.get_unchecked_mut(index).assume_init_mut() }
    }

    pub fn pop_multiple(&mut self, amount: usize) -> &[T] {
        unsafe {
            self.index -= amount;

            std::slice::from_raw_parts(self.data.get_unchecked_mut(self.index).as_ptr(), amount)
        }
    }

    #[inline]
    pub fn truncate(&mut self, length: usize) {
        self.index = length;
    }

    #[inline]
    pub fn top(&self) -> &T {
        unsafe { self.data.get_unchecked(self.index - 1).assume_init_ref() }
    }

    #[inline]
    pub fn top_mut(&mut self) -> &mut T {
        unsafe {
            self.data
                .get_unchecked_mut(self.index - 1)
                .assume_init_mut()
        }
    }

    #[inline]
    pub fn len(&self) -> usize {
        self.index
    }
}
