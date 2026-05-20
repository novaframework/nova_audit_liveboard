-module(nova_audit_liveboard_main_controller).
-moduledoc """
Controller for the `nova_audit_liveboard` browser panel.

Renders a filterable, paginated table of audit events from a configured
`nova_audit` log. Read-only.
""".

-export([index/1]).

-define(DEFAULT_PAGE_SIZE, 50).

index(Req) ->
    LogName = log_name_from(Req),
    Qs = cowboy_req:parse_qs(Req),
    Filter = build_filter(Qs),
    QueryOpts = build_query_opts(Qs),
    case nova_audit:query(LogName, Filter, QueryOpts) of
        {ok, Events, Cursor} ->
            {ok, [
                {log_name, atom_to_binary(LogName)},
                {events, [format_event(E) || E <- Events]},
                {has_events, Events =/= []},
                {filter_actor_id, maps:get(actor_id, Filter, <<>>)},
                {filter_action, maps:get(action, Filter, <<>>)},
                {filter_target_id, maps:get(target_id, Filter, <<>>)},
                {filter_target_type, maps:get(target_type, Filter, <<>>)},
                {filter_request_id, maps:get(request_id, Filter, <<>>)},
                {filter_outcome, outcome_to_binary(maps:get(outcome, Filter, undefined))},
                {filter_since, time_field(Filter, occurred_after)},
                {filter_until, time_field(Filter, occurred_before)},
                {next_url, next_url(Qs, Cursor)},
                {has_next, Cursor =/= done},
                {error, undefined}
            ]};
        {error, Reason} ->
            {ok, [
                {log_name, atom_to_binary(LogName)},
                {events, []},
                {has_events, false},
                {filter_actor_id, <<>>},
                {filter_action, <<>>},
                {filter_target_id, <<>>},
                {filter_target_type, <<>>},
                {filter_request_id, <<>>},
                {filter_outcome, <<>>},
                {filter_since, <<>>},
                {filter_until, <<>>},
                {next_url, <<>>},
                {has_next, false},
                {error, format_error(Reason)}
            ]}
    end.

%% --- Inputs ---

log_name_from(Req) ->
    Bindings = cowboy_req:bindings(Req),
    case maps:get(log_name, Bindings, undefined) of
        undefined ->
            case application:get_env(nova_audit_liveboard, default_log, undefined) of
                undefined -> error(no_log_configured);
                D -> D
            end;
        Bin when is_binary(Bin) ->
            binary_to_atom(Bin)
    end.

build_filter(Qs) ->
    Map = maps:from_list(Qs),
    F0 = #{},
    F1 = maybe_add(F0, actor_id, maps:get(<<"actor_id">>, Map, undefined)),
    F2 = maybe_add(F1, action, maps:get(<<"action">>, Map, undefined)),
    F3 = maybe_add(F2, target_id, maps:get(<<"target_id">>, Map, undefined)),
    F4 = maybe_add(F3, target_type, maps:get(<<"target_type">>, Map, undefined)),
    F5 = maybe_add(F4, request_id, maps:get(<<"request_id">>, Map, undefined)),
    F6 = maybe_add_outcome(F5, maps:get(<<"outcome">>, Map, undefined)),
    F7 = maybe_add_time(F6, occurred_after, maps:get(<<"since">>, Map, undefined)),
    maybe_add_time(F7, occurred_before, maps:get(<<"until">>, Map, undefined)).

build_query_opts(Qs) ->
    Map = maps:from_list(Qs),
    PageSize = page_size(),
    Q0 = #{limit => PageSize},
    case maps:get(<<"cursor">>, Map, undefined) of
        undefined -> Q0;
        <<>> -> Q0;
        C -> Q0#{cursor => C}
    end.

page_size() ->
    application:get_env(nova_audit_liveboard, page_size, ?DEFAULT_PAGE_SIZE).

maybe_add(M, _, undefined) -> M;
maybe_add(M, _, <<>>) -> M;
maybe_add(M, K, V) -> M#{K => V}.

maybe_add_outcome(M, undefined) -> M;
maybe_add_outcome(M, <<>>) -> M;
maybe_add_outcome(M, <<"success">>) -> M#{outcome => success};
maybe_add_outcome(M, <<"failure">>) -> M#{outcome => failure};
maybe_add_outcome(M, _) -> M.

maybe_add_time(M, _, undefined) ->
    M;
maybe_add_time(M, _, <<>>) ->
    M;
