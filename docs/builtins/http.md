# The HyperText Transfer Protocol Built-in Module

## Expectations

I expect that you imported the http module like that

```
http = import("http")
```

## Functions

- listen

Starts a server and calls the handler function on each request the server gets, the handler function is expected to get one parameter which is the request and returns a value which is the response

```
http.listen("0.0.0.0", 8080, fn (request) {
    return "Hello, World!"
})
```
