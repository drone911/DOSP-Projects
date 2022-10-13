% project2 numNodes topology algorithm
-module(gossip).

-export([start/3, start/4, actor_start/4, start_iter_with_file_write/5]).

-define(GOSSIP_STOP, 10).
-define(PUSH_SUM_STOP, 3).
-define(NODE_SLEEP_TIME, 10).
-define(PUSH_SUM_DELTA, 0.0000000001).

start_iter_with_file_write(NumNodesList, Topology, Algorithm, FailureProbability, OutputFileName) ->
    {ok, FileHandler} = file:open(OutputFileName, [append]),
    io:format(FileHandler, "NumNode,Topology,Algorithm,FailureProbability,TimeTaken\n", []),

    WriteResults = fun(NumNodes) ->
        NumNodesRounded =
            case string:uppercase(Topology) of
                "IMP3D" ->
                    round_nodes(NumNodes, 1);
                "2D" ->
                    round_nodes(NumNodes, 1);
                _ ->
                    NumNodes
            end,

        io:format(FileHandler, "~w,~p,~p,~w,~w\n", [
            NumNodesRounded,
            Topology,
            Algorithm,
            FailureProbability,
            start(NumNodesRounded, Topology, Algorithm, FailureProbability)
        ])
    end,
    lists:foreach(WriteResults, NumNodesList),
    file:close(FileHandler).

clear_messages() ->
    receive
        _Any ->
            clear_messages()
    after 0 ->
        ok
    end.

listen(Nodes) ->
    AliveNodes = lists:filter(fun is_alive/1, Nodes),
    if
        AliveNodes == [] ->
            {_, TimeDiff} = statistics(wall_clock),
            io:format("[Server] All nodes have converge finished execution, Time taken ~w ms\n", [
                TimeDiff
            ]),
            io:format("[Server] Clearing messages, if any\n"),
            clear_messages(),
            unregister(server),
            TimeDiff;
        true ->
            receive
                {'DOWN', _, process, Pid, Reason} ->
                    case Reason of
                        normal ->
                            io:format(
                                "[Server] Node with process Id ~w has converged\n",
                                [Pid]
                            );
                        simulated_failure ->
                            io:format(
                                "[Server] Node with process Id ~w has exited as a simulated failure\n",
                                [Pid]
                            );
                        true ->
                            io:format(
                                "[Server] Node with process ID ~w has exited with Reason ~p\n", [
                                    Pid, Reason
                                ]
                            )
                    end,
                    listen(AliveNodes);
                {Node, receivedonce} ->
                    listen(lists:keyreplace(Node, 1, AliveNodes, {Node, true}))
            after 2000 ->
                case lists:all(fun(Elem) -> not element(2, Elem) end, AliveNodes) of
                    true ->
                        io:format(
                            "[Server] No active node is remaining with a rumor, sending kill to all stuck actors\n"
                        ),
                        lists:foreach(
                            fun(Elem) -> catch (list_to_atom([element(1, Elem)]) ! killsignal) end,
                            AliveNodes
                        ),
                        {_, TimeDiff} = statistics(wall_clock),
                        io:format(
                            "[Server] total convergence did not happen, Time taken ~w ms\n", [
                                TimeDiff - 2000
                            ]
                        ),
                        io:format("[Server] Clearing messages, if any\n"),
                        clear_messages(),
                        unregister(server),
                        TimeDiff - 2000;
                    false ->
                        listen(AliveNodes)
                end
            end
    end.

start(NumNodes, Topology, Algorithm) ->
    start(NumNodes, Topology, Algorithm, 0).

