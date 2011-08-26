%%%-------------------------------------------------------------------
%%% @author Martin Scholl <martin@infinipool.com>
%%% @copyright (C) 2011, Martin Scholl
%%% @doc
%%%
%%% @end
%%% Created : 21 Aug 2011 by Martin Scholl <martin@infinipool.com>
%%%-------------------------------------------------------------------
-module(ct_surefire).

%% API
-export([
	 to_surefire_xml/1,
	 to_surefire_xml/2
	]).

-define(TAG(Name), ?TAG(Name, _, _)).
-define(TAG(Name, Childs), ?TAG(Name, _, Childs)).
-define(TAG(Name, Args, Childs), {<<??Name>>, Args, Childs}).

-record(res, {test_id,suite,case_id,duration,result,error}).

%%%===================================================================
%%% API
%%%===================================================================
to_surefire_xml([CtDir, OutputDir]) when is_list(CtDir), 
					 is_list(OutputDir) ->
    to_surefire_xml(CtDir, OutputDir).

%% computes a surefire XML report from a CT directory
%% @param CtDir directory where CT logs are stored
%% @param OutputDir Directory where XML report files will be stored
to_surefire_xml(CtDir, OutputDir) ->
    RunDir = find_latest_rundir(CtDir),
    Reports = available_reports(RunDir),
    [begin
	 ReportFilename = "TEST-" ++ App ++ ".xml",
	 OutputFilename = filename:join([OutputDir, ReportFilename]),
	 write_report(ReportDir, App, OutputFilename)
     end || {App, ReportDir} <- Reports],
    ok.


find_latest_rundir(Dir) ->
    Dirs = filelib:wildcard(filename:join([Dir, "ct_run.ct*"])),
    hd(lists:reverse(lists:sort(Dirs))).

available_reports(Dir) ->
    Apps = [string:substr(A, 6) || A <- filelib:wildcard("apps.*", Dir)],
    Dirs = filelib:wildcard(filename:join([Dir, "apps.*", "run.201*"])),
    lists:zip(Apps, Dirs).

write_report(ReportDir, App, OutputFilename) ->
    LogFilename = filename:join(ReportDir, "suite.log.html"),
    Results = parse_results(LogFilename),
    Xml = results_to_xml(App, Results),
    ok = file:write_file(OutputFilename, Xml).
    
    

parse_results(Filename) ->
    {ok, RawHTML} = file:read_file(Filename),
    case mochiweb_html:parse(RawHTML) of
	?TAG(html, [], [?TAG(head), ?TAG(body, _, TestResults)]) ->
	    DescendPath = [<<"p">>,<<"p">>,<<"p">>,<<"p">>,<<"table">>],
	    TestTab = follow(DescendPath, TestResults),
	    filter_tests(TestTab);
	_ ->
	    error(unsupported_html, Filename)
    end.

results_to_xml(App, Results) ->
    XmlHdr = io_lib:format(
	       "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"
	       "<testsuite tests=\"~b\" failures=\"0\" errors=\"~b\" skipped=\"~b\" time=\"~f\" name=\"ct.~s'\">", 
	       [
		length(Results),
		count_by_result(failed, Results),
		count_by_result(skipped, Results),
		sum_duration(Results),
		App
	       ]),
    Testcases = [xmlify_result(R) || R <- Results],
    XmlFooter = "</testsuite>",
    
    [XmlHdr, Testcases, XmlFooter].
	    
    

%%%===================================================================
%%% Internal functions
%%%===================================================================
xmlify_result(#res{result = ok, suite = Suite, case_id = Case,
		   test_id = Id, duration = D}) ->
    io_lib:format(" <testcase name=\"~s.~s.~s\" time=\"~s\" />~n",
		  [Suite,Case,Id,D]);
xmlify_result(#res{error = Error, suite = Suite, case_id = Case,
		   test_id = Id, duration = D}) ->
    io_lib:format(" <testcase name=\"~s.~s.~s\" time=\"~s\">~n"
		  "  <error type=\"error\">~s</error>~n"
		  "  <system-out></system-out>~n"
		  " </testcase>~n",
		  [Suite,Case,Id,D,Error]).


follow([], HTML) ->
    HTML;
follow([Key | Rest], HTML) ->
    {value, {Key, _, Childs}} = lists:keysearch(Key, 1, HTML),
    follow(Rest, Childs).

filter_tests(HTML) ->
    lists:reverse(lists:foldl(fun fold_row/2, [], HTML)).

fold_row(Row, Result) ->
    case parse_row(Row) of
	false ->
	    Result;
	Res ->
	    [Res | Result]
    end.

parse_row(Row) ->
    case Row of
	?TAG(tr, _,
	     [
	      ?TAG(td, [?TAG(font, _, [TestNum])]),
	      ?TAG(td, [?TAG(font, _, [Suite])]),
	      ?TAG(td, [{_, _, [Case]}]),
	      ?TAG(td), %% log
	      ?TAG(td, [?TAG(font, _, [Time])]),
	      ?TAG(td, [?TAG(font, _, [RawResult])]),
	      ?TAG(td, RawError)
	     ]) ->
	    Error = iolist_to_binary(error_to_text(RawError)),
	    Duration = parse_duration(Time),
	    Result = to_result(RawResult),
	    {res, TestNum, Suite, Case, Duration, Result, Error};
	?TAG(tr, _,
	     [
	      ?TAG(td, [?TAG(font, _, [TestNum])]),
	      ?TAG(td, [?TAG(font, _, [Suite])]),
	      ?TAG(td, [{_, _, [Case]}]),
	      ?TAG(td), %% log
	      ?TAG(td, [?TAG(font, _, [Time])]),
	      ?TAG(td, [?TAG(font, _, [<<"Ok">>])])
	     ]) ->	
	    {res, TestNum, Suite, Case, parse_duration(Time),
	     ok, <<>>};
	_ ->
	    false
    end.
	
to_result(<<"SKIPPED">>) ->
    skipped;
to_result(<<"FAILED">>) ->
    failed.

error_to_text(B) when is_binary(B) ->
    B;
error_to_text({_, _, Text}) ->
    error_to_text(Text);
error_to_text(HtmlError) when is_list(HtmlError) ->
    lists:map(fun error_to_text/1, HtmlError).

count_by_result(Status, Res) ->
    Filtered = lists:filter(
		 fun (#res{result=S}) -> S == Status end,
		 Res),
    length(Filtered).

sum_duration(Res) ->
    Durations = lists:map(
		  fun(#res{duration=D}) ->
			  list_to_float(binary_to_list(D))
		  end,
		  Res),
    lists:foldl(fun erlang:'+'/2, 0.0, Durations).				 

parse_duration(D) ->
    BS = byte_size(D)-1,
    <<Dura:BS/binary,"s">> = D,
    Dura.
