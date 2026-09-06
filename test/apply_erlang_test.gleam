import apply
import gleeunit

// 仅在 erlang 运行时执行测试，其它运行时直接跳过
fn on_erlang(run: fn() -> a) -> Nil {
  case apply.platform_name() {
    "erlang" -> {
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
pub fn platform_name_is_erlang_test() {
  on_erlang(fn() {
    assert apply.platform_name() == "erlang"
  })
}

// ---- is_tuple / is_function（erlang FFI 均为真实 BIF）----
pub fn is_tuple_true_for_tuples_test() {
  on_erlang(fn() {
    assert apply.is_tuple(#(1, 2))
    assert apply.is_tuple(#("a", "b"))
  })
}

pub fn is_function_true_for_functions_test() {
  on_erlang(fn() {
    assert apply.is_function(fn() { 1 })
    assert apply.is_function(fn(x) { x + 1 })
  })
}

// ---- get_erl_func ----
pub fn get_erl_func_qualified_existing_test() {
  on_erlang(fn() {
    let assert Ok(_) = apply.get_erl_func("erlang:apply", 3)
  })
}

pub fn get_erl_func_unqualified_existing_test() {
  on_erlang(fn() {
    let assert Ok(_) = apply.get_erl_func("length", 1)
  })
}

pub fn get_erl_func_lists_map_test() {
  on_erlang(fn() {
    let assert Ok(_) = apply.get_erl_func("lists:map", 2)
  })
}

pub fn get_erl_func_missing_function_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.get_erl_func("lists:map", 3)
    assert msg == "lists:map/3 is not exported in erlang (existing arities: 2)"
  })
}

pub fn get_erl_func_arity_in_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.get_erl_func("length", 2)
    assert msg
      == "erlang:length/2 is not exported in erlang (existing arities: 1)"
  })
}

pub fn get_erl_func_missing_function_atom_test() {
  on_erlang(fn() {
    let assert Error(msg) =
      apply.get_erl_func("erlang:this_fn_does_not_exist", 1)
    assert msg
      == "erlang:this_fn_does_not_exist/1 not found in erlang (module or function does not exist)"
  })
}

// ---- apply（成功路径）----
pub fn apply_erlang_length_test() {
  on_erlang(fn() {
    let assert Ok(3) = apply.apply("erlang:length", #([1, 2, 3]))
  })
}

pub fn apply_erlang_max_test() {
  on_erlang(fn() {
    let assert Ok(10) = apply.apply("erlang:max", #(10, 2))
  })
}

pub fn apply_erlang_abs_test() {
  on_erlang(fn() {
    let assert Ok(5) = apply.apply("erlang:abs", #(-5))
  })
}

pub fn apply_erlang_integer_to_binary_test() {
  on_erlang(fn() {
    let assert Ok("123") = apply.apply("erlang:integer_to_binary", #(123))
  })
}

pub fn apply_ok_result_maps_to_nil_test() {
  on_erlang(fn() {
    // io:format/2 返回 ok，try_apply 应映射为 Ok(Nil)
    let assert Ok(Nil) = apply.apply("io:format", #("", []))
  })
}

// ---- apply（运行时错误，与 JS 侧对称）----
pub fn apply_non_tuple_args_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:length", "oops")
    assert msg == "args \"oops\" must be tuple type"
  })
}

pub fn apply_missing_module_not_found_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("not_a_module:foo", #(1))
    assert msg
      == "not_a_module:foo/1 not found in erlang (module or function does not exist)"
  })
}

pub fn apply_undef_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:length", #())
    assert msg == "error: undef when calling \"erlang:length/0\""
  })
}

pub fn apply_arity_in_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:length", #(1, 2))
    assert msg == "error: undef when calling \"erlang:length/2\""
  })
}

pub fn apply_bad_path_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("Math.max", #(1, 5))
    assert msg == "bad path: \"Math.max\", expected \"Module:Function\""
  })
}

pub fn apply_bad_path_empty_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("", #(1))
    assert msg == "bad path: \"\", expected \"Module:Function\""
  })
}

pub fn apply_runtime_throw_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:throw", #("oops"))
    assert msg == "throw: oops when calling \"erlang:throw/1\""
  })
}

pub fn apply_runtime_exit_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:exit", #("bye"))
    assert msg == "exit: bye when calling \"erlang:exit/1\""
  })
}

pub fn apply_runtime_badarg_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.apply("erlang:length", #(1))
    assert msg == "error: badarg when calling \"erlang:length/1\""
  })
}

// ---- get_js_obj（erlang 运行时恒返回错误）----
pub fn get_js_obj_needs_javascript_runtime_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.get_js_obj("Math.max")
    assert msg == "need javascript runtime, now is erlang runtime"
  })
}
