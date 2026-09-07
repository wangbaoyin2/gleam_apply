import apply
import gleeunit

// Only run these tests on the erlang runtime; skip elsewhere
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

// ---- is_tuple / is_function (real BIFs on the erlang FFI) ----
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

// ---- apply (success paths) ----
pub fn apply_erlang_length_test() {
  on_erlang(fn() {
    let assert Ok(3) = apply.guard_type("erlang:length", #([1, 2, 3]), 0)
  })
}

pub fn apply_erlang_max_test() {
  on_erlang(fn() {
    let assert Ok(10) = apply.guard_type("erlang:max", #(10, 2), 0)
  })
}

pub fn apply_erlang_abs_test() {
  on_erlang(fn() {
    let assert Ok(5) = apply.guard_type("erlang:abs", #(-5), 0)
  })
}

pub fn apply_erlang_integer_to_binary_test() {
  on_erlang(fn() {
    let assert Ok("123") =
      apply.guard_type("erlang:integer_to_binary", #(123), "")
  })
}

pub fn apply_ok_result_maps_to_nil_test() {
  on_erlang(fn() {
    // io:format/2 returns ok; try_apply should map it to Ok(Nil)
    let assert Ok(Nil) = apply.guard_type("io:format", #("", []), Nil)
  })
}

// ---- apply (runtime errors, mirroring the JS side) ----
pub fn apply_non_tuple_args_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:length", "oops", 0)
    assert msg == "args \"oops\" must be tuple type"
  })
}

pub fn apply_missing_module_not_found_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("not_a_module:foo", #(1), 0)
    assert msg
      == "not_a_module:foo/1 not found in erlang (module or function does not exist)"
  })
}

pub fn apply_undef_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:length", #(), 0)
    assert msg == "error: undef when calling \"erlang:length/0\""
  })
}

pub fn apply_arity_in_error_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:length", #(1, 2), 0)
    assert msg == "error: undef when calling \"erlang:length/2\""
  })
}

pub fn apply_bad_path_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("Math.max", #(1, 5), 0)
    assert msg == "bad path: \"Math.max\", expected \"Module:Function\""
  })
}

pub fn apply_bad_path_empty_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("", #(1), 0)
    assert msg == "bad path: \"\", expected \"Module:Function\""
  })
}

pub fn apply_runtime_throw_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:throw", #("oops"), 0)
    assert msg == "throw: oops when calling \"erlang:throw/1\""
  })
}

pub fn apply_runtime_exit_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:exit", #("bye"), 0)
    assert msg == "exit: bye when calling \"erlang:exit/1\""
  })
}

pub fn apply_runtime_badarg_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.guard_type("erlang:length", #(1), 0)
    assert msg == "error: badarg when calling \"erlang:length/1\""
  })
}

