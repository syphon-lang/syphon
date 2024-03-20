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

```
exit(10) # exits with 10
exit(-2) # exits with 254 instead
exit("") # exits with 1 because "" is not an integer
```
