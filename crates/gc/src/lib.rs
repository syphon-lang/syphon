use std::any::Any;
use std::collections::HashMap;
use std::marker::PhantomData;

pub trait Trace {
    fn format(&self, gc: &GarbageCollector, f: &mut std::fmt::Formatter) -> std::fmt::Result;
    fn trace(&self, gc: &mut GarbageCollector);
    fn as_any(&self) -> &dyn Any;
    fn as_any_mut(&mut self) -> &mut dyn Any;
}

impl Trace for String {
    fn format(&self, _: &GarbageCollector, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", self)
    }

    fn trace(&self, _: &mut GarbageCollector) {}

    #[inline]
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    #[inline]
    fn as_any_mut(&mut self) -> &mut dyn std::any::Any {
        self
    }
}

pub struct TraceFormatter<'a, T: Trace> {
    object: T,
    gc: &'a GarbageCollector,
}

impl<'a, T: Trace> TraceFormatter<'a, T> {
    pub fn new(object: T, gc: &GarbageCollector) -> TraceFormatter<T> {
        TraceFormatter { object, gc }
    }
}

impl<'a, T: Trace> std::fmt::Display for TraceFormatter<'a, T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.object.format(self.gc, f)
    }
}

#[derive(PartialEq)]
pub struct Ref<T: ?Sized> {
    index: usize,
    phantom: PhantomData<T>,
}

impl<T: ?Sized> Copy for Ref<T> {}

impl<T: ?Sized> Clone for Ref<T> {
    fn clone(&self) -> Self {
        *self
    }
}

pub struct ObjectHeader {
    data: Box<dyn Trace>,
    marked: bool,
    size: usize,
}

pub struct GarbageCollector {
    objects: Vec<Option<ObjectHeader>>,
    free_slots: Vec<usize>,
    gray_stack: Vec<usize>,
    strings: HashMap<String, Ref<String>>,
    bytes_allocated: usize,
    next_gc: usize,
}

impl Default for GarbageCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl GarbageCollector {
    const HEAP_GROW_FACTOR: usize = 2;

    pub fn new() -> GarbageCollector {
        GarbageCollector {
            objects: Vec::new(),
            free_slots: Vec::new(),
            gray_stack: Vec::new(),
            strings: HashMap::new(),
            bytes_allocated: 0,
            next_gc: 1024 * 1024,
        }
    }

    pub fn alloc<T: Trace + 'static>(&mut self, value: T) -> Ref<T> {
        let size = std::mem::size_of_val(&value) + std::mem::size_of::<ObjectHeader>();

        self.bytes_allocated += size;

        let object_header = ObjectHeader {
            data: Box::new(value),
            marked: false,
            size,
        };

        let index = match self.free_slots.pop() {
            Some(free_slot) => {
                self.objects.insert(free_slot, Some(object_header));

                free_slot
            }

            None => {
                self.objects.push(Some(object_header));

                self.objects.len() - 1
            }
        };

        #[cfg(feature = "debug_log")]
        {
            println!(
                "alloc(size = {}, bytes_allocated = {}, next_gc = {}, index = {})",
                size, self.bytes_allocated, self.next_gc, index
            );
        }

        Ref {
            index,
            phantom: PhantomData,
        }
    }

    pub fn intern(&mut self, value: String) -> Ref<String> {
        if let Some(reference) = self.strings.get(&value) {
            *reference
        } else {
            let reference = self.alloc(value.clone());

            self.strings.insert(value, reference);

            reference
        }
    }

    #[inline]
    pub fn deref<T: Trace + 'static>(&self, reference: Ref<T>) -> &T {
        self.objects[reference.index]
            .as_ref()
            .unwrap()
            .data
            .as_any()
            .downcast_ref()
            .unwrap()
    }

    #[inline]
    pub fn deref_mut<T: Trace + 'static>(&mut self, reference: Ref<T>) -> &mut T {
        self.objects[reference.index]
            .as_mut()
            .unwrap()
            .data
            .as_any_mut()
            .downcast_mut()
            .unwrap()
    }

    pub fn mark<T: Trace>(&mut self, reference: Ref<T>) {
        if let Some(object_header) = self.objects[reference.index].as_mut() {
            if object_header.marked {
                return;
            }

            #[cfg(feature = "debug_log")]
            println!(
                "mark(size = {}, index = {})",
                object_header.size, reference.index
            );

            object_header.marked = true;

            self.gray_stack.push(reference.index);
        }
    }

    fn blacken(&mut self, index: usize) {
        if let Some(object_header) = self.objects[index].take() {
            object_header.data.trace(self);

            #[cfg(feature = "debug_log")]
            println!("blacken(size = {}, index = {})", object_header.size, index);

            self.objects[index] = Some(object_header);
        }
    }

    fn trace_references(&mut self) {
        while let Some(index) = self.gray_stack.pop() {
            self.blacken(index);
        }
    }

    fn remove_white_strings(&mut self) {
        self.strings.retain(|_, v| {
            self.objects
                .get(v.index)
                .unwrap()
                .as_ref()
                .is_some_and(|obj| obj.marked)
        });
    }

    fn free(&mut self, index: usize) {
        let old = self.objects[index].take().unwrap();

        #[cfg(feature = "debug_log")]
        println!("free(size = {}, index = {})", old.size, index);

        self.bytes_allocated -= old.size;

        self.free_slots.push(index);
    }

    fn sweep(&mut self) {
        for index in 0..self.objects.len() {
            if let Some(object_header) = self.objects[index].as_mut() {
                if object_header.marked {
                    object_header.marked = false;
                } else {
                    self.free(index);
                }
            }
        }
    }

    pub fn should_gc(&self) -> bool {
        self.bytes_allocated > self.next_gc
    }

    pub fn collect_garbage(&mut self) {
        #[cfg(feature = "debug_log")]
        let before = self.bytes_allocated;

        self.trace_references();
        self.remove_white_strings();
        self.sweep();

        self.next_gc = self.bytes_allocated * GarbageCollector::HEAP_GROW_FACTOR;

        #[cfg(feature = "debug_log")]
        println!(
            "collected(before = {}, after = {}, next = {})",
            before, self.bytes_allocated, self.next_gc
        );
    }
}
