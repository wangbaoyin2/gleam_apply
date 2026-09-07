# apply

[![Package Version](https://img.shields.io/hexpm/v/apply)](https://hex.pm/packages/apply)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/apply/)

Call **Erlang and JavaScript runtime functions at runtime, by string path** —
no `@external` + hand-written `*_ffi.erl` / `*_ffi.mjs` boilerplate for every
function you want to reach.

```gleam
import apply

pub fn main() {
  // Erlang target
  let assert Ok(3) = apply.apply_typed("erlang:length", #([1, 2, 3]), 0)

  // JavaScript target
  let assert Ok(5) = apply.apply_typed("Math.max", #(1, 5), 0)
}
```

## Why?

Normally each runtime function you want from Gleam needs an `@external`
declaration plus a hand-written `*_ffi.erl` / `*_ffi.mjs` entry — and then you
still have to deal with `any`-typed results and odd return values on your own.

`apply` needs **two FFI files total** for the whole library. You pass a path
string, a tuple of arguments, and an anchor value; you get a typed
`Result` back. The path format follows your `gleam.toml` target:

| | Erlang | JavaScript |
| --- | --- | --- |
| Path format | `"Module:Function"` | `"object.property"` |
| Example | `"erlang:length"` | `"Math.max"` |

## Installation

```sh
gleam add apply@1
```

## Examples

### Strict type calls — `apply_typed`

`apply_typed(path, args, default)` — the result must have the same runtime
type as `default`, otherwise you get an `Error`.

```gleam
let assert Ok(3) = apply.apply_typed("erlang:length", #([1, 2, 3]), 0)
let assert Ok(10) = apply.apply_typed("erlang:max", #(10, 2), 0)
let assert Ok("123") = apply.apply_typed("erlang:integer_to_binary", #(123), "")
let assert Ok(5) = apply.apply_typed("Math.max", #(1, 5), 0)

// Type mismatch → Error (the message shows both types)
let assert Error(msg) = apply.apply_typed("erlang:is_atom", #(1), 0)
// msg == "erlang:is_atom/1 returned false (type boolean), expected type int"

let assert Error(msg) = apply.apply_typed("erlang:max", #(1.5, 2.5), 0)
// msg == "erlang:max/2 returned 2.5 (type float), expected type int"

// Call-level failures → Error
let assert Error(_) = apply.apply_typed("erlang:length", #(), 0)  // undef
let assert Error(_) = apply.apply_typed("Math.PI", #(1), 0)       // not a function
let assert Error(_) = apply.apply_typed("Math.max", "oops", 0)    // args not a tuple
```

### Failure-value calls — `apply_guard`

`apply_guard(path, args, error_value)` — the result is a failure when it
**equals** `error_value`; anything else comes back as `Ok(any)`. Use it when
you know which value the function uses to signal failure.

```gleam
// is_atom uses false for "not an atom"
let assert Error(msg) = apply.apply_guard("erlang:is_atom", #(1), False)
// msg == "erlang:is_atom/1 returned false (guard error value)"

let assert Ok(False) = apply.apply_guard("erlang:is_atom", #(1), 0)  // false ≠ 0
let assert Ok(5) = apply.apply_guard("Math.max", #(1, 5), Nil)       // 5 ≠ nil

// console.log returns undefined (the JS failure sentinel)
let assert Error(msg) = apply.apply_guard("console.log", #(1), Nil)
// msg == "console.log/1 returned undefined (guard error value)"
```

### Platform-local types — `apply_guard` + `Nil`

Fetch values Gleam cannot express: Erlang references/atoms, JavaScript
objects. Any result that is not `nil`/`undefined` comes back as `Ok(any)`;
treat it as an **opaque handle** and feed it back into the runtime.

```gleam
// Erlang: make_ref returns a reference
let assert Ok(ref) = apply.apply_guard("erlang:make_ref", #(), Nil)
let assert Ok(True) = apply.apply_typed("erlang:is_reference", #(ref), False)

// JavaScript: JSON.parse returns a plain JS object
let assert Ok(obj) = apply.apply_guard("JSON.parse", #("{\"a\":1}"), Nil)
let assert Ok("{\"a\":1}") = apply.apply_typed("JSON.stringify", #(obj), "")
```

### Values you already hold — `unwrap` / `unwrap_not`

No calls involved; settle a dynamic value directly.

```gleam
// unwrap(value, default): same type → value, otherwise → default
apply.unwrap(5, 0)         // 5   (Int == Int)
apply.unwrap(5.5, 0)       // 0   (Float ≠ Int)
apply.unwrap("x", "")      // "x"
apply.unwrap(5, "")        // ""
apply.unwrap(False, False) // False

// unwrap_not(value, error_value): equals the error value → Error, else Ok(value)
let assert Ok(5) = apply.unwrap_not(5, False)
let assert Error(False) = apply.unwrap_not(False, False)
let assert Error(0) = apply.unwrap_not(0, 0)
let assert Error(Nil) = apply.unwrap_not(Nil, Nil)
```

### Fetching references — `get_erl_func` / `get_js_obj`

```gleam
// Erlang: export checked against arity; errors list the existing arities
let assert Ok(f) = apply.get_erl_func("lists:map", 2)
let assert Error(msg) = apply.get_erl_func("lists:map", 3)
// msg == "lists:map/3 is not exported in erlang (existing arities: 2)"

// JavaScript: resolve a dotted path on globalThis (no arity check)
let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
let assert Ok(_) = apply.get_js_obj("Math.max")
```

### Runtime checks

```gleam
apply.platform_name()          // "erlang" | "javascript"
apply.is_tuple(#(1, 2))        // True
apply.is_function(fn() { 1 })  // True
```

## API at a glance

| Function | Anchor | Returns | Use when |
| --- | --- | --- | --- |
| `apply_typed(path, args, default)` | type | `Result(a, String)` | call by path and require the result type to match `default` |
| `apply_guard(path, args, error_value)` | value | `Result(any, String)` | call by path; a result equal to `error_value` is a failure |
| `unwrap(value, default)` | type | `a` | settle a value in hand: same type → value, else `default` |
| `unwrap_not(value, error_value)` | value | `Result(any, a)` | settle a value in hand: equals `error_value` → `Error` |
| `get_erl_func(path, arity)` | - | `Result(any, String)` | fetch an Erlang function reference |
| `get_js_obj(path)` | - | `Result(any, String)` | fetch a JS global object / function |
| `platform_name()` / `is_tuple()` / `is_function()` | - | - | runtime checks |

## Type judgement rules

| Value | Erlang | JavaScript |
| --- | --- | --- |
| `true` / `false` | `Bool` (separated from other atoms) | `Bool` |
| `Int` vs `Float` | native types | `Math.ceil(v) - v === 0` → int, else float |
| `Nil` | atom `nil` | `undefined` |
| `String` / `BitArray` | both `binary` | `string` / `bit_array` |
| abnormal values | `false` / `nil` / `{error, _}` | `undefined` / `null` |

> On JavaScript `5.0` is the number `5` and is judged an `Int`; on Erlang
> `5.0` is a `Float`.

## Error messages

Both runtimes share a `path/arity + reason` style:

| Scenario | erlang | javascript |
| --- | --- | --- |
| Invalid path format | `bad path: "", expected "Module:Function"` | `bad path: "", expected "object.property"` |
| Target missing | `not_a_module:foo/1 not found in erlang (…)` | `Math.notExist/1 not found in javascript (…)` |
| Not exported at that arity | `erlang:length/2 is not exported in erlang (existing arities: 1)` | - |
| Target not callable | `error: undef when calling "erlang:length/2"` | `error: not a function when calling "Math.PI/1"` |
| Exception while executing | `error: badarg when calling "erlang:length/1"` | `SyntaxError: … when calling "JSON.parse/1"` |
| throw / exit | `throw: oops when calling "erlang:throw/1"` / `exit: bye …` | - |
| Type mismatch (`apply_typed`) | `erlang:is_atom/1 returned false (type boolean), expected type int` | `console.log/1 returned undefined (type undefined), expected type int` |
| Guard value hit (`apply_guard`) | `erlang:is_atom/1 returned false (guard error value)` | `console.log/1 returned undefined (guard error value)` |
| Args not a tuple | `args "oops" must be tuple type` | same as left |

## Development

```sh
gleam test                # default target
gleam test --target erlang
gleam test --target javascript
```

Tests skip themselves based on the runtime, so both files can stay enabled:

- `test/apply_test.gleam` (30 tests) — runs only on the javascript target
- `test/apply_erlang_test.gleam` (38 tests) — runs only on the erlang target

The Erlang toolchain or Node.js must be on `PATH`, depending on the target.
**Consumers never need to worry about any of this.**

Further documentation: <https://hexdocs.pm/apply/>.
