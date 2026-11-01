% lc_packs.pl - language packs
%
% A pack tells Lucian CI/CD 2 how to handle files of one language:
%
%   lc_packs:pack_def(Name, Options)        Options: extensions(Exts),
%                                           language(LangDescName)
%   lc_packs:pack_run(Name, Tests, Text, Ctx, Results)
%                                           run tests on a candidate file
%
% Prolog is built in (lc_engine).  C, JavaScript, HTML and Markdown are in
% src/packs/.  Add a pack by dropping a file defining these two multifile
% predicates into packs/ (loaded at start-up).  A file whose extension no
% pack claims, but whose text a learnt language description proves (see
% lc_grammar), gets a generic pack with "valid" and "contains" tests.
%
% Tests live in comments, one per line, after the marker "test:", e.g.
%   // test: 2 3 => 5              (C: command-line args => stdout)
%   // test: add(2,3) => 5         (JavaScript: expression => value)
%   <!-- test: contains <h1>Hi</h1> -->
%
% The engine is the same as for Prolog: the file's lines are diffed with the
% last good version, comment lines always come from the new version, and
% combinations of the other changes are tried (all changes first, then
% fewer) until the tests pass.

:- module(lc_packs,
	  [ pack_of/2,          % +Path, -Pack
	    pack_ci/8,          % +Pack, +Path, +Old, +New, +Max, +Mode, +Cwd, -Text
	    pack_tests/3,       % +Pack, +Text, -Tests
	    pack_test_file/4,   % +Pack, +Text, +Cwd, -Results
	    pack_valid/3,       % +Pack, +Text, -Proof
	    packs/1,            % -[Name-Exts]
	    load_packs/1        % +Dir
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lc_vfs).
:- use_module(lc_diff).
:- use_module(lc_grammar).

:- multifile pack_def/2, pack_run/5.
:- dynamic pack_def/2, pack_run/5.

pack_def(prolog, [extensions(["pl", "pro", "lp"]), language(prolog)]).

packs(Ps) :- findall(N-Es, ( pack_def(N, O), memberchk(extensions(Es), O) ), Ps).

load_packs(Dir) :-
	(   exists_directory(Dir)
	->  directory_files(Dir, Fs),
	    forall(( member(F, Fs), file_name_extension(_, pl, F) ),
		   ( directory_file_path(Dir, F, P), load_files(P, [if(not_loaded)]) ))
	;   true
	).

%!	pack_of(+Path, -Pack)
pack_of(Path, Pack) :-
	vfs_extension(Path, Ext),
	(   pack_def(Pack0, O), memberchk(extensions(Es), O), memberchk(Ext, Es)
	->  Pack = Pack0
	;   Ext \== "", Ext \== "txt", language_for_extension(Ext, L)
	->  Pack = learned(L)
	;   Pack = data
	).

pack_language(learned(L), D) :- !, language(L, D).
pack_language(P, D) :-
	pack_def(P, O), memberchk(language(L), O), language(L, D), !.
pack_language(_, []).

% ---------------------------------------------------------------- comments and tests

comment_line(D, Line) :-
	normalize_space(string(T), Line), T \== "",
	(   memberchk(line_comment(LC), D), member(M, LC), string_concat(M, _, T)
	;   memberchk(block_comment(BC), D), member([O, C], BC),
	    string_concat(O, _, T), string_concat(_, C, T)
	), !.

%!	pack_tests(+Pack, +Text, -Tests)
pack_tests(Pack, Text, Tests) :-
	pack_language(Pack, D),
	( memberchk(test_marker(TM), D) -> true ; TM = "test:" ),
	split_string(Text, "\n", "", Lines),
	findall(T, ( member(L, Lines), comment_line(D, L), test_spec(D, TM, L, T) ), Tests).

test_spec(D, TM, L, Spec) :-
	sub_string(L, B, _, _, TM), !,
	string_length(TM, TL), S is B+TL,
	sub_string(L, S, _, 0, R0),
	(   memberchk(block_comment(BC), D), member([_, C], BC), string_concat(R1, C, R0) -> true ; R1 = R0 ),
	normalize_space(string(Spec), R1),
	Spec \== "".

% ---------------------------------------------------------------- CI for a file

pack_ci(Pack, Path, Old, New, Max, Mode, Cwd, Text) :-
	pack_language(Pack, D),
	split_string(Old, "\n", "", OL0), ( Old == "" -> OL = [] ; OL = OL0 ),
	split_string(New, "\n", "", NL),
	diff_ops(OL, NL, Ops),
	label_changes(Ops, comment_line(D), L0, N0),
	(   N0 =< Max -> L = L0, N = N0 ; hunk_labels(L0, L, N) ),
	pack_tests(Pack, New, Tests),
	Ctx = ctx(Path, Cwd),
	member(Phase, [simple, both]),
	candidate_omit(N, Max, Mode, Omit),
	apply_omit(L, Omit, Lines, Both),
	( Phase == simple -> Both =:= 0 ; Both > 0 ),
	atomic_list_concat(Lines, '\n', A), atom_string(A, Text),
	(   Tests == []
	->  pack_valid(Pack, Text, _)
	;   pack_valid(Pack, Text, _),
	    run_pack_tests(Pack, Tests, Text, Ctx, Rs),
	    forall(member(_-R, Rs), R == pass)
	),
	!.

pack_test_file(Pack, Text, Cwd, Results) :-
	pack_tests(Pack, Text, Tests),
	run_pack_tests(Pack, Tests, Text, ctx("", Cwd), Results).

run_pack_tests(Pack, Tests, Text, Ctx, Results) :-
	(   catch(pack_run(Pack, Tests, Text, Ctx, Results0), E,
		  ( print_message(warning, E), fail ))
	->  Results = Results0
	;   generic_run(Pack, Tests, Text, Results)
	).

%	"valid" and "contains X" work for every language.
generic_run(Pack, Tests, Text, Results) :-
	maplist([T, T-R]>>generic_test(Pack, T, Text, R), Tests, Results).

generic_test(Pack, "valid", Text, R) :- !,
	( pack_valid(Pack, Text, _) -> R = pass ; R = fail(no_proof) ).
generic_test(_, T, Text, R) :-
	string_concat("contains ", X, T), !,
	( sub_string(Text, _, _, _, X) -> R = pass ; R = fail(missing(X)) ).
generic_test(_, T, _, fail(unknown_test(T))).

%!	pack_valid(+Pack, +Text, -Proof)
%	A file is valid if its language description proves it.
pack_valid(Pack, Text, Proof) :-
	pack_language(Pack, D),
	(   D == [] -> Proof = none ; prove_text(D, Text, Proof) ).
