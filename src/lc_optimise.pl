% lc_optimise.pl - proof-guided optimisation of Prolog
%
% lc_optimise(+Text, -Report, -NewText) makes a tested program faster
% without changing what its tests see.  Every change is kept only if all
% tests still pass and the tests take fewer inferences (measured, not
% guessed).
%
%   tabling          proofs that solve the same sub-goal again and again
%                    (e.g. naive Fibonacci) get ":- table p/n."
%   redundant goals  true, X=X, and repeated pure goals are removed
%   guard hoisting   comparisons and type tests move earlier in a body, to
%                    the first place where the tests still pass, so failing
%                    branches are cut short
%   hints            patterns that are slow in general (append/3 to add one
%                    item in a loop, findall then length) are reported
%
% Run it on a file with lc_optimise_file(File).

:- module(lc_optimise,
	  [ lc_optimise/3,
	    lc_optimise_file/1,
	    lc_inferences/2        % +Text, -Inferences for its tests (or fails)
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(lc_parse).
:- use_module(lc_tests).
:- use_module(lc_proof).
:- use_module(lc_debug, [lc_program/2]).
:- use_module(lc_engine, [rebuild/5]).

lc_optimise_file(File) :-
	read_file_to_string(File, Text, []),
	lc_optimise(Text, Report, New),
	forall(member(L, Report), writeln(L)),
	(   New \== Text
	->  file_name_extension(Base, Ext, File),
	    format(atom(Out), "~w_optimised.~w", [Base, Ext]),
	    setup_call_cleanup(open(Out, write, S), write(S, New), close(S)),
	    format("Wrote ~w~n", [Out])
	;   true
	).

lc_optimise(Text, Report, NewText) :-
	lc_program(Text, Prog),
	Prog = prog(PF, _, KeyCls0, Tests, Dirs),
	(   Tests == []
	->  Report = ["No tests: nothing to measure, so nothing is changed."], NewText = Text
	;   \+ cost(KeyCls0, [], Dirs, Tests, _)
	->  Report = ["Some tests fail: run lc_debug first (optimising needs passing tests)."], NewText = Text
	;   cost(KeyCls0, [], Dirs, Tests, C0),
	    format(string(L0), "Tests pass in ~D inferences.", [C0]),
	    tabling(Prog, KeyCls0, Tests, Dirs, C0, Tabled, C1, R1),
	    redundant(KeyCls0, Tabled, Dirs, Tests, C1, KeyCls1, C2, R2),
	    hoist(KeyCls1, Tabled, Dirs, Tests, C2, KeyCls2, C3, R3),
	    hints(KeyCls2, R4),
	    length(Tests, NT),
	    (   C3 < C0
	    ->  Pct is round(100*(C0-C3)/C0),
		format(string(LF), "Optimised: ~D -> ~D inferences (~w% fewer), all ~w tests pass.", [C0, C3, Pct, NT])
	    ;   LF = "No change made the tests faster."
	    ),
	    append([[L0], R1, R2, R3, R4, [LF]], Report),
	    findall(("file":K)-Cls, member(K-Cls, KeyCls2), Chosen),
	    rebuild("file", PF, pl_file([], ""), Chosen, T1),
	    table_text(Tabled, TT),
	    string_concat(TT, T1, NewText)
	).

lc_inferences(Text, C) :-
	lc_program(Text, prog(_, _, KC, Tests, Dirs)),
	cost(KC, [], Dirs, Tests, C).

% ---------------------------------------------------------------- measuring

%	cost(+KeyCls, +Tabled, +Dirs, +Tests, -Inferences): fails if a test fails.
cost(KeyCls, Tabled, Dirs, Tests, C) :-
	program_text(KeyCls, Tabled, Dirs, Text),
	with_program_text(Text, "/", measure(Tests, C0)),
	nonvar(C0), C0 \== failed,
	C = C0.

measure(Tests, C, M) :-
	statistics(inferences, I0),
	(   forall(member(T, Tests), run_test(M, T, pass))
	->  statistics(inferences, I1), C is I1-I0
	;   C = failed
	).

program_text(KeyCls, Tabled, Dirs, Text) :-
	findall(S, ( member(K, Tabled), format(string(S), ":- table ~q.", [K]) ), TS),
	findall(S, ( member(D, Dirs), term_text((:- D), S0), string_concat(S0, ".", S) ), DS),
	findall(S, ( member(_-Cls, KeyCls), member(C, Cls), clause_text(C, S) ), CS),
	append([TS, DS, CS], All),
	atomic_list_concat(All, '\n', A), atom_string(A, Text).

table_text([], "") :- !.
table_text(Ks, T) :-
	findall(S, ( member(K, Ks), format(string(S), ":- table ~q.~n", [K]) ), Ss),
	atomic_list_concat(Ss, '', A), atom_string(A, T).

% ---------------------------------------------------------------- tabling

%	Predicates whose proofs repeat a sub-goal with the same arguments.
tabling(_Prog, KeyCls, Tests, Dirs, C0, Tabled, C, Report) :-
	findall(K-N, ( repeated_subgoals(KeyCls, Dirs, Tests, Reps), member(K-N, Reps) ), KNs0),
	sort(KNs0, KNs),
	foldl(try_table(KeyCls, Dirs, Tests), KNs, [C0, [], []], [C, Tabled, Report]).

try_table(KeyCls, Dirs, Tests, K-N, [C0, T0, R0], [C, T, R]) :-
	append(T0, [K], T1),
	(   cost(KeyCls, T1, Dirs, Tests, C1), C1 < C0 * 0.7
	->  C = C1, T = T1,
	    format(string(L), "Tabling ~q: its proofs solved the same sub-goal ~w times; inferences ~D -> ~D.", [K, N, C0, C1]),
	    append(R0, [L], R)
	;   C = C0, T = T0, R = R0
	).

repeated_subgoals(KeyCls, Dirs, Tests, Reps) :-
	findall(C, ( member(_-Cs, KeyCls), member(C, Cs) ), Cls),
	with_program(Cls, Dirs, "/", proof_repeats(Tests, Reps0)),
	nonvar(Reps0), Reps = Reps0.

proof_repeats(Tests, Reps, M) :-
	findall(K-N,
		( member(test(_, G0, _), Tests), unground(G0, G),
		  catch(once(prove(M, G, P, 5000)), _, fail),
		  proof_nodes(P, Ns),
		  findall(Gi, member(node(Gi, _), Ns), Gs),
		  msort(Gs, S), clumped_variants(S, Cl),
		  member(Gv-N, Cl), N >= 3, functor(Gv, F, A), K = F/A ),
		KNs),
	sort(KNs, Reps).

clumped_variants(Sorted, Counts) :-
	findall(G-N, ( member(G, Sorted), aggregate_all(count, ( member(G2, Sorted), G2 =@= G ), N) ), C0),
	sort(C0, Counts).

% ---------------------------------------------------------------- redundant goals

redundant(KeyCls0, Tabled, Dirs, Tests, C0, KeyCls, C, Report) :-
	findall(K-CI-GI, ( member(K-Cls, KeyCls0), nth1(CI, Cls, Cl), clause_parts(Cl, _, Gs),
			   nth1(GI, Gs, G), redundant_goal(G, GI, Gs) ), Cands),
	foldl(try_remove(Tabled, Dirs, Tests), Cands, [KeyCls0, C0, [], 0], [KeyCls, C, Report, _]).

redundant_goal(true, _, _).
redundant_goal(A = B, _, _) :- A == B.
redundant_goal(G, I, Gs) :- pure(G), I > 1, I0 is I-1, between(1, I0, J), nth1(J, Gs, G2), G2 == G, !.

pure(G) :- compound(G), functor(G, F, N), memberchk(F/N, [is/2, (=)/2, (<)/2, (>)/2, (=<)/2, (>=)/2,
		(=:=)/2, (=\=)/2, (==)/2, (\==)/2, length/2, append/3, member/2, memberchk/2,
		number/1, atom/1, is_list/1, integer/1, string/1, nonvar/1, sum_list/2, msort/2, sort/2, reverse/2]).

%	Removing earlier goals shifts goal numbers: Removed counts them per clause.
try_remove(Tabled, Dirs, Tests, K-CI-GI, [KC0, C0, R0, _], [KC, C, R, 0]) :-
	memberchk(K-Cls, KC0), nth1(CI, Cls, Cl),
	clause_parts(Cl, H, Gs),
	(   nth1(GI, Gs, G, Gs1), redundant_goal(G, GI, Gs)
	->  build_clause(H, Gs1, Cl1),
	    replace_clause(KC0, K, CI, Cl1, KC1),
	    (   cost(KC1, Tabled, Dirs, Tests, C1), C1 =< C0 + 10      % removing a goal never adds work; allow measuring noise
	    ->  KC = KC1, C = C1,
		clause_text(Cl, T0), clause_text(Cl1, T1),
		format(string(L), "Removed a redundant goal: ~w  ->  ~w", [T0, T1]),
		append(R0, [L], R)
	    ;   KC = KC0, C = C0, R = R0
	    )
	;   KC = KC0, C = C0, R = R0
	).

% ---------------------------------------------------------------- guard hoisting

hoist(KeyCls0, Tabled, Dirs, Tests, C0, KeyCls, C, Report) :-
	findall(K-CI-GI, ( member(K-Cls, KeyCls0), nth1(CI, Cls, Cl), clause_parts(Cl, _, Gs),
			   nth1(GI, Gs, G), GI > 1, guard(G) ), Cands),
	foldl(try_hoist(Tabled, Dirs, Tests), Cands, [KeyCls0, C0, []], [KeyCls, C, Report]).

guard(G) :- compound(G), functor(G, F, N), memberchk(F/N, [(<)/2, (>)/2, (=<)/2, (>=)/2, (=:=)/2,
		(=\=)/2, (==)/2, (\==)/2, number/1, atom/1, is_list/1, integer/1, string/1, atomic/1]).

try_hoist(Tabled, Dirs, Tests, K-CI-GI, [KC0, C0, R0], [KC, C, R]) :-
	memberchk(K-Cls, KC0), nth1(CI, Cls, Cl), clause_parts(Cl, H, Gs),
	(   nth1(GI, Gs, G, Rest), guard(G),
	    GI0 is GI-1, between(1, GI0, P),            % earliest position first
	    nth1(P, Gs1, G, Rest),
	    build_clause(H, Gs1, Cl1),
	    replace_clause(KC0, K, CI, Cl1, KC1),
	    cost(KC1, Tabled, Dirs, Tests, C1), C1 < C0
	->  KC = KC1, C = C1,
	    clause_text(Cl, T0), clause_text(Cl1, T1),
	    format(string(L), "Moved a test earlier (inferences ~D -> ~D): ~w  ->  ~w", [C0, C1, T0, T1]),
	    append(R0, [L], R)
	;   KC = KC0, C = C0, R = R0
	).

% ---------------------------------------------------------------- hints

hints(KeyCls, Hints) :-
	findall(H, ( member(N/A-Cls, KeyCls), member(Cl, Cls), clause_parts(Cl, _, Gs), hint(N/A, Gs, H) ), H0),
	list_to_set(H0, Hints).

hint(N/A, Gs, H) :-
	member(append(_, [_], _), Gs), member(G, Gs), callable(G), functor(G, N, A),
	format(string(H), "Hint: ~q adds one item with append/3 in a recursive loop (quadratic); collect in reverse and reverse once, or use an accumulator.", [N/A]).
hint(N/A, Gs, H) :-
	nth1(I, Gs, findall(_, _, L)), nth1(J, Gs, length(L2, _)), J > I, L2 == L,
	format(string(H), "Hint: ~q uses findall/3 then length/2; aggregate_all(count, ...) avoids building the list.", [N/A]).

% ---------------------------------------------------------------- utilities

clause_parts((H :- B), H, Gs) :- !, conj_goals(B, Gs).
clause_parts(H, H, []).

%	Like body_goals/2, but keeps true so that it can be reported.
conj_goals((A, B), Gs) :- !, conj_goals(A, GA), conj_goals(B, GB), append(GA, GB, Gs).
conj_goals(G, [G]).

build_clause(H, [], H) :- !.
build_clause(H, Gs, (H :- B)) :- goals_body(Gs, B).

replace_clause(KC0, K, CI, Cl1, KC) :-
	maplist([K0-Cs0, K0-Cs]>>( K0 == K -> nth1(CI, Cs0, _, R), nth1(CI, Cs, Cl1, R) ; Cs = Cs0 ), KC0, KC).
