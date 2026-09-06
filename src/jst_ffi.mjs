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

export function try_apply(path, args) {
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
    return Result$Ok(content);
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
