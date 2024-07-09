# The Foreign Function Interface Built-in Module

## Expectations

I expect that you imported the ffi module like that

```
ffi = import("ffi")
```

## Constants

- types

Contains a map of types to choose from, available keys are:

[

    void,

    u8,
    u16,
    u32,
    u64,

    i8,
    i16,
    i32,
    i64,

    f32,
    f64,

    pointer,

]

## Functions

- dll.open

Open a dynamic link library (searches in the libraries directory of the user by default (e.g. /usr/lib), use a relative path if you want it to be based on the current working directory (e.g. "./libadd.so")

```
libc = ffi.dll.open("libc.so.6", {
    "exit": {
        "parameters": [ffi.types.i32],
        "returns": ffi.types.void,
    },

    "puts": {
        "parameters": [ffi.types.pointer],
        "returns": ffi.types.void,
    },
})
```

- dll.close

Closes an open dynamic link library

```
ffi.dll.close(libc)
```

- call

Call a foreign function

```
ffi.call(libc.exit, [4])
```

- cstring

Make a C string

```
ffi.call(libc.puts, [ffi.cstring("Hello, world!")])
```
