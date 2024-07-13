# The Global Built-in Module

## Functions

- print

Print values to the stdout

Usage:

```
print("Hello, World!")
```

Stdout:

```
Hello, World!
```

- println

Print values then new line to the stdout

Usage:

```
print("Hello, World!")
```

Stdout:

```
Hello, World!

```

- random

Gives you a random value between two values exclusivly

Usage:

```
random(5, 10) # 7.268858764248719
random(10, 5) # same as above
random(0.1, 0.2) # 0.1783036218123609
random(0, 0) # 0.0
random("", "") # none
```

- exit

Exits from the process with the status code provided

Usage:

```
exit(10) # exits with 10
exit(-2) # exits with 254 instead
exit("") # exits with 1 because "" is provided
```

- typeof

Gives you the type of provided value

Usage:

```
typeof(none) # "none"
typeof("") # "string"
typeof(1) # "int"
typeof(1.5) # "float"
typeof(true) # "bool"
typeof([]) # "array"
typeof({}) # "map"
typeof(print) # "function"
```

- to_int

Casts (string, float, boolean) to int

```
to_int(5) # 5
to_int(5.5) # 5
to_int(true) # 1
to_int("5") # 5
to_int("hey") # none
```

- to_float

Casts (int, boolean) to float

```
to_float(5.5) # 5.5
to_float(5) # 5.0
to_float(true) # 1.0
to_float("5.5") # 5.5
to_float("hey") # none
```

- to_string

Casts any writeable value to string

```
to_string(5) # "5"
to_string(5.5) # "5.5"
to_string(true) # "true"
to_string("hey") # "hey"
to_string(none) # "none"
to_string([1, 2, 3]) # "[1, 2, 3]"
to_string({2: 4}) # "{2: 4}"
```

- array_push

Pushes the value provided into an array

```
arr = []

array_push(arr, 5)
array_push(2, 5) # no errors
```

- array_pop

Pops the last value in the array

```
arr = [5]

array_pop(arr) # 5
array_pop(arr) # none
array_pop(2) # none
```

- array_reverse

Gives you a copy of an array but reversed

```
arr = [0, 1]

array_reverse(arr) # [1, 0]
```

- foreach

Runs the provided callback on (array, string, map) entries

```
arr = [1, 2, 3]

str = "aaa"

map = {1: 2, 3: 4, 4: 5}

foreach(arr, fn (v) {
    println(v)
})

foreach(str, fn (s) {
    println(s)
})

foreach(map, fn (k, v) {
    println(k, v)
})
```

- length

Gives you the length of an (array, string, map)

```
arr = [1, 2, 3]

str = "aaa"

map = {1: 2, 3: 4, 4: 5}

length(str) # 3
length(arr) # 3
length(map) # 3
length(89) # none
```

- contains

Checks if a value in (array values, string sequences, map keys)

```
arr = ["a", "b", "c"]

map = {"a": "b", "c": "d"}

str = "abc"

contains(arr, "ab") # false
contains(arr, "c") # true

contains(map, "ab") # false
contains(map, "c") # true

contains(str, "cd") # false
contains(str, "ab") # true

contains(4, "ab") # none
```

- string_split

Splits the string into multiple strings by the sequence you provided, if the sequence is empty it will split each character instead

```
string_split("Hello world", " ") # ["Hello", "world"]
string_split("world", "") # ["w", "o", "r", "l", "d"]
```

- ord

Gives you the unicode representation of a one character

```
ord("?") # 63
ord(2) # none
```

- chr

Converts the unicode representation to a character

```
chr(63) # "?"
chr("jdlf") # none
```

- export

Changes the value exported to the users of this module, by default it exports none

```
export({"hey": 5})
```

- import

Evaluates a file and gives you the exported value

```
import("some_file.sy") # {"hey": 5}
```

- eval

Evaluates a string and gives you the exported value

```
eval("export({\"hey\": 5})") # {"hey": 5}
```

- hash

Gives you the number representation of the hashable value

```
hash(5) # 5
hash("string") # 5389953989438782544
hash([1, 2]) # none
```

- map_keys

Gives you an array of the keys stored in the provided map

```
map = {1: 2, 3: 4}

println(map_keys(map)) # [1, 3]
```

- map_from_keys

Gives you the map with keys you provided and all values are none

```
map = map_from_keys([1, 3])

println(map) # {1: none, 3: none}
```

- map_values

Gives you an array of the values stored in the provided map

```
map = {1: 2, 3: 4}

println(map_values(map)) # [2, 4]
```
