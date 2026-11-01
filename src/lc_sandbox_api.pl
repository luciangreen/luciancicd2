% lc_sandbox_api.pl - the file predicates that code under test can call.
%
% They read from the Virtual File System (relative to the directory of the
% repository being tested) and write to a scratch overlay, so tests are fast,
% repeatable and never change the repositories.  The names follow
% luciancicd / listprologinterpreter (read_file_s, open_file_s, ...), and
% the vfs_ prefixed names luciancicd used are accepted too.

:- module(lc_sandbox_api,
	  [ read_file_s/2, open_string_file_s/2, open_file_s/2,
	    read_term_file_s/2, save_file_s/2, exists_file_s/1,
	    exists_directory_s/1, make_directory_s/1,
	    make_directory_recursive_s/2, read_file/2, save_file/2,
	    phrase_from_file_s/2,
	    vfs_read_file_s/2, vfs_open_string_file_s/2, vfs_open_file_s/2,
	    vfs_save_file_s/2, vfs_exists_file_s/1, vfs_exists_directory_s/1,
	    vfs_make_directory_s/1, vfs_make_directory_recursive_s/2,
	    vfs_read_file/2, vfs_save_file/2, vfs_phrase_from_file_s/2,
	    lc_sandbox_cwd/1
	  ]).

:- use_module(lc_vfs).

:- meta_predicate phrase_from_file_s(//, +), vfs_phrase_from_file_s(//, +).

lc_sandbox_cwd(D) :- ( nb_current(lc_sandbox_cwd, D0), D0 \== [] -> D = D0 ; D = "/" ).

path(P0, P) :- lc_sandbox_cwd(D), vfs_join(D, P0, P).

%	read_file_s(+Path, ?String): the whole file as a string.
read_file_s(P0, S) :-
	path(P0, P),
	(   vfs_scratch_read(P, S0) -> S = S0
	;   existence_error(file, P0)
	).
open_string_file_s(P, S) :- read_file_s(P, S).

%	open_file_s(+Path, -Term): the file holds one Prolog term.
open_file_s(P, T) :-
	read_file_s(P, S),
	term_string(T, S).
read_term_file_s(P, T) :- open_file_s(P, T).
read_file(P, T) :- open_file_s(P, T).

save_file_s(P0, C) :-
	path(P0, P),
	(   string(C) -> S = C ; atom(C) -> atom_string(C, S)
	;   format(string(S), "~q", [C])
	),
	vfs_scratch_write(P, S).
save_file(P, T) :- save_file_s(P, T).

exists_file_s(P0) :- path(P0, P), vfs_scratch_exists(P).
exists_directory_s(P0) :- path(P0, P), vfs_dir_exists(P).
make_directory_s(_).
make_directory_recursive_s(_, _).

phrase_from_file_s(G, P) :-
	read_file_s(P, S), string_codes(S, Cs), phrase(G, Cs).

vfs_read_file_s(P, S) :- read_file_s(P, S).
vfs_open_string_file_s(P, S) :- read_file_s(P, S).
vfs_open_file_s(P, T) :- open_file_s(P, T).
vfs_save_file_s(P, C) :- save_file_s(P, C).
vfs_exists_file_s(P) :- exists_file_s(P).
vfs_exists_directory_s(P) :- exists_directory_s(P).
vfs_make_directory_s(P) :- make_directory_s(P).
vfs_make_directory_recursive_s(A, B) :- make_directory_recursive_s(A, B).
vfs_read_file(P, T) :- read_file(P, T).
vfs_save_file(P, T) :- save_file(P, T).
vfs_phrase_from_file_s(G, P) :- phrase_from_file_s(G, P).
