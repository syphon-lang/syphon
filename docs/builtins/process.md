# The Process Built-in Module

## Expectations

I expect that you imported the process module like that

```
process = import("process")
```

## Constants

- argv

The arguments provided to `syphon run` command as an array of strings

## Functions

- get_env

Get the current environment variables map, any change to this map does not change the actual environment variables

```
process.get_env() # {"HOME": "/home/yhya"}
```
