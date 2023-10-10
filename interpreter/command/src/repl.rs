use syphon_bytecode::assembler::Assembler;
use syphon_bytecode::values::Value;
use syphon_errors::ErrorHandler;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use io::{BufRead, BufReader, Write};
use std::io;

pub fn start() -> io::Result<()> {
    let mut reader = BufReader::new(io::stdin());

    loop {
        let mut input = String::new();

        print!(">> ");
        io::stdout().flush()?;

        reader.read_line(&mut input)?;

        input = input.trim_end_matches('\n').to_string();

        let lexer = Lexer::new(&input);
        let mut parser = Parser::new(lexer);
        let module = parser.module();

        if !parser.lexer.errors.is_empty() {
            ErrorHandler::handle_errors(String::from("<stdin>"), parser.lexer.errors);
            continue;
        }

        if !parser.errors.is_empty() {
            ErrorHandler::handle_errors(String::from("<stdin>"), parser.errors);
            continue;
        }

        let mut assembler = Assembler::new();

        assembler.assemble(module);

        if !assembler.errors.is_empty() {
            ErrorHandler::handle_errors(String::from("<stdin>"), assembler.errors);
            continue;
        }

        let mut vm = VirtualMachine::new(assembler.to_chunk());

        match vm.run() {
            Ok(value) => {
                if value != Value::None {
                    println!("{}", value)
                }
            }
            Err(error) => {
                ErrorHandler::handle_error(String::from("<stdin>"), error);
                continue;
            }
        }
    }
}
