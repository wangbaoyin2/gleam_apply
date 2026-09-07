# apply

[![Package Version](https://img.shields.io/hexpm/v/apply)](https://hex.pm/packages/apply)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/apply/)

Call **Erlang and JavaScript runtime functions at runtime, by string path** —
no `@external` + hand-written `*_ffi.erl` / `*_ffi.mjs` boilerplate for every
function you want to reach. One path string, one tuple of arguments, one
`default` value — done.

```gleam
import apply

pub fn main() {
  // Erlang target
  let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]), 0)

  // JavaScript target
  let assert Ok(5) = apply.apply("Math.max", #(1, 5), 0)
}
```

## Why?

Calling into the runtime from Gleam normally means, **per function**:

- an `@external` declaration in Gleam,
- a matching entry in a hand-written `*_ffi.erl` / `*_ffi.mjs`,
- dealing with `any`-typed results, exceptions and odd return values
  (`undefined`, `false`, `{error, _}`, ...) on your own.

`apply` collapses all of that into **two FFI files total** for the whole
library (`src/erl_ffi.erl` + `src/jst_ffi.mjs`), one path-based API, and a
**type-checked `Result(a, String)`** that pins the return type for you. You
write ordinary Gleam; the path string is the only "FFI".

## How it works

| | Erlang | JavaScript |
| --- | --- | --- |
| FFI implementation | `src/erl_ffi.erl` | `src/jst_ffi.mjs` |
| Path format | `"Module:Function"`, e.g. `"erlang:length"` | `"object.property"`, e.g. `"Math.max"` |
| Resolution | `binary_to_existing_atom` + export check | `globalThis` property walk |

The runtime is decided by your project's target in `gleam.toml`, not by this
library — the path format simply follows that runtime.

## Installation

```sh
gleam add apply@2.0.0
```

## API overview

| Function | Description |
| --- | --- |
| `apply/3` | **Main entry point**: dynamically invoke a function, result type-checked against `default` |
| `unwrap/2` | Settle any dynamic value: same type as `default` → value, otherwise → `default` |
| `get_erl_func/2` | Fetch an Erlang function reference (export checked against arity) |
| `get_js_obj/1` | Fetch a JavaScript global object / function |
| `call_erl/2`, `call_js/1` | Quick-check helpers that crash on failure; prefer `apply` in real code |
| `platform_name/0` | Current runtime: `"erlang"` / `"javascript"` |
| `is_tuple/1`, `is_function/1` | Runtime value checks |

> `get_erl_func` / `get_js_obj` are **runtime-specific**: calling them on the
> other runtime returns a runtime error. `apply/3` and `unwrap/2` work on both.

## Usage

The path format follows the runtime your project targets; `args` must be a
tuple, its elements are spread as call arguments in order; `default` anchors
the expected return type.

### Erlang

```gleam
import apply

pub fn main() {
  let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]), 0)
  let assert Ok(10) = apply.apply("erlang:max", #(10, 2), 0)
  let assert Ok("123") = apply.apply("erlang:integer_to_binary", #(123), "")

  // Non-tuple arguments return an error
  let assert Error(_) = apply.apply("erlang:length", "not a tuple", 0)
}
```

### JavaScript

```gleam
import apply

pub fn main() {
  let assert Ok(5) = apply.apply("Math.max", #(1, 5), 0)
  let assert Ok("123") = apply.apply("JSON.stringify", #(123), "")

  // A path that does not exist on this runtime returns an error
  let assert Error(_) = apply.apply("erlang:length", #([1, 2, 3]), 0)
}
```

## Multi-type return values

Runtime functions are **untyped** from Gleam's point of view: the same path can
return an `Int` on one call and a `Float`/`Bool`/`String` on another, and
"abnormal" values (`undefined`, `null`, `false`, `nil`, `{error, _}`, ...) are
just values too. Gleam has no way to know which one you got — so it types
everything as `any`. `apply/3` and `unwrap/2` resolve this with a runtime
**type judgement against `default`**:

- `apply.apply(path, args, default)` returns `Result(a, String)` — type-safe,
  no raw `any` ever reaches your code:

```gleam
let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]), 0)   // Int

let assert Error(msg) = apply.apply("erlang:is_atom", #(1), 0)
// msg == "erlang:is_atom/1 returned false (type boolean), expected type int"
```

- `unwrap(value, default)` returns a plain `a` — value when the types match,
  `default` otherwise. Handy when you call a fetched function yourself:

```gleam
let dynamic = apply.call_js("JSON.parse")("123") // any
let int = apply.unwrap(dynamic, 0)               // Int or 0
let text = apply.unwrap(dynamic, "")             // String or ""
```

### Type judgement rules

| Value | Erlang | JavaScript |
| --- | --- | --- |
| `true` / `false` | `Bool` (separated from other atoms) | `Bool` |
| `Int` vs `Float` | native types | `Math.ceil(v) - v === 0` → int, else float |
| `Nil` | atom `nil` | `undefined` |
| `String` / `BitArray` | both `binary` | `string` / `bit_array` |
| abnormal values | `false` / `nil` / `{error, _}` | `undefined` / `null` |

Any value whose type does not match `default` becomes an `Error` (for `apply`)
or the `default` (for `unwrap`) — you decide what is "normal" per call by
choosing the default.

> Note: on Erlang `5.0` is a `Float` literal, while on JavaScript `5.0` is the
> number `5` and therefore judged an `Int` (the round-then-subtract precision
> trick cannot see a float with an integral value).

## Fetching function references

```gleam
// Erlang runtime: export checked against arity; errors list existing arities
let assert Ok(f) = apply.get_erl_func("lists:map", 2)

let assert Error(msg) = apply.get_erl_func("lists:map", 3)
// msg == "lists:map/3 is not exported in erlang (existing arities: 2)"

// JavaScript runtime: resolve a dotted path on globalThis (no arity check)
let assert Ok(_) = apply.get_js_obj("Math.max")
let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
```

## Runtime checks

```gleam
apply.platform_name()          // "erlang" or "javascript"
apply.is_tuple(#(1, 2))        // True
apply.is_function(fn() { 1 })  // True
```

## Error message format

Both runtimes share a `path/arity + reason` style:

| Scenario | erlang | javascript |
| --- | --- | --- |
| Invalid path format | `bad path: "", expected "Module:Function"` | `bad path: "", expected "object.property"` |
| Target missing | `not_a_module:foo/1 not found in erlang (module or function does not exist)` | `Math.notExist/1 not found in javascript (object or property does not exist)` |
| Not exported at that arity | `erlang:length/2 is not exported in erlang (existing arities: 1)` | - (JS does not check arity) |
| Target not callable | `error: undef when calling "erlang:length/2"` | `error: not a function when calling "Math.PI/1"` |
| Exception while executing | `error: badarg when calling "erlang:length/1"` | `SyntaxError: ... when calling "JSON.parse/1"` |
| Explicit throw / exit | `throw: oops when calling "erlang:throw/1"`, `exit: bye when calling "erlang:exit/1"` | - |
| Result type ≠ default | `erlang:is_atom/1 returned false (type boolean), expected type int` | `console.log/1 returned undefined (type undefined), expected type int` |
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

Both test files can stay enabled — tests skip themselves based on the runtime:

- `test/apply_test.gleam` (24 tests) — runs only on the javascript target
- `test/apply_erlang_test.gleam` (31 tests) — runs only on the erlang target

`gleam test` defaults to the Erlang target; pass `--target` to be explicit:

```sh
gleam test --target erlang
gleam test --target javascript
```

The Erlang toolchain (`erl`, `erlc`, `escript`) and/or Node.js must be on
`PATH` for the target you test. **Consumers never need any of this** — it only
affects this library's own tests.

Further documentation can be found at <https://hexdocs.pm/apply/>.
