use syphon_errors::ErrorHandler;
use syphon_evaluator::*;
use syphon_lexer::Lexer;
use syphon_parser::Parser;

use io::{BufRead, BufReader, Write};
use std::io;

pub fn start() -> io::Result<()> {
    let mut reader = BufReader::new(io::stdin());

    let mut env = Environment::new(None);

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
            ErrorHandler::handle_errors(String::from("<stdout>"), parser.lexer.errors);
            continue;
        }

        if !parser.errors.is_empty() {
            ErrorHandler::handle_errors(String::from("<stdout>"), parser.errors);
            continue;
        }

        let mut evaluator = Evaluator::new(&mut env);

        let value = evaluator.eval(module);

        if !evaluator.errors.is_empty() {
            ErrorHandler::handle_errors(String::from("<stdout>"), evaluator.errors);
            continue;
        }

        match value {
            Value::None => continue,
            _ => println!("{}", value),
        }
    }
}