start(NumNodes, Topology, Algorithm, FailureProbability) ->
    NumNodesRounded =
        case string:uppercase(Topology) of
            "IMP3D" ->
                round_nodes(NumNodes, 1);
            "2D" ->
                round_nodes(NumNodes, 1);
            _ ->
                NumNodes
        end,
    rand:seed(default, 1337),
    case string:uppercase(Topology) of
        "FULL" ->
            io:format("Spawning ~w Full Nodes with Algo ~p\n", [NumNodesRounded, Algorithm]),
            spawn_full_nodes(1, NumNodesRounded, Algorithm, FailureProbability);
        "2D" ->
            io:format("Spawning ~w 2D Nodes with Algo ~p\n", [NumNodesRounded, Algorithm]),
            spawn_2d_nodes(1, NumNodesRounded, Algorithm, FailureProbability);
        "LINE" ->
            io:format("Spawning ~w Line Nodes with Algo ~p\n", [NumNodesRounded, Algorithm]),
            spawn_line_nodes(1, NumNodesRounded, Algorithm, FailureProbability);
        "IMP3D" ->
            io:format("Spawning ~w Imp3D Nodes with Algo ~p\n", [NumNodesRounded, Algorithm]),
            spawn_imp_3d_nodes(1, NumNodesRounded, Algorithm, FailureProbability);
        true ->
            io:format("Unknown topolgy ~p, know topologies are ~p", [
                Topology, ["full", "2d", "line", "imp3d"]
            ])
    end,
    register(server, self()),
    io:format("Server Pid ~p\n", [self()]),
    statistics(wall_clock),
    lists:foreach(fun(Node) -> list_to_atom([Node]) ! start end, lists:seq(1, NumNodesRounded - 1)),
    list_to_atom([NumNodesRounded]) ! rumor,
    io:format("[Server] Sending first message\n"),
    listen(lists:zip(lists:seq(1, NumNodesRounded), lists:duplicate(NumNodesRounded, false))).

round_nodes(Nodes, I) ->
    RoundedNumNodes = I * I,
    if
        RoundedNumNodes >= Nodes ->
            RoundedNumNodes;
        true ->
            round_nodes(Nodes, I + 1)
    end.

spawn_full_nodes(CurrNode, NumNodes, Algorithm, FailureProbability) ->
    if
        CurrNode > NumNodes ->
            true;
        true ->
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                lists:seq(1, CurrNode - 1) ++ lists:seq(CurrNode + 1, NumNodes),
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),
            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_full_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability)
    end.

in_range(Start, End) ->
    fun(Element) ->
        if
            Element < Start ->
                false;
            Element > End ->
                false;
            true ->
                true
        end
    end.

spawn_2d_nodes(CurrNode, NumNodes, Algorithm, FailureProbability) ->
    Dim = round(math:sqrt(NumNodes)),
    Left = CurrNode - 1,
    Right = CurrNode + 1,
    Up = CurrNode - Dim,
    Down = CurrNode + Dim,
    if
        CurrNode rem Dim == 1 ->
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                lists:filter(in_range(1, NumNodes), [Up, Right, Down]),
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),
            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_2d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability);
        CurrNode rem Dim == 0 ->
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                lists:filter(in_range(1, NumNodes), [Up, Down, Left]),
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),
            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            if
                CurrNode =/= NumNodes ->
                    spawn_2d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability);
                true ->
                    ok
            end;
        true ->
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                lists:filter(in_range(1, NumNodes), [Up, Right, Down, Left]),
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_2d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability)
    end.

spawn_line_nodes(CurrNode, NumNodes, Algorithm, FailureProbability) ->
    if
        CurrNode == 1 ->
            Pid = spawn(gossip, actor_start, [CurrNode, [2], Algorithm, FailureProbability]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]), Pid
            ),
            spawn_line_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability);
        CurrNode >= NumNodes ->
            Pid = spawn(gossip, actor_start, [
                CurrNode, [CurrNode - 1], Algorithm, FailureProbability
            ]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]),
                Pid
            );
        true ->
            Pid = spawn(gossip, actor_start, [
                CurrNode, [CurrNode - 1, CurrNode + 1], Algorithm, FailureProbability
            ]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_line_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability)
    end.

