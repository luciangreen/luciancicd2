% Pack: C.  Tests: "// test: ARGS => EXPECTED STDOUT" (or /* test: ... */).
% The candidate is compiled with gcc (or cc/clang) and run with ARGS.

:- use_module(lc_proc).

lc_packs:pack_def(c, [extensions(["c", "h"]), language(c)]).

lc_packs:pack_run(c, Tests, Text, _Ctx, Results) :-
	c_compiler(CC), !,
	with_tmp_dir(Dir, (
	    atomic_list_concat([Dir, '/prog.c'], Src),
	    atomic_list_concat([Dir, '/prog'], Exe),
	    setup_call_cleanup(open(Src, write, S), write(S, Text), close(S)),
	    run_tool(CC, ['-std=c11', '-O0', '-o', Exe, Src, '-lm'], 20, Exit, Msg),
	    (   Exit == 0
	    ->  maplist(c_test(Exe), Tests, Results)
	    ;   maplist([T, T-fail(compile_error(Msg))]>>true, Tests, Results)
	    ))).

c_compiler(CC) :- member(CC, [gcc, cc, clang]), tool_available(CC), !.

c_test(Exe, T, T-R) :-
	(   T == "valid" -> R = pass
	;   split_expect(T, Args, Exp)
	->  atom_string(ExeA, Exe),
	    run_tool(ExeA, Args, 5, _, Out0),
	    normalize_space(string(Out), Out0),
	    ( Out == Exp -> R = pass ; R = fail(got(Out), expected(Exp)) )
	;   R = fail(bad_test(T))
	).

split_expect(T, Args, Exp) :-
	sub_string(T, B, 2, A, "=>"), !,
	sub_string(T, 0, B, _, AT), sub_string(T, _, A, 0, ET),
	split_string(AT, " ", " ", As0), exclude(==(""), As0, Args),
	normalize_space(string(Exp), ET).
