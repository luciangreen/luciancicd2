% Pack: JavaScript.  Tests: "// test: EXPRESSION => EXPECTED".
% The candidate is run with node; each expression is evaluated after it.

:- use_module(lc_proc).
:- use_module(library(http/json)).

lc_packs:pack_def(javascript, [extensions(["js", "mjs", "cjs"]), language(javascript)]).

lc_packs:pack_run(javascript, Tests, Text, _Ctx, Results) :-
	tool_available(node), !,
	partition(==("valid"), Tests, Valid, Exprs),
	maplist([T, T-pass]>>true, Valid, VR),
	maplist(js_expr, Exprs, Parts),
	atomic_list_concat(Parts, '\n', Calls),
	format(string(Prog),
	       "~w~n;(function(){~n const __r=[];~n const __s=v=>(typeof v==='object')?JSON.stringify(v):String(v);~n~w~n console.log(JSON.stringify(__r));~n})();~n",
	       [Text, Calls]),
	with_tmp_dir(Dir, (
	    atomic_list_concat([Dir, '/prog.js'], F),
	    setup_call_cleanup(open(F, write, S), write(S, Prog), close(S)),
	    run_tool(node, [F], 10, Exit, Out))),
	(   Exit == 0, split_string(Out, "\n", "", Ls), exclude(==(""), Ls, Ls1), last(Ls1, Last),
	    catch(( open_string(Last, St), json_read_dict(St, Got) ), _, fail), is_list(Got)
	->  maplist(js_result, Exprs, Got, ER)
	;   maplist([T, T-fail(run_error(Out))]>>true, Exprs, ER)
	),
	append(VR, ER, Results).

js_expr(T, Line) :-
	( split_js(T, E, _) -> true ; E = T ),
	format(string(Line), " try{__r.push(__s((~w)))}catch(e){__r.push('Error: '+e.message)}", [E]).

split_js(T, E, X) :-
	sub_string(T, B, 2, A, "=>"),
	\+ ( sub_string(T, B2, 2, _, "=>"), B2 > B ), !,
	sub_string(T, 0, B, _, E0), sub_string(T, _, A, 0, X0),
	normalize_space(string(E), E0), normalize_space(string(X), X0).

js_result(T, G, T-R) :-
	(   split_js(T, _, Exp)
	->  ( G == Exp -> R = pass ; R = fail(got(G), expected(Exp)) )
	;   R = pass
	).
