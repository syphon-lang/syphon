use crate::*;
use values::*;

use rustc_hash::FxHashMap;

#[derive(Clone)]
pub struct Environment {
    values: FxHashMap<String, Option<Value>>,
    outer: Option<Box<Environment>>,
}

impl Environment {
    pub fn new(outer: Option<Box<Environment>>) -> Environment {
        Environment {
            values: FxHashMap::default(),
            outer,
        }
    }

    pub fn get(&self, name: &str) -> Option<&Value> {
        match self.values.get(name) {
            Some(value) => value.as_ref(),
            None => match &self.outer {
                Some(outer) => match outer.values.get(name) {
                    Some(value) => value.as_ref(),
                    None => None,
                },
                None => None,
            },
        }
    }

    pub fn set(&mut self, name: String, value: Option<Value>) {
        self.values.insert(name, value);
    }

    pub fn set_multiple(&mut self, names: ThinVec<String>, values: ThinVec<Value>) {
        for (index, name) in names.iter().enumerate() {
            self.set(
                name.to_string(),
                Some(values.get(index).unwrap_or(&Value::None).clone()),
            )
        }
    }
}
