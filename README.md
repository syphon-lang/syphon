# Syphon

A general-purpose programming language for scripting and all sort of stuff

## Documentation

We only have a [markdown files](docs) to explain the language in detatil
Looking forward to make a website explaining it more

## Installing

### Building from source

You need the latest version of Zig tools (Recommeneded to get the dev version from the master branch)

Choose one of the following ways of compilation, the binary will be at `zig-out/bin/syphon` add it to your PATH and here you go you just installed the interpreter

- Fast runtime but slow compilation 
```
zig build -Doptimize=ReleaseFast
```

- Small binary but slow compilation and medium-fast runtime
```
zig build -Doptimize=ReleaseSmall
```

- Safe but slow compilation and medium runtime
```
zig build -Doptimize=ReleaseSafe
```

- Safe and fast compilation but slow runtime
```
zig build
```
