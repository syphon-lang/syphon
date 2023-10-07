mod env;
pub use env::Environment;

mod values;
pub use values::*;

mod expr;
mod stmt;

use syphon_ast::*;
use syphon_errors::EvaluateError;

use thin_vec::ThinVec;

pub struct Evaluator<'a> {
    env: &'a mut Environment,

    pub errors: ThinVec<EvaluateError>,
}

impl<'a> Evaluator<'a> {
    pub fn new(env: &mut Environment) -> Evaluator {
        Evaluator {
            env,

            errors: ThinVec::new(),
        }
    }

    pub fn eval(&mut self, node: Node) -> Value {
        match node {
            Node::Module { body } => self.eval_module(body),
            Node::Stmt(kind) => self.eval_stmt(*kind),
            Node::Expr(kind) => self.eval_expr(*kind),
        }
    }

    fn eval_module(&mut self, body: ThinVec<Node>) -> Value {
        let mut result = Value::None;

        for node in body {
            result = self.eval(node)
        }

        result
    }
}
