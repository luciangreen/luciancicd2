% lc_vfs.pl - In-memory Virtual File System for Lucian CI/CD 2
%
% Every file Lucian CI/CD 2 works on lives here as vfs_file(Path,Contents),
% where Path is a normalised absolute string ("/vfs/GitHub2/c/c.pl") and
% Contents is a string.  Disk is only touched by vfs_load_disk/2 and
% vfs_save_disk/2, so testing never pauses on slow disks and never leaves
% junk behind.
%
% Code under test sees a small file API (read_file_s/2, save_file_s/2,
% open_file_s/2 ...) through lc_sandbox_api.  Writes made by code under test
% go to a scratch overlay that is thrown away after each test run.

:- module(lc_vfs,
	  [ vfs_reset/0,
	    vfs_reset/1,          % +RootPrefix
	    vfs_write/2,          % +Path, +Contents
	    vfs_read/2,           % +Path, -Contents
	    vfs_exists/1,         % +Path
	    vfs_dir_exists/1,     % +Dir
	    vfs_delete/1,         % +Path
	    vfs_delete_tree/1,    % +Dir
	    vfs_files_under/2,    % +Dir, -[Rel-Contents]
	    vfs_copy_tree/2,      % +FromDir, +ToDir
	    vfs_norm/2,           % +Path, -Norm
	    vfs_join/3,           % +Dir, +Rel, -Path
	    vfs_dirname/2,        % +Path, -Dir
	    vfs_basename/2,       % +Path, -Base
	    vfs_extension/2,      % +Path, -Ext
	    vfs_load_disk/2,      % +DiskDir, +VDir
	    vfs_save_disk/2,      % +VDir, +DiskDir
	    vfs_scratch_clear/0,
	    vfs_scratch_write/2,
	    vfs_scratch_read/2,
	    vfs_scratch_exists/1
	  ]).

:- dynamic vfs_file/2.
:- dynamic vfs_scratch/2.

vfs_reset :- retractall(vfs_file(_,_)), retractall(vfs_scratch(_,_)).

vfs_reset(Prefix0) :-
	vfs_norm(Prefix0, Prefix),
	forall(( vfs_file(P,_), under(Prefix, P) ), retractall(vfs_file(P,_))).

%!	vfs_norm(+Path, -Norm) is det.
%	Normalise "a/./b/../c" to "a/c"; keeps a leading "/".
vfs_norm(Path0, Norm) :-
	text_to_string(Path0, Path),
	split_string(Path, "/", "", Parts0),
	(   Parts0 = [""|_] -> Abs = true ; Abs = false ),
	exclude(==(""), Parts0, Parts1),
	norm_parts(Parts1, [], RevParts),
	reverse(RevParts, Parts),
	atomic_list_concat(Parts, '/', A),
	atom_string(A, S),
	(   Abs == true -> string_concat("/", S, Norm) ; Norm = S ).

norm_parts([], Acc, Acc).
norm_parts(["."|T], Acc, R) :- !, norm_parts(T, Acc, R).
norm_parts([".."|T], [P|Acc], R) :- P \== "..", !, norm_parts(T, Acc, R).
norm_parts([X|T], Acc, R) :- norm_parts(T, [X|Acc], R).

vfs_join(Dir, Rel0, Path) :-
	text_to_string(Rel0, Rel),
	(   sub_string(Rel, 0, 1, _, "/")
	->  vfs_norm(Rel, Path)
	;   text_to_string(Dir, D),
	    atomic_list_concat([D, '/', Rel], P0),
	    vfs_norm(P0, Path)
	).

vfs_dirname(Path, Dir) :-
	vfs_norm(Path, P),
	(   sub_string(P, B, 1, A, "/"), A >= 0,
	    \+ ( sub_string(P, B2, 1, _, "/"), B2 > B )
	->  sub_string(P, 0, B, _, Dir0),
	    ( Dir0 == "" -> Dir = "/" ; Dir = Dir0 )
	;   Dir = "."
	).

