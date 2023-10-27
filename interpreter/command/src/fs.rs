use crate::cli::Arguments;

use syphon_bytecode::compiler::*;
use syphon_bytecode::disassembler::disassmeble;
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

pub fn run_file(file_path: PathBuf, args: Arguments) -> io::Result<()> {
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

    let mut compiler = Compiler::new(CompilerMode::Script);

    compiler.compile(module);

    if !compiler.errors.is_empty() {
        ErrorHandler::handle_errors(
            file_path.to_str().unwrap_or_default().to_string(),
            compiler.errors,
        );
        exit(1);
    }

    let chunk = compiler.to_chunk();

    if args.emit_bytecode {
        println!("------------------------------------");
        println!(
            "{}",
            disassmeble(file_path.to_str().unwrap_or_default(), &chunk)
        );
        println!("------------------------------------");
        println!();
    }

    let mut globals = FxHashMap::default();

    let mut vm = VirtualMachine::new(chunk, &mut globals);

    match vm.run() {
        Ok(_) => Ok(()),
        Err(error) => {
            ErrorHandler::handle_error(file_path.to_str().unwrap_or_default().to_string(), error);
            exit(1)
        }
    }
}