spawn_imp_3d_nodes(CurrNode, NumNodes, Algorithm, FailureProbability) ->
    Dim = round(math:sqrt(NumNodes)),
    Left = CurrNode - 1,
    Right = CurrNode + 1,
    Up = CurrNode - Dim,
    Down = CurrNode + Dim,
    DiagUpLeft = CurrNode - Dim - 1,
    DiagUpRight = CurrNode - Dim + 1,
    DiagDownLeft = CurrNode + Dim - 1,
    DiagDownRight = CurrNode + Dim + 1,

    if
        CurrNode rem Dim == 1 ->
            Neighbours = lists:filter(in_range(1, NumNodes), [
                Up, DiagUpRight, Right, DiagDownRight, Down
            ]),
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                Neighbours ++ [get_imperfect_neighbour(Neighbours ++ [CurrNode], NumNodes)],
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_imp_3d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability);
        CurrNode rem Dim == 0 ->
            Neighbours = lists:filter(in_range(1, NumNodes), [
                Up, Down, DiagDownLeft, Left, DiagUpLeft
            ]),
            Pid = spawn(gossip, actor_start, [
                CurrNode,
                Neighbours ++ [get_imperfect_neighbour(Neighbours ++ [CurrNode], NumNodes)],
                Algorithm,
                FailureProbability
            ]),
            monitor(process, Pid),

            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            if
                CurrNode =/= NumNodes ->
                    spawn_imp_3d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability);
                true ->
                    ok
            end;
        true ->
            Neighbours = lists:filter(in_range(1, NumNodes), [
                Up, DiagUpRight, Right, DiagDownRight, Down, DiagDownLeft, Left, DiagUpLeft
            ]),
            if
                % Filter the 3x3 grid as the middle element could not have more than 8 neighbours without repeating a neighbour
                NumNodes >= 10 ->
                    WithRandomNeighbours =
                        Neighbours ++ [get_imperfect_neighbour(Neighbours ++ [CurrNode], NumNodes)];
                true ->
                    if
                        CurrNode == 5 ->
                            WithRandomNeighbours = Neighbours;
                        true ->
                            WithRandomNeighbours =
                                Neighbours ++
                                    [get_imperfect_neighbour(Neighbours ++ [CurrNode], NumNodes)]
                    end
            end,
            Pid = spawn(gossip, actor_start, [
                CurrNode, WithRandomNeighbours, Algorithm, FailureProbability
            ]),
            monitor(process, Pid),
            register(
                list_to_atom([CurrNode]),
                Pid
            ),
            spawn_imp_3d_nodes(CurrNode + 1, NumNodes, Algorithm, FailureProbability)
    end.

actor_start(Node, Neighbours, Algorithm, FailureProbability) ->
    io:format("[Node ~w] Process ID is ~p, with neighbours ~w\n", [
        Node, whereis(list_to_atom([Node])), Neighbours
    ]),
    receive
        start ->
            HasReceivedOnce = false;
        rumor ->
            io:format("[Node ~w] Received First rumor\n", [Node]),
            HasReceivedOnce = true,
            server ! {Node, receivedonce}
    end,
    case string:uppercase(Algorithm) of
        "GOSSIP" ->
            actor_run(
                Node, Neighbours, Algorithm, #{count => 0}, HasReceivedOnce, FailureProbability
            );
        "PUSH-SUM" ->
            actor_run(
                Node,
                Neighbours,
                Algorithm,
                #{w => 1, s => Node, last_change => 0},
                HasReceivedOnce,
                FailureProbability
            );
        true ->
            io:format("Unknown algorithm ~p, know algorithms are ~p", [
                Algorithm, ["gossip", "push-sum"]
            ])
    end,
    unregister(list_to_atom([Node])).

get_imperfect_neighbour(Exclude, NumNodes) ->
    RandomNum = rand:uniform(NumNodes),
    case lists:member(RandomNum, Exclude) of
        true ->
            get_imperfect_neighbour(Exclude, NumNodes);
        false ->
            RandomNum
    end.

is_alive(Element) ->
    case is_tuple(Element) of
        true ->
            Key = element(1, Element);
        false ->
            Key = Element
    end,
    case whereis(list_to_atom([Key])) of
        undefined ->
            false;
        _ ->
            true
    end.

