use crate::runner;

use syphon_bytecode::value::Value;

use syphon_vm::VirtualMachine;

use std::{collections::HashMap, io::{stdin, stdout, BufRead, BufReader, Write}};

pub fn start() {
    let mut reader = BufReader::new(stdin());

    let mut global_atoms = HashMap::new();

    let mut vm = VirtualMachine::new();

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

        let Some(value) = runner::run_repl_with_atoms("<stdin>", input, &mut vm, &mut global_atoms) else {
            continue;
        };

        match value {
            Value::None => (),
            _ => println!("{}", value),
        };
    }
}
