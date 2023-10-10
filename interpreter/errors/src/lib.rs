use thin_vec::ThinVec;

use derive_more::{Display, Error};

pub struct ErrorHandler {}

impl ErrorHandler {
    pub fn handle_errors(file_path: String, errors: ThinVec<SyphonError>) {
        for error in errors {
            ErrorHandler::handle_error(file_path.clone(), error);
        }
    }

    pub fn handle_error(file_path: String, error: SyphonError) {
        eprintln!("{} {}", file_path, error)
    }
}

#[derive(Error, Display, Debug, Clone)]
pub enum SyphonError {
    #[display(fmt = "at {}:{}: {}", "at.0", "at.1", message)]
    AssemblingError { at: (usize, usize), message: String },

    #[display(fmt = "at {}:{}: {}", "at.0", "at.1", message)]
    RuntimeError { at: (usize, usize), message: String },
}

impl SyphonError {
    pub fn new_assembling_error(at: (usize, usize), message: String) -> SyphonError {
        SyphonError::AssemblingError { at, message }
    }

    pub fn new_runtime_error(at: (usize, usize), message: String) -> SyphonError {
        SyphonError::RuntimeError { at, message }
    }

    pub fn invalid(at: (usize, usize), stmt: &str) -> SyphonError {
        SyphonError::new_assembling_error(at, format!("invalid {}", stmt))
    }

    pub fn unsupported(at: (usize, usize), stmt: &str) -> SyphonError {
        SyphonError::new_runtime_error(at, format!("unsupported {}", stmt))
    }

    pub fn undefined(at: (usize, usize), stmt: &str, identifier: &str) -> SyphonError {
        SyphonError::new_runtime_error(at, format!("undefined {} '{}'", stmt, identifier))
    }

    pub fn unexpected(at: (usize, usize), stmt: &str, got: &str) -> SyphonError {
        SyphonError::new_assembling_error(at, format!("unexpected {} '{}'", stmt, got))
    }

    pub fn expected(at: (usize, usize), expected: &str) -> SyphonError {
        SyphonError::new_assembling_error(at, format!("expected {}", expected))
    }

    pub fn expected_got(at: (usize, usize), expected: &str, got: &str) -> SyphonError {
        SyphonError::new_assembling_error(at, format!("expected {} got {}", expected, got))
    }

    pub fn unable_to(at: (usize, usize), stmt: &str) -> SyphonError {
        SyphonError::new_assembling_error(at, format!("unable to {}", stmt))
    }

    pub fn mismatched(at: (usize, usize), stmt: &str) -> SyphonError {
        SyphonError::new_runtime_error(at, format!("mismatched {}", stmt))
    }
}
