% lc_diff.pl - differences between versions and combinations of changes
%
% diff_ops/3 is a longest-common-subsequence diff over any list of ground
% terms (clause units for Prolog, lines for other languages).  Deletions
% come before insertions inside a replaced region.
%
% A candidate is the new version with a set of changes omitted (undone).
% Candidates are generated in order of preference: all changes first, then
% omitting 1 change, then 2, ...  That order makes luciancicd's test 9
% ("A=2,B=2" + "A=1,B=1" with test C=3) choose "A=1,B=2".

:- module(lc_diff,
	  [ diff_ops/3,          % +Old, +New, -Ops
	    label_changes/4,     % +Ops, +Pinned, -Labelled, -NChanges
	    hunk_labels/3,       % +Labelled, -HunkLabelled, -NHunks
	    candidate_omit/4,    % +N, +Max, +Mode, -OmitSet   (nondet)
	    apply_omit/3,        % +Labelled, +OmitSet, -Units
	    ops_counts/3         % +Ops, -Ins, -Del
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).

%!	diff_ops(+Old, +New, -Ops) is det.
%	Ops: keep(X), del(X), ins(X).
diff_ops(Old, New, Ops) :-
	length(Old, N), length(New, M),
	OA =.. [o|Old], NA =.. [n|New],
	M1 is M+1,
	length(Zs, M1), maplist(=(0), Zs),
	ZRow =.. [r|Zs],
	build_rows(N, M, OA, NA, ZRow, [ZRow], Rows),   % Rows = [Row0, Row1, ..., RowN]
	RowsT =.. [t|Rows],
	walk(0, 0, N, M, OA, NA, RowsT, Ops).

build_rows(0, _, _, _, _, Rows, Rows) :- !.
build_rows(I, M, OA, NA, Next, Acc, Rows) :-
	I0 is I-1,                     % computing row for suffix starting at I0 (0-based)
	arg(I, OA, X),
	row(M, M, X, NA, Next, [], RowL),
	Row =.. [r|RowL],
	build_rows(I0, M, OA, NA, Row, [Row|Acc], Rows).

% row(J, M, X, NA, Next, Acc, Row): L(i,j) for j = J down to 0, where
% Next holds L(i+1,_) and Acc starts with L(i,J+1).
row(J, M, X, NA, Next, Acc, Row) :-
	(   J =:= M
	->  V = 0
	;   J1 is J+1, arg(J1, NA, Y), X == Y
	->  J2 is J+2, arg(J2, Next, D), V is D+1
	;   J1 is J+1, arg(J1, Next, Down), Acc = [Right|_], V is max(Down, Right)
	),
	Acc1 = [V|Acc],
	(   J =:= 0 -> Row = Acc1 ; J0 is J-1, row(J0, M, X, NA, Next, Acc1, Row) ).

lcs(RowsT, I, J, V) :- I1 is I+1, arg(I1, RowsT, Row), J1 is J+1, arg(J1, Row, V).

walk(I, J, N, M, _, _, _, []) :- I >= N, J >= M, !.
walk(I, J, N, M, OA, NA, R, [Op|Ops]) :-
	(   I < N, J < M, I1 is I+1, J1 is J+1, arg(I1, OA, X), arg(J1, NA, Y), X == Y
	->  Op = keep(X), I2 = I1, J2 = J1
	;   I < N, ( J >= M -> true
		   ; I1 is I+1, J1 is J+1, lcs(R, I1, J, Down), lcs(R, I, J1, Right), Down >= Right )
	->  I1 is I+1, arg(I1, OA, X), Op = del(X), I2 = I1, J2 = J
	;   J1 is J+1, arg(J1, NA, Y), Op = ins(Y), I2 = I, J2 = J1
	),
	walk(I2, J2, N, M, OA, NA, R, Ops).

ops_counts(Ops, I, D) :-
	aggregate_all(count, member(ins(_), Ops), I),
	aggregate_all(count, member(del(_), Ops), D).

%!	label_changes(+Ops, :Pinned, -Labelled, -N)
%	Number each del/ins op.  Ops on pinned units (e.g. comments, which always
%	come from the new version) are applied without being counted.
:- meta_predicate label_changes(+, 1, -, -).
label_changes(Ops, Pinned, Labelled, N) :-
	foldl(label(Pinned), Ops, Labelled, 0, N).

label(_, keep(X), c(none, keep(X)), N, N) :- !.
label(P, Op, c(none, Op), N, N) :- arg(1, Op, X), call(P, X), !.
label(_, Op, c(N1, Op), N, N1) :- N1 is N+1.

%!	hunk_labels(+Labelled, -HunkLabelled, -NHunks)
%	Coarser changes: consecutive changes become one hunk.
hunk_labels(L, H, N) :- hunks(L, none, 0, H, N).
hunks([], _, N, [], N).
hunks([c(none, Op)|T], _, N0, [c(none, Op)|H], N) :- !, hunks(T, none, N0, H, N).
hunks([c(_, Op)|T], Prev, N0, [c(Id, Op)|H], N) :-
	(   Prev == none -> Id is N0+1, N1 = Id ; Id = Prev, N1 = N0 ),
	hunks(T, Id, N1, H, N).

%!	candidate_omit(+N, +Max, +Mode, -Omit) is nondet.
%	Mode i (integration testing): only the new version.
%	Mode d (deployment / changing): every subset, fewest omissions first,
%	when N =< Max; otherwise only all-new and all-old.
candidate_omit(_, _, i, []) :- !.
candidate_omit(N, Max, _, Omit) :-
	( N =:= 0 -> Ids = [] ; numlist(1, N, Ids) ),
	(   N =< Max
	->  between(0, N, K), comb(K, Ids, Omit)
	;   ( Omit = [] ; Omit = Ids )
	).

comb(0, _, []) :- !.
comb(K, [X|Xs], [X|C]) :- K1 is K-1, comb(K1, Xs, C).
comb(K, [_|Xs], C) :- length(Xs, L), L >= K, comb(K, Xs, C).

%!	apply_omit(+Labelled, +Omit, -Units)
%	Inside a replaced region, deletions and insertions are paired by
%	position; for each pair the inserted (new) unit comes before the
%	restored (old) one.  So omitting the deletion of b(1) when b(2)
%	replaced it gives b(2), b(1) (luciancicd test 23), and keeping the
%	old A=1 but the new B=2 gives A=1,B=2 (test 9).
apply_omit([], _, []) :- !.
apply_omit([c(_, keep(X))|T], Omit, [X|Us]) :- !, apply_omit(T, Omit, Us).
apply_omit(L, Omit, Us) :-
	region(L, Region, Rest),
	include([c(_,Op)]>>(Op = del(_)), Region, Ds),
	include([c(_,Op)]>>(Op = ins(_)), Region, Is),
	pair_up(Ds, Is, Omit, RUs),
	append(RUs, Us1, Us),
	apply_omit(Rest, Omit, Us1).

region([C|T], [C|R], Rest) :- C = c(_, Op), Op \= keep(_), !, region(T, R, Rest).
region(L, [], L).

pair_up([], [], _, []) :- !.
pair_up(Ds, Is, Omit, Us) :-
	( Ds = [D|Ds1] -> true ; D = none, Ds1 = [] ),
	( Is = [I|Is1] -> true ; I = none, Is1 = [] ),
	( I = c(II, ins(X)), \+ omitted(II, Omit) -> U1 = [X] ; U1 = [] ),
	( D = c(DI, del(Y)), omitted(DI, Omit) -> U2 = [Y] ; U2 = [] ),
	append(U1, U2, U12),
	pair_up(Ds1, Is1, Omit, Us1),
	append(U12, Us1, Us).

omitted(Id, Omit) :- Id \== none, memberchk(Id, Omit).