vfs_basename(Path, Base) :-
	text_to_string(Path, P),
	split_string(P, "/", "", Parts),
	last(Parts, Base).

vfs_extension(Path, Ext) :-
	vfs_basename(Path, Base),
	(   sub_string(Base, B, 1, _, "."),
	    \+ ( sub_string(Base, B2, 1, _, "."), B2 > B ),
	    B > 0
	->  B1 is B+1, sub_string(Base, B1, _, 0, Ext0), string_lower(Ext0, Ext)
	;   Ext = ""
	).

vfs_write(Path0, Contents0) :-
	vfs_norm(Path0, Path),
	text_to_string(Contents0, Contents),
	retractall(vfs_file(Path,_)),
	assertz(vfs_file(Path, Contents)).

vfs_read(Path0, Contents) :-
	vfs_norm(Path0, Path),
	vfs_file(Path, Contents), !.

vfs_exists(Path0) :- vfs_norm(Path0, Path), vfs_file(Path, _), !.

vfs_dir_exists(Dir0) :-
	vfs_norm(Dir0, Dir),
	vfs_file(P, _), under(Dir, P), !.

vfs_delete(Path0) :- vfs_norm(Path0, Path), retractall(vfs_file(Path,_)).

vfs_delete_tree(Dir) :- vfs_reset(Dir).

%	under(+Dir, +Path): Path is strictly below Dir.
under(Dir, Path) :-
	(   sub_string(Dir, _, 1, 0, "/") -> D = Dir ; string_concat(Dir, "/", D) ),
	string_concat(D, _, Path).

vfs_files_under(Dir0, Files) :-
	vfs_norm(Dir0, Dir),
	(   sub_string(Dir, _, 1, 0, "/") -> D = Dir ; string_concat(Dir, "/", D) ),
	findall(Rel-C, ( vfs_file(P, C), string_concat(D, Rel, P) ), Files0),
	msort(Files0, Files).

vfs_copy_tree(From, To) :-
	vfs_files_under(From, Fs),
	forall(member(Rel-C, Fs), ( vfs_join(To, Rel, P), vfs_write(P, C) )).

% ---------------------------------------------------------------- disk

vfs_load_disk(DiskDir, VDir) :-
	(   exists_directory(DiskDir)
	->  load_dir(DiskDir, VDir)
	;   true
	).

load_dir(DiskDir, VDir) :-
	directory_files(DiskDir, Es),
	forall(( member(E, Es), \+ sub_atom(E, 0, 1, _, '.') ),
	       (   directory_file_path(DiskDir, E, DP),
		   vfs_join(VDir, E, VP),
		   (   exists_directory(DP)
		   ->  load_dir(DP, VP)
		   ;   catch(read_file_to_string(DP, S, [encoding(utf8)]), _, fail)
		   ->  vfs_write(VP, S)
		   ;   true
		   )
	       )).

vfs_save_disk(VDir, DiskDir) :-
	vfs_files_under(VDir, Fs),
	forall(member(Rel-C, Fs),
	       (   directory_file_path(DiskDir, Rel, DP),
		   file_directory_name(DP, DD),
		   make_directory_path(DD),
		   setup_call_cleanup(open(DP, write, S, [encoding(utf8)]),
				      write(S, C), close(S))
	       )).

% ---------------------------------------------------------------- scratch overlay

vfs_scratch_clear :- retractall(vfs_scratch(_,_)).
vfs_scratch_write(P0, C0) :-
	vfs_norm(P0, P), text_to_string(C0, C),
	retractall(vfs_scratch(P,_)), assertz(vfs_scratch(P, C)).
vfs_scratch_read(P0, C) :-
	vfs_norm(P0, P),
	(   vfs_scratch(P, C) -> true ; vfs_file(P, C) ), !.
vfs_scratch_exists(P0) :-
	vfs_norm(P0, P), ( vfs_scratch(P,_) -> true ; vfs_file(P,_) ), !.
