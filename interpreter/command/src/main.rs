use syphon::cli::{Command, CLI};

use clap::Parser;

use std::io;

use std::process::exit;

fn main() -> io::Result<()> {
    let cli = CLI::parse();

    match cli.clone().command {
        Command::Run { file_path } => {
            syphon::runner::run_file(file_path.to_str().unwrap_or_default(), cli).unwrap_or_else(
                |err| {
                    eprintln!("{}: {}", file_path.display(), err);
                    exit(1)
                },
            );

            Ok(())
        }

        Command::Repl => syphon::repl::start(cli),
    }
}
