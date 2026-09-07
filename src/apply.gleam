//// Cross-runtime dynamic function invocation for Erlang and JavaScript.
////
//// Resolve functions by string path in the target runtime and call them:
//// `guard_type` enforces a return type via a `default` anchor,
//// `guard_not` treats a specific value as failure. Error messages share a
//// unified `path/arity + reason` style on both targets.

///
import gleam/bool
import gleam/list
import gleam/string

/// The current runtime platform.
///
/// Returns `"erlang"` on the Erlang target and `"javascript"` on the
/// JavaScript target.
@external(erlang, "erl_ffi", "platform_name")
@external(javascript, "./jst_ffi.mjs", "platform_name")
pub fn platform_name() -> String

/// Whether a value is a tuple.
@external(erlang, "erl_ffi", "confirm_tuple")
@external(javascript, "./jst_ffi.mjs", "confirm_tuple")
pub fn is_tuple(any: tuple) -> Bool

/// Whether a value is a function.
@external(erlang, "erl_ffi", "confirm_function")
@external(javascript, "./jst_ffi.mjs", "confirm_function")
pub fn is_function(func: function) -> Bool

/// Low-level access to a runtime object or function.
///
/// On Erlang, exports are checked against `erl_arity`; on JavaScript the path
/// is only resolved and arity is ignored. Prefer `get_erl_func` / `get_js_obj`.
@external(erlang, "erl_ffi", "get")
@external(javascript, "./jst_ffi.mjs", "get")
fn do_get(raw_script: String, erl_arity: Int) -> Result(any, String)

/// Internal: invoke a function by path (arguments must be a tuple).
@external(erlang, "erl_ffi", "try_apply")
@external(javascript, "./jst_ffi.mjs", "try_apply")
fn try_apply_typed(
  raw_path: String,
  args: any_type_tuple,
  default: a,
) -> Result(a, String)

/// Internal: invoke a function by path, treating a specific value as failure.
@external(erlang, "erl_ffi", "try_apply_guard")
@external(javascript, "./jst_ffi.mjs", "try_apply_guard")
fn try_apply_guard(
  raw_path: String,
  args: any_type_tuple,
  error_value: a,
) -> Result(any, String)

/// Type-checked fallback for a dynamic value.
///
/// Functions fetched from a runtime (`get_js_obj` / `get_erl_func`) can return
/// **more than one type**: an `Int`, a `Float`, a `Bool`, a `String`, a list -
/// or even an abnormal value such as JS `undefined`/`null` or Erlang
/// `false`/`nil`/`{error, _}`. Gleam cannot know which one you got, so it types
/// the value as `any`. `unwrap/2` settles that:
///
/// - same runtime type as `default` -> `value` (already of type `a`)
/// - otherwise                     -> `default`
///
/// ```gleam
/// let int = apply.unwrap(5, 0)    // 5   （Int 与 0 同类型）
/// let text = apply.unwrap(5, "")  // ""  （Int ≠ String，回退默认值）
/// ```
@external(erlang, "erl_ffi", "unwrap")
@external(javascript, "./jst_ffi.mjs", "unwrap")
pub fn unwrap(value: any, default: a) -> a

/// Value-anchor check for a dynamic value — the value-level `guard_not`.
///
/// If `value` is **not** the `error_value`, returns `Ok(value)` (any type);
/// if it **equals** `error_value`, returns `Error(error_value)`.
///
/// Unlike `unwrap` (which compares *types* and falls back), this compares
/// *values* and reports the match as an error. Unlike `guard_not` (which
/// resolves and calls a path), this just checks a value you already hold.
///
/// ```gleam
/// let assert Ok(5) = apply.unwrap_not(5, False)   // 5 ≠ false
/// let assert Error(False) = apply.unwrap_not(False, False)
/// let assert Error(Nil) = apply.unwrap_not(Nil, Nil)
/// ```
@external(erlang, "erl_ffi", "unwrap_not")
@external(javascript, "./jst_ffi.mjs", "unwrap_not")
pub fn unwrap_not(value: any, error_value: a) -> Result(any, a)

