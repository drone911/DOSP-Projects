-module(bitcoin).

-define(WORK_UNIT, 500000).

% use printable characters from ascii 33 (!) to 126 (~)
-define(PRINTABLE_CHAR_OFFSET, 33).
-define(CHAR_START, 0).
-define(CHAR_END, 93).

-export([start_server/0,start_server/2, start_worker/1, mine/3, to_character_list/1]).

% Server method to listen/assign work to workers
% Start: Denotes the current starting value that will be given to a worker on the next work request
% Workers: List of active workers
% GatorID: The id whose coin needs to be found (User input)
% NumZeroes: The number of zeroes required in the Hash (User input)
% IsFound: Boolean value to indicate whether the coin was found
listen(Start, Workers, GatorID, NumZeroes, IsFound) ->
    if
        Workers == [] ->
            io:format("No worker remaining to inform to exit, stopping...\n");
        true ->
            receive
                % When worker sends the coin
                {FromNode, Suffix, Hash} ->
                    {_, TimeDiff} = statistics(wall_clock),

                    % Print the Coin received from worker FromNode
                    io:format("Received coin ~p ~p From ~p\n", [
                        GatorID ++ Suffix, Hash, FromNode
                    ]),
                    io:format("Time take to find the Coin (in milliseconds): ~w\n", [TimeDiff]),
                    
                    % Set IsFound to true to inform workers to stop on subsequent work requests and remove the worker FromNode from active workers
                    listen(
                        Start + ?WORK_UNIT + 1,
                        lists:delete(FromNode, Workers),
                        GatorID,
                        NumZeroes,
                        true
                    );

                % Work request from worker
                FromNode ->
                    case IsFound of
                        true ->
                            % When coin has already been found, inform the worker to stop and remove it from active workers
                            io:format("Coin has been found, sending kill signal to ~p \n", [FromNode]),
                            {worker, FromNode} ! work_finished,
                            listen(Start, lists:delete(FromNode, Workers), GatorID, NumZeroes, IsFound);
                        false ->
                            % When coin is not found, send next work Start value
                            io:format("Received Work Request from ~p, giving start ~w\n", [FromNode, Start]),
                            {worker, FromNode} ! {Start, GatorID, NumZeroes},

                            % Check if worker is already in the active workers list, if not add it, and increase the Start value by WORK_UNIT
                            case lists:member(FromNode, Workers) of
                                true ->
                                    listen(
                                        Start + ?WORK_UNIT + 1, Workers, GatorID, NumZeroes, IsFound
                                    );
                                false ->
                                    listen(
                                        Start + ?WORK_UNIT  + 1,
                                        Workers ++ [FromNode],
                                        GatorID,
                                        NumZeroes,
                                        IsFound
                                    )
                            end
                    end
            end
    end.

% Alternate entry method for the Server
start_server()->
    {ok, GatorID} = io:read("Enter gator id: "),
    {ok, NumZeroes} = io:read("Enter number of zeroes in hash: "),
    start_server(GatorID, NumZeroes).

% Entry method for the Server
% GatorID: Input from user whose coin needs to be found
% NumZeroes: Input from user regarding the number of zeroes required in the Hash prefix
start_server(GatorID, NumZeroes) ->
    
    statistics(wall_clock),
    io:format("Started Server with input ~p ~p\n", [GatorID, NumZeroes]),
    register(server, self()),

    % Server starts its own worker to mine coins
    spawn(bitcoin, start_worker, [node()]),

    % Server now enters into a listen loop to listen/assign work to workers    
    listen(0, [node()], GatorID, NumZeroes, false),
    unregister(server).

% Entry method for Workers
% ServerNode: Node name of the server
start_worker(ServerNode) ->
    register(worker, self()),
    {server, ServerNode} ! node(),
    statistics(runtime),
    start_worker_util(ServerNode).

% Utility method for the worker loop to spawn/give work to mine, and wait for the mined coin 
% ServerNode: Node name of the server
start_worker_util(ServerNode) ->
    receive
        % When server gives work
        {Start, GatorID, NumZeroes} ->            
            % Check existance of miner process
            case whereis(miner) of
                undefined ->
                    % Spawn the miner process
                    register(miner, spawn(bitcoin, mine, [Start, GatorID, NumZeroes]));
                _ ->
                    % Send the new Start value received from server
                    miner ! Start
            end,
            % Go back to listening to either miner or server
            start_worker_util(ServerNode);

        % When miner is finished with its work unit and did not find a coin
        mine_finished ->
            % Request new work from server    
            {server, ServerNode} ! node(),
            % Go back to listening to either miner or server
            start_worker_util(ServerNode);

        % When server sends the finished signal as coin is found by another worker
        work_finished ->
            io:format("Received Work Finished From Server, exiting...\n"),
            % Send miner signal to stop
            miner ! work_finished,
            {_, NodeTime} = statistics(runtime),
            % Print the node CPU runtime, and exit
            io:format("Node Runtime (in milliseconds): ~w\n", [NodeTime]),
            unregister(worker);

        % When miner found the challenge coin
        {Suffix, Hash} ->
            % Send server the found coin
            {server, ServerNode} ! {node(), Suffix, Hash},
            {_, NodeTime} = statistics(runtime),
            % Print the node CPU runtime, and exit
            io:format("Node Runtime (in milliseconds): ~w\n", [NodeTime]),
            unregister(worker)
    end.

