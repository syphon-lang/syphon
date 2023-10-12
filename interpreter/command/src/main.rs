use syphon::cli::Arguments;
use syphon::fs;
use syphon::repl;

use clap::Parser;

use std::io;

use std::process::exit;

fn main() -> io::Result<()> {
    let args = Arguments::parse();

    match args.file_path.clone() {
        Some(file_path) => {
            fs::run_file(file_path.clone(), args).unwrap_or_else(|err| {
                eprintln!("{}: {}", file_path.display(), err);
                exit(1)
            });

            Ok(())
        }

        None => repl::start(args),
    }
}
