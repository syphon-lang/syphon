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
    let mut open_character_count = input.chars().filter(|&c| c == open_character).count();

    let mut close_character_count = input.chars().filter(|&c| c == close_character).count();

    let used_open = open_character_count > close_character_count;

    while open_character_count > close_character_count {
        print!(".. ");
        stdout().flush().unwrap();

        let mut input_nest = String::new();

        reader.read_line(&mut input_nest).unwrap();

        open_character_count += input_nest.chars().filter(|&c| c == open_character).count();
        close_character_count += input_nest.chars().filter(|&c| c == close_character).count();

        input.push_str(input_nest.as_str());
    }

    used_open
}
