REBAR = ./rebar3
DIALYZER = dialyzer
TOUCH = touch

.PHONY: all deps compile escripize clean doc eunit ct test \
	run plt analyze get-deps compile-deps

all: deps compile

deps: get-deps compile-deps

compile: 
	@$(REBAR) compile skip_deps=true

escriptize: 
	@$(REBAR) escriptize

clean: 
	@$(REBAR) clean
	@rm -f test/*.beam erl_crash.dump ./deps/.compile-deps 

eunit: deps compile 
	@$(REBAR) skip_deps=true eunit

ct: deps compile 
	@$(REBAR) skip_deps=true ct 

test: eunit ct

plt:
	@$(DIALYZER) --build_plt --output_plt .backend-api.plt \
		-pa deps/lager/ebin \
		-pa deps/mochiweb/ebin \
		-c deps/mochiweb/ebin \
		--apps kernel stdlib sasl inets crypto \
		public_key ssl mnesia runtime_tools erts \
		compiler tools syntax_tools xmerl hipe webtool

analyze: compile
	@$(DIALYZER) --no_check_plt \
		     -c ebin \
		--plt .ddb.plt \
		-pa deps/lager/ebin \
		-pa deps/mochiweb/ebin \
		-Werror_handling \
		-Wunmatched_returns #-Wunderspecs

docs:
	@$(REBAR) doc skip_deps=true

get-deps:
	@$(REBAR) get-deps

compile-deps:
	@$(REBAR) compile
