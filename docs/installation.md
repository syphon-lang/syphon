# Installing Syphon

### Build from source

You need the latest version of Zig tools

Choose one of the following ways of compilation, the binary file will be at `zig-out/bin/syphon`

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
