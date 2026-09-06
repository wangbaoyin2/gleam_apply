-module(erl_ffi).

-export([
    wait_msg/2,
    wait_msg_forever/1,
    try_apply/2,
    confirm_tuple/1,
    confirm_function/1,
    get/2,
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
%% try_apply/2 - dynamic call; errors carry the actual arity (number of args)
%% ============================================================================
try_apply(Raw, Args) when is_tuple(Args) ->
    try
        Arity = tuple_size(Args),
        case do_get(Raw) of
            {ok, {M, F}} ->
                case apply(M, F, tuple_to_list(Args)) of
                    ok        -> {ok, nil};
                    {ok, Any} -> {ok, Any};
                    Other     -> {ok, Other}
                end;
            {error, ErrReason} ->
                {error, resolve_error(Raw, Arity, ErrReason)}
        end
    catch
        Class:Reason:Stacktrace ->
            _ = Stacktrace,
            {error, apply_error(Raw, tuple_size(Args), Class, Reason)}
    end;
try_apply(_Raw, _Args) ->
    {error, <<"args must be a tuple">>}.

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
