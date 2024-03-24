# Syphon's Syntax

## Variable Declaration

- Mutable Variable
```
let variable_name = variable_value
```

- Unmutable Variable (Constants)
```
const variable_name = variable_value
```

- None-Initialized Variable
```
let variable_name;
```

## Function Declaration

- No Parameters
```
fn function_name() {

}
```

- With Parameters
```
fn function_name(a, b) {

}
```

## Function Calling

- No Arguments
```
function_name()
```

- With Arguments
```
function_name(1, 2)
```

## Conditional

```
if condition {

} else if another_condition {

} else {

}
```

## While Loop

```
while condition {

}
```

## Comments

```
# This is a comment
```

## Array Subscript

```
let a = [0, 1, 2, 3, 4, 5];

a[0] # 0
a[-1] # 5
a[6] # error: index out of bounds
a[-7] # error: index out of bounds
```
