# apply

[![Package Version](https://img.shields.io/hexpm/v/apply)](https://hex.pm/packages/apply)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/apply/)

跨 Erlang / JavaScript 运行时的动态函数调用库：通过字符串路径在目标运行时中
解析并调用函数，统一返回 `Result(any, String)`，错误信息两侧风格一致
（带 `path/arity` 与具体原因）。

## 双目标架构

| | Erlang | JavaScript |
| --- | --- | --- |
| FFI 实现 | `src/erl_ffi.erl` | `src/jst_ffi.mjs` |
| 路径格式 | `"Module:Function"`，如 `"erlang:length"` | `"object.property"`，如 `"Math.max"` |
| 目标切换 | `gleam.toml` 中 `target = "erlang"` | `gleam.toml` 中 `target = "javascript"` |

## 安装

```sh
gleam add apply@1
```

## API 一览

| 函数 | 说明 |
| --- | --- |
| `apply/2` | 主入口：动态调用运行时函数（参数须为元组） |
| `get_erl_func/2` | 取 Erlang 函数引用，按 arity 校验导出（仅 erlang） |
| `get_js_obj/1` | 取 JavaScript 全局对象 / 函数（仅 javascript） |
| `call_erl/2`、`call_js/1` | 快速验证用，失败直接崩溃；正式使用请用 `apply` |
| `platform_name/0` | 当前运行时：`"erlang"` / `"javascript"` |
| `is_tuple/1`、`is_function/1` | 运行时值判断 |
| `do_get/2` | 底层接口，通常不直接使用 |

## 用法

### 动态调用函数（`apply/2`）

`raw_path` 在 Erlang 侧为 `"Module:Function"`，在 JavaScript 侧为 `"object.property"`；
`args` 必须是元组，元素按顺序展开为调用参数。

```gleam
import apply

pub fn main() {
  // ---- Erlang 目标 ----
  let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]))
  let assert Ok(10) = apply.apply("erlang:max", #(10, 2))
  let assert Ok("123") = apply.apply("erlang:integer_to_binary", #(123))

  // ---- JavaScript 目标 ----
  let assert Ok(5) = apply.apply("Math.max", #(1, 5))
  let assert Ok("123") = apply.apply("JSON.stringify", #(123))

  // 参数不是元组时返回错误（两侧一致）
  let assert Error(_) = apply.apply("erlang:length", "not a tuple")
}
```

> 注：Erlang 示例需在 `target = "erlang"` 下运行，JavaScript 示例需在
> `target = "javascript"` 下运行。

### 返回值处理

| 被调函数返回 | Erlang 侧 | JavaScript 侧 |
| --- | --- | --- |
| `ok` | 映射为 `Ok(Nil)` | 原样返回 |
| `{ok, X}` | 映射为 `Ok(X)` | 原样返回 |
| 其它 `Other` | `Ok(Other)` | `Ok(Other)` |
| 异常 / 目标不存在 | `Error(信息)` | `Error(信息)` |

> JavaScript 侧不做 `ok`/`{ok, X}` 特殊映射；函数返回 `undefined` 时（如
> `console.log`）对应 Gleam 的 `Ok(Nil)`。

### 获取运行时对象 / 函数引用

```gleam
// 仅 erlang 目标可用：按 arity 校验导出，错误信息会列出已有 arity
let assert Ok(f) = apply.get_erl_func("lists:map", 2)

let assert Error(msg) = apply.get_erl_func("lists:map", 3)
// msg == "lists:map/3 is not exported in erlang (existing arities: 2)"

// 仅 javascript 目标可用：按点路径取全局对象（不校验 arity，非函数也可取）
let assert Ok(_) = apply.get_js_obj("Math.max")
let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
```

### 运行时判断

```gleam
apply.platform_name()          // "erlang" 或 "javascript"
apply.is_tuple(#(1, 2))        // True
apply.is_function(fn() { 1 })  // True
```

## 错误信息格式

两侧统一为 `class: reason when calling "path/arity"` 风格：

| 场景 | erlang | javascript |
| --- | --- | --- |
| 路径格式非法 | `bad path: "a:b", expected "Module:Function"` | `bad path: "a..b", expected "object.property"` |
| 目标不存在 | `not_a_module:foo/1 not found in erlang (module or function does not exist)` | `Math.notExist not found in javascript (object or property does not exist)` |
| 该 arity 未导出 | `erlang:length/2 is not exported in erlang (existing arities: 1)` | —（JS 不校验 arity） |
| 目标不可调用 | `error: undef when calling "erlang:length/2"` | `error: not a function when calling "Math.PI/1"` |
| 执行抛异常 | `error: badarg when calling "erlang:length/1"` | `SyntaxError: ... when calling "JSON.parse/1"` |
| 显式 throw / exit | `throw: oops when calling "erlang:throw/1"`、`exit: bye when calling "erlang:exit/1"` | — |
| 参数非元组 | `args "oops" must be tuple type` | 同左 |
| 平台不匹配 | `need javascript runtime, now is erlang runtime` | `need erlang runtime, now is javascript runtime` |

补充说明：

- Erlang 侧 `get` 按 arity 校验导出，错误会列出该函数**已有的 arity**；
  JavaScript 侧 `get` 只做路径解析、不校验 arity，且允许返回任意对象（非函数也可取到）。
- Erlang 异常原因不限于原子（`throw`/`exit` 可抛任意 term），会按可读方式格式化。

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

两个测试文件可同时启用，测试内部按运行时自动跳过：

- `test/apply_test.gleam`（22 个用例）—— 只在 javascript 目标执行
- `test/apply_erlang_test.gleam`（24 个用例）—— 只在 erlang 目标执行

切换目标只需修改 `gleam.toml` 后执行 `gleam test` 重测：

```toml
# target = "erlang"
target = "javascript"
```

进一步文档见 <https://hexdocs.pm/apply/>。
