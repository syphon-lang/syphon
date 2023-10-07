mod env;
pub use env::Environment;

mod values;
pub use values::*;

use thin_vec::ThinVec;

use syphon_ast::*;
use syphon_errors::EvaluateError;

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

    fn eval_stmt(&mut self, kind: StmtKind) -> Value {
        match kind {
            StmtKind::VariableDeclaration(variable) => self.eval_variable_declaration(variable),
            StmtKind::FunctionDefinition(function) => self.eval_function_definition(function),
            StmtKind::Return(ret) => self.eval_return(ret),

            StmtKind::Unknown => unreachable!(),
        }
    }

    fn eval_variable_declaration(&mut self, variable: Variable) -> Value {
        match variable.value {
            Some(expr) => {
                let value = self.eval_expr(expr);

                self.env.set(variable.name, Some(value));
            }

            None => self.env.set(variable.name, None),
        }

        Value::None
    }

    fn eval_function_definition(&mut self, function: Function) -> Value {
        self.env.set(
            function.name.clone(),
            Some(Value::Function {
                name: function.name,
                parameters: function.parameters,
                body: function.body,
                env: Environment::new(Some(self.env.clone().into())),
            }),
        );

        Value::None
    }

    fn eval_return(&mut self, ret: Return) -> Value {
        match ret.value {
            Some(expr) => {
                let value = self.eval_expr(expr);

                Value::Return(value.into())
            }

            None => Value::None,
        }
    }

    fn eval_exprs(&mut self, kinds: ThinVec<ExprKind>) -> ThinVec<Value> {
        let mut result = ThinVec::new();

        for kind in kinds {
            result.push(self.eval_expr(kind));
        }

        result
    }

    fn eval_expr(&mut self, kind: ExprKind) -> Value {
        match kind {
            ExprKind::Identifier { symbol, at } => self.eval_identifier(symbol, at),
            ExprKind::Str { value, .. } => Value::Str(value),
            ExprKind::Int { value, .. } => Value::Int(value),
            ExprKind::Float { value, .. } => Value::Float(value),
            ExprKind::Bool { value, .. } => Value::Bool(value),

            ExprKind::Call {
                function_name,
                arguments,
                at,
            } => self.eval_function_call(function_name, arguments, at),

            ExprKind::UnaryOperation {
                operator,
                right,
                at,
            } => self.eval_unary_operation(operator, *right, at),

            ExprKind::BinaryOperation {
                left,
                operator,
                right,
                at,
            } => self.eval_binary_operation(*left, operator, *right, at),

            ExprKind::Unknown => Value::None,
        }
    }

    fn eval_identifier(&mut self, symbol: String, at: (usize, usize)) -> Value {
        match self.env.get(&symbol) {
            Some(value) => value.clone(),
            None => {
                self.errors
                    .push(EvaluateError::undefined(at, "value", &symbol));
                Value::None
            }
        }
    }

    fn eval_function_call(
        &mut self,
        name: String,
        arguments: ThinVec<ExprKind>,
        at: (usize, usize),
    ) -> Value {
        let value = self.env.get(&name);

        if let Some(Value::Function {
            parameters,
            body,
            env,
            ..
        }) = value
        {
            let mut env = env.clone();

            let body = body.clone();

            let parameters_names: ThinVec<String> =
                parameters.iter().map(|param| param.name.clone()).collect();

            let arguments = self.eval_exprs(arguments);

            env.set_multiple(parameters_names, arguments);

            let mut evaluator = Evaluator::new(&mut env);

            evaluator.eval_function_body(body)
        } else {
            self.errors
                .push(EvaluateError::undefined(at, "function", &name));

            Value::None
        }
    }

    fn eval_function_body(&mut self, body: ThinVec<Node>) -> Value {
        for node in body {
            let value = self.eval(node);

            if let Value::Return(value) = value {
                return *value;
            }
        }

        Value::None
    }

    fn eval_unary_operation(
        &mut self,
        operator: char,
        right: ExprKind,
        at: (usize, usize),
    ) -> Value {
        let right = self.eval_expr(right);

        match operator {
            '!' => match right {
                Value::Bool(value) => Value::Bool(!value),
                Value::Int(value) => match value {
                    0 => Value::Bool(true),
                    _ => Value::Bool(false),
                },

                Value::None => Value::Bool(true),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '!' unary operator"));

                    Value::None
                }
            },

            '-' => match right {
                Value::Int(value) => Value::Int(-value),
                Value::Float(value) => Value::Float(-value),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '-' unary operator"));

                    Value::None
                }
            },

            _ => unreachable!(),
        }
    }

    fn eval_binary_operation(
        &mut self,
        left: ExprKind,
        operator: String,
        right: ExprKind,
        at: (usize, usize),
    ) -> Value {
        let lhs = self.eval_expr(left);
        let rhs = self.eval_expr(right);

        match operator.as_str() {
            "+" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs + rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 + rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs + rhs),
                (Value::Str(lhs), Value::Str(rhs)) => Value::Str(lhs + rhs.as_str()),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '+' binary operator"));

                    Value::None
                }
            },

            "-" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs - rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 - rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs - rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '-' binary operator"));

                    Value::None
                }
            },

            "/" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs / rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 / rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs / rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '/' binary operator"));

                    Value::None
                }
            },

            "*" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs * rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 * rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs * rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '*' binary operator"));

                    Value::None
                }
            },

            "**" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Float((lhs as f64).powf(rhs as f64)),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float((lhs as f64).powf(rhs)),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs.powf(rhs)),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '**' binary operator"));

                    Value::None
                }
            },

            "%" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Int(lhs % rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Float(lhs as f64 % rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Float(lhs % rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '%' binary operator"));

                    Value::None
                }
            },

            ">" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs > rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 > rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs > rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '>' binary operator"));

                    Value::None
                }
            },

            "<" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs < rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Bool((lhs as f64) < rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs < rhs),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '<' binary operator"));

                    Value::None
                }
            },

            "==" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs == rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 == rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs == rhs),
                (Value::Str(lhs), Value::Str(rhs)) => Value::Bool(lhs == rhs),
                (Value::None, Value::None) => Value::Bool(true),
                (Value::None, ..) => Value::Bool(false),
                (.., Value::None) => Value::Bool(false),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '==' binary operator"));

                    Value::None
                }
            },

            "!=" => match (lhs, rhs) {
                (Value::Int(lhs), Value::Int(rhs)) => Value::Bool(lhs != rhs),
                (Value::Int(lhs), Value::Float(rhs)) => Value::Bool(lhs as f64 != rhs),
                (Value::Float(lhs), Value::Float(rhs)) => Value::Bool(lhs != rhs),
                (Value::Str(lhs), Value::Str(rhs)) => Value::Bool(lhs != rhs),
                (Value::None, Value::None) => Value::Bool(false),
                (Value::None, ..) => Value::Bool(true),
                (.., Value::None) => Value::Bool(true),

                _ => {
                    self.errors
                        .push(EvaluateError::unable_to(at, "apply '!=' binary operator"));

                    Value::None
                }
            },

            _ => unreachable!(),
        }
    }
}