/// Dynamically invoke a runtime function with a strict type check.
///
/// - `raw_path`: `"Module:Function"` on Erlang, `"object.property"` on JavaScript.
/// - `args`: must be a tuple; elements are spread as call arguments in order.
/// - `default`: pins the expected return type; the call result is type-checked
///   against it at runtime before being returned.
///
/// Returns `Result(a, String)` where `a` is the type of `default`:
///
/// - `Ok(value)`      - the call succeeded and the result has the same runtime
///   type as `default`
/// - `Error(message)` - bad path, target not callable, exception caught, or the
///   result type does not match `default`
///
///
/// ```gleam
/// apply.guard_type("erlang:length", #([1, 2, 3]), 0) // Ok(3)  (Int)
/// apply.guard_type("Math.max", #(1, 5), 0)           // Ok(5)  (Int)
/// apply.guard_type("erlang:is_atom", #(1), 0)
/// // Error("erlang:is_atom/1 returned false (type boolean), expected type int")
/// ```
///
/// The type judgement rules are shared with `unwrap/2` (see there). If you
/// only care about *which value* the function uses as its failure signal (not
/// its type), use `guard_not` instead.
pub fn guard_type(
  raw_path: String,
  args: args_tuple,
  default: a,
) -> Result(a, String) {
  // Arguments must be a tuple: delegate to the FFI when it is, fail otherwise
  use <- bool.lazy_guard(is_tuple(args), fn() {
    try_apply_typed(raw_path, args, default)
  })

  Error("args " <> { args |> string.inspect } <> " must be tuple type")
}

/// Dynamically invoke a runtime function, treating a specific value as failure.
///
/// - `raw_path`: `"Module:Function"` on Erlang, `"object.property"` on JavaScript.
/// - `args`: must be a tuple; elements are spread as call arguments in order.
/// - `error_value`: the exact value the function uses to signal failure — JS
///   `undefined`/`null`, Erlang `false`/`nil`/`{error, _}`, `-1`, `""`, ...
///
/// Returns `Result(any, String)`:
///
/// - `Ok(value)`     - the call succeeded and the result is **not** the error
///   value (any type; interpret it yourself)
/// - `Error(message)` - bad path, target not callable, exception caught, or the
///   result **equals** `error_value`
///
/// This checks *values*, not types — the result comes back as `any`. Use
/// `guard_type` when you need a type guarantee instead.
///
/// Passing `Nil` as `error_value` is the natural way to fetch **platform-local
/// values** (Erlang references, JavaScript objects): anything except `nil`/
/// `undefined` comes back as `Ok`, so no type signature is bent:
///
/// ```gleam
/// let assert Ok(ref) = apply.guard_not("erlang:make_ref", #(), Nil)
/// let assert Ok(True) = apply.guard_type("erlang:is_reference", #(ref), False)
///
/// let assert Error(msg) = apply.guard_not("erlang:is_atom", #(1), False)
/// // msg == "erlang:is_atom/1 returned false (guard error value)"
/// ```
pub fn guard_not(
  raw_path: String,
  args: args_tuple,
  error_value: a,
) -> Result(any, String) {
  // Arguments must be a tuple: delegate to the FFI when it is, fail otherwise
  use <- bool.lazy_guard(is_tuple(args), fn() {
    try_apply_guard(raw_path, args, error_value)
  })

  Error("args " <> { args |> string.inspect } <> " must be tuple type")
}

/// Fetch an Erlang function reference (Erlang target only).
///
/// Accepts `"Module:Function"`, or a bare function name which is prefixed
/// with `erlang:`. Returns `Ok(fun)` on success; always returns a runtime
/// error on the JavaScript target.
///```
/// let assert Ok(map) = apply.get_erl_func("lists:map", 2)
/// ```
/// Errors include the arity, e.g.
/// `"erlang:length/2 is not exported in erlang (existing arities: 1)"`.
pub fn get_erl_func(raw_path: String, erl_arity: Int) {
  use <- bool.lazy_guard(platform_name() == "erlang", fn() {
    // "Module:Function" -> resolve as-is; bare name -> prefix "erlang:"
    case raw_path |> string.split(":") |> list.length {
      2 -> do_get(raw_path, erl_arity)
      1 -> do_get("erlang:" <> raw_path, erl_arity)
      _ -> Error("gleam side input bad args")
    }
  })
  Error("need erlang runtime, now is javascript runtime")
}

/// Fetch a JavaScript runtime object or function (JavaScript target only).
///
/// Takes a dotted path such as `"Math.PI"` or `"console.log"`.
/// ```
/// let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
/// let assert Ok(max) = apply.get_js_obj("Math.max")
/// ```
/// Always returns a runtime error on the Erlang target.
pub fn get_js_obj(raw_script: String) -> Result(any, String) {
  use <- bool.lazy_guard(platform_name() == "javascript", fn() {
    do_get(raw_script, 0)
  })
  Error("need javascript runtime, now is erlang runtime")
}

pub fn main() {
  1
}
