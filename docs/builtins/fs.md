# The File System Built-in Module

## Expectations

I expect that you imported the fs module like that

```
fs = import("fs")
```

## Functions

- open

Opens a file to read or write, also creates one if does not exist

```
fs.open("some_file") # some file descriptor
fs.open(3) # none
```

- delete

Deletes a file if exists

```
fs.delete("some_file")
```

- close

Closes a file by descriptor

```
fs.close(fd)
```

- close_all

Closes all open files

```
fs.close_all()
```

- write

Replaces the content of a file with the provided one

```
fs.write(fd, "Hello.")
```

- read

Reads a character from the file stream

```
fs.read(fd) # "H"
fs.read(fd) # "e"
fs.read(fd) # "l"
fs.read(fd) # "l"
fs.read(fd) # "o"
```

- read_line

Reads until new line or the end of the file stream

```
fs.read_line(fd) # "Hello World"
fs.read_line(fd) # ""
```

- read_all

Reads until the end of the file stream

```
fs.read_all(fd) # "Hello World"
fs.read_all(fd) # ""
```

- cwd

Gives you the currently working directory

```
fs.cwd() # "/home/yhya/Programming/syphon"
```

- chdir

Changes the currently working directory

```
fs.chdir("../")
fs.cwd() # "/home/yhya/Programming"
fs.chdir("/")
fs.cwd() # "/"
```

- access

Checks if file can be accessed

```
fs.access("some_file") # true
fs.access("other_non_existent_file") # false
fs.access(02) # none
```
