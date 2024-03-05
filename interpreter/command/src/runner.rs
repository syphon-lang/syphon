use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::compiler::{Compiler, CompilerMode};
use syphon_bytecode::disassembler;
use syphon_bytecode::value::Value;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use crate::cli::CLI;

use std::fs::File;
use std::io;
use std::io::BufRead;
use std::io::BufReader;
use std::process::exit;

pub fn run(file_path: &str, input: String, vm: &mut VirtualMachine) -> Option<(Value, Chunk)> {
    let lexer = Lexer::new(&input);

    let mut parser = Parser::new(lexer);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return None;
        }
    };

    let mut compiler = Compiler::new(CompilerMode::Script);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return None;
        }
    };

    let chunk = compiler.to_chunk();

    vm.load_chunk(chunk.clone());

    match vm.run() {
        Ok(value) => Some((value, chunk)),

        Err(err) => {
            eprintln!("{} {}", file_path, err);

            None
        }
    }
}

pub fn run_file(file_path: &str, cli: CLI) -> io::Result<()> {
    let file = File::open(file_path)?;
    let reader = BufReader::new(file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let mut vm = VirtualMachine::new();

    let Some((_, chunk)) = run(file_path, file_content, &mut vm) else {
        exit(1);
    };

    if cli.emit_bytecode {
        println!("------------------------------------");
        println!("{}", disassembler::disassmeble(file_path, &chunk));
        println!("------------------------------------");
        println!();
    }

    Ok(())
}
