use syphon::cli::Arguments;

use clap::Parser;

use std::io;

use std::process::exit;

fn main() -> io::Result<()> {
    let args = Arguments::parse();

    match args.file_path.clone() {
        Some(file_path) => {
            syphon::run_file(file_path.to_str().unwrap_or_default(), args).unwrap_or_else(|err| {
                eprintln!("{}: {}", file_path.display(), err);
                exit(1)
            });

            Ok(())
        }

        None => syphon::repl::start(args),
    }
}
