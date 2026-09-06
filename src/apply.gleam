//// Cross-runtime dynamic function invocation for Erlang and JavaScript.
////
//// Resolve functions by string path in the target runtime and call them,
//// returning `Result(any, String)`. Error messages share a unified
//// `path/arity + reason` style on both targets.

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
pub fn do_get(raw_script: String, erl_arity: Int) -> Result(any, String)

/// Internal: invoke a function by path (arguments must be a tuple).
@external(erlang, "erl_ffi", "try_apply")
@external(javascript, "./jst_ffi.mjs", "try_apply")
fn try_apply(raw_path: String, args: any_type_tuple) -> Result(a, String)

/// Dynamically invoke a runtime function - the main entry point.
///
/// - `raw_path`: `"Module:Function"` on Erlang, `"object.property"` on JavaScript.
/// - `args`: must be a tuple; elements are spread as call arguments in order.
///
/// Returns an error when `args` is not a tuple, and a unified error message
/// when the path is missing, the target is not callable, or the call throws.
///
/// ```gleam
/// apply.apply("erlang:length", #([1, 2, 3])) // Ok(3)
/// apply.apply("Math.max", #(1, 5))           // Ok(5)
/// ```
pub fn apply(raw_path: String, args: args_tuple) -> Result(any, String) {
  // Arguments must be a tuple: delegate to the FFI when it is, fail otherwise
  use <- bool.lazy_guard(is_tuple(args), fn() { try_apply(raw_path, args) })

  Error("args " <> { args |> string.inspect } <> " must be tuple type")
}

/// Fetch an Erlang function reference (Erlang target only).
///
/// Accepts `"Module:Function"`, or a bare function name which is prefixed
/// with `erlang:`. Returns `Ok(fun)` on success; always returns a runtime
/// error on the JavaScript target.
///
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
