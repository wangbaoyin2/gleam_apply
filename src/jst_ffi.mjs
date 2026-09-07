import { Result$Ok, Result$Error, List } from "./gleam.mjs";

export function platform_name() {
  return "javascript";
}

export function confirm_tuple(any) {
  return Array.isArray(any);
}

export function confirm_function(f) {
  return typeof f === "function";
}

// Resolve a "a.b.c" path -> [target, name]
// Throws "bad_path" for invalid formats, "not_found" when a middle segment is missing.
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

// ---- Error message format, unified with the Erlang side ----

// "path/Arity" label (the number is joined into the message, mirrors Erlang's label/2)
function label(path, arity) {
  return `${path}/${arity}`;
}

function badPathError(path) {
  return `bad path: "${path}", expected "object.property"`;
}

// Object/property not found; get does not carry arity, try_apply does (real arg count)
function notFoundError(path, arity) {
  const who = arity === undefined ? path : label(path, arity);
  return `${who} not found in javascript (object or property does not exist)`;
}

function applyError(path, arity, className, reason) {
  return `${className}: ${reason} when calling "${label(path, arity)}"`;
}

// ---- Type check: JS kind tag (mirrors Erlang gleam_type/1) ----
function kind(v) {
  if (v === undefined) return "undefined"; // Nil
  if (v === null) return "null";
  if (Array.isArray(v)) return "tuple";
  if (v instanceof List) return "list";
  if (v instanceof Uint8Array) return "bit_array";
  if (typeof v === "number") {
    // Int / Float 判定：先取整（Math.ceil）再与原值相减——
    // int 结果为 0，float 因精度问题结果非 0
    return Math.ceil(v) - v === 0 ? "int" : "float";
  }
  return typeof v; // string | boolean | function | object
}

function sameType(a, b) {
  return kind(a) === kind(b);
}

// unwrap/2: value type matches default type ? value : default
export function unwrap(value, default_) {
  return sameType(value, default_) ? value : default_;
}

function renderValue(v) {
  if (v === undefined) return "undefined";
  if (v === null) return "null";
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

// get/2 - fetch a runtime object/function only, no arity checking
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

export function try_apply(path, args, default_) {
  const arity = args.length;
  try {
    const [target, name] = resolve(path);
    const fn = target?.[name];
    if (fn == null) {
      // Mirrors Erlang's not_found
      return Result$Error(notFoundError(path, arity));
    }
    if (typeof fn !== "function") {
      // The property exists but is not callable: be explicit
      // (the Erlang side reports `undef` here)
      return Result$Error(
        `error: not a function when calling "${label(path, arity)}"`,
      );
    }
    const content = fn.apply(target, args);
    // Type-check against the default: same kind -> Ok(content),
    // otherwise -> Error(mismatch message)
    if (sameType(content, default_)) {
      return Result$Ok(content);
    }
    return Result$Error(typeMismatchError(path, arity, content, default_));
  } catch (error) {
    if (error.message === "bad_path") {
      return Result$Error(badPathError(path));
    }
    if (error.message === "not_found") {
      return Result$Error(notFoundError(path, arity));
    }
    // Exception thrown while executing the function, mirrors Erlang's apply_error
    return Result$Error(applyError(path, arity, error.name, error.message));
  }
}

function typeMismatchError(path, arity, value, default_) {
  return `${label(path, arity)} returned ${renderValue(value)} (type ${kind(value)}), expected type ${kind(default_)}`;
}
