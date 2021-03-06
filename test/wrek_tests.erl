-module(wrek_tests).
-include_lib("eunit/include/eunit.hrl").
-include("wrek_event.hrl").

from_verts_ok_test() ->
    Verts = #{
      foo => ok_v([]),
      bar => ok_v([foo]),
      baz => ok_v([bar])
     },
    {ok, Dag} = wrek_utils:from_verts(Verts),

    ?assertEqual([foo, bar, baz],
                 digraph_utils:topsort(Dag)).

from_verts_cycle_test() ->
    Cycle = #{
      foo => ok_v([baz]),
      bar => ok_v([foo]),
      baz => ok_v([bar])
     },
    ?assertMatch({error, {bad_edge, _}},
                 wrek_utils:from_verts(Cycle)).

from_verts_missing_dep_test() ->
    Verts = #{bar => #{deps => [foo]}},

    ?assertMatch({error, {bad_vertex, _}},
                 wrek_utils:from_verts(Verts)).

ok_test() ->
    error_logger:tty(false),
    exec:start(),
    application:start(wrek),

    VertMap = #{
      one => ok_v([]),
      two => ok_v([one]),
      two_and_a_half => ok_v([one]),
      three => ok_v([two])
     },

    {ok, Pid} = wrek:start(VertMap),

    MonitorRef = erlang:monitor(process, Pid),

    Atom = receive
        {'DOWN', MonitorRef, process, Pid, A} -> A
    end,

    ?assertEqual(normal, Atom).

not_ok_test() ->
    error_logger:tty(false),
    exec:start(),
    application:start(wrek),

    VertMap = #{
      one => ok_v([]),
      two => ok_v([one]),
      two_and_a_half => ok_v([one]),
      three => bad_v([two])
     },

    {ok, Pid} = wrek:start(VertMap),

    MonitorRef = erlang:monitor(process, Pid),

    Atom = receive
        {'DOWN', MonitorRef, process, Pid, A} -> A
    end,

    ?assertMatch({error, _}, Atom).

