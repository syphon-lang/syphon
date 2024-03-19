use std::mem::MaybeUninit;

pub struct Stack<T, const N: usize> {
    data: Box<[MaybeUninit<T>]>,

    top_pointer: *mut MaybeUninit<T>,
    top_index: usize,
}

impl<T, const N: usize> Stack<T, N> {
    pub fn new() -> Self {
        unsafe {
            let mut data = Vec::with_capacity(N);

            for _ in 0..N {
                data.push(MaybeUninit::uninit());
            }

            let mut stack = Stack {
                data: data.into_boxed_slice(),

                top_pointer: std::ptr::null_mut(),
                top_index: 0,
            };

            stack.top_pointer = stack.data.get_unchecked_mut(0);

            stack
        }
    }

    pub fn push(&mut self, value: T) {
        unsafe {
            self.top_pointer.write(MaybeUninit::new(value));

            self.top_pointer = self.top_pointer.add(1);
            self.top_index += 1;
        }
    }

    pub fn pop(&mut self) -> T {
        unsafe {
            self.top_pointer = self.top_pointer.sub(1);
            self.top_index -= 1;

            self.top_pointer.read().assume_init()
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
            self.top_pointer = self.top_pointer.sub(amount);
            self.top_index -= amount;

            std::slice::from_raw_parts(self.top_pointer as *const _, amount)
        }
    }

    #[inline]
    pub fn truncate(&mut self, length: usize) {
        unsafe {
            self.top_pointer = std::ptr::from_mut(self.data.get_unchecked_mut(length));
            self.top_index = length;
        }
    }

    #[inline]
    pub fn top(&self) -> &T {
        unsafe {
            self.top_pointer
                .sub(1)
                .as_ref()
                .unwrap_unchecked()
                .assume_init_ref()
        }
    }

    #[inline]
    pub fn top_mut(&mut self) -> &mut T {
        unsafe {
            self.top_pointer
                .sub(1)
                .as_mut()
                .unwrap_unchecked()
                .assume_init_mut()
        }
    }

    #[inline]
    pub fn len(&self) -> usize {
        self.top_index
    }
}
