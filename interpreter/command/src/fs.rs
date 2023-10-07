use syphon_errors::ErrorHandler;
use syphon_evaluator::*;
use syphon_lexer::Lexer;
use syphon_parser::Parser;

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

    let mut env = Environment::new(None);
    let mut evaluator = Evaluator::new(&mut env);

    evaluator.eval(module);

    if !evaluator.errors.is_empty() {
        ErrorHandler::handle_errors(
            file_path.to_str().unwrap_or_default().to_string(),
            evaluator.errors,
        );
        exit(1);
    }

    Ok(())
}
