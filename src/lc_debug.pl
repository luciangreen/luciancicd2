% lc_debug.pl - automatic debugging of Prolog with proofs and an MNN
%
% lc_debug(+Text, -Report, -FixedText) takes a Prolog file with tests in
% comments and, while tests fail:
%   1. picks the lowest failing predicate (bottom-up, as in CI/CD);
%   2. diagnoses the failing test from its proof (lc_proof):
%        error          - the clause and goal that raised it
%        missing answer - the clause whose head fits the intended answer and
%                         the first goal of its body that fails
%        wrong answer   - algorithmic debugging: walk down the proof tree,
%                         asking the tests of the called predicates (the
%                         oracle) whether each sub-proof is right, to the
%                         clause whose sub-proofs are all right but whose
%                         answer is wrong
%   3. ranks kinds of repair with an MNN trained on bugs it planted itself
%      (swapped operators, changed constants, swapped goals, ...), using
%      features of the failure such as "off by a constant" or "sign flipped";
%   4. tries repairs at the diagnosed clause and goal, in that order, and
%      keeps the first that makes the predicate's tests pass without
%      breaking any test that passed;
%   5. if no small repair works, asks S2A2 to rewrite the predicate from its
%      tests.
% Every repair is proved by running all the tests.

:- module(lc_debug,
	  [ lc_debug/3,          % +Text, -Report, -FixedText
	    lc_debug_file/1,     % +File
	    lc_diagnose/3,       % +Text, +TestNo, -Diagnosis
	    lc_program/2,        % +Text, -Prog
	    lc_results/2,        % +Prog, -[Test-Result]
	    repair_mnn/1,
	    repair_train/0
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(readutil)).
:- use_module(lc_parse).
:- use_module(lc_tests).
:- use_module(lc_deps).
:- use_module(lc_proof).
:- use_module(lc_mnn).
:- use_module(lc_s2a2).
:- use_module(lc_engine, [rebuild/5]).

:- dynamic repair_cache/1.

% ---------------------------------------------------------------- program model

lc_program(T, P) :- program(T, P).
lc_results(P, R) :- results(P, R).

program(Text, prog(PF, Keys, KeyCls, Tests, Dirs)) :-
	pl_parse(Text, PF), PF = pl_file(Items, _),
	findall(K, member(item(clause(K,_),_,_), Items), Ks0), list_to_set(Ks0, Keys0),
	findall(K, ( member(item(comment(C),_,_), Items), test_comment_key(C, K) ), TK0),
	append(Keys0, TK0, AllK0), list_to_set(AllK0, Keys),
	findall(K-Cls, ( member(K, Keys), findall(G, member(item(clause(K,G),_,_), Items), Cls) ), KeyCls),
	comment_tests(Items, Keys, Tests),
	findall(D, ( member(item(directive(D),_,_), Items), \+ directive_includes(D, [_|_]) ), Dirs).

test_comment_key(C, N/A) :-
	sub_string(C, 0, 1, _, "%"), sub_string(C, 1, _, 0, S0), normalize_space(string(S), S0),
	catch(term_string(T, S), _, fail), callable(T), T \= (_=_), T \= (_,_),
	( T = not(G) -> true ; G = T ), callable(G), functor(G, N, A).

collect_results(Tests, Rs, M) :- findall(T-R, ( member(T, Tests), run_test(M, T, R) ), Rs).

all_clauses(KeyCls, Cls) :- findall(C, ( member(_-Cs, KeyCls), member(C, Cs) ), Cls).

results(Prog, Results) :-
	Prog = prog(_, _, KeyCls, Tests, Dirs),
	all_clauses(KeyCls, Cls),
	(   with_program(Cls, Dirs, "/", collect_results(Tests, Rs0)),
	    nonvar(Rs0)
	->  Results = Rs0
	;   findall(T-fail(load_error), member(T, Tests), Results)
	).

% ---------------------------------------------------------------- main loop

lc_debug_file(File) :-
	read_file_to_string(File, Text, []),
	lc_debug(Text, Report, Fixed),
	forall(member(L, Report), writeln(L)),
	(   Fixed \== Text
	->  file_name_extension(Base, Ext, File),
	    format(atom(Out), "~w_fixed.~w", [Base, Ext]),
	    setup_call_cleanup(open(Out, write, S), write(S, Fixed), close(S)),
	    format("Wrote ~w~n", [Out])
	;   true
	).

lc_debug(Text, Report, Fixed) :-
	program(Text, Prog),
	debug_loop(Prog, 6, [], Report0, Prog1),
	Prog1 = prog(PF1, _, KeyCls1, _, _),
	Prog = prog(PF0, _, _, _, _),
	(   PF1 == PF0, Prog1 = Prog
	->  Fixed = Text
	;   findall(("file":K)-Cls, member(K-Cls, KeyCls1), Chosen),
	    rebuild("file", PF0, pl_file([], ""), Chosen, Fixed)
	),
	Report = Report0.

debug_loop(Prog, N, R0, R, ProgF) :-
	results(Prog, Rs),
	include([_-X]>>(X \== pass), Rs, Failing),
	length(Rs, NT), length(Failing, NF),
	(   Failing == []
	->  format(string(L), "All ~w tests pass.", [NT]), append(R0, [L], R), ProgF = Prog
	;   N =:= 0
	->  format(string(L), "Stopping: ~w of ~w tests still fail.", [NF, NT]), append(R0, [L], R), ProgF = Prog
	;   lowest_failing(Prog, Failing, T-Res),
	    test_text(T, TT),
	    format(string(L1), "Failing: ~w (~q).", [TT, Res]),
	    diagnose(Prog, T, Diag),
	    diag_text(Diag, L2),
	    (   repair(Prog, Rs, T, Diag, Prog1, How)
	    ->  append(R0, [L1, L2, How], R1),
		N1 is N-1,
		debug_loop(Prog1, N1, R1, R, ProgF)
	    ;   append(R0, [L1, L2, "No repair found that passes the tests."], R), ProgF = Prog
	    )
	).

lowest_failing(prog(_, Keys, KeyCls, _, _), Failing, F) :-
	findall(K-Cs, ( member(K-Cls, KeyCls), findall(C1, ( member(Cl, Cls), clause_calls(Cl, Cs0), member(C1, Cs0), memberchk(C1, Keys) ), Cs1), sort(Cs1, Cs) ), Edges),
	bottom_up_groups(Keys, Edges, Groups),
	append(Groups, Order),
	member(K, Order), member(F, Failing), F = T-_, test_key(T, K), !.

% ---------------------------------------------------------------- diagnosis

%	diag(Key, Kind, ClauseNo, GoalNo, Detail, Features)
diagnose(Prog, T, Diag) :-
	Prog = prog(_, _, KeyCls, Tests, Dirs),
	all_clauses(KeyCls, Cls),
	T = test(Key, _, _),
	(   with_program(Cls, Dirs, "/", diag_in_m(KeyCls, Tests, T, Diag0)), nonvar(Diag0)
	->  Diag = Diag0
	;   Diag = diag(Key, unknown, 0, 0, "could not diagnose", [])
	).

diag_in_m(KeyCls, Tests, T, Diag, M) :- diag_in(M, KeyCls, Tests, T, Diag).

diag_in(M, KeyCls, Tests, T, Diag) :-
	T = test(Key, G0, Exp),
	unground_names(G0, G, Names),
	catch(findall(G-P, limit(20, prove(M, G, P)), Sols), E, true),
	(   nonvar(E)
	->  error_location(M, KeyCls, Key, G, E, C, J),
	    features(error(E), Key, KeyCls, C, J, Fs),
	    Diag = diag(Key, error(E), C, J, "", Fs)
	;   Exp == fails
	->  ( Sols = [_-P|_] -> wrong_clause(M, Tests, P, Key1, C) ; Key1 = Key, C = 0 ),
	    features(should_fail, Key1, KeyCls, C, 0, Fs),
	    Diag = diag(Key1, should_fail, C, 0, "", Fs)
	;   Exp == succeeds
	->  missing_location(M, KeyCls, Key, G, C, J),
	    features(no_answer, Key, KeyCls, C, J, Fs),
	    Diag = diag(Key, no_answer, C, J, "", Fs)
	;   Exp = bindings(Bs),
	    (   Sols == []
	    ->  intended(G, Names, Bs, GI),
		missing_location(M, KeyCls, Key, GI, C, J),
		features(no_answer, Key, KeyCls, C, J, Fs),
		Diag = diag(Key, no_answer, C, J, "", Fs)
	    ;   Sols = [GS-P|_],
		G = GS,
		findall(A-V, ( member(N-V0, Bs), memberchk(N-A, Names), unground(V0, V) ), AVs),
		wrong_clause(M, Tests, P, Key1, C),
		answer_goal(KeyCls, Key1, C, J),
		features(wrong(AVs), Key1, KeyCls, C, J, Fs),
		format(string(D), "got ~q", [AVs]),
		Diag = diag(Key1, wrong_answer, C, J, D, Fs)
	    )
	).

intended(G, Names, Bs, GI) :-
	copy_term(G-Names, GI-NI),
	bind_expected(Bs, NI).

bind_expected([], _).
bind_expected([N-V0|Bs], NI) :-
	memberchk(N-Var, NI), unground(V0, V), Var = V,
	bind_expected(Bs, NI).

%	The clause and body goal where an error is raised: run the body of each
%	clause whose head matches, goal by goal.
error_location(M, KeyCls, Key, G, _E, C, J) :-
	memberchk(Key-Cls, KeyCls),
	(   nth1(C, Cls, Cl0), unground(Cl0, Cl), clause_parts(Cl, H, Gs),
	    copy_term(G, G1), G1 = H,
	    first_bad_goal(M, Gs, 1, error, J)
	->  true
	;   C = 0, J = 0
	).

%	For a missing answer: the matching clause that gets furthest.
missing_location(M, KeyCls, Key, GI, C, J) :-
	memberchk(Key-Cls, KeyCls),
	findall(Prog-(Ci-Ji),
		( nth1(Ci, Cls, Cl0), unground(Cl0, Cl), clause_parts(Cl, H, Gs),
		  copy_term(GI, G1), G1 = H,
		  ( first_bad_goal(M, Gs, 1, fail, Ji) -> true ; length(Gs, L), Ji is L+1 ),
		  Prog = Ji ), Ps),
	(   Ps == [] -> C = 0, J = 0            % no head matches: a missing clause
	;   keysort(Ps, S), last(S, _-(C-J))
	).

%	Run the goals in order (bindings carry over) to the first that fails
%	(Kind = fail) or raises an error (Kind = error).
first_bad_goal(M, [G|Gs], I, Kind, J) :-
	catch(( once(prove(M, G, _)) -> R = ok ; R = failed ), _, R = error),
	(   R == ok -> I1 is I+1, first_bad_goal(M, Gs, I1, Kind, J)
	;   Kind == error -> R == error, J = I
	;   J = I
	).

clause_parts((H :- B), H, Gs) :- !, body_goals(B, Gs).
clause_parts(H, H, []).

%	Algorithmic debugging on a proof of a wrong answer.
wrong_clause(M, Tests, node(G, C, B), Key, CF) :-
	proof_children(B, Ch),
	(   member(node(G2, C2, B2), Ch), oracle(M, Tests, G2, wrong)
	->  wrong_clause(M, Tests, node(G2, C2, B2), Key, CF)
	;   functor(G, N, A), Key = N/A, CF = C
	).
wrong_clause(_, _, P, '?'/0, 0) :- P \= node(_,_,_).

proof_children(P, Ns) :- phrase(children(P), Ns).
children(node(G, C, B)) --> !, [node(G, C, B)].
children(and(A, B)) --> !, children(A), children(B).
children(left(A)) --> !, children(A).
children(right(A)) --> !, children(A).
children(then(A, B)) --> !, children(A), children(B).
children(else(A)) --> !, children(A).
children(all(_, Ps)) --> !, children_list(Ps).
children(_) --> [].
children_list([]) --> [].
children_list([P|Ps]) --> children(P), children_list(Ps).

%	The tests are the oracle: a sub-proof of p(In..., Out) is wrong if a
%	test of p with the same inputs expects another output.
oracle(_, Tests, Inst, Verdict) :-
	functor(Inst, N, A),
	(   member(test(N/A, G0, bindings(Bs)), Tests),
	    unground_names(G0, G, Names),
	    forall(member(Nm-_, Bs), ( memberchk(Nm-V, Names), var(V) )),
	    \+ \+ ( same_inputs(G, Inst) )
	->  intended(G, Names, Bs, GI),
	    ( \+ \+ ( same_inputs(G, Inst), GI =@= Inst ) -> Verdict = right
	    ; subsumes_term(GI, Inst) -> Verdict = right
	    ; Verdict = wrong )
	;   Verdict = unknown
	).

same_inputs(G, Inst) :-
	G =.. [_|GA], Inst =.. [_|IA],
	maplist([X, Y]>>( var(X) -> true ; X =@= Y ), GA, IA).

%	The goal that computes the answer: the last arithmetic or unification goal.
answer_goal(KeyCls, Key, C, J) :-
	(   memberchk(Key-Cls, KeyCls), nth1(C, Cls, Cl), clause_parts(Cl, _, Gs),
	    findall(I, ( nth1(I, Gs, G), compound(G), functor(G, F, 2), memberchk(F, [is, =]) ), Is),
	    last(Is, J0)
	->  J = J0
	;   J = 0
	).

diag_text(diag(K, Kind, C, J, D, _), T) :-
	(   Kind = error(E) -> format(string(KT), "error ~q", [E]) ; format(string(KT), "~w", [Kind]) ),
	(   C =:= 0 -> Where = "no clause fits"
	;   J =:= 0 -> format(string(Where), "clause ~w", [C])
	;   format(string(Where), "clause ~w, goal ~w", [C, J])
	),
	format(string(T), "Diagnosis (from the proof): ~w in ~w, ~w ~w.", [KT, K, Where, D]).

% ---------------------------------------------------------------- features

feature_names([err_instantiation, err_type, err_existence, err_other, no_answer, wrong_answer,
	       should_fail, off_by_const, sign_flip, ratio, list_reversed, list_permutation,
	       list_length_diff, wrong_case, arith_goal, compare_goal, user_goal,
	       no_clause_fits, recursive, has_base_case]).

repair_classes([op_swap, cmp_swap, const_change, goal_swap, arg_swap, add_base_case, head_const, goal_delete]).

features(Kind, Key, KeyCls, C, J, Fs) :-
	feature_names(Ns),
	( memberchk(Key-Cls, KeyCls) -> true ; Cls = [] ),
	( C > 0, nth1(C, Cls, Cl), clause_parts(Cl, _, Gs), J > 0, nth1(J, Gs, Goal) -> true ; Goal = none ),
	maplist([N, V]>>( catch(feat(N, Kind, Key, Cls, C, Goal), _, fail) -> V = 1.0 ; V = 0.0 ), Ns, Fs).

feat(err_instantiation, error(error(instantiation_error,_)), _, _, _, _).
feat(err_type, error(error(type_error(_,_),_)), _, _, _, _).
feat(err_existence, error(error(existence_error(_,_),_)), _, _, _, _).
feat(err_other, error(_), _, _, _, _).
feat(no_answer, no_answer, _, _, _, _).
feat(wrong_answer, wrong(_), _, _, _, _).
feat(should_fail, should_fail, _, _, _, _).
feat(off_by_const, wrong(AVs), _, _, _, _) :- member(A-V, AVs), number(A), number(V), D is abs(A-V), D > 0, D =< 2.
feat(sign_flip, wrong(AVs), _, _, _, _) :- member(A-V, AVs), number(A), number(V), A =:= -V, A =\= 0.
feat(ratio, wrong(AVs), _, _, _, _) :- member(A-V, AVs), number(A), number(V), V =\= 0, A =\= V, R is A/V, R =:= round(R).
feat(list_reversed, wrong(AVs), _, _, _, _) :- member(A-V, AVs), is_list(A), reverse(A, V), A \== V.
feat(list_permutation, wrong(AVs), _, _, _, _) :- member(A-V, AVs), is_list(A), is_list(V), msort(A, S), msort(V, S).
feat(list_length_diff, wrong(AVs), _, _, _, _) :- member(A-V, AVs), is_list(A), is_list(V), length(A, L1), length(V, L2), L1 =\= L2.
feat(wrong_case, wrong(AVs), _, _, _, _) :- member(A-V, AVs), string(A), string(V), string_lower(A, L), string_lower(V, L).
feat(arith_goal, _, _, _, _, G) :- compound(G), ( G = (_ is _) ; sub_term(S, G), compound(S), functor(S, F, 2), memberchk(F, [+, -, *, /, //]) ).
feat(compare_goal, _, _, _, _, G) :- compound(G), functor(G, F, 2), memberchk(F, [<, >, =<, >=, =:=, =\=]).
feat(user_goal, _, _, Cls, _, G) :- compound(G), functor(G, N, A), \+ predicate_property(system:G, defined), \+ memberchk(N/A, []), Cls \== [].
feat(no_clause_fits, _, _, _, 0, _).
feat(recursive, _, N/A, Cls, _, _) :- member(Cl, Cls), clause_parts(Cl, _, Gs), member(G, Gs), callable(G), functor(G, N, A).
feat(has_base_case, _, _, Cls, _, _) :- member(Cl, Cls), Cl \= (_ :- _).

% ---------------------------------------------------------------- repairs

%	repair(+Prog, +Results, +Test, +Diag, -Prog1, -How)
%	Repairs are tried at the diagnosed clause first, then in predicates it
%	calls that have no tests of their own (the oracle could not judge them).
repair(Prog, Rs, _T, Diag, Prog1, How) :-
	Diag = diag(Key, _, C, J, _, Fs),
	repair_classes(Classes),
	(   repair_mnn(mnn(_, _, _, Net)) -> mnn_rank(Net, Fs, Classes, Ranked) ; Ranked = Classes ),
	include([_-pass]>>true, Rs, Passing0), pairs_keys(Passing0, Passing),
	length(Passing, NP),
	Prog = prog(_, _, KeyCls, Tests, _),
	untested_callees(KeyCls, Tests, Key, Suspects),
	findall(L, ( L = Key-C-J ; member(SK, Suspects), L = SK-0-0 ), Locs),
	(   member(Op, Ranked),
	    member(LK-LC-LJ, Locs),
	    candidate(Op, Prog, KeyCls, LK, LC, LJ, Diag, NewCls, What),
	    replace_key(Prog, LK, NewCls, ProgC),
	    results(ProgC, RsC),
	    include([_-pass]>>true, RsC, PC0), pairs_keys(PC0, PC),
	    length(PC, NPC), NPC > NP,
	    forall(member(T0, Passing), memberchk(T0, PC)),
	    forall(( member(T1-_, RsC), test_key(T1, Key) ), memberchk(T1-pass, RsC))
	->  Prog1 = ProgC,
	    ( LK == Key -> Where = "" ; format(string(Where), " in ~q, called by ~q and without tests of its own", [LK, Key]) ),
	    format(string(How), "Repair (~w~w; MNN ranked ~w first): ~w", [Op, Where, Ranked, What])
	;   resynthesise(Prog, Key, Prog1, How)
	).

%	Predicates called (directly or not) by Key that have no tests.
untested_callees(KeyCls, Tests, Key, Ks) :-
	findall(K-Cs, ( member(K-Cls, KeyCls),
			findall(C1, ( member(Cl, Cls), clause_calls(Cl, Cs0), member(C1, Cs0), memberchk(C1-_, KeyCls) ), Cs1),
			sort(Cs1, Cs) ), Edges),
	reach([Key], Edges, [Key], R),
	findall(K, ( member(K, R), K \== Key, \+ ( member(T, Tests), test_key(T, K) ) ), Ks).

reach([], _, R, R).
reach([K|Ks], Edges, Acc, R) :-
	( memberchk(K-Cs, Edges) -> true ; Cs = [] ),
	exclude([C]>>memberchk(C, Acc), Cs, New),
	append(Acc, New, Acc1), append(Ks, New, Ks1),
	reach(Ks1, Edges, Acc1, R).

replace_key(prog(PF, Keys, KeyCls, Tests, Dirs), Key, NewCls, prog(PF, Keys, KeyCls1, Tests, Dirs)) :-
	maplist([K-Cs, K-Cs1]>>( K == Key -> Cs1 = NewCls ; Cs1 = Cs ), KeyCls, KeyCls1).

%	candidate(+Op, ..., -NewClauses, -Description) is nondet.
candidate(Op, prog(_, _, _, Tests, _), KeyCls, Key, C, J, _, NewCls, What) :-
	memberchk(Key-Cls, KeyCls),
	length(Cls, NC),
	(   Op == add_base_case
	->  base_case(Tests, Key, Fact), NewCls = [Fact|Cls],
	    clause_text(Fact, FT), format(string(What), "added base case ~w", [FT])
	;   ( C > 0, CI = C ; between(1, NC, CI), CI =\= C ),
	    nth1(CI, Cls, Cl),
	    clause_units(Cl, [h(H)|GUs]), maplist([g(G), G]>>true, GUs, Gs),
	    mutate(Op, Tests, H, Gs, J, H1, Gs1),
	    maplist([G, g(G)]>>true, Gs1, GUs1),
	    units_clauses([h(H1)|GUs1], [Cl1]),
	    Cl1 \== Cl,
	    nth1(CI, Cls, _, Rest), nth1(CI, NewCls, Cl1, Rest),
	    clause_text(Cl, T0), clause_text(Cl1, T1),
	    format(string(What), "clause ~w: ~w  ->  ~w", [CI, T0, T1])
	).

goal_index(J, Gs, I) :- length(Gs, L), ( J > 0, J =< L -> ( I = J ; between(1, L, I), I =\= J ) ; between(1, L, I) ).

mutate(op_swap, _, H, Gs, J, H, Gs1) :-
	goal_index(J, Gs, I), nth1(I, Gs, G, R),
	sub_mutation(op_swap1, G, G1), nth1(I, Gs1, G1, R).
mutate(cmp_swap, _, H, Gs, J, H, Gs1) :-
	goal_index(J, Gs, I), nth1(I, Gs, G, R),
	G =.. [F, A, B], cmp(F, F1), G1 =.. [F1, A, B], nth1(I, Gs1, G1, R).
mutate(const_change, Tests, H, Gs, J, H, Gs1) :-
	goal_index(J, Gs, I), nth1(I, Gs, G, R),
	test_consts(Tests, Ks),
	sub_mutation(const1(Ks), G, G1), nth1(I, Gs1, G1, R).
mutate(head_const, Tests, H, Gs, _, H1, Gs) :-
	test_consts(Tests, Ks), sub_mutation(const1(Ks), H, H1).
mutate(goal_swap, _, H, Gs, J, H, Gs1) :-
	length(Gs, L), L >= 2,
	( J > 0 -> ( I = J ; I is J-1 ) ; between(1, L, I) ),
	I >= 1, I2 is I+1, I2 =< L,
	nth1(I, Gs, A), nth1(I2, Gs, B),
	swap_at(Gs, I, I2, A, B, Gs1).
mutate(arg_swap, _, H, Gs, J, H, Gs1) :-
	goal_index(J, Gs, I), nth1(I, Gs, G, R),
	G =.. [F|As], length(As, NA), NA >= 2,
	between(1, NA, P1), P2 is P1+1, P2 =< NA,
	nth1(P1, As, X), nth1(P2, As, Y), swap_at(As, P1, P2, X, Y, As1),
	G1 =.. [F|As1], nth1(I, Gs1, G1, R).
mutate(goal_delete, _, H, Gs, J, H, Gs1) :-
	goal_index(J, Gs, I), nth1(I, Gs, _, Gs1).

swap_at(L, I, J, A, B, L1) :-
	findall(E, ( nth1(K, L, E0), ( K =:= I -> E = B ; K =:= J -> E = A ; E = E0 ) ), L1),
	true.

sub_mutation(M, T, T1) :- call(M, T, T1).
sub_mutation(M, T, T1) :-
	compound(T), T \= '$VAR'(_),
	T =.. [F|As], nth1(I, As, A, R),
	sub_mutation(M, A, A1),
	nth1(I, As1, A1, R), T1 =.. [F|As1].

op_swap1(T, T1) :- compound(T), T =.. [F, A, B], op(F, F1), T1 =.. [F1, A, B].
op(+, -). op(-, +). op(*, /). op(/, *). op(*, +). op(+, *). op(//, *). op(-, *). op(mod, //).
op(is, =:=).
cmp(<, >). cmp(>, <). cmp(=<, >=). cmp(>=, =<). cmp(<, =<). cmp(>, >=). cmp(=<, <). cmp(>=, >).
cmp(=:=, =\=). cmp(=\=, =:=). cmp(==, \==). cmp(\==, ==).

const1(Ks, N, N1) :- number(N), integer(N), ( N1 is N+1 ; N1 is N-1 ; member(N1, [0, 1]) ; member(N1, Ks), number(N1) ), N1 \== N.

test_consts(Tests, Ks) :-
	findall(K, ( member(test(_, G, E), Tests), ( sub_term(K, G) ; E = bindings(Bs), member(_-V, Bs), sub_term(K, V) ), integer(K) ), K0),
	sort(K0, Ks1), ( length(Ks, 6), append(Ks, _, Ks1) -> true ; Ks = Ks1 ).

%	A fact from a test whose inputs are ground, e.g. f(0,1) from
%	"%f(0,A). %A=1."  (a missing base case).
base_case(Tests, Key, Fact) :-
	member(test(Key, G0, bindings(Bs)), Tests),
	unground_names(G0, G, Names),
	intended(G, Names, Bs, GI),
	ground(GI),
	G =.. [_|Args], include(nonvar, Args, Ins), Ins \== [],
	maplist(base_value, Ins),             % a base case, not a copy of any test
	ground_term(GI, [], Fact).

base_value(X) :- X == [] ; X == 0 ; X == "" ; X == 1 ; atom(X).

resynthesise(Prog, N/A, Prog1, How) :-
	Prog = prog(_, _, _, Tests, _),
	A >= 2,
	findall([Ins, Y], ( member(test(N/A, G0, bindings([_-Y0])), Tests),
			    unground(G0-Y0, G-Y), G =.. [_|Args], append(Ins, [Out], Args),
			    var(Out), ground(Ins), ground(Y) ), Specs),
	Specs = [_,_|_],
	length(Specs, NS), MaxD is min(3, NS-1),
	s2a2(N, Specs, Code, [max_depth(MaxD)]),
	pl_parse(Code, pl_file(Items, _)),
	findall(K-Cl, member(item(clause(K,Cl),_,_), Items), KCs),
	findall(Cl, member((N/A)-Cl, KCs), Main),
	replace_key(Prog, N/A, Main, Prog2),
	findall(K, ( member(K-_, KCs), K \== N/A ), HKs0), sort(HKs0, HKs),
	foldl([K, P0, P]>>( P0 = prog(PF, Ks, KC, T, D),
			      findall(C, member(K-C, KCs), Cs),
			      append(Ks, [K], Ks1), append(KC, [K-Cs], KC1),
			      P = prog(PF, Ks1, KC1, T, D) ), HKs, Prog2, Prog1),
	results(Prog1, Rs),
	forall(( member(T-R, Rs), test_key(T, N/A) ), R == pass),
	split_string(Code, "\n", "", Ls), exclude([L]>>sub_string(L, 0, 1, _, "%"), Ls, CLs),
	atomic_list_concat(CLs, ' ', CT),
	format(string(How), "Repair (S2A2 rewrote ~w from its tests): ~w", [N/A, CT]).

lc_diagnose(Text, I, D) :-
	program(Text, Prog), Prog = prog(_, _, _, Tests, _),
	nth1(I, Tests, T), diagnose(Prog, T, D).

% ---------------------------------------------------------------- the repair MNN

repair_mnn(M) :- repair_cache(M), !.
repair_mnn(M) :- repair_file(F), mnn_load(F, M), !, assertz(repair_cache(M)).
repair_mnn(M) :- repair_train, repair_cache(M).

repair_file(F) :-
	module_property(lc_debug, file(Src)), file_directory_name(Src, D),
	atomic_list_concat([D, '/../data/mnn_repair.pl'], F).

%	Plant bugs in correct programs, diagnose them, and learn which kind of
%	repair undoes each kind of bug.
repair_train :-
	repair_classes(Classes), feature_names(Fs),
	findall(X-Y, planted_bug(Classes, X, Y), Data0),
	sort(Data0, Data),
	length(Fs, NIn), length(Classes, NOut),
	mnn_new(NIn, 12, NOut, 3, Net0),
	mnn_train(Net0, Data, 150, 0.1, Net),
	mnn_accuracy(Net, Data, Acc), length(Data, ND),
	format(user_error, "Repair MNN trained on ~w planted bugs, accuracy ~2f~n", [ND, Acc]),
	M = mnn(repair, Fs, Classes, Net),
	retractall(repair_cache(_)), assertz(repair_cache(M)),
	repair_file(File), file_directory_name(File, Dir), make_directory_path(Dir),
	catch(mnn_save(File, M), _, true).

seed_program("%count([a,b,c],A).\n%A=3.\n%count([],A).\n%A=0.\ncount([],0).\ncount([_|T],N):-count(T,N0),N is N0+1.").
seed_program("%sum([1,2,3],A).\n%A=6.\n%sum([5],A).\n%A=5.\nsum([],0).\nsum([H|T],S):-sum(T,S0),S is S0+H.").
seed_program("%mx(3,2,A).\n%A=3.\n%mx(1,4,A).\n%A=4.\nmx(A,B,A):-A>=B,!.\nmx(_,B,B).").
seed_program("%f(3,A).\n%A=6.\n%f(0,A).\n%A=1.\nf(0,1):-!.\nf(N,F):-N1 is N-1,f(N1,F1),F is N*F1.").
seed_program("%c(A).\n%A=3.\nc(C):-A=1,B=2,C is A+B.").
seed_program("%p(2,3,A).\n%A=8.\n%p(5,0,A).\n%A=1.\np(_,0,1):-!.\np(X,N,R):-N1 is N-1,p(X,N1,R1),R is X*R1.").
seed_program("%d(5,3,A).\n%A=2.\n%d(1,4,A).\n%A= -3.\nd(A,B,C):-C is A-B.").
seed_program("%inr(5).\n%not(inr(12)).\n%not(inr(0)).\ninr(X):-X>0,X<10.").
seed_program("%half([1,2,3,4],A).\n%A=[2,4].\nhalf([],[]).\nhalf([H|T],R):-(0 is H mod 2->R=[H|R1];R=R1),half(T,R1).").
seed_program("%len2(A,[x,y]).\n%A=2.\nlen2(N,L):-length(L,N).").

bug_kind(op_swap). bug_kind(cmp_swap). bug_kind(const_change). bug_kind(goal_swap).
bug_kind(arg_swap). bug_kind(head_const). bug_kind(add_base_case).

planted_bug(Classes, X, Y) :-
	seed_program(Text),
	program(Text, Prog), Prog = prog(_, _, KeyCls, Tests, _),
	member(Key-Cls, KeyCls), Cls \== [],
	bug_kind(Kind),
	limit(4, plant(Kind, Tests, Cls, Cls1)),
	replace_key(Prog, Key, Cls1, ProgB),
	results(ProgB, Rs),
	once(( member(T-R, Rs), R \== pass, test_key(T, Key) )),
	diagnose(ProgB, T, diag(_, _, _, _, _, X)),
	nth1(Y, Classes, Kind).

plant(add_base_case, _, Cls, Cls1) :- select(F, Cls, Cls1), F \= (_ :- _), Cls1 \== [].
plant(Kind, Tests, Cls, Cls1) :-
	Kind \== add_base_case,
	nth1(I, Cls, Cl, Rest),
	clause_units(Cl, [h(H)|GUs]), maplist([g(G), G]>>true, GUs, Gs),
	mutate(Kind, Tests, H, Gs, 0, H1, Gs1),
	maplist([G, g(G)]>>true, Gs1, GUs1), units_clauses([h(H1)|GUs1], [Cl1]),
	Cl1 \== Cl,
	nth1(I, Cls1, Cl1, Rest).
