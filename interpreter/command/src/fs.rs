use syphon_bytecode::assembler::Assembler;
use syphon_errors::ErrorHandler;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use rustc_hash::FxHashMap;

use io::{BufRead, BufReader};
use std::io;

use std::path::PathBuf;

use std::fs::File;

use std::process::exit;

pub fn run_file(file_path: PathBuf) -> io::Result<()> {
    let file = File::open(file_path.clone())?;
    let reader = BufReader::new(file);

    let mut content = String::new();

    for line in reader.lines() {
        content.push_str(line?.as_str());
        content.push('\n');
    }

    let lexer = Lexer::new(&content);
    let mut parser = Parser::new(lexer);
    let module = parser.module();

    if !parser.lexer.errors.is_empty() {
        ErrorHandler::handle_errors(
            file_path.to_str().unwrap_or_default().to_string(),
            parser.lexer.errors,
        );
        exit(1);
    }

    if !parser.errors.is_empty() {
        ErrorHandler::handle_errors(
            file_path.to_str().unwrap_or_default().to_string(),
            parser.errors,
        );
        exit(1);
    }

    let mut assembler = Assembler::new();

    assembler.assemble(module);

    if !assembler.errors.is_empty() {
        ErrorHandler::handle_errors(
            file_path.to_str().unwrap_or_default().to_string(),
            assembler.errors,
        );
        exit(1);
    }

    let mut globals = FxHashMap::default();

    let mut vm = VirtualMachine::new(assembler.to_chunk(), &mut globals);

    match vm.run() {
        Ok(_) => Ok(()),
        Err(error) => {
            ErrorHandler::handle_error(file_path.to_str().unwrap_or_default().to_string(), error);
            exit(1)
        }
    }
}
