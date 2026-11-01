% lc_tests.pl - tests in comments, and running programs in a sandbox
%
% Test format (unchanged from luciancicd), in comments before or after the
% predicate:
%     % remove_and_find_item_number([a,b,b,c],2,c,N3).
%     % N3 = 3.
%     % d.                 (no variables: must succeed)
%     % not(d(1)).         (must fail)
%
% A test is test(Key, Goal, Expect) with Goal ground ('$VAR' variables) and
%   Expect = bindings([Name-Value, ...]) | succeeds | fails
% A test passes if some solution of Goal makes every named variable a
% variant of its expected value.

:- module(lc_tests,
	  [ comment_tests/3,      % +Items, +DefinedKeys, -Tests
	    test_key/2,
	    with_program/4,       % +Clauses, +Directives, +Cwd, :Goal(M)
	    run_test/3,           % +Module, +Test, -Result (pass|fail(Why))
	    run_tests/4,          % +Module, +Tests, -Passed, -Failed
	    test_text/2,          % +Test, -Text
	    lc_time_limit/1
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(time)).
:- use_module(lc_parse).
:- use_module(lc_vfs).
:- use_module(lc_sandbox_api).

:- meta_predicate with_program(+, +, +, 1).

lc_time_limit(T) :-
	(   catch(user:time_limit(T0), _, fail), number(T0) -> T = T0 ; T = 1 ).

% ---------------------------------------------------------------- extraction

comment_tests(Items, Defined, Tests) :-
	include([item(K,_,_)]>>(K = comment(_)), Items, Cs),
	maplist([item(comment(C),_,_), S]>>comment_body(C, S), Cs, Ss),
	tests_from_lines(Ss, Defined, Tests).

comment_body(C, S) :-
	(   sub_string(C, 0, 2, _, "/*")
	->  sub_string(C, 2, _, 2, S0)
	;   strip_percents(C, S0)
	),
	normalize_space(string(S), S0).

strip_percents(C, S) :-
	(   sub_string(C, 0, 1, _, "%") -> sub_string(C, 1, _, 0, C1), strip_percents(C1, S)
	;   S = C
	).

tests_from_lines([], _, []).
tests_from_lines([L|Ls], Defined, Tests) :-
	(   parse_goal(L, G, Names),
	    test_goal_key(G, Key, Expect0, G1),
	    memberchk(Key, Defined)
	->  (   Expect0 == fails
	    ->  Tests = [test(Key, G1, fails)|Ts], Rest = Ls
	    ;   Names == []
	    ->  Tests = [test(Key, G, succeeds)|Ts], Rest = Ls
	    ;   Ls = [L2|Ls2], parse_bindings(L2, Bs)
	    ->  Tests = [test(Key, G, bindings(Bs))|Ts], Rest = Ls2
	    ;   Tests = [test(Key, G, succeeds)|Ts], Rest = Ls
	    ),
	    tests_from_lines(Rest, Defined, Ts)
	;   tests_from_lines(Ls, Defined, Tests)
	).

parse_goal(L, G, Names) :-
	L \== "",
	catch(term_string(T, L, [variable_names(Vs), syntax_errors(quiet)]), _, fail),
	nonvar(T), callable(T), T \= (_ = _), T \= (_ , _),
	ground_term(T, Vs, G),
	findall(N, member(N=_, Vs), Names).

test_goal_key(not(G), K, fails, G) :- !, callable(G), functor(G, N, A), K = N/A.
test_goal_key(\+(G), K, fails, G) :- !, callable(G), functor(G, N, A), K = N/A.
test_goal_key(G, N/A, succeeds, G) :- functor(G, N, A).

parse_bindings(L, Bs) :-
	catch(term_string(T, L, [variable_names(Vs), syntax_errors(quiet)]), _, fail),
	nonvar(T),
	ground_term(T, Vs, G),
	conj_list(G, Eqs),
	maplist([E, N-V]>>(nonvar(E), E = ('$VAR'(N) = V), atom(N)), Eqs, Bs).

conj_list((A,B), L) :- !, conj_list(A, LA), conj_list(B, LB), append(LA, LB, L).
conj_list(A, [A]).

test_key(test(K,_,_), K).

test_text(test(_, G, Exp), Text) :-
	term_text(G, GT),
	(   Exp = bindings(Bs)
	->  maplist([N-V, S]>>(term_text(V, VT), format(string(S), "~w=~w", [N, VT])), Bs, Ss),
	    atomic_list_concat(Ss, ',', BT),
	    format(string(Text), "~w -> ~w", [GT, BT])
	;   Exp == fails
	->  format(string(Text), "not(~w)", [GT])
	;   Text = GT
	).

% ---------------------------------------------------------------- sandbox

%!	with_program(+Clauses, +Directives, +Cwd, :Goal) is semidet.
%	Load ground Clauses into a fresh temporary module M and call Goal(M)
%	with the VFS current directory set to Cwd.  The module is destroyed
%	afterwards.  Fails if the program cannot be loaded.
with_program(Clauses, Directives, Cwd, Goal) :-
	in_temporary_module(M,
			    setup_program(M, Clauses, Directives),
			    run_in(M, Cwd, Goal)).

run_in(M, Cwd, Goal) :-
	nb_setval(lc_sandbox_cwd, Cwd),
	vfs_scratch_clear,
	call_cleanup(call(Goal, M),
		     ( vfs_scratch_clear, nb_setval(lc_sandbox_cwd, []) )).

setup_program(M, Clauses, Directives) :-
	add_import_module(M, lc_sandbox_api, start),
	forall(member(D, Directives), run_directive(M, D)),
	catch(forall(member(C, Clauses), add_clause(M, C)), E,
	      ( print_message(silent, E), nb_setval(lc_load_error, E), fail )),
	!.

add_clause(M, G) :-
	unground(G, C0),
	(   C0 = (_ --> _) -> dcg_translate_rule(C0, C) ; C = C0 ),
	assertz(M:C).

run_directive(M, D0) :-
	unground(D0, D),
	(   allowed_directive(D)
	->  catch(with_output_to(string(_), M:D), _, true)
	;   true
	).

allowed_directive(dynamic(_)).
allowed_directive(discontiguous(_)).
allowed_directive(table(_)).
allowed_directive(op(_,_,_)).
allowed_directive(set_prolog_flag(_,_)).
allowed_directive(use_module(library(_))).
allowed_directive(use_module(library(_), _)).
allowed_directive(ensure_loaded(library(_))).

%!	run_test(+M, +Test, -Result)
run_test(M, test(_, G0, Exp), Result) :-
	unground_names(G0, G, Names),
	lc_time_limit(T),
	(   Exp == fails
	->  Check = (\+ M:G)
	;   Exp == succeeds
	->  Check = M:G
	;   Exp = bindings(Bs),
	    Check = ( M:G, maplist(binding_ok(Names), Bs) )
	),
	catch(( with_output_to(string(_), call_with_time_limit(T, once(Check)))
	      -> Result = pass
	      ;  Result = fail(no_matching_solution)
	      ),
	      E, ( error_reason(E, Why), Result = fail(Why) )).

binding_ok(Names, N-V0) :-
	memberchk(N-Var, Names),
	unground(V0, V),
	Var =@= V.

error_reason(time_limit_exceeded, time_limit_exceeded) :- !.
error_reason(error(E, _), error(E)) :- !.
error_reason(E, exception(E)).

run_tests(M, Tests, Passed, Failed) :-
	partition([Tt]>>(run_test(M, Tt, R), R == pass), Tests, Passed, Failed).
