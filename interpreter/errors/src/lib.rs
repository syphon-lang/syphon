use thin_vec::ThinVec;

use std::error::Error;
use std::fmt::Display;

pub struct ErrorHandler {}

impl ErrorHandler {
    pub fn handle_errors(file_name: String, errors: ThinVec<EvaluateError>) {
        for mut error in errors {
            error.file_name = file_name.clone();

            ErrorHandler::handle_error(error);
        }
    }

    pub fn handle_error(error: EvaluateError) {
        eprintln!("{}", error);
    }
}

#[derive(Clone, Debug)]
pub struct EvaluateError {
    pub file_name: String,
    at: (usize, usize),
    message: String,
}

impl EvaluateError {
    pub fn new(at: (usize, usize), message: String) -> EvaluateError {
        EvaluateError {
            file_name: String::new(),
            at,
            message,
        }
    }

    pub fn invalid(at: (usize, usize), stmt: &str) -> EvaluateError {
        EvaluateError::new(at, format!("invalid {}", stmt))
    }

    pub fn unsupported(at: (usize, usize), stmt: &str) -> EvaluateError {
        EvaluateError::new(at, format!("unsupported {}", stmt))
    }

    pub fn undefined(at: (usize, usize), stmt: &str, identifier: &str) -> EvaluateError {
        EvaluateError::new(at, format!("undefined {} '{}'", stmt, identifier))
    }

    pub fn unexpected(at: (usize, usize), stmt: &str, got: &str) -> EvaluateError {
        EvaluateError::new(at, format!("unexpected {} '{}'", stmt, got))
    }

    pub fn expected(at: (usize, usize), expected: &str) -> EvaluateError {
        EvaluateError::new(at, format!("expected {}", expected))
    }

    pub fn expected_got(at: (usize, usize), expected: &str, got: &str) -> EvaluateError {
        EvaluateError::new(at, format!("expected {} got '{}'", expected, got))
    }

    pub fn unable_to(at: (usize, usize), stmt: &str) -> EvaluateError {
        EvaluateError::new(at, format!("unable to {}", stmt))
    }

    pub fn mismatched(at: (usize, usize), stmt: &str) -> EvaluateError {
        EvaluateError::new(at, format!("mismatched {}", stmt))
    }
}

impl Display for EvaluateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} at {}:{}: {}",
            self.file_name, self.at.0, self.at.1, self.message
        )
    }
}

impl Error for EvaluateError {}
