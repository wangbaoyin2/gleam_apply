-module(erl_ffi).

-export([
    wait_msg/2,
    wait_msg_forever/1,
    try_apply/3,
    try_apply_guard/3,
    confirm_tuple/1,
    confirm_function/1,
    get/2,
    unwrap/2,
    unwrap_not/2,
    platform_name/0
]).

platform_name() ->
    ~"erlang".

%% ============================================================================
%% Resolve a "Module:Function" path -> {ok, {M, F}} | {error, Reason}
%% ============================================================================
do_get(Raw) ->
    try
        case binary:split(Raw, <<":">>, []) of
            [M, F] ->
                {ok, {
                    binary_to_existing_atom(M, utf8),
                    binary_to_existing_atom(F, utf8)
                }};
            _ ->
                {error, bad_path}
        end
    catch
        error:badarg ->
            {error, not_found}
    end.

%% ============================================================================
%% get/2 - check the export for the given arity and return a fun reference
%% ============================================================================
get(Raw, Arity) ->
    case do_get(Raw) of
        {ok, {M, F}} ->
            case erlang:function_exported(M, F, Arity) of
                true ->
                    {ok, fun M:F/Arity};
                false ->
                    {error, not_exported_error(Raw, M, F, Arity)}
            end;
        {error, Reason} ->
            {error, resolve_error(Raw, Arity, Reason)}
    end.

%% ============================================================================
%% try_apply/3 - dynamic call with a type-checked default:
%% result type matches Default -> {ok, Result}, otherwise -> {error, Msg}
%% ============================================================================
try_apply(Raw, Args, Default) when is_tuple(Args) ->
    try
        Arity = tuple_size(Args),
        case do_get(Raw) of
            {ok, {M, F}} ->
                case apply(M, F, tuple_to_list(Args)) of
                    ok         -> check_or_error(Raw, Arity, nil, Default);
                    {ok, Any}  -> check_or_error(Raw, Arity, Any, Default);
                    {error, E} -> check_or_error(Raw, Arity, {error, E}, Default);
                    false      -> check_or_error(Raw, Arity, false, Default);
                    nil        -> check_or_error(Raw, Arity, nil, Default);
                    Other      -> check_or_error(Raw, Arity, Other, Default)
                end;
            {error, ErrReason} ->
                {error, resolve_error(Raw, Arity, ErrReason)}
        end
    catch
        Class:Reason:Stacktrace ->
            _ = Stacktrace,
            {error, apply_error(Raw, tuple_size(Args), Class, Reason)}
    end;
try_apply(_Raw, _Args, _Default) ->
    {error, <<"args must be a tuple">>}.

%% Type-check the call result against Default (strict):
%% same type -> {ok, Value}; different -> {error, mismatch message}.
check_or_error(Raw, Arity, Value, Default) ->
    case gleam_type(Value) =:= gleam_type(Default) of
        true  -> {ok, Value};
        false -> {error, type_mismatch_error(Raw, Arity, Value, Default)}
    end.

type_mismatch_error(Raw, Arity, Value, Default) ->
    V = fmt_term(Value),
    VT = atom_to_binary(gleam_type(Value), utf8),
    DT = atom_to_binary(gleam_type(Default), utf8),
    <<(label(Raw, Arity))/binary, " returned ", V/binary,
      " (type ", VT/binary, "), expected type ", DT/binary>>.

%% ============================================================================
%% try_apply_guard/3 - dynamic call treating a specific value as failure:
%% result =:= ErrorValue -> {error, guard message}, otherwise {ok, Value}.
%% ============================================================================
try_apply_guard(Raw, Args, ErrorValue) when is_tuple(Args) ->
    try
        Arity = tuple_size(Args),
        case do_get(Raw) of
            {ok, {M, F}} ->
                case apply(M, F, tuple_to_list(Args)) of
                    ok         -> check_guard(Raw, Arity, nil, ErrorValue);
                    {ok, Any}  -> check_guard(Raw, Arity, Any, ErrorValue);
                    {error, E} -> check_guard(Raw, Arity, {error, E}, ErrorValue);
                    false      -> check_guard(Raw, Arity, false, ErrorValue);
                    nil        -> check_guard(Raw, Arity, nil, ErrorValue);
                    Other      -> check_guard(Raw, Arity, Other, ErrorValue)
                end;
            {error, ErrReason} ->
                {error, resolve_error(Raw, Arity, ErrReason)}
        end
    catch
        Class:Reason:Stacktrace ->
            _ = Stacktrace,
            {error, apply_error(Raw, tuple_size(Args), Class, Reason)}
    end;