event_ok_test() ->
    exec:start(),
    application:start(wrek),

    {ok, EvMgr} = gen_event:start_link({local, wrek_test_manager}),
    gen_event:add_handler(EvMgr, wrek_test_handler, [total, self()]),

    VertMap = #{
      one => ok_v([]),
      two => ok_v([one]),
      two_and_a_half => ok_v([one]),
      three => ok_v([two])
     },

    {ok, _Pid} = wrek:start(VertMap, [{event_manager, EvMgr}]),

    Events = receive
        #{evts := Evts} -> Evts
    end,

    gen_event:stop(EvMgr),

    WrekStarts =
        [E || E = #wrek_event{type = {wrek, start}} <- Events],
    StartingVerts =
        [E || E = #wrek_event{msg = {starting_vert, _}} <- Events],
    VertStarts =
        [E || E = #wrek_event{type = {vert, start}} <- Events],
    VertDones =
        [E || E = #wrek_event{type = {vert, done}} <- Events],
    WrekDones =
        [E || E = #wrek_event{type = {wrek, done}} <- Events],

    ?assertEqual(1, length(WrekStarts)),
    ?assertEqual(4, length(StartingVerts)),
    ?assertEqual(4, length(VertStarts)),
    ?assertEqual(4, length(VertDones)),
    ?assertEqual(1, length(WrekDones)).

event_bad_test() ->
    exec:start(),
    application:start(wrek),

    {ok, EvMgr} = gen_event:start_link({local, wrek_test_manager}),
    gen_event:add_handler(EvMgr, wrek_test_handler, [total, self()]),

    VertMap = #{
      one => ok_v([]),
      two => ok_v([one]),
      two_and_a_half => ok_v([one]),
      three => bad_v([two])
     },

    {ok, _Pid} = wrek:start(VertMap, [{event_manager, EvMgr}]),

    Events = receive
        #{evts := Evts} -> Evts
    end,

    gen_event:stop(EvMgr),

    WrekStarts =
        [E || E = #wrek_event{type = {wrek, start}} <- Events],
    StartingVerts =
        [E || E = #wrek_event{msg = {starting_vert, _}} <- Events],
    VertStarts =
        [E || E = #wrek_event{type = {vert, start}} <- Events],
    VertDones =
        [E || E = #wrek_event{type = {vert, done}} <- Events],
    WrekErrors =
        [E || E = #wrek_event{type = {wrek, error}} <- Events],

    ?assertEqual(1, length(WrekStarts)),
    ?assertEqual(4, length(StartingVerts)),
    ?assertEqual(4, length(VertStarts)),
    ?assertEqual(4, length(VertDones)),
    ?assertEqual(1, length(WrekErrors)).

event_time_diff_test() ->
    E1 = #wrek_event{},
    E2 = #wrek_event{},
    ?assert(wrek_event:time_diff(E1, E2) >= 0).


fail_cancels_transitive_closure_test() ->
    application:start(wrek),

    VertMap = #{
      one => bad_v([]),
      two => ok_v([one]),
      three => ok_v([two])
    },

    {ok, EvMgr} = gen_event:start_link({local, wrek_test_manager}),
    gen_event:add_handler(EvMgr, wrek_test_handler, [partial, self()]),

    Opts = [{event_manager, EvMgr}, {failure_mode, partial}],
    {ok, _Pid} = wrek:start(VertMap, Opts),

    Msgs = receive
        #{evts := M} -> M
    end,

    gen_event:stop(EvMgr),

    CancelMsgs = lists:filter(fun
        (#wrek_event{msg = {vert_cancelled, _}}) -> true;
        (_) -> false
    end, Msgs),

    ?assertEqual(2, length(CancelMsgs)).


partial_success_test() ->
    application:start(wrek),

    VertMap = #{
      one => ok_v([]),
      bad_two => bad_v([one]),
      bad_three => bad_v([bad_two]),
      ok_two => ok_v([one]),
      ok_three => ok_v([ok_two]),
      four => ok_v([ok_three, bad_three])
    },

    {ok, EvMgr} = gen_event:start_link({local, wrek_test_manager}),
    gen_event:add_handler(EvMgr, wrek_test_handler, [partial, self()]),

    Opts = [{event_manager, EvMgr}, {failure_mode, partial}],
    {ok, _Pid} = wrek:start(VertMap, Opts),

    Events = receive
        #{evts := M} -> M
    end,

    gen_event:stop(EvMgr),

    SuccessMsgs =
        [E || E = #wrek_event{type = {vert, done}, msg = {ok, _}} <- Events],

    CancelMsgs =
        [E || E = #wrek_event{msg = {vert_cancelled, _}} <- Events],

    FailMsgs =
        [E || E = #wrek_event{type = {_, error}, msg = {vert, _}} <- Events],

    % one, ok_two, ok_three
    ?assertEqual(3, length(SuccessMsgs)),
    % bad_two
    ?assertEqual(1, length(FailMsgs)),
    % bad_three, four
    ?assertEqual(2, length(CancelMsgs)).


timeout_test() ->
    VertDefn = #{module => wrek_sleep_vert, args => [], deps => [], timeout => 0},
    VertMap = #{cat => VertDefn},

    {ok, EvMgr} = gen_event:start_link({local, wrek_test_manager}),
    gen_event:add_handler(EvMgr, wrek_test_handler, [total, self()]),

    {ok, _Pid} = wrek:start(VertMap, [{event_manager, EvMgr}]),

    Map = receive
        M -> M
    end,

    gen_event:stop(EvMgr),

    FailMsgs = lists:filter(fun
        (#wrek_event{type = {wrek, error}, msg = {vert, _}}) -> true;
        (#wrek_event{type = {vert, done}, msg = timeout}) -> true;
        (_) -> false
    end, maps:get(evts, Map)),

    ?assertEqual(2, length(FailMsgs)).


%% private

ok_v(Deps) ->
    #{module => wrek_true_vert, args => [], deps => Deps}.

bad_v(Deps) ->
    #{module => wrek_bad_vert, args => [], deps => Deps}.
