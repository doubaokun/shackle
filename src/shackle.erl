-module(shackle).
-include("shackle_internal.hrl").

%% public
-export([
    call/2,
    call/3,
    cast/3,
    handle_timing/1,
    receive_response/1,
    receive_response/2
]).

%% public
-spec call(pool_name(), term()) -> {ok, term()} | {error, term()}.

call(PoolName, Request) ->
    call(PoolName, Request, ?DEFAULT_TIMEOUT).

-spec call(atom(), term(), timeout()) -> {ok, term()} | {error, term()}.

call(PoolName, Request, Timeout) ->
    case cast(PoolName, Request, self()) of
        {ok, RequestId} ->
            receive_response(RequestId, Timeout);
        {error, Reason} ->
            {error, Reason}
    end.

-spec cast(pool_name(), term(), pid()) -> {ok, request_id()} | {error, backlog_full}.

cast(PoolName, Request, Pid) ->
    Timestamp = os:timestamp(),
    case shackle_pool:server(PoolName) of
        {ok, Client, Server} ->
            Ref = make_ref(),
            Server ! #cast {
                client = Client,
                pid = Pid,
                pool_name = PoolName,
                ref = Ref,
                request = Request,
                timestamp = Timestamp
            },
            {ok, {PoolName, Ref}};
        {error, backlog_full} ->
            {error, backlog_full}
    end.

-spec handle_timing(cast()) -> ok.

handle_timing(#cast {
        client = Client,
        request = Request,
        timestamp = Timestamp,
        timing = Timing
    }) ->

    Timing2 = shackle_utils:timing(Timestamp, Timing),
    Timing3 = lists:reverse(Timing2),
    Client:handle_timing(Request, Timing3).

-spec receive_response(request_id()) ->
    {ok, reference()} | {error, term()}.

receive_response(RequestId) ->
    receive_response(RequestId, ?DEFAULT_TIMEOUT).

-spec receive_response(request_id(), timeout()) ->
    {ok, reference()} | {error, term()}.

receive_response({PoolName, Ref} = RequestId, Timeout) ->
    Timestamp = os:timestamp(),
    receive
        #cast {
            pool_name = PoolName,
            ref = Ref
        } = Cast ->

            handle_timing(Cast),
            Cast#cast.reply;
        #cast {pool_name = PoolName} ->
            Timeout2 = shackle_utils:timeout(Timeout, Timestamp),
            receive_response(RequestId, Timeout2)
    after Timeout ->
        {error, timeout}
    end.
