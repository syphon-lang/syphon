# The Shell Built-in Module

## Expectations

I expect that you imported the shell module like that

```
shell = import("shell")
```

## Functions

- run

Run a command

```
shell.run("echo Hello, World!") # { "termination": "exited", "status_code": 0, "stdout": "Hello, World!\n", "stderr": "Hello, World!\n" }
```
