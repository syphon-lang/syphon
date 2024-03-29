use syphon_core::cli::{Command, CLI};

use clap::Parser;

use std::process::exit;

fn main() {
    let cli = CLI::parse();

    match &cli.command {
        Command::Compile { file_path } => {
            syphon_core::runner::compile_file(file_path).unwrap_or_else(|err| {
                eprintln!("{}: {}", file_path.display(), err);
                exit(1)
            });
        }

        Command::Disassemble { file_path } => {
            syphon_core::runner::disassemble_file(file_path).unwrap_or_else(|err| {
                eprintln!("{}: {}", file_path.display(), err);
                exit(1)
            });
        }

        Command::Run { file_path } => {
            syphon_core::runner::run_file(file_path).unwrap_or_else(|err| {
                eprintln!("{}: {}", file_path.display(), err);
                exit(1)
            });
        }

        Command::Repl => syphon_core::repl::start(),
    }
}
