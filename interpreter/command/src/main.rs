use syphon::cli::Arguments;
use syphon::repl;

use clap::Parser;

use std::io;

fn main() -> io::Result<()> {
    let args = Arguments::parse();

    match args.file_name {
        Some(_) => Ok(()),
        None => repl::start(),
    }
}