% Miner method to find the coin
% Start: Denotes the current starting value
% GatorID: The id whose coin needs to be found (User input)
% NumZeroes: The number of zeroes required in the Hash (User input)
mine(Start, GatorID, NumZeroes) ->
    % Uncomment this to print the start value of the work received by the miner
    % io:format("Started Miner with ~w ~p\n", [Start, node()]),

    % String representing the required number of zeroes prefix (eg. "000" for NumZeroes = 3)
    RequiredStart = lists:flatten(lists:duplicate(NumZeroes, "0")),
    
    % Call the mine_helper method to start the mine with the Start and the WORK_UNIT
    case mine_helper(Start, Start + ?WORK_UNIT, GatorID, RequiredStart, NumZeroes) of
        % When the coin is found by mine_helper, send it to worker and exit
        {Suffix, Hash} ->
            worker ! {Suffix, Hash},
            unregister(miner);

        % When the coin is not found, ask worker for more work
        mine_finished ->
            % Uncomment this to print that mine_helper has completed its WORK_UNIT
            % io:format("Mine Finished ~w ~p\n", [Start, node()]),
            worker ! mine_finished
    end,
    % Listen for worker response
    receive
        % Work is finished as coin was found by another worker, exit
        work_finished ->
            unregister(miner);

        % New Start has been received, start the mine with it
        NewStart ->
            mine(NewStart, GatorID, NumZeroes)
    end.


% miner_helper method to iterate from Iter to End and calculate and compare the Hash
% Iter: Denotes the current starting value
% End: Denotes the value of Iter of when to end (Start + WORK_UNIT + 1)
% GatorID: The id whose coin needs to be found (User input)
% RequiredStart: String representing the required number of zeroes prefix (eg. "000" for NumZeroes = 3)
% NumZeroes: The number of zeroes required in the Hash (User input)
mine_helper(Iter, End, GatorID, RequiredStart, NumZeroes) ->
    if
        % When Iter is finished and coin not found, end loop
        Iter > End ->
            mine_finished;

        % Iter is not finished, continue searching for the coin
        true ->
            % Convert Iter to a fixed mapped ASCII printable character string and append it to the input Gator ID
            % eg. 0 maps to '!', 94 maps to '~', 50000 maps to '&^w' 
            ToAppend = to_character_list(Iter),
            Hash = io_lib:format("~64.16.0b", [
                binary:decode_unsigned(crypto:hash(sha256, GatorID ++ ToAppend))
            ]),

            % Check if the Hash suffix matches the required number of zeroes
            case string:equal(RequiredStart, string:slice(Hash, 0, NumZeroes)) of
                % Hash found
                true ->
                    {ToAppend, Hash};
                % Hash not found
                false ->
                    mine_helper(Iter + 1, End, GatorID, RequiredStart, NumZeroes)
            end
    end.

% Method to map the string/list from Iter value that will be appended to GatorId
% eg. 0 maps to '!', 93 maps to '~', 50000 maps to '&^w'
to_character_list(Iter) ->
    to_character_list(Iter, calculate_list_lenght(Iter), []).

% Helper Method to map the string/list from Iter value that will be appended to GatorId
to_character_list(Iter, ListLength, CharacterList) ->
    if
        ListLength < 0 ->
            CharacterList;
        true ->
            RaisedCharCount = math:pow(?CHAR_END - ?CHAR_START + 1, ListLength),
            Quotient = math:floor(Iter / RaisedCharCount),
            to_character_list(
                Iter - Quotient * RaisedCharCount,
                ListLength - 1,
                lists:append(CharacterList, [trunc(Quotient) + ?PRINTABLE_CHAR_OFFSET])
            )
    end.

% Method to calculate the length of the string from Iter that will be appended to GatorId
calculate_list_lenght(N) ->
    calculate_list_lenght(N, 1).

% Helper method to calculate the length of the string from Iter that will be appended to GatorId
calculate_list_lenght(N, J) ->
    Quotient = math:floor(N / math:pow(?CHAR_END - ?CHAR_START + 1, J)),
    if
        Quotient < 1.0 ->
            J - 1;
        true ->
            calculate_list_lenght(N, J + 1)
    end.