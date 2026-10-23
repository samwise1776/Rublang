# Rublang

Rublang is an experimental programming language implemented in Ruby.

## Run

Requires Ruby. For GUI support, install `glimmer-dsl-libui` separately.

```sh
ruby app.rb hello.lang
```

Example `hello.lang`:

```text
vs name = "World"
stdout::c << "Hello"
```

## Source files

- `app.rb` — interpreter
- `gui.rb` — optional GUI bridge
- `pkg.rb` — package manager

## Package installation

Create `rublang.json` and a matching `.lang` entry file, then run:

```sh
ruby pkg.rb install .
```

Remote package installs require an HTTPS URL registered with a SHA-256 digest.

## Development

```sh
ruby -c app.rb
ruby -c gui.rb
ruby -c pkg.rb
ruby test/smoke.rb
```

## Versioning

- v1.0.0: first public release
- v1.0.1: maintenance and developer tooling (in progress)

Native extensions and GUI functionality may require external compilers and desktop dependencies.
