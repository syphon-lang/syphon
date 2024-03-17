use crate::runner;

use syphon_bytecode::value::Value;

use syphon_gc::{GarbageCollector, TraceFormatter};
use syphon_vm::VirtualMachine;

use std::io::{stdin, stdout, BufRead, BufReader, Write};

pub fn start() {
    let mut reader = BufReader::new(stdin());

    let mut gc = GarbageCollector::new();

    let mut vm = VirtualMachine::new(&mut gc);

    vm.init_globals();

    loop {
        let mut input = String::new();

        print!(">> ");

        stdout().flush().unwrap();

        reader.read_line(&mut input).unwrap();

        input = input.trim_end_matches('\n').to_string();

        if input.is_empty() {
            continue;
        }

        let Some(value) = runner::run_repl("<stdin>", input, &mut vm) else {
            continue;
        };

        match value {
            Value::None => (),
            _ => println!("{}", TraceFormatter::new(value, vm.gc)),
        };
    }
}
