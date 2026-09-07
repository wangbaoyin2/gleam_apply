import apply
import gleam/string
import gleeunit

// Only run these tests on the javascript runtime; skip elsewhere
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
    let assert Ok(5) = apply.guard_type("Math.max", #(1, 5), 0)
  })
}

pub fn apply_math_max_three_args_test() {
  on_javascript(fn() {
    let assert Ok(10) = apply.guard_type("Math.max", #(10, 2, 8), 0)
  })
}

pub fn apply_math_abs_test() {
  on_javascript(fn() {
    let assert Ok(5) = apply.guard_type("Math.abs", #(-5), 0)
  })
}

pub fn apply_json_stringify_test() {
  on_javascript(fn() {
    let assert Ok("123") = apply.guard_type("JSON.stringify", #(123), "")
  })
}

pub fn apply_console_log_type_mismatch_error_test() {
  on_javascript(fn() {
    // console.log 返回 undefined，default 0（number）→ 类型不匹配
    let assert Error(msg) = apply.guard_type("console.log", #(1), 0)
    assert msg
      == "console.log/1 returned undefined (type undefined), expected type int"
  })
}

pub fn apply_non_function_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("Math.PI", #(1), 0)
    assert msg == "error: not a function when calling \"Math.PI/1\""
  })
}

pub fn apply_non_tuple_args_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("Math.max", "oops", 0)
    assert msg == "args \"oops\" must be tuple type"
  })
}

pub fn apply_missing_path_returns_error_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("not.exist.path", #(1, 2), 0)
    assert msg
      == "not.exist.path/2 not found in javascript (object or property does not exist)"
  })
}

// ---- runtime errors ----
pub fn apply_runtime_exception_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("JSON.parse", #("not json"), "")
    //echo msg
    // JS exception thrown while executing: includes the exception type and call target
    assert string.contains(msg, "SyntaxError")
    assert string.contains(msg, "when calling \"JSON.parse/1\"")
  })
}

pub fn apply_missing_last_part_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("Math.notExist", #(1), 0)
    assert msg
      == "Math.notExist/1 not found in javascript (object or property does not exist)"
  })
}

pub fn apply_bad_path_empty_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("", #(1), 0)
    assert msg == "bad path: \"\", expected \"object.property\""
  })
}

pub fn apply_bad_path_empty_segment_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.guard_type("a..b", #(1), 0)
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
    // A single-segment path resolves directly on globalThis (mirrors the bare-name case on Erlang)
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

// ---- unwrap（类型判定 + 默认值）----
pub fn unwrap_returns_value_when_type_matches_test() {
  on_javascript(fn() {
    assert apply.unwrap(5, 0) == 5
    assert apply.unwrap("x", "") == "x"
    assert apply.unwrap(False, False) == False
    let assert #(1, 2) = apply.unwrap(#(1, 2), #(0, 0))
  })
}

pub fn unwrap_returns_default_on_type_mismatch_test() {
  on_javascript(fn() {
    assert apply.unwrap(5, "") == ""
    assert apply.unwrap("x", 0) == 0
    // 注：JS 按数值判定——5.0(值为5) 算 int，5.5 算 float
  })
}

// ---- Nil default = 逃生舱：不做类型验证，返回任意值 ----
pub fn guard_not_nil_returns_platform_local_test() {
  on_javascript(fn() {
    // guard_not 的 error_value 传 Nil（undefined）：JSON.parse 返回 JS 对象 → Ok
    let assert Ok(obj) = apply.guard_not("JSON.parse", #("{\"a\":1}"), Nil)
    let assert Ok("{\"a\":1}") = apply.guard_type("JSON.stringify", #(obj), "")
  })
}

pub fn guard_not_console_log_nil_hit_test() {
  on_javascript(fn() {
    // console.log 返回 undefined == error_value Nil → Error
    let assert Error(msg) = apply.guard_not("console.log", #(1), Nil)
    assert msg == "console.log/1 returned undefined (guard error value)"
  })
}

pub fn guard_not_miss_ok_test() {
  on_javascript(fn() {
    // error_value Nil，Math.max 返回 5 ≠ undefined → Ok(5)
    let assert Ok(5) = apply.guard_not("Math.max", #(1, 5), Nil)
  })
}

pub fn unwrap_nil_default_still_strict_test() {
  on_javascript(fn() {
    // unwrap 恢复严格模式：default Nil 不再逃生
    assert apply.unwrap(5, Nil) == Nil
    assert apply.unwrap("x", Nil) == Nil
    assert apply.unwrap(Nil, Nil) == Nil
  })
}

// ---- unwrap_not（值锚定）----
pub fn unwrap_not_returns_ok_when_not_error_value_test() {
  on_javascript(fn() {
    let assert Ok(5) = apply.unwrap_not(5, False)
    let assert Ok("x") = apply.unwrap_not("x", "")
  })
}

pub fn unwrap_not_returns_error_on_error_value_test() {
  on_javascript(fn() {
    let assert Error(False) = apply.unwrap_not(False, False)
    let assert Error(0) = apply.unwrap_not(0, 0)
    let assert Error(Nil) = apply.unwrap_not(Nil, Nil)
  })
}

// ---- get_erl_func (always an error on the JS runtime) ----
pub fn get_erl_func_needs_erlang_runtime_test() {
  on_javascript(fn() {
    let assert Error(msg) = apply.get_erl_func("erlang:apply", 3)
    assert msg == "need erlang runtime, now is javascript runtime"
  })
}