try_apply_guard(_Raw, _Args, _ErrorValue) ->
    {error, <<"args must be a tuple">>}.

%% Guard check: Value =:= ErrorValue -> {error, ...}, otherwise {ok, Value}
check_guard(Raw, Arity, Value, ErrorValue) ->
    case Value =:= ErrorValue of
        true  -> {error, guard_error(Raw, Arity, Value)};
        false -> {ok, Value}
    end.

guard_error(Raw, Arity, Value) ->
    V = fmt_term(Value),
    <<(label(Raw, Arity))/binary, " returned ", V/binary,
      " (guard error value)">>.

%% ============================================================================
%% unwrap/2 - if Value has the same runtime type as Default, return Value,
%% otherwise return Default. Pins a dynamic value to the type of Default.
%% ============================================================================
unwrap(Value, Default) ->
    case gleam_type(Value) =:= gleam_type(Default) of
        true  -> Value;
        false -> Default
    end.

%% ============================================================================
%% unwrap_not/2 - value-level apply_guard:
%% Value =/= ErrorValue -> {ok, Value}; Value =:= ErrorValue -> {error, ErrorValue}
%% ============================================================================
unwrap_not(Value, ErrorValue) ->
    case Value =:= ErrorValue of
        true  -> {error, ErrorValue};
        false -> {ok, Value}
    end.

%% Normalised Gleam-level type tag (mirrored by kind/1 in jst_ffi.mjs).
%% true/false are separated from other atoms -> boolean.
gleam_type(true)  -> boolean;
gleam_type(false) -> boolean;
gleam_type(V) when is_atom(V)     -> atom;      % Nil / other atoms
gleam_type(V) when is_binary(V)   -> binary;    % String / BitArray
gleam_type(V) when is_integer(V)  -> int;
gleam_type(V) when is_float(V)    -> float;
gleam_type(V) when is_list(V)     -> list;
gleam_type(V) when is_tuple(V)    -> tuple;
gleam_type(V) when is_map(V)      -> map;
gleam_type(V) when is_function(V) -> function;
gleam_type(V) when is_pid(V)      -> pid;
gleam_type(_)                     -> other.

%% ============================================================================
%% Error message formatting
%% ============================================================================

%% "Module:Function/Arity" label; the number is joined into the binary
%% with integer_to_binary/1
label(Raw, Arity) ->
    <<Raw/binary, "/", (integer_to_binary(Arity))/binary>>.

%% do_get stage errors
resolve_error(Raw, _Arity, bad_path) ->
    <<"bad path: \"", Raw/binary, "\", expected \"Module:Function\"">>;
resolve_error(Raw, Arity, not_found) ->
    <<(label(Raw, Arity))/binary,
      " not found in erlang (module or function does not exist)">>.

%% Function not exported at the given arity: also list the existing arities
not_exported_error(Raw, M, F, Arity) ->
    case exported_arities(M, F) of
        [] ->
            <<(label(Raw, Arity))/binary,
              " is not exported in erlang (no such function)">>;
        Arities ->
            Existing = list_to_binary(
                lists:join(", ", [integer_to_binary(A) || A <- Arities])
            ),
            <<(label(Raw, Arity))/binary,
              " is not exported in erlang (existing arities: ",
              Existing/binary, ")">>
    end.

%% apply stage exceptions: class: reason when calling "M:F/Arity"
apply_error(Raw, Arity, Class, Reason) ->
    C = atom_to_binary(Class, utf8),
    R = fmt_term(Reason),
    <<C/binary, ": ", R/binary, " when calling \"",
      (label(Raw, Arity))/binary, "\"">>.

%% Turn an exception reason into a readable binary (not always an atom)
fmt_term(Term) when is_atom(Term) ->
    atom_to_binary(Term, utf8);
fmt_term(Term) when is_binary(Term) ->
    Term;
fmt_term(Term) ->
    unicode:characters_to_binary(io_lib:format("~0p", [Term])).

%% Exported arities of function F in module M (ascending)
exported_arities(M, F) ->
    case erlang:module_loaded(M) of
        true ->
            lists:sort([A || {F2, A} <- M:module_info(exports), F2 =:= F]);
        false ->
            []
    end.

confirm_function(F) ->
    is_function(F).

confirm_tuple(A) ->
    is_tuple(A).

wait_msg(Dura, Fn) ->
    receive
        Any ->
            {ok, Fn(Any)}
    after Dura ->
        {error, nil}
    end.

wait_msg_forever(Fn) ->
    receive
        Any ->
            Fn(Any)
    end.