maybe_add_time(M, K, V) ->
    case parse_time(V) of
        {ok, Us} -> M#{K => Us};
        error -> M
    end.

parse_time(Bin) ->
    try
        case binary:match(Bin, <<"T">>) of
            nomatch ->
                case binary:match(Bin, <<"-">>) of
                    nomatch -> {ok, binary_to_integer(Bin)};
                    _ -> parse_iso8601(Bin)
                end;
            _ ->
                parse_iso8601(Bin)
        end
    catch
        _:_ -> error
    end.

parse_iso8601(Bin) ->
    Str = unicode:characters_to_list(Bin),
    {Date, Time} =
        case string:split(Str, "T") of
            [D] -> {D, "00:00:00"};
            [D, T] -> {D, string:trim(T, trailing, "Z")}
        end,
    [Y, Mo, D2] = [list_to_integer(X) || X <- string:split(Date, "-", all)],
    Clean = lists:takewhile(fun(C) -> C =/= $. end, Time),
    [H, Mi, S] = [list_to_integer(X) || X <- string:split(Clean, ":", all)],
    Secs = calendar:datetime_to_gregorian_seconds({{Y, Mo, D2}, {H, Mi, S}}),
    Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
    {ok, (Secs - Epoch) * 1_000_000}.

%% --- Event formatting for the template ---

format_event(E) ->
    Actor = maps:get(actor, E, #{}),
    Target = maps:get(target, E, undefined),
    [
        {occurred_at, format_iso(maps:get(occurred_at, E, 0))},
        {actor, format_actor(Actor)},
        {action, maps:get(action, E, <<>>)},
        {target, format_target(Target)},
        {outcome, outcome_to_binary(maps:get(outcome, E, undefined))},
        {outcome_class, outcome_class(maps:get(outcome, E, undefined))},
        {request_id, maps:get(request_id, E, <<>>)},
        {source, maps:get(source, E, <<>>)}
    ].

format_actor(#{type := Type, id := Id}) ->
    iolist_to_binary([to_bin(Type), <<":">>, to_bin(Id)]);
format_actor(_) ->
    <<"-">>.

format_target(undefined) -> <<"-">>;
format_target(#{type := T, id := Id}) -> iolist_to_binary([to_bin(T), <<":">>, to_bin(Id)]);
format_target(_) -> <<"-">>.

outcome_to_binary(undefined) -> <<>>;
outcome_to_binary(success) -> <<"success">>;
outcome_to_binary(failure) -> <<"failure">>;
outcome_to_binary(O) -> to_bin(O).

outcome_class(success) -> <<"success">>;
outcome_class(failure) -> <<"failure">>;
outcome_class(_) -> <<"">>.

format_iso(0) ->
    <<"-">>;
format_iso(Us) when is_integer(Us) ->
    Secs = Us div 1_000_000,
    Sub = Us rem 1_000_000,
    {{Y, Mo, D}, {H, Mi, S}} = calendar:gregorian_seconds_to_datetime(
        Secs + calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
    ),
    iolist_to_binary(
        io_lib:format(
            "~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w.~6..0wZ",
            [Y, Mo, D, H, Mi, S, Sub]
        )
    );
format_iso(_) ->
    <<"-">>.

time_field(Filter, Key) ->
    case maps:get(Key, Filter, undefined) of
        undefined -> <<>>;
        Us -> integer_to_binary(Us)
    end.

next_url(_Qs, done) ->
    <<>>;
next_url(Qs, Cursor) when is_binary(Cursor) ->
    Stripped = [{K, V} || {K, V} <- Qs, K =/= <<"cursor">>],
    Pairs = Stripped ++ [{<<"cursor">>, Cursor}],
    Encoded = [<<(uri_encode(K))/binary, "=", (uri_encode(V))/binary>> || {K, V} <- Pairs],
    iolist_to_binary([<<"?">>, lists:join(<<"&">>, Encoded)]).

uri_encode(B) when is_binary(B) ->
    iolist_to_binary([encode_byte(C) || <<C>> <= B]).

encode_byte(C) when
    (C >= $A andalso C =< $Z);
    (C >= $a andalso C =< $z);
    (C >= $0 andalso C =< $9);
    C =:= $-;
    C =:= $.;
    C =:= $_;
    C =:= $~
->
    <<C>>;
encode_byte(C) ->
    list_to_binary(io_lib:format("%~2.16.0B", [C])).

format_error(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

to_bin(B) when is_binary(B) -> B;
to_bin(A) when is_atom(A) -> atom_to_binary(A);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(_) -> <<>>.
