//// Cross-runtime dynamic function invocation for Erlang and JavaScript.
////
//// Resolve functions by string path in the target runtime and call them,
//// returning a type-checked `Result(a, String)` where `a` is the type of the
//// `default` you pass. Error messages share a unified `path/arity + reason`
//// style on both targets.

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
fn try_apply(raw_path: String, args: any_type_tuple, default: a) -> Result(a, String)

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
/// Type judgement is precise on both runtimes:
///
/// - `true`/`false` are `Bool`, separated from other atoms (Erlang) and from
///   every other type (JavaScript)
/// - `Int` vs `Float`: Erlang distinguishes them natively; JavaScript rounds
///   the value (`Math.ceil(value) - value === 0`) - an `Int` yields exactly 0,
///   a `Float` never does because of its precision
///
/// ```gleam
/// let dynamic = apply.call_js("JSON.parse")("123") // any
/// let int = apply.unwrap(dynamic, 0)               // Int or 0
/// let text = apply.unwrap(dynamic, "")             // String or ""
/// ```
@external(erlang, "erl_ffi", "unwrap")
@external(javascript, "./jst_ffi.mjs", "unwrap")
pub fn unwrap(value: any, default: a) -> a

/// Dynamically invoke a runtime function - the main entry point.
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
/// **Handling multi-type returns.** Runtime functions are untyped from Gleam's
/// point of view: the same path can come back as an `Int` on one call and a
/// `Float` or `Bool` on another, and "abnormal" values (`undefined`, `false`,
/// `{error, _}`, ...) are just values too. `default` is the anchor that resolves
/// all of this: whatever comes back is compared against the type of `default`,
/// so you always get a type-safe `Result(a, String)` and never have to handle
/// raw `any` in Gleam:
///
/// ```gleam
/// apply.apply("erlang:length", #([1, 2, 3]), 0) // Ok(3)  (Int)
/// apply.apply("Math.max", #(1, 5), 0)           // Ok(5)  (Int)
/// apply.apply("erlang:is_atom", #(1), 0)
/// // Error("erlang:is_atom/1 returned false (type boolean), expected type int")
/// ```
///
/// The type judgement rules are shared with `unwrap/2` (see there).
pub fn apply(
  raw_path: String,
  args: args_tuple,
  default: a,
) -> Result(a, String) {
  // Arguments must be a tuple: delegate to the FFI when it is, fail otherwise
  use <- bool.lazy_guard(is_tuple(args), fn() {
    try_apply(raw_path, args, default)
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

/// Quick check helper: fetch a JS object, crashing on failure.
///
/// Prefer `apply` in real code; when `apply` is not enough, fetch the object
/// first and define the call behaviour yourself.
pub fn call_js(raw: String) {
  let assert Ok(f) = get_js_obj(raw)
  f
}

/// Quick check helper: fetch an Erlang function, crashing on failure.
///
/// Prefer `apply` in real code; when `apply` is not enough, fetch the function
/// first and define the call behaviour yourself.
pub fn call_erl(raw: String, arity: Int) {
  let assert Ok(f) = get_erl_func(raw, arity)
  f
}

/// Demo entry point.
pub fn main() {
  1
}
