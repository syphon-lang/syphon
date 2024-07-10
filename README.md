# Syphon

[Documentation](docs) - [Examples](examples)

A general-purpose programming language for scripting and all sort of stuff

## Why to use Syphon? here is our main goals:

1. Community-Driven: The syntax and features all being in control by the community, want something? add it or open an issue for someone else to add it
2. Fast: The main goal to make it as fast as possible compared to other interpreted languages
3. Simple: There is one way to do it, no semicolons and very readable by default, easy to make println unlike stupid Java
4. Open-Software: All our software is open and maintainable in readable idiomatic Zig code
5. Modern: We learn from other's mistake, which makes the language much more modern than stinky Java

## Did you achieved any of that goals?

You would think "yeah all people say that" and yes all people say that, we are from those people but here is a little roadmap:

- Is it community-driven, at least one (me, yhya) who manages the language

- Is it fast? not quite.. but there is incremental improvements

Currently, on my (Core2Duo E6300) I get a 1.8s on average for fibonacci not-cached recursive function, you can see the benchmark [here](tests/benchmarks/fibonacci.sy), and only a couple micro seconds for fibonacci cached recursive function, you can see the benchmark [here](tests/benchmarks/fibonacci_cached.sy) too

- Is it simple? very simple, quite too simple because there is no for loop btw

- Is it open software? yes, you are reading this because it is on GitHub

- Is it modern? this is for you to say

## Why the hate on Java?

Because why not?

## How can I contribute?

Try the language, open issues, open pull requests, join our [Discord](https://discord.com/invite/h7NaMc4rJA)
