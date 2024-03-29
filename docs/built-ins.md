# Syphon's Built-ins

## Native Functions

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

- time

Gives you the elapsed time after startup (in nanoseconds)

Usage:

```
time() # 2170826152
```

- random

Gives you a random value between (min, max) exclusivly and always returns float unless if the values are not numbers then it will return none

Usage:

```
random(5, 10) # 7.268858764248719
random(10, 5) # also works
random(0.1, 0.2) # 0.1783036218123609
random(0, 0) # 0
random("", "") # none
```

- exit

Exits from the process with the status code provided, the status code maps to 0-255 range and if you provide any value other than integer it will exit with 1 instead

Usage:

```
exit(10) # exits with 10
exit(-2) # exits with 254 instead
exit("") # exits with 1 because "" is not an integer
```

- typeof

Gives you the type of provided value in a string

Usage:

```
typeof(none) # none
typeof("") # string
typeof(1) # int
typeof(1.5) # float
typeof(true) # bool
typeof([]) # array
typeof(print) # function
```

- array_push

Pushes the value provided into an array, returns none always and does not care if you provided non-array types

```
let arr = [];

array_push(arr, 5) # arr is now [5]

array_push(2, 5) # does not care
```

- array_pop

Pops the last value in the array, checks if the array is empty but does not care and will just return none also just like the array_push if you provided non-array types it will return none

```
let arr = [5];

array_pop(arr) # 5
array_pop(arr) # none
array_pop(2) # none
```