actor_run(Node, Neighbours, Algorithm, State, HasReceivedOnce, FailureProbability) ->
    FailureIn = FailureProbability * 100,
    Rand = rand:uniform(100),
    if
        Rand =< FailureIn ->
            unregister(list_to_atom([Node])),
            exit(simulated_failure);
        true ->
            ok
    end,
    if
        Neighbours == [] ->
            ok;
        true ->
            receive
                killsignal ->
                    NewHasReceivedOnce = true,
                    NewState = State,
                    io:format("[Node ~w] Got killsignal from Server\n", [Node]),
                    unregister(list_to_atom([Node])),
                    exit(normal);
                message ->
                    NewHasReceivedOnce = true,
                    NewState = #{count => maps:get(count, State) + 1},
                    io:format("[Node ~w] Received message, count=~w\n", [Node, maps:get(count, NewState)]);

                {W, S} ->
                    NewHasReceivedOnce = true,
                    OldRatio = maps:get(s, State) / maps:get(w, State),

                    TempState = #{w => maps:get(w, State) + W, s => maps:get(s, State) + S},
                    NewRatio = maps:get(s, TempState) / maps:get(w, TempState),
                    if
                        abs(NewRatio - OldRatio) =< ?PUSH_SUM_DELTA ->
                            NewState = maps:put(
                                last_change, maps:get(last_change, State) + 1, TempState
                            );
                        true ->
                            NewState = maps:put(last_change, 0, TempState)
                    end,
                    io:format("[Node ~w] Received message, state is s=~w w=~w No change count=~w\n", [Node, maps:get(s, NewState), maps:get(w, NewState), maps:get(last_change, NewState)])
            after 0 ->
                % io:format("Did not Recieved ~w\n", [Node]),
                NewHasReceivedOnce = HasReceivedOnce,
                NewState = State
            end,
            timer:sleep(?NODE_SLEEP_TIME),
            case NewHasReceivedOnce of
                true ->
                    case HasReceivedOnce of
                        false ->
                            server ! {Node, receivedonce};
                        true ->
                            ok
                    end,
                    case string:uppercase(Algorithm) of
                        "GOSSIP" ->
                            CurrCount = maps:get(count, NewState),
                            if
                                CurrCount >= ?GOSSIP_STOP ->
                                    ok;
                                true ->
                                    AliveNeighbours = lists:filter(fun is_alive/1, Neighbours),
                                    if
                                        AliveNeighbours == [] ->
                                            ok;
                                        true ->
                                            NextNode = lists:nth(
                                                rand:uniform(length(AliveNeighbours)),
                                                AliveNeighbours
                                            ),
                    
                                            try list_to_atom([NextNode]) ! message of
                                                _ -> ok
                                            catch
                                                error:badarg ->
                                                    io:format("[Node ~w] Sent to dead node ~w\n", [
                                                        Node, NextNode
                                                    ])
                                            end,
                                            % io:format(
                                            %     "~w Gossip, count at ~w,sending to ~w\n", [
                                            %         Node, CurrCount, NextNode
                                            %     ]
                                            % ),
                                            actor_run(
                                                Node,
                                                lists:filter(fun is_alive/1, Neighbours),
                                                Algorithm,
                                                NewState,
                                                NewHasReceivedOnce,
                                                FailureProbability
                                            )
                                    end
                            end;
                        "PUSH-SUM" ->
                            CurrLastChange = maps:get(last_change, NewState),
                            if
                                CurrLastChange >= ?PUSH_SUM_STOP ->
                                    ok;
                                true ->
                                    AliveNeighbours = lists:filter(fun is_alive/1, Neighbours),
                                    if
                                        AliveNeighbours == [] ->
                                            ok;
                                        true ->
                                            NextNode = lists:nth(
                                                rand:uniform(length(AliveNeighbours)),
                                                AliveNeighbours
                                            ),                                                                                        

                                            try
                                                list_to_atom([NextNode]) !
                                                    {
                                                        maps:get(w, NewState) / 2,
                                                        maps:get(s, NewState) / 2
                                                    }
                                            of
                                                _ -> ok
                                            catch
                                                error:badarg ->
                                                    io:format("[~w] Sent to dead node ~w\n", [
                                                        Node, NextNode
                                                    ])
                                            end,
                                            % io:format(
                                            %     "~w Push-Sum, State as ~p, Ratio at ~p, ,sending to ~w\n",
                                            %     [
                                            %         Node,
                                            %         NewState,
                                            %         maps:get(w, NewState) / maps:get(s, NewState),
                                            %         NextNode
                                            %     ]
                                            % ),
                                            actor_run(
                                                Node,
                                                lists:filter(fun is_alive/1, AliveNeighbours),
                                                Algorithm,
                                                #{
                                                    w => maps:get(w, NewState) / 2,
                                                    s => maps:get(s, NewState) / 2,
                                                    last_change => maps:get(last_change, NewState)
                                                },
                                                NewHasReceivedOnce,
                                                FailureProbability
                                            )
                                    end
                            end
                    end;
                false ->
                    actor_run(
                        Node,
                        lists:filter(fun is_alive/1, Neighbours),
                        Algorithm,
                        State,
                        NewHasReceivedOnce,
                        FailureProbability
                    )
            end
    end.
