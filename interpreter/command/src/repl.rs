use crate::cli::Arguments;

use crate::runner;

use syphon_bytecode::disassembler::disassmeble;
use syphon_bytecode::values::Value;

use rustc_hash::FxHashMap;

use io::{BufRead, BufReader, Write};
use std::io;

pub fn start(args: Arguments) -> io::Result<()> {
    let mut reader = BufReader::new(io::stdin());

    let mut globals = FxHashMap::default();

    loop {
        let mut input = String::new();

        print!(">> ");
        io::stdout().flush()?;

        reader.read_line(&mut input)?;

        input = input.trim_end_matches('\n').to_string();

        let Ok((value, chunk)) = runner::run("<stdin>".to_string(), input, &mut globals) else {
            continue;
        };

        if args.emit_bytecode {
            println!("------------------------------------");
            println!("{}", disassmeble("<stdin>", &chunk));
            println!("------------------------------------");
            println!();
        }

        match value {
            Value::None => (),
            _ => println!("{}", value),
        }
    }
}
