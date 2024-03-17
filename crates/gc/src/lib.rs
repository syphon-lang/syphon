use std::any::Any;
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
        Self {
            index: self.index,
            phantom: PhantomData,
        }
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
    grey_stack: Vec<usize>,
    allocated: usize,
    next_gc: usize,
}

impl GarbageCollector {
    const HEAP_GROW_FACTOR: usize = 2;

    pub fn new() -> GarbageCollector {
        GarbageCollector {
            objects: Vec::new(),
            free_slots: Vec::new(),
            grey_stack: Vec::new(),
            allocated: 0,
            next_gc: 1024,
        }
    }

    pub fn alloc<T: Trace + 'static>(&mut self, value: T) -> Ref<T> {
        let size = std::mem::size_of_val(&value) + std::mem::size_of::<ObjectHeader>();

        self.allocated += size;

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

        Ref {
            index,
            phantom: PhantomData,
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

            object_header.marked = true;

            self.grey_stack.push(reference.index);
        }
    }

    fn blacken(&mut self, index: usize) {
        let object = self.objects[index].take().unwrap();
        object.data.trace(self);
        self.objects[index] = Some(object);
    }

    fn trace_references(&mut self) {
        while let Some(index) = self.grey_stack.pop() {
            self.blacken(index);
        }
    }

    fn free(&mut self, index: usize) {
        let old = self.objects[index].take().unwrap();

        self.allocated -= old.size;

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
        self.allocated > self.next_gc
    }

    pub fn collect_garbage(&mut self) {
        self.trace_references();

        self.sweep();

        self.next_gc = self.allocated * GarbageCollector::HEAP_GROW_FACTOR;
    }
}