// ---- 失败哨兵归一化（FFI 契约：false / nil / {error, _} 视为失败）----
pub fn apply_false_type_mismatch_error_test() {
  on_erlang(fn() {
    // is_atom(1) 返回 false（atom），default 是 0（integer）→ 类型不匹配
    let assert Error(msg) = apply.guard_type("erlang:is_atom", #(1), 0)
    assert msg
      == "erlang:is_atom/1 returned false (type boolean), expected type int"
  })
}

pub fn apply_true_value_ok_test() {
  on_erlang(fn() {
    // member 命中返回 true，default False（同为 atom 类型）→ Ok(True)
    let assert Ok(True) = apply.guard_type("lists:member", #(1, [1, 2]), False)
  })
}

pub fn apply_false_matches_bool_default_test() {
  on_erlang(fn() {
    // member 未命中返回 false，default False → 类型匹配 → Ok(False)
    let assert Ok(False) =
      apply.guard_type("lists:member", #(3, [1, 2]), False)
  })
}

pub fn apply_float_vs_int_mismatch_test() {
  on_erlang(fn() {
    // max 返回 2.5（float），default 0（integer）→ 类型不匹配
    let assert Error(msg) = apply.guard_type("erlang:max", #(1.5, 2.5), 0)
    assert msg == "erlang:max/2 returned 2.5 (type float), expected type int"
  })
}

pub fn apply_error_wrapper_type_mismatch_test() {
  on_erlang(fn() {
    // 函数返回 {error, einval}（tuple），default ""（binary）→ 类型不匹配
    let assert Error(msg) =
      apply.guard_type("inet:parse_address", #("not-an-ip"), "")
    assert msg
      == "inet:parse_address/1 returned {error,einval} (type tuple), expected type binary"
  })
}

// ---- unwrap（类型判定 + 默认值）----
pub fn unwrap_returns_value_when_type_matches_test() {
  on_erlang(fn() {
    assert apply.unwrap(5, 0) == 5
    assert apply.unwrap("x", "") == "x"
    assert apply.unwrap(False, False) == False
    let assert #(1, 2) = apply.unwrap(#(1, 2), #(0, 0))
  })
}

pub fn unwrap_returns_default_on_type_mismatch_test() {
  on_erlang(fn() {
    assert apply.unwrap(5, "") == ""
    assert apply.unwrap("x", 0) == 0
    // Float 与 Int 在 erlang 上是不同类型 → 返回默认值
    assert apply.unwrap(5.0, 0) == 0
  })
}

// ---- Nil default = 逃生舱：不做类型验证，返回平台本地类型 ----
pub fn guard_not_nil_returns_platform_local_test() {
  on_erlang(fn() {
    // guard_not 的 error_value 传 Nil：make_ref 返回 reference（≠ nil）→ Ok
    let assert Ok(ref) = apply.guard_not("erlang:make_ref", #(), Nil)
    // 把不透明句柄喂回 typed_apply 验证
    let assert Ok(True) =
      apply.guard_type("erlang:is_reference", #(ref), False)
  })
}

pub fn guard_not_hit_error_test() {
  on_erlang(fn() {
    // is_atom(1) 返回 false == error_value False → Error
    let assert Error(msg) = apply.guard_not("erlang:is_atom", #(1), False)
    assert msg == "erlang:is_atom/1 returned false (guard error value)"
  })
}

pub fn guard_not_miss_ok_test() {
  on_erlang(fn() {
    // error_value 是 0，is_atom(1) 返回 false ≠ 0 → Ok(False)
    let assert Ok(False) = apply.guard_not("erlang:is_atom", #(1), 0)
  })
}

pub fn guard_not_ok_result_maps_to_nil_test() {
  on_erlang(fn() {
    // io:format 返回 ok → 映射为 nil；error_value Nil → 命中 → Error
    let assert Error(msg) = apply.guard_not("io:format", #("", []), Nil)
    assert msg == "io:format/2 returned nil (guard error value)"
  })
}

pub fn unwrap_nil_default_still_strict_test() {
  on_erlang(fn() {
    // unwrap 恢复严格模式：default Nil 不再逃生，类型不同就返回 Nil
    assert apply.unwrap(5, Nil) == Nil
    assert apply.unwrap(#(1, 2, 3), Nil) == Nil
    assert apply.unwrap(Nil, Nil) == Nil
  })
}

// ---- unwrap_not（值锚定，值级 guard_not）----
pub fn unwrap_not_returns_ok_when_not_error_value_test() {
  on_erlang(fn() {
    let assert Ok(5) = apply.unwrap_not(5, False)
    let assert Ok("x") = apply.unwrap_not("x", "")
    // 平台本地句柄：make_ref 的 reference ≠ nil → Ok
    let assert Ok(ref) = apply.guard_not("erlang:make_ref", #(), Nil)
    let assert Ok(_) = apply.unwrap_not(ref, Nil)
  })
}

pub fn unwrap_not_returns_error_on_error_value_test() {
  on_erlang(fn() {
    let assert Error(False) = apply.unwrap_not(False, False)
    let assert Error(0) = apply.unwrap_not(0, 0)
    let assert Error(Nil) = apply.unwrap_not(Nil, Nil)
  })
}

// ---- get_js_obj (always an error on the erlang runtime) ----
pub fn get_js_obj_needs_javascript_runtime_test() {
  on_erlang(fn() {
    let assert Error(msg) = apply.get_js_obj("Math.max")
    assert msg == "need javascript runtime, now is erlang runtime"
  })
}
