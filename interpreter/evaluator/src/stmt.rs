use crate::*;

impl<'a> Evaluator<'a> {
    pub(crate) fn eval_stmt(&mut self, kind: StmtKind) -> Value {
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
}
