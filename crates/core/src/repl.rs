use crate::cli::CLI;

use crate::runner;

use syphon_bytecode::disassembler::disassmeble;
use syphon_bytecode::value::Value;

use syphon_vm::VirtualMachine;

use std::io::{stdin, stdout, BufRead, BufReader, Write};

pub fn start(cli: &CLI) {
    let mut reader = BufReader::new(stdin());

    let mut vm = VirtualMachine::new();

    loop {
        let mut input = String::new();

        print!(">> ");

        stdout().flush().unwrap();

        reader.read_line(&mut input).unwrap();

        input = input.trim_end_matches('\n').to_string();

        if input.is_empty() {
            continue;
        }

        let Some((value, chunk)) = runner::run("<stdin>", input, &mut vm) else {
            continue;
        };

        if cli.emit_bytecode {
            println!("------------------------------------");
            println!("{}", disassmeble("<stdin>", &chunk));
            println!("------------------------------------");
            println!();
        }

        match value {
            Value::None => (),
            _ => println!("{}", value),
        };
    }
}
