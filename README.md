# apply

[![Package Version](https://img.shields.io/hexpm/v/apply)](https://hex.pm/packages/apply)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/apply/)

Call functions in the Erlang and JavaScript runtimes **at runtime, by path** -
no `@external` + `*_ffi.erl` / `*_ffi.mjs` boilerplate for every function you
want to reach.

```gleam
import apply

pub fn main() {
  let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]))
  let assert Ok(5) = apply.apply("Math.max", #(1, 5))
}
```

Resolve a path like `"erlang:length"` or `"Math.max"`, apply your arguments,
and get a `Result(any, String)` back - with unified, arity-aware error messages
on both runtimes.


## How it works

| | Erlang | JavaScript |
| --- | --- | --- |
| FFI implementation | `src/erl_ffi.erl` | `src/jst_ffi.mjs` |
| Path format | `"Module:Function"`, e.g. `"erlang:length"` | `"object.property"`, e.g. `"Math.max"` |

The runtime is decided by your project's target in `gleam.toml`, not by this
library - the path format simply follows that runtime.

## Installation

```sh
gleam add apply@1
```

## API overview

| Function | Description |
| --- | --- |
| `apply/2` | Main entry point: dynamically invoke a runtime function (args must be a tuple) |
| `get_erl_func/2` | Fetch an Erlang function reference, export checked against arity |
| `get_js_obj/1` | Fetch a JavaScript global object / function |
| `call_erl/2`, `call_js/1` | Quick-check helpers that crash on failure; prefer `apply` in real code |
| `platform_name/0` | Current runtime: `"erlang"` / `"javascript"` |
| `is_tuple/1`, `is_function/1` | Runtime value checks |

> `get_erl_func` / `get_js_obj` are **runtime-specific**: calling them on the
> other runtime returns a runtime error (see below). `apply` itself works on
> both runtimes.

## Usage

The path format follows the runtime your project targets:

- **Erlang target** - `"Module:Function"`, e.g. `"erlang:length"`
- **JavaScript target** - `"object.property"`, e.g. `"Math.max"`

`args` must be a tuple; its elements are spread as call arguments in order.

### Erlang

```gleam
import apply

pub fn main() {
  let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]))
  let assert Ok(10) = apply.apply("erlang:max", #(10, 2))
  let assert Ok("123") = apply.apply("erlang:integer_to_binary", #(123))

  // Non-tuple arguments return an error
  let assert Error(_) = apply.apply("erlang:length", "not a tuple")
}
```

### JavaScript

```gleam
import apply

pub fn main() {
  let assert Ok(5) = apply.apply("Math.max", #(1, 5))
  let assert Ok("123") = apply.apply("JSON.stringify", #(123))

  // A path that does not exist on this runtime returns an error
  let assert Error(_) = apply.apply("erlang:length", #([1, 2, 3]))
}
```

### Return value handling

| Called function returns | Erlang | JavaScript |
| --- | --- | --- |
| `ok` | mapped to `Ok(Nil)` | returned as-is |
| `{ok, X}` | mapped to `Ok(X)` | returned as-is |
| anything else `Other` | `Ok(Other)` | `Ok(Other)` |
| exception / target missing | `Error(message)` | `Error(message)` |

> JavaScript performs no `ok`/`{ok, X}` mapping; a function returning
> `undefined` (e.g. `console.log`) maps to `Ok(Nil)` in Gleam.

### Fetching objects / function references

```gleam
// Erlang runtime: export checked against arity; errors list existing arities
let assert Ok(f) = apply.get_erl_func("lists:map", 2)

let assert Error(msg) = apply.get_erl_func("lists:map", 3)
// msg == "lists:map/3 is not exported in erlang (existing arities: 2)"

// JavaScript runtime: resolve a dotted path on globalThis (no arity check)
let assert Ok(_) = apply.get_js_obj("Math.max")
let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
```

### Runtime checks

```gleam
apply.platform_name()          // "erlang" or "javascript"
apply.is_tuple(#(1, 2))        // True
apply.is_function(fn() { 1 })  // True
```

## Error message format

Both runtimes share a `class: reason when calling "path/arity"` style:

| Scenario | erlang | javascript |
| --- | --- | --- |
| Invalid path format | `bad path: "a:b", expected "Module:Function"` | `bad path: "a..b", expected "object.property"` |
| Target missing | `not_a_module:foo/1 not found in erlang (module or function does not exist)` | `Math.notExist not found in javascript (object or property does not exist)` |
| Not exported at that arity | `erlang:length/2 is not exported in erlang (existing arities: 1)` | - (JS does not check arity) |
| Target not callable | `error: undef when calling "erlang:length/2"` | `error: not a function when calling "Math.PI/1"` |
| Exception while executing | `error: badarg when calling "erlang:length/1"` | `SyntaxError: ... when calling "JSON.parse/1"` |
| Explicit throw / exit | `throw: oops when calling "erlang:throw/1"`, `exit: bye when calling "erlang:exit/1"` | - |
| Non-tuple arguments | `args "oops" must be tuple type` | same as left |
| Runtime-specific function on the wrong runtime | `need javascript runtime, now is erlang runtime` | `need erlang runtime, now is javascript runtime` |

Notes:

- The Erlang `get` checks exports against the arity and lists the **existing
  arities** on mismatch; the JavaScript `get` only resolves the path and can
  return any object (not just functions).
- Erlang exception reasons are not limited to atoms (`throw`/`exit` can carry
  any term) and are formatted in a readable way.

## Development (maintaining this library)

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

Both test files can stay enabled - tests skip themselves based on the runtime:

- `test/apply_test.gleam` (22 tests) - runs only on the javascript target
- `test/apply_erlang_test.gleam` (24 tests) - runs only on the erlang target

To develop against the other runtime, edit `gleam.toml` and run `gleam test`.
**Consumers never need to do this** - it only affects this library's own tests:

```toml
# target = "erlang"
target = "javascript"
```

Further documentation can be found at <https://hexdocs.pm/apply/>.
