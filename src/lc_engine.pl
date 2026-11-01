% lc_engine.pl - the Lucian CI/CD 2 engine
%
% lc_run(+Options, -Result) integrates and tests a set of repositories held
% in the Virtual File System:
%
%   1. Find repositories whose files differ from the last good version
%      (the store), and the repositories that include their files.
%   2. Group Prolog files into programs (connected by include/consult).
%   3. For each program, go through predicates bottom-up.  For each group
%      of predicates, diff the last good and new versions goal by goal, and
%      try combinations of the changes (all changes first, then fewer) until
%      the tests in comments for those predicates pass.
%   4. Other languages are handled by language packs (lc_packs).
%   5. On success, write the result to the output folder and make it the new
%      last good version.
%
% Options: repos(Dir), store(Dir), out(Dir), max(N), mode(i|d), omit(List)

:- module(lc_engine,
	  [ lc_run/2,
	    lc_record/2,           % +ReposDir, +StoreDir : save without testing
	    lc_message/1,
	    lc_messages/1,
	    lc_clear_messages/0
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(lc_vfs).
:- use_module(lc_parse).
:- use_module(lc_tests).
:- use_module(lc_deps).
:- use_module(lc_diff).
:- use_module(lc_packs).

:- dynamic msg/1.
:- dynamic budget/1.

lc_message(Fmt-Args) :- !, format(string(S), Fmt, Args), lc_message(S).
lc_message(S0) :-
	text_to_string(S0, S),
	assertz(msg(S)),
	(   nb_current(lc_quiet, true) -> true ; format(user_error, "~w~n", [S]) ).
lc_messages(Ms) :- findall(M, msg(M), Ms).
lc_clear_messages :- retractall(msg(_)).

opt(Opts, Term, Default) :- ( memberchk(Term, Opts) -> true ; arg(1, Term, Default) ).

%!	lc_record(+Repos, +Store): make the current repositories the last good version.
lc_record(Repos, Store) :-
	vfs_delete_tree(Store),
	vfs_copy_tree(Repos, Store).

% ---------------------------------------------------------------- main

lc_run(Opts, Result) :-
	opt(Opts, repos(Repos), "/vfs/GitHub2"),
	opt(Opts, store(Store), "/vfs/Github_lc"),
	opt(Opts, out(Out), "/vfs/GitHub2o"),
	opt(Opts, max(Max), 7),
	opt(Opts, mode(Mode), d),
	opt(Opts, omit(Omit), []),
	retractall(budget(_)), assertz(budget(20000)),
	repo_files(Repos, Omit, NewFiles),
	repo_files(Store, Omit, OldFiles),
	changed_repos(NewFiles, OldFiles, Changed),
	(   Changed == []
	->  lc_message("No changes to test."),
	    Final = NewFiles, Status = passed
	;   lc_message("Changed repositories: ~w"-[Changed]),
	    include_graph(NewFiles, Incl),
	    dependents(Changed, Incl, Scope),
	    lc_message("Repositories to build and test: ~w"-[Scope]),
	    C = ctx(Repos, Max, Mode, NewFiles, OldFiles, Incl),
	    (   catch(build_scope(C, Scope, Decided), E,
		      ( lc_message("Error: ~q"-[E]), fail ))
	    ->  findall(P-T, ( member(P-T0, NewFiles),
			       ( memberchk(P-T1, Decided) -> T = T1 ; T = T0 ) ), Final),
		Status = passed
	    ;   Final = NewFiles, Status = failed
	    )
	),
	(   Status == passed
	->  vfs_delete_tree(Out),
	    forall(member(P-T, Final), ( vfs_join(Out, P, OP), vfs_write(OP, T) )),
	    vfs_delete_tree(Store),
	    forall(member(P-T, Final), ( vfs_join(Store, P, SP), vfs_write(SP, T) )),
	    lc_message("All tests passed."),
	    Result = passed(Final)
	;   lc_message("1 or more tests failed."),
	    Result = failed
	).

repo_files(Root, Omit, Files) :-
	vfs_files_under(Root, Fs),
	exclude([P-_]>>( split_string(P, "/", "", [R|_]), memberchk(R, Omit) ), Fs, Files).

repo_of(Path, Repo) :- split_string(Path, "/", "", [Repo|_]).

changed_repos(New, Old, Changed) :-
	findall(R, ( member(P-T, New), \+ memberchk(P-T, Old), repo_of(P, R) ), R1),
	findall(R, ( member(P-_, Old), \+ memberchk(P-_, New), repo_of(P, R) ), R2),
	append(R1, R2, R3), sort(R3, Changed).

%	include_graph(+Files, -Edges): File-[IncludedFile] for Prolog files.
include_graph(Files, Edges) :-
	findall(P-Is,
		( member(P-T, Files), pack_of(P, prolog),
		  ( pl_parse_safe(T, pl_file(Items, _)) -> true ; Items = [] ),
		  findall(I, ( member(item(directive(D),_,_), Items),
			       directive_includes(D, Rels), member(Rel, Rels),
			       resolve_include(P, Rel, I) ), Is0),
		  sort(Is0, Is) ),
		Edges).

resolve_include(From, Rel0, Path) :-
	vfs_dirname(From, Dir0),
	( Dir0 == "." -> Dir = "" ; Dir = Dir0 ),
	(   sub_string(Rel0, _, _, 0, ".pl") -> Rel = Rel0 ; string_concat(Rel0, ".pl", Rel) ),
	atomic_list_concat([Dir, '/', Rel], P0),
	vfs_norm(P0, P1),
	( sub_string(P1, 0, 1, _, "/") -> sub_string(P1, 1, _, 0, Path) ; Path = P1 ).

%	Repositories in scope: changed ones and those that include their files.
dependents(Changed, Incl, Scope) :-
	findall(RA-RB, ( member(F-Is, Incl), member(I, Is), repo_of(F, RA), repo_of(I, RB), RA \== RB ), Deps),
	close_deps(Changed, Deps, Scope0),
	sort(Scope0, Scope).
close_deps(S, Deps, R) :-
	findall(A, ( member(A-B, Deps), memberchk(B, S), \+ memberchk(A, S) ), New0),
	sort(New0, New),
	(   New == [] -> R = S ; append(S, New, S1), close_deps(S1, Deps, R) ).

% ---------------------------------------------------------------- build

build_scope(C, Scope, Decided) :-
	C = ctx(_, _, _, NewFiles, _, Incl),
	include([P-_]>>( repo_of(P, R), memberchk(R, Scope) ), NewFiles, InScope),
	% Prolog programs
	include([P-_]>>pack_of(P, prolog), InScope, PlFiles),
	pairs_keys(PlFiles, PlPaths),
	components(PlPaths, Incl, Comps),
	foldl(build_component(C), Comps, [], DecidedPl),
	% other languages
	exclude([P-_]>>pack_of(P, prolog), InScope, Others),
	foldl(build_other(C), Others, [], DecidedOther),
	append(DecidedPl, DecidedOther, Decided).

%	Connected components of the include graph (both directions), closed
%	over included files.
components(Paths, Incl, Comps) :-
	findall(A-B, ( member(A-Bs, Incl), member(B, Bs) ), Es),
	comps(Paths, Es, [], Comps).
comps([], _, _, []).
comps([P|Ps], Es, Done, Cs) :-
	(   memberchk(P, Done) -> comps(Ps, Es, Done, Cs)
	;   grow([P], Es, Comp0), sort(Comp0, Comp),
	    append(Comp, Done, Done1),
	    Cs = [Comp|Cs1],
	    comps(Ps, Es, Done1, Cs1)
	).
grow(S, Es, R) :-
	findall(X, ( member(Y, S), ( member(Y-X, Es) ; member(X-Y, Es) ), \+ memberchk(X, S) ), N0),
	sort(N0, N),
	(   N == [] -> R = S ; append(S, N, S1), grow(S1, Es, R) ).

%	file_model(+Files, +Path, -pl_file)
file_model(Files, P, PF) :-
	(   memberchk(P-T, Files)
	->  (   pl_parse_safe(T, PF0) -> PF = PF0
	    ;   lc_message("Syntax error in ~w."-[P]), throw(syntax_error(P))
	    )
	;   PF = pl_file([], "")
	).

file_units(pl_file(Items, _), P, KeyUnits) :-
	findall(K, member(item(clause(K,_),_,_), Items), Ks0),
	list_to_set(Ks0, Ks),
	findall((P:K)-Us,
		( member(K, Ks),
		  findall(U, ( member(item(clause(K,G),_,_), Items), clause_units(G, U0), member(U, U0) ), Us) ),
		KeyUnits).

build_component(C, Comp, Acc, Acc1) :-
	C = ctx(Repos, Max, Mode, NewFiles, OldFiles, _),
	lc_message("Building ~w"-[Comp]),
	maplist([P, P-PF]>>file_model(NewFiles, P, PF), Comp, NewPFs),
	maplist([P, P-PF]>>(catch(file_model(OldFiles, P, PF), _, PF = pl_file([], ""))), Comp, OldPFs),
	findall(KU, ( member(P-PF, NewPFs), file_units(PF, P, KUs), member(KU, KUs) ), NewKU),
	findall(KU, ( member(P-PF, OldPFs), file_units(PF, P, KUs), member(KU, KUs) ), OldKU),
	pairs_keys(NewKU, NK), pairs_keys(OldKU, OK),
	append(NK, OK, AK0), list_to_set(AK0, Keys),
	findall(NA, member(_:NA, Keys), NAs0), sort(NAs0, NAs),
	% call graph over both versions
	findall(K-Cs,
		( member(K, Keys), K = _:_,
		  findall(C1, ( ( memberchk(K-Us, NewKU) ; memberchk(K-Us, OldKU) ),
				units_clauses(Us, Cls), member(Cl, Cls),
				clause_calls(Cl, Calls), member(CNA, Calls),
				member(C1, Keys), C1 = _:CNA ), Cs0),
		  sort(Cs0, Cs) ),
		Edges),
	main_roots(NewFiles, Comp, Keys, Roots),
	bottom_up_groups(Roots, Edges, Groups),
	% tests and directives come from the new version
	findall(P-T, ( member(P-pl_file(Items,_), NewPFs),
		       comment_tests(Items, NAs, Ts), member(T, Ts) ), Tests),
	findall(D, ( member(_-pl_file(Items,_), NewPFs), member(item(directive(D),_,_), Items),
		     \+ directive_includes(D, [_|_]) ), Dirs),
	length(Tests, NT),
	lc_message("~w predicates in ~w groups, ~w tests."-[Keys, Groups, NT]),
	Model = model(Repos, Keys, NewKU, OldKU, Tests, Dirs),
	(   decide_groups(Groups, Model, Max, Mode, [], Chosen)
	->  true
	;   lc_message("Could not find a combination of changes that passes the tests in ~w."-[Comp]),
	    fail
	),
	!,
	findall(P-Text, ( member(P-NPF, NewPFs), memberchk(P-T0, NewFiles), T0 \== "",
			  memberchk(P-OPF, OldPFs),
			  rebuild(P, NPF, OPF, Chosen, Text) ), Texts),
	append(Acc, Texts, Acc1).

main_roots(Files, Comp, Keys, Roots) :-
	findall(Key,
		( member(P, Comp), repo_of(P, R),
		  atomic_list_concat([R, '/main_file.txt'], MF0), atom_string(MF0, MF),
		  memberchk(MF-T, Files),
		  catch(term_string(Spec, T), _, fail), is_list(Spec),
		  member([F, Preds], Spec), atomic_list_concat([R, '/', F], P0), atom_string(P0, P),
		  member([N, A], Preds), atom_string(NA0, N), Key = P:(NA0/A),
		  memberchk(Key, Keys) ),
		Roots).

% ---------------------------------------------------------------- search

decide_groups([], _, _, _, Chosen, Chosen).
decide_groups([G|Gs], Model, Max, Mode, Ch0, Ch) :-
	Model = model(_, _, NewKU, OldKU, Tests, _),
	group_changes(G, NewKU, OldKU, Labelled, N),
	group_tests(G, Tests, GT),
	(   N =< Max -> L = Labelled, NC = N, Max1 = Max
	;   foldl(key_hunks, Labelled, L, 0, NC), Max1 = Max
	),
	length(GT, NGT),
	lc_message("Group ~w: ~w changes, ~w tests."-[G, NC, NGT]),
	member(Phase, [simple, both]),
	candidate_omit(NC, Max1, Mode, Omit),
	foldl([K-KL, K-Us, B0, B1]>>( apply_omit(KL, Omit, Us, B), B1 is B0+B ), L, Cand, 0, Both),
	( Phase == simple -> Both =:= 0 ; Both > 0 ),
	spend,
	maplist([K-Us, K-Cls]>>units_clauses(Us, Cls), Cand, CandCls),
	append(CandCls, Ch0, Ch1),
	(   GT == []
	->  program_loads(Model, Ch1)
	;   tests_pass(Model, Ch1, GT)
	),
	( Omit == [] -> true ; lc_message("  kept old version of ~w change(s) ~w."-[G, Omit]) ),
	decide_groups(Gs, Model, Max, Mode, Ch1, Ch).

key_hunks(K-KL, K-HL, N0, N) :-
	hunk_labels(KL, HL0, NH),
	maplist([c(I,Op), c(I1,Op)]>>( I == none -> I1 = none ; I1 is I+N0 ), HL0, HL),
	N is N0+NH.

spend :-
	retract(budget(B)), B1 is B-1, assertz(budget(B1)),
	(   B1 < 0 -> lc_message("Search budget exhausted."), !, fail ; true ).

group_changes(G, NewKU, OldKU, Labelled, N) :-
	foldl(key_changes(NewKU, OldKU), G, Labelled, 0, N).
key_changes(NewKU, OldKU, K, K-KL, N0, N) :-
	( memberchk(K-NU, NewKU) -> true ; NU = [] ),
	( memberchk(K-OU, OldKU) -> true ; OU = [] ),
	diff_ops(OU, NU, Ops),
	label_changes(Ops, [_]>>fail, KL0, NK),
	maplist([c(I,Op), c(I1,Op)]>>( I == none -> I1 = none ; I1 is I+N0 ), KL0, KL),
	N is N0+NK.

group_tests(G, Tests, GT) :-
	findall(P-T, ( member(P-T, Tests), test_key(T, NA), memberchk(_:NA, G) ), GT).

%	The program: decided/candidate clauses, and the new version of the rest.
program(model(_, Keys, NewKU, _, _, _), Chosen, Clauses) :-
	findall(Cl, ( member(K, Keys),
		      (   memberchk(K-Cls, Chosen) -> true
		      ;   memberchk(K-Us, NewKU) -> units_clauses(Us, Cls)
		      ;   Cls = []
		      ),
		      member(Cl, Cls) ), Clauses).

program_loads(Model, Chosen) :-
	program(Model, Chosen, Clauses),
	Model = model(Repos, _, _, _, _, Dirs),
	with_program(Clauses, Dirs, Repos, [_]>>true).

tests_pass(Model, Chosen, GT) :-
	program(Model, Chosen, Clauses),
	Model = model(Repos, _, _, _, _, Dirs),
	findall(Dir, ( member(P-_, GT), test_cwd(Repos, P, Dir) ), Dirs0), sort(Dirs0, Cwds),
	forall(member(Cwd, Cwds),
	       ( findall(T, ( member(P-T, GT), test_cwd(Repos, P, Cwd) ), Ts),
		 with_program(Clauses, Dirs, Cwd, all_pass(Ts)) )).

test_cwd(Repos, P, Dir) :- vfs_join(Repos, P, Full), vfs_dirname(Full, Dir).

all_pass(Ts, M) :- forall(member(T, Ts), test_passes(M, T)).

test_passes(M, T) :-
	run_test(M, T, R),
	(   R == pass -> true
	;   (   nb_current(lc_verbose, true)
	    ->  test_text(T, TT), lc_message("  test ~w: ~q"-[TT, R])
	    ;   true
	    ),
	    fail
	).

% ---------------------------------------------------------------- output

%	rebuild(+Path, +NewPF, +OldPF, +Chosen, -Text)
%	Lay the chosen clauses out like the new file: each predicate where it
%	first appears, comments and directives as they are, and the original
%	text of every clause that is unchanged.
rebuild(P, NPF, OPF, Chosen, Text) :-
	NPF = pl_file(Items, Tail),
	OPF = pl_file(OItems, _),
	findall(G-T, ( member(item(clause(_,G),_,T), Items) ; member(item(clause(_,G),_,T), OItems) ), TextMap),
	emit_items(Items, P, Chosen, TextMap, [], Parts, Done),
	findall(Extra, ( member((P:K)-Cls, Chosen), \+ memberchk(K, Done), Cls \== [],
			 clauses_text(Cls, TextMap, "\n", Extra0), string_concat("\n", Extra0, Extra) ), Extras),
	atomic_list_concat(Parts, '', T1),
	atomic_list_concat(Extras, '', T2),
	atomic_list_concat([T1, T2, Tail], T3),
	atom_string(T3, Text).

%	Each clause of the new file is a slot.  The chosen clauses are aligned
%	with the new clauses, so unchanged clauses stay where they were and
%	added ones go next to their neighbours.
emit_items(Items, P, Chosen, Map, Done0, Parts, Done) :-
	findall(K, ( member(item(clause(K,_),_,_), Items) ), Ks0), list_to_set(Ks0, Ks),
	findall(K-Slots, ( member(K, Ks),
			   findall(G, member(item(clause(K,G),_,_), Items), NewCls),
			   ( memberchk((P:K)-Cls, Chosen) -> true ; Cls = [] ),
			   diff_ops(NewCls, Cls, Ops),
			   slots(Ops, Slots) ), SlotMap),
	emit_slots(Items, SlotMap, Map, [], Parts),
	append(Done0, Ks, Done).

%	slots(+Ops, -Slots): one list of clauses per new clause.
slots(Ops, Slots) :- slots(Ops, [], Slots0), fix_trailing(Slots0, Slots).
slots([], Pending, [trailing(Pending)]).
slots([ins(C)|Ops], Pend, S) :- !, append(Pend, [C], Pend1), slots(Ops, Pend1, S).
slots([keep(C)|Ops], Pend, [S1|S]) :- !, append(Pend, [C], S1), slots(Ops, [], S).
slots([del(_)|Ops], Pend, [Pend|S]) :- slots(Ops, [], S).

fix_trailing(Slots0, Slots) :-
	append(Front, [trailing(T)], Slots0),
	(   T == [] -> Slots = Front
	;   Front == [] -> Slots = [T]
	;   append(F1, [Last], Front), append(Last, T, Last1), append(F1, [Last1], Slots)
	).

emit_slots([], _, _, _, []).
emit_slots([item(Kind, Sep, T)|Is], SlotMap, Map, Seen, Parts) :-
	(   Kind = clause(K, _)
	->  aggregate_all(count, member(K, Seen), I),
	    memberchk(K-Slots, SlotMap),
	    (   nth0(I, Slots, Cls), Cls \== []
	    ->  clauses_text(Cls, Map, "\n", CT), Parts = [Sep, CT|Parts1]
	    ;   Parts = Parts1
	    ),
	    emit_slots(Is, SlotMap, Map, [K|Seen], Parts1)
	;   Parts = [Sep, T|Parts1],
	    emit_slots(Is, SlotMap, Map, Seen, Parts1)
	).

clauses_text(Cls, Map, SepS, Text) :-
	maplist([G, T]>>( memberchk(G-T0, Map) -> T = T0 ; clause_text(G, T) ), Cls, Ts),
	atomic_list_concat(Ts, SepS, A), atom_string(A, Text).

% ---------------------------------------------------------------- other languages

build_other(C, P-New, Acc, Acc1) :-
	C = ctx(Repos, Max, Mode, _, OldFiles, _),
	(   memberchk(P-Old, OldFiles) -> true ; Old = "" ),
	(   pack_of(P, Pack), Pack \== prolog, Pack \== data
	->  vfs_join(Repos, P, Full), vfs_dirname(Full, Cwd),
	    (   pack_ci(Pack, P, Old, New, Max, Mode, Cwd, Text)
	    ->  append(Acc, [P-Text], Acc1)
	    ;   lc_message("~w (~w): no combination of changes passes the tests."-[P, Pack]),
		fail
	    )
	;   append(Acc, [P-New], Acc1)
	).
