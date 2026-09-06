import { Result$Ok, Result$Error } from "./gleam.mjs";

export function platform_name() {
  return "javascript";
}

export function confirm_tuple(any) {
  return Array.isArray(any);
}

export function confirm_function(f) {
  return typeof f === "function";
}

// 解析 "a.b.c" 路径 -> [target, name]
// 格式非法抛 bad_path；中间段缺失抛 not_found
function resolve(path) {
  const parts = path.split(".");
  if (path === "" || parts.some((segment) => segment === "")) {
    throw new Error("bad_path");
  }
  let target = globalThis;
  for (let i = 0; i < parts.length - 1; i++) {
    target = target?.[parts[i]];
    if (target == null) {
      throw new Error("not_found");
    }
  }
  return [target, parts[parts.length - 1]];
}

// ---- 与 erlang 侧统一的错误信息格式 ----

// "path/Arity" 标签（数字拼进信息，对应 erlang 的 label/2）
function label(path, arity) {
  return `${path}/${arity}`;
}

function badPathError(path) {
  return `bad path: "${path}", expected "object.property"`;
}

// 对象/属性不存在；get 不需要 arity，try_apply 需要（带实际参数个数）
function notFoundError(path, arity) {
  const who = arity === undefined ? path : label(path, arity);
  return `${who} not found in javascript (object or property does not exist)`;
}

function applyError(path, arity, className, reason) {
  return `${className}: ${reason} when calling "${label(path, arity)}"`;
}

// get/2 —— 只负责取运行时对象/函数，不校验 arity
export function get(path) {
  try {
    const [target, name] = resolve(path);
    if (target?.[name] == null) {
      return Result$Error(notFoundError(path));
    }
    return Result$Ok(target[name]);
  } catch (error) {
    if (error.message === "bad_path") {
      return Result$Error(badPathError(path));
    }
    return Result$Error(notFoundError(path));
  }
}

export function try_apply(path, args) {
  const arity = args.length;
  try {
    const [target, name] = resolve(path);
    const fn = target?.[name];
    if (fn == null) {
      return Result$Error(notFoundError(path, arity));
    }
    if (typeof fn !== "function") {
      // 属性存在但不是函数：明确提示（比 erlang 的 undef 更直白）
      return Result$Error(
        `error: not a function when calling "${label(path, arity)}"`,
      );
    }
    const content = fn.apply(target, args);
    return Result$Ok(content);
  } catch (error) {
    if (error.message === "bad_path") {
      return Result$Error(badPathError(path));
    }
    if (error.message === "not_found") {
      return Result$Error(notFoundError(path, arity));
    }
    // 函数执行中抛出的 JS 异常，格式对应 erlang 的 apply_error
    return Result$Error(applyError(path, arity, error.name, error.message));
  }
}
