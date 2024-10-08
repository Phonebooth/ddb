%%% Copyright (C) 2012 Issuu ApS. All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions
%%% are met:
%%% 1. Redistributions of source code must retain the above copyright
%%%    notice, this list of conditions and the following disclaimer.
%%% 2. Redistributions in binary form must reproduce the above copyright
%%%    notice, this list of conditions and the following disclaimer in the
%%%    documentation and/or other materials provided with the distribution.
%%%
%%% THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
%%% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
%%% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
%%% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
%%% OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
%%% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
%%% OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
%%% SUCH DAMAGE.

-module(ddb_aws).

-export([retry/3, retry/4, timestamp/0]).

-define(DATE_FMT, "~4.10.0b-~2.10.0b-~2.10.0bT~2.10.0b:~2.10.0b:~2.10.0b.000Z").

-spec retry(function(), non_neg_integer(), function()) -> {'ok', _} | {'error', _}.

retry(F, Max, H) 
  when is_function(F),
       is_integer(Max),
       Max >= 0,
       is_function(H) ->
    retry(F, Max, 0, H).

retry(_, Max, N, _) 
  when Max == N ->
    ok = lager:error([{component, ddb}], "Maximum retries (~p) reached, aborting...", [Max]),
    {'error', 'maximum_retries_reached'};

retry(F, Max, N, H) 
  when is_function(F),
       is_integer(Max),
       is_integer(N),
       is_function(H) ->
    backoff(N),
    case F() of
        {ok, "200", _, Body} ->
            {'ok', H(Body)};
        {ok, Code, _, Body} when Code >= "400" andalso Code < "500" ->
	    case jsx:is_json(Body) of
		false ->
		    ok = lager:error([{component, ddb}], "Got client error (~s) ~p, aborting...", [Code, Body]),
		    {'error', H(Body)};
		true ->
		    JSON = jsx:json_to_term(Body),
		    case proplists:get_value(<<"__type">>, JSON) of
			<<"com.amazonaws.dynamodb.v20120810#ProvisionedThroughputExceededException">> ->
			    ok = lager:debug([{component, ddb}], "Provisioned capacity exceeded (~s) ~p", [Code, Body]),
                {'error', 'throughput_exceeded'};
			<<"com.amazonaws.dynamodb.v20120810#ThrottlingException">> ->
			    ok = lager:debug([{component, ddb}], "Request was throttled (~s) ~p", [Code, Body]),
                {'error', 'throttling_exception'};
			<<"com.amazon.coral.service#ExpiredTokenException">> ->
			    ok = lager:debug([{component, ddb}], "Token has expired (~s) ~p", [Code, Body]),
			    {'error', 'expired_token'};
			<<"com.amazonaws.dynamodb.v20120810#ConditionalCheckFailedException">> ->
			    %% This is expected in some use cases, so just trace at info level
			    ok = lager:info([{component, ddb}], "Got client error (~s) ~p", [Code, Body]),
			    {'error', H(Body)};
			_ ->
			    ok = lager:error([{component, ddb}], "Got client error (~s) ~p", [Code, Body]),
			    {'error', H(Body)}
		    end
	    end;
	{'ok', Code, _, Body} ->
	    ok = lager:warning([{component, ddb}], "Unexpected response (~s) ~p", [Code, Body]),
	    {'error', 'unexpected_response'};
	{'error', Error} ->
	    ok = lager:debug([{component, ddb}], "Unexpected error ~p", [Error]),
	    {'error', Error}
    end.

-spec backoff(non_neg_integer()) -> 'ok'.

backoff(0) -> 'ok';
backoff(Attempts) 
  when is_integer(Attempts) ->
    %% attempt exponential backoff
    Delay = round(rand:uniform(101) * math:pow(4, Attempts)),
    ok = lager:debug([{component, ddb}], "Waiting ~bms before retrying", [Delay]),
    timer:sleep(Delay).

-spec timestamp() -> string().

timestamp() ->
    {{YYYY, MM, DD}, {HH, MI, SS}} = erlang:universaltime(),
    lists:flatten(io_lib:format(?DATE_FMT, [YYYY, MM, DD, HH, MI, SS])).
