import apply
import gleam/string
import gleeunit

// 仅在 javascript 运行时执行测试，其它运行时直接跳过
fn on_javascript(run: fn() -> a) -> Nil {
  case apply.platform_name() {
    "javascript" -> {
      let _ = run()
      Nil
    }
    _ -> Nil
  }
}

pub fn main() -> Nil {
  gleeunit.main()
}

// ---- platform_name ----
pub fn platform_name_is_javascript_test() {
  on_javascript(fn() {
    assert apply.platform_name() == "javascript"
  })
}

// ---- is_tuple ----
pub fn is_tuple_true_for_tuples_test() {
  on_javascript(fn() {
    assert apply.is_tuple(#(1, 3, 4))
    assert apply.is_tuple(#("a"))
    assert apply.is_tuple(#())
    assert !apply.is_tuple([])
    assert !apply.is_tuple("")
  })
}

// ---- is_function ----
pub fn is_function_true_for_functions_test() {
  on_javascript(fn() {
    assert apply.is_function(fn() { 1 })
    assert apply.is_function(fn(x) { x })
  })
}

// ---- apply ----
pub fn apply_math_max_test() {
  on_javascript(fn() {
    let assert Ok(5) = apply.apply("Math.max", #(1, 5))
  })
}

pub fn apply_math_max_three_args_test() {
  on_javascript(fn() {
    let assert Ok(10) = apply.apply("Math.max", #(10, 2, 8))
  })
}

pub fn apply_math_abs_test() {
  on_javascript(fn() {
    let assert Ok(5) = apply.apply("Math.abs", #(-5))
  })
}

pub fn apply_json_stringify_test() {
  on_javascript(fn() {
    let assert Ok("123") = apply.apply("JSON.stringify", #(123))
  })
}

pub fn apply_console_log_returns_nil_test() {
  on_javascript(fn() {
    let assert Ok(Nil) = apply.apply("console.log", #(1))
  })
}

pub fn apply_non_function_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("Math.PI", #(1))
    assert msg == "error: not a function when calling \"Math.PI/1\""
  })
}

pub fn apply_non_tuple_args_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("Math.max", "oops")
    assert msg == "args \"oops\" must be tuple type"
  })
}

pub fn apply_missing_path_returns_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("not.exist.path", #(1, 2))
    assert msg
      == "not.exist.path/2 not found in javascript (object or property does not exist)"
  })
}

// ---- 运行时错误 ----
pub fn apply_runtime_exception_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("JSON.parse", #("not json"))
    echo msg
    // 函数执行中抛出的 JS 异常：带异常类型与调用目标
    assert string.contains(msg, "SyntaxError")
    assert string.contains(msg, "when calling \"JSON.parse/1\"")
  })
}

pub fn apply_missing_last_part_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("Math.notExist", #(1))
    assert msg
      == "Math.notExist/1 not found in javascript (object or property does not exist)"
  })
}

pub fn apply_bad_path_empty_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("", #(1))
    assert msg == "bad path: \"\", expected \"object.property\""
  })
}

pub fn apply_bad_path_empty_segment_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.apply("a..b", #(1))
    assert msg == "bad path: \"a..b\", expected \"object.property\""
  })
}

pub fn get_js_obj_bad_path_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.get_js_obj("")
    assert msg == "bad path: \"\", expected \"object.property\""
  })
}

pub fn get_js_obj_single_part_test() {
  on_javascript(fn() {
    // 单段路径直接解析到 globalThis（对应 erlang 侧省略模块前缀）
    let assert Ok(_) = apply.get_js_obj("console")
  })
}

// ---- get_js_obj ----
pub fn get_js_obj_math_pi_test() {
  on_javascript(fn() {
    let assert Ok(3.141592653589793) = apply.get_js_obj("Math.PI")
  })
}

pub fn get_js_obj_existing_function_test() {
  on_javascript(fn() {
    let assert Ok(_) = apply.get_js_obj("Math.max")
  })
}

pub fn get_js_obj_missing_last_part_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.get_js_obj("Math.notExist")
    assert msg
      == "Math.notExist not found in javascript (object or property does not exist)"
  })
}

pub fn get_js_obj_missing_middle_part_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.get_js_obj("not.exist.path")
    assert msg
      == "not.exist.path not found in javascript (object or property does not exist)"
  })
}

// ---- get_erl_func (JS 运行时总是返回错误) ----
pub fn get_erl_func_needs_erlang_runtime_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.get_erl_func("erlang:apply", 3)
    assert msg == "need erlang runtime, now is javascript runtime"
  })
}
