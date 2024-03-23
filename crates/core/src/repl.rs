use crate::runner;

use syphon_bytecode::value::Value;

use syphon_gc::{GarbageCollector, TraceFormatter};
use syphon_vm::VirtualMachine;

use std::io::{stdin, stdout, BufRead, BufReader, Stdin, Write};

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

        if input.is_empty() {
            break;
        }

        let _ = !handle_multi_line(&mut reader, &mut input, '{', '}')
            && !handle_multi_line(&mut reader, &mut input, '[', ']')
            && !handle_multi_line(&mut reader, &mut input, '(', ')');

        let Some(value) = runner::run_repl("<stdin>", input, &mut vm) else {
            continue;
        };

        match value {
            Value::None => (),

            _ => println!("{}", TraceFormatter::new(value, vm.gc)),
        };
    }
}

fn handle_multi_line(
    reader: &mut BufReader<Stdin>,
    input: &mut String,
    open_character: char,
    close_character: char,
) -> bool {
    let mut open = input.chars().filter(|&c| c == open_character).count();

    let mut close = input.chars().filter(|&c| c == close_character).count();

    let used_open = open > close;

    while open > close {
        print!(".. ");
        stdout().flush().unwrap();

        let mut input_nest = String::new();

        reader.read_line(&mut input_nest).unwrap();

        *input += input_nest.as_str();

        open += input_nest.chars().filter(|&c| c == open_character).count();

        close += input_nest.chars().filter(|&c| c == close_character).count();
    }

    used_open
}
