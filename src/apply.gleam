//// 跨 Erlang / JavaScript 运行时的动态函数调用库。
////
//// 通过字符串路径在目标运行时中解析并调用函数，统一返回
//// `Result(any, String)`。错误信息两侧统一为带 `path/arity` 与具体原因的风格。

///
import gleam/bool
import gleam/list
import gleam/string

/// 当前所在运行时平台。
///
/// Erlang 目标返回 `"erlang"`，JavaScript 目标返回 `"javascript"`。
@external(erlang, "erl_ffi", "platform_name")
@external(javascript, "./jst_ffi.mjs", "platform_name")
pub fn platform_name() -> String

/// 判断一个值是否为元组。
@external(erlang, "erl_ffi", "confirm_tuple")
@external(javascript, "./jst_ffi.mjs", "confirm_tuple")
pub fn is_tuple(any: tuple) -> Bool

/// 判断一个值是否为函数。
@external(erlang, "erl_ffi", "confirm_function")
@external(javascript, "./jst_ffi.mjs", "confirm_function")
pub fn is_function(func: function) -> Bool

/// 获取运行时对象/函数引用（底层接口）。
///
/// Erlang 侧按 `erl_arity` 校验函数导出；JavaScript 侧仅做路径解析、不校验 arity。
/// 通常不直接调用，请使用 `get_erl_func` / `get_js_obj`。
@external(erlang, "erl_ffi", "get")
@external(javascript, "./jst_ffi.mjs", "get")
pub fn do_get(raw_path: String, erl_arity: Int) -> Result(any, String)

/// 内部接口：按路径调用函数（要求参数是元组）。
@external(erlang, "erl_ffi", "try_apply")
@external(javascript, "./jst_ffi.mjs", "try_apply")
fn try_apply(raw_path: String, args: any_type_tuple) -> Result(a, String)

/// 动态调用运行时函数，库的主入口。
///
/// - `raw_path`：Erlang 用 `"Module:Function"`，JavaScript 用 `"object.property"`。
/// - `args`：必须是元组，元素按顺序展开为调用参数。
///
/// 参数不是元组时返回错误；路径不存在、目标不可调用或执行抛异常时，
/// 返回统一格式的错误信息。
///
/// ```gleam
/// apply.apply("erlang:length", #([1, 2, 3])) // Ok(3)
/// apply.apply("Math.max", #(1, 5))           // Ok(5)
/// ```
pub fn apply(raw_path: String, args: args_tuple) -> Result(any, String) {
  // 参数必须是元组：是则交给 FFI 调用，否则返回类型错误
  use <- bool.lazy_guard(is_tuple(args), fn() { try_apply(raw_path, args) })

  Error("args " <> { args |> string.inspect } <> " must be tuple type")
}

/// 获取 Erlang 运行时函数引用（仅 erlang 目标可用）。
///
/// 传入 `"Module:Function"`，或仅函数名（自动补 `erlang:` 前缀）。
/// 成功返回 `Ok(fun)`；在 JavaScript 目标上恒返回运行时错误。
///
/// 错误信息包含 arity，例如：
/// `"erlang:length/2 is not exported in erlang (existing arities: 1)"`
pub fn get_erl_func(raw_path: String, erl_arity: Int) {
  use <- bool.lazy_guard(platform_name() == "erlang", fn() {
    // "Module:Function" -> 直接解析；只有函数名 -> 补 erlang: 前缀
    case raw_path |> string.split(":") |> list.length {
      2 -> do_get(raw_path, erl_arity)
      1 -> do_get("erlang:" <> raw_path, erl_arity)
      _ -> Error("gleam side input bad args")
    }
  })
  Error("need erlang runtime, now is javascript runtime")
}

/// 获取 JavaScript 运行时对象/函数（仅 javascript 目标可用）。
///
/// 传入点路径如 `"Math.PI"`、`"console.log"`。
/// 在 Erlang 目标上恒返回运行时错误。
pub fn get_js_obj(raw_script: String) -> Result(any, String) {
  use <- bool.lazy_guard(platform_name() == "javascript", fn() {
    do_get(raw_script, 0)
  })
  Error("need javascript runtime, now is erlang runtime")
}

/// 快速验证用：取 JS 运行时对象，失败时直接崩溃。
///
/// 正式使用请用 `apply`；当 `apply` 不满足需求时，
/// 可先取到对象再自行定义调用行为。
pub fn call_js(raw: String) {
  let assert Ok(f) = get_js_obj(raw)
  f
}

/// 快速验证用：取 Erlang 函数引用，失败时直接崩溃。
///
/// 正式使用请用 `apply`；当 `apply` 不满足需求时，
/// 可先取到函数再自行定义调用行为。
pub fn call_erl(raw: String, arity: Int) {
  let assert Ok(f) = get_erl_func(raw, arity)
  f
}

/// 演示入口。
pub fn main() {
  echo is_tuple(#(1, 3, 4))
  // echo get_erl("erlang:apply", 3)
  // echo get_erl("erlang:atom", 2)
  // echo get_erl("atom", 1)
  echo get_js_obj("console.log.sdf")
  echo get_js_obj("console.sdf.sdf")
  // calljs("console.lo")(123, 436)
  echo string.split("atom", ":") |> list.length

  // echo call_erl("binary_to_atom", 1)("hello")
  echo apply("console.log", #(123, 434))
}
