% lc_main.pl - the luciancicd-compatible commands
%
%   set_up_luciancicd.            record the repositories as the last good version
%   luciancicd.                   test changed repositories (settings.pl)
%   luciancicd(Mode).             Mode = i (test only) or d (find working changes)
%   luciancicd(At_start,Max,CICD,Start_files,End_files)   used by the tests
%   move_to_repository_or_back.   copy the result into the repositories, or undo
%   lc_logs(-Logs)                [Time-Status-Text]

:- module(lc_main,
	  [ set_up_luciancicd/0,
	    luciancicd/0,
	    luciancicd/1,
	    luciancicd/5,
	    move_to_repository_or_back/0,
	    lc_logs/1,
	    lc_last_diff/1,
	    lc_home/1,
	    lc_setting/2,
	    files_equivalent/2,
	    gh_init/1
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(lc_vfs).
:- use_module(lc_parse).
:- use_module(lc_engine).
:- use_module(lc_diff).

:- dynamic lc_log/4.          % lc_log(Stamp, Status, Text, DiffHtml)
:- dynamic home/1.

:- prolog_load_context(directory, D), file_directory_name(D, H),
   retractall(home(_)), assertz(home(H)).

lc_home(H) :- home(H).

%	Settings come from settings.pl (loaded into user), as in luciancicd.
lc_setting(Name, Value) :-
	(   setting_goal(Name, G, Value), catch(user:G, _, fail) -> true
	;   default(Name, Value)
	).
setting_goal(user, user(V), V).
setting_goal(repos, repositories_paths1([V]), V).
setting_goal(omit, omit_paths1(V), V).
setting_goal(output, output_path1([V]), V).
setting_goal(max, fail_if_greater_than_n_changes1(V), V).
setting_goal(time_limit, time_limit(V), V).
setting_goal(mode, lc_mode(V), V).
default(user, "luciangreen").
default(repos, "../../GitHub2/").
default(omit, []).
default(output, "../../GitHub2o/").
default(max, 7).
default(time_limit, 1).
default(mode, d).

disk_path(Rel, Abs) :-
	home(H),
	(   is_absolute_file_name(Rel) -> A0 = Rel ; directory_file_path(H, Rel, A0) ),
	absolute_file_name(A0, Abs0), atom_string(Abs0, Abs).

disk_dirs(Repos, Store, Out, Logs, Backup) :-
	lc_setting(repos, R), disk_path(R, Repos),
	lc_setting(output, O), disk_path(O, Out),
	file_directory_name(Repos, Parent),
	directory_file_path(Parent, 'Github_lc2', Store),
	directory_file_path(Parent, 'gh2_tmp_lc2', Backup),
	home(H), directory_file_path(H, '../../lc_logs', L0),
	absolute_file_name(L0, Logs).

v(repos, "/vfs/GitHub2").
v(store, "/vfs/Github_lc").
v(out, "/vfs/GitHub2o").

% ---------------------------------------------------------------- disk mode

set_up_luciancicd :-
	disk_dirs(Repos, Store, _, _, _),
	v(repos, VR), v(store, VS),
	vfs_delete_tree(VR), vfs_load_disk(Repos, VR),
	lc_record(VR, VS),
	delete_dir(Store), vfs_save_disk(VS, Store),
	format("Recorded the repositories in ~w as the last good version.~n", [Repos]).

luciancicd :- lc_setting(mode, M), luciancicd(M).

luciancicd(Mode) :-
	disk_dirs(Repos, Store, Out, Logs, _),
	v(repos, VR), v(store, VS), v(out, VO),
	vfs_delete_tree(VR), vfs_delete_tree(VS),
	vfs_load_disk(Repos, VR),
	vfs_load_disk(Store, VS),
	lc_setting(max, Max), lc_setting(omit, Omit),
	run_and_log([repos(VR), store(VS), out(VO), max(Max), mode(Mode), omit(Omit)], R),
	(   R = passed(_)
	->  delete_dir(Out), vfs_save_disk(VO, Out),
	    delete_dir(Store), vfs_save_disk(VS, Store),
	    format("Result in ~w.  Run move_to_repository_or_back. to copy it into the repositories.~n", [Out])
	;   true
	),
	save_last_log(Logs),
	R = passed(_).

delete_dir(D) :- ( exists_directory(D) -> delete_directory_contents(D) ; make_directory_path(D) ).

move_to_repository_or_back :-
	disk_dirs(Repos, _, Out, _, Backup),
	(   exists_directory(Backup), directory_files(Backup, Fs), Fs \== ['.', '..'], member(F, Fs), F \== '.', F \== '..'
	->  delete_dir(Repos), copy_directory(Backup, Repos), delete_directory_and_contents(Backup),
	    format("Restored the repositories from ~w.~n", [Backup])
	;   make_directory_path(Backup), copy_directory(Repos, Backup),
	    copy_directory(Out, Repos),
	    format("Copied ~w into ~w (backup in ~w; run again to undo).~n", [Out, Repos, Backup])
	), !.

% ---------------------------------------------------------------- logs

run_and_log(Opts, R) :-
	lc_clear_messages,
	memberchk(store(VS), Opts), memberchk(repos(VR), Opts),
	vfs_files_under(VS, Before),
	lc_run(Opts, R),
	lc_messages(Ms),
	atomic_list_concat(Ms, '\n', T), atom_string(T, Text),
	( R = passed(Final) -> Status = 0 ; Status = 1, vfs_files_under(VR, Final) ),
	diff_html(Before, Final, Html),
	get_time(Now), format_time(string(Stamp), "%Y%m%d-%H%M%S", Now),
	assertz(lc_log(Stamp, Status, Text, Html)).

lc_logs(Logs) :- findall(S-St-T, lc_log(S, St, T, _), Logs).
lc_last_diff(H) :- findall(H0, lc_log(_, _, _, H0), Hs), last(Hs, H).

save_last_log(Dir) :-
	(   findall(S-St-T-H, lc_log(S, St, T, H), L), last(L, S-St-T-H)
	->  make_directory_path(Dir),
	    format(atom(LF), "~w/log~w.txt", [Dir, S]),
	    format(atom(DF), "~w/diff~w.html", [Dir, S]),
	    setup_call_cleanup(open(LF, write, O), format(O, "~q", [[St, T]]), close(O)),
	    setup_call_cleanup(open(DF, write, O2), write(O2, H), close(O2))
	;   true
	).

diff_html(Before, After, Html) :-
	findall(Part,
		( member(P-T, After), ( memberchk(P-T0, Before) -> true ; T0 = "" ), T0 \== T,
		  split_string(T0, "\n", "", A), split_string(T, "\n", "", B),
		  diff_ops(A, B, Ops),
		  maplist(op_html, Ops, Ls), atomic_list_concat(Ls, '', Body),
		  format(string(Part), "<h3>~w</h3><pre>~w</pre>", [P, Body]) ),
		Parts),
	atomic_list_concat(Parts, '', H), atom_string(H, Html).

op_html(keep(L), H) :- esc(L, E), format(string(H), "  ~w~n", [E]).
op_html(del(L), H) :- esc(L, E), format(string(H), "<span style=\"color:#b00\">- ~w</span>~n", [E]).
op_html(ins(L), H) :- esc(L, E), format(string(H), "<span style=\"color:#070\">+ ~w</span>~n", [E]).

esc(S, E) :-
	foldl([F-T, A0, A1]>>( atomic_list_concat(Ps, F, A0), atomic_list_concat(Ps, T, A1) ),
	      ['&'-'&amp;', '<'-'&lt;', '>'-'&gt;'], S, E0),
	atom_string(E0, E).

% ---------------------------------------------------------------- test mode

gh_init(_) :- true.

%!	luciancicd(+At_start, +Max, +CICD, +Start_files, +End_files)
%	The test entry point of luciancicd, run entirely in the VFS.
luciancicd(At_start, Max, CICD, Start_files, End_files) :-
	v(repos, VR), v(store, VS), v(out, VO),
	(   At_start == true -> vfs_delete_tree(VR), vfs_delete_tree(VS) ; true ),
	forall(member([F, C], Start_files), ( vfs_join(VR, F, P), vfs_write(P, C) )),
	run_and_log([repos(VR), store(VS), out(VO), max(Max), mode(CICD)], R),
	R = passed(_),
	vfs_files_under(VO, Out),
	maplist([[F, C], F1-C]>>( atom_string(F, F0), ( string_concat("./", F1, F0) -> true ; F1 = F0 ) ),
		End_files, Expected0),
	msort(Expected0, Expected),
	(   files_equivalent(Out, Expected)
	->  true
	;   format("Result: ~q~nCorrect Result: ~q~n", [Out, Expected]), fail
	).

%	Same file names; Prolog files must have the same comments and clauses
%	(as terms), other files the same text apart from trailing white space.
files_equivalent(A, B) :-
	pairs_keys_(A, KA), pairs_keys_(B, KB), msort(KA, S), msort(KB, S),
	forall(member(P-TA, A), ( memberchk(P-TB, B), file_equiv(P, TA, TB) )).

pairs_keys_(Ps, Ks) :- findall(K, member(K-_, Ps), Ks).

file_equiv(_, T, T) :- !.
file_equiv(P, A, B) :-
	(   sub_string(P, _, _, 0, ".pl")
	->  pl_equivalent(A, B)
	;   normalize_space(string(N), A), normalize_space(string(N), B)
	).
