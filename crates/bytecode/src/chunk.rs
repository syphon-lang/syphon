use crate::instruction::Instruction;
use crate::value::Value;

use syphon_ast::Location;
use syphon_gc::GarbageCollector;

use derive_more::Display;

use once_cell::sync::Lazy;

use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display)]
pub struct Atom(usize);

static ATOMS: Lazy<Mutex<HashMap<String, Atom>>> = Lazy::new(|| Mutex::new(HashMap::new()));

impl Atom {
    pub fn new(name: String) -> Atom {
        let mut atoms_lock = ATOMS.lock().unwrap();

        if let Some(atom) = atoms_lock.get(&name) {
            return *atom;
        }

        let atom = Atom(atoms_lock.len());

        atoms_lock.insert(name.to_owned(), atom);

        atom
    }

    pub fn get(name: &str) -> Atom {
        let atoms_lock = ATOMS.lock().unwrap();

        *atoms_lock.get(name).unwrap()
    }

    pub fn get_name(&self) -> String {
        let atoms_lock = ATOMS.lock().unwrap();

        atoms_lock
            .iter()
            .find_map(|(k, v)| if v == self { Some(k) } else { None })
            .unwrap()
            .to_owned()
    }

    pub fn from_be_bytes(bytes: [u8; std::mem::size_of::<usize>()]) -> Atom {
        Atom(usize::from_be_bytes(bytes))
    }

    pub fn to_be_bytes(&self) -> [u8; std::mem::size_of::<usize>()] {
        self.0.to_be_bytes()
    }
}

#[derive(Default, Clone, PartialEq)]
pub struct Chunk {
    pub instructions: Vec<Instruction>,
    pub locations: Vec<Location>,
    pub constants: Vec<Value>,
}

impl Chunk {
    #[inline]
    pub fn add_constant(&mut self, value: Value) -> usize {
        self.constants.iter().position(|c| c == &value).unwrap_or({
            self.constants.push(value);

            self.constants.len() - 1
        })
    }

    #[inline]
    pub fn get_constant(&self, index: usize) -> &Value {
        unsafe { self.constants.get_unchecked(index) }
    }

    pub fn to_bytes(&self, gc: &GarbageCollector) -> Vec<u8> {
        let mut bytes = Vec::new();

        let atoms_lock = ATOMS.lock().unwrap();

        bytes.extend(atoms_lock.len().to_be_bytes());
        atoms_lock.iter().for_each(|(name, atom)| {
            bytes.extend(name.len().to_be_bytes());
            bytes.extend(name.as_bytes());

            bytes.extend(atom.to_be_bytes());
        });

        drop(atoms_lock);

        bytes.extend(self.constants.len().to_be_bytes());
        for constant in self.constants.iter() {
            bytes.extend(constant.to_bytes(gc));
        }

        bytes.extend(self.locations.len().to_be_bytes());
        for location in self.instructions.iter() {
            bytes.extend(location.to_bytes());
        }

        bytes.extend(self.instructions.len().to_be_bytes());
        self.instructions.iter().for_each(|instruction| {
            bytes.extend(instruction.to_bytes());
        });

        bytes
    }

    pub fn parse(bytes: &mut impl Iterator<Item = u8>, gc: &mut GarbageCollector) -> Chunk {
        let mut chunk = Chunk::default();

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

        fn get_multiple(bytes: &mut impl Iterator<Item = u8>, len: usize) -> Vec<u8> {
            let mut data = Vec::with_capacity(len);

            for _ in 0..len {
                data.push(bytes.next().unwrap());
            }

            data
        }

        let mut atoms_lock = ATOMS.lock().unwrap();

        let atoms_len = usize::from_be_bytes(get_8_bytes(bytes));
        for _ in 0..atoms_len {
            let name_len = usize::from_be_bytes(get_8_bytes(bytes));
            let name = String::from_utf8(get_multiple(bytes, name_len)).unwrap();

            let atom = Atom::from_be_bytes(get_8_bytes(bytes));

            atoms_lock.insert(name, atom);
        }

        drop(atoms_lock);

        let constants_len = usize::from_be_bytes(get_8_bytes(bytes));
        for _ in 0..constants_len {
            let constant_tag = bytes.next().unwrap();

            chunk.add_constant(Value::from_bytes(bytes, gc, constant_tag));
        }

        let locations_len = usize::from_be_bytes(get_8_bytes(bytes));
        for _ in 0..locations_len {
            let location = Location::from_bytes(bytes);

            chunk.locations.push(location);
        }

        let instructions_len = usize::from_be_bytes(get_8_bytes(bytes));
        for _ in 0..instructions_len {
            let instruction_tag = bytes.next().unwrap();

            chunk
                .instructions
                .push(Instruction::from_bytes(bytes, instruction_tag));
        }

        chunk
    }
}
