% lc_parse.pl - Prolog source <-> terms, keeping comments and layout
%
% A Prolog file becomes pl_file(Items, Tail) where each item is
%   item(Kind, Sep, Text)
%     Kind = comment(String)          a single comment line or block
%          | directive(G)             G ground ('$VAR'(Name) variables)
%          | clause(Key, G)           Key = Name/Arity of the head
%     Sep  = layout text before the item
%     Text = the item's original source text (re-used when unchanged)
%   Tail = layout after the last item.
%
% Ground terms make diffing, hashing and comparing clauses trivial (==),
% and unground/2 turns them back into executable clauses.

:- module(lc_parse,
	  [ pl_parse/2,          % +Text, -pl_file(Items,Tail)
	    pl_parse_safe/2,     % +Text, -PlFile or fails on syntax error
	    pl_items_text/2,     % +pl_file, -Text
	    clause_key/2,        % +GroundClause, -Name/Arity
	    clause_units/2,      % +GroundClause, -Units
	    units_clauses/2,     % +Units, -GroundClauses   (fails if malformed)
	    clause_text/2,       % +GroundClause, -Text
	    term_text/2,         % +GroundTerm, -Text
	    ground_term/3,       % +Term, +VarNames, -Ground
	    unground/2,          % +Ground, -Term
	    unground_names/3,    % +Ground, -Term, -[Name-Var]
	    body_goals/2,        % +Body, -Goals
	    goals_body/2,        % +Goals, -Body
	    pl_equivalent/2      % +TextA, +TextB : same comments and clauses
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).

%!	pl_parse(+Text, -PlFile) is det.
%	Throws syntax_error on unparseable text.
pl_parse(Text0, pl_file(Items, Tail)) :-
	text_to_string(Text0, Text),
	setup_call_cleanup(open_string(Text, S),
			   read_raw(S, Raw),
			   close(S)),
	msort(Raw, Sorted),
	layout(Sorted, Text, 0, Items, End),
	string_length(Text, Len),
	(   End < Len -> sub_string(Text, End, _, 0, Tail) ; Tail = "" ).

pl_parse_safe(Text, PlFile) :-
	catch(pl_parse(Text, PlFile), _, fail).

read_raw(S, Raw) :-
	read_term(S, T, [ subterm_positions(P), comments(Cs),
			  variable_names(Vs), syntax_errors(error),
			  double_quotes(string)
			]),
	comment_entries(Cs, CEs),
	(   T == end_of_file
	->  Raw = CEs
	;   arg(1, P, From),
	    term_end(S, P, To),
	    ground_term(T, Vs, G),
	    classify(G, Kind),
	    append(CEs, [raw(From, To, Kind)|Rest], Raw),
	    read_raw(S, Rest)
	).

term_end(_S, P, To0) :- arg(2, P, To0).

comment_entries([], []).
comment_entries([Pos-Str|T], Es) :-
	stream_position_data(char_count, Pos, Off),
	(   sub_string(Str, 0, 1, _, "%")
	->  split_string(Str, "\n", "", Lines),
	    comment_lines(Lines, Off, Es0)
	;   string_length(Str, L), End is Off+L,
	    Es0 = [raw(Off, End, comment(Str))]
	),
	comment_entries(T, Es1),
	append(Es0, Es1, Es).

comment_lines([], _, []).
comment_lines([L|Ls], Off, Es) :-
	string_length(L, Len),
	End is Off+Len,
	Next is End+1,
	(   L == "" -> Es = Es1 ; Es = [raw(Off, End, comment(L))|Es1] ),
	comment_lines(Ls, Next, Es1).

classify((:- G), directive(G)) :- !.
classify(G, clause(K, G)) :- clause_key(G, K).

%	Turn raw entries into items with layout.  Clause ends are refined so
%	that the text is exactly "head :- body." (the stream position may be
%	one layout character past the full stop).
layout([], _, End, [], End).
layout([raw(From, To0, Kind)|T], Text, Prev, [item(Kind, Sep, ItemText)|Items], End) :-
	(   Kind = comment(C)
	->  string_length(C, L), To is From+L
	;   fullstop_end(Text, From, To0, To)
	),
	(   From >= Prev
	->  SepLen is From-Prev, sub_string(Text, Prev, SepLen, _, Sep)
	;   Sep = ""
	),
	Len is To-From,
	sub_string(Text, From, Len, _, ItemText),
	layout(T, Text, To, Items, End).

%	The clause ends just after the first full stop after its last token.
fullstop_end(Text, _From, To0, To) :-
	(   sub_string(Text, B, 1, _, "."), B >= To0
	->  To is B+1
	;   To = To0
	).

pl_items_text(pl_file(Items, Tail), Text) :-
	foldl(item_text, Items, "", T0),
	string_concat(T0, Tail, Text).

item_text(item(_, Sep, T), Acc, Acc1) :-
	string_concat(Acc, Sep, A1), string_concat(A1, T, Acc1).

% ---------------------------------------------------------------- terms

clause_key((H :- _), K) :- !, head_key(H, K).
clause_key((H --> _), N/A) :- !, head_key(H, N/A0), A is A0+2.
clause_key(H, K) :- head_key(H, K).

head_key((H, _), K) :- !, head_key(H, K).          % pushback DCG
head_key(_:H, K) :- !, head_key(H, K).
head_key(H, N/A) :- callable(H), !, functor(H, N, A).
head_key(_, '$invalid'/0).

%!	ground_term(+Term, +VarNames, -Ground)
ground_term(T, Vs, G) :-
	copy_term(T-Vs, G-Vs1),
	maplist(bind_name, Vs1),
	term_variables(G, Rest),
	maplist(=('$VAR'('_')), Rest).

bind_name(N=V) :- ( var(V) -> V = '$VAR'(N) ; true ).

%!	unground(+Ground, -Term)
%	'$VAR'(Name) -> shared variable; '$VAR'('_') -> fresh variable.
unground(G, T) :- empty_assoc(A0), ung(G, T, A0, _).

unground_names(G, T, Pairs) :- empty_assoc(A0), ung(G, T, A0, A), assoc_to_list(A, Pairs).

ung(X, X, A, A) :- var(X), !.
ung('$VAR'(N), V, A0, A) :- atom(N), !,
	(   N == '_' -> A = A0
	;   get_assoc(N, A0, V0) -> V = V0, A = A0
	;   put_assoc(N, A0, V, A)
	).
ung(X, X, A, A) :- atomic(X), !.
ung(X, Y, A0, A) :-
	compound_name_arguments(X, F, As),
	ung_list(As, Bs, A0, A),
	compound_name_arguments(Y, F, Bs).

ung_list([], [], A, A).
ung_list([X|Xs], [Y|Ys], A0, A) :- ung(X, Y, A0, A1), ung_list(Xs, Ys, A1, A).

% ---------------------------------------------------------------- units
%
% A clause is split into units so that changes can be combined goal by goal:
%   h(Head) followed by g(Goal) for each top-level conjunct of the body.
% DCG rules and clauses with module-qualified heads stay whole: w(Clause).

clause_units((H :- B), [h(H)|Gs]) :- H \= _:_, !,
	body_goals(B, Goals), maplist([G, g(G)]>>true, Goals, Gs).
clause_units((H --> B), [w((H --> B))]) :- !.
clause_units(H, [h(H)]).

units_clauses([], []).
units_clauses([w(C)|Us], [C|Cs]) :- !, units_clauses(Us, Cs).
units_clauses([h(H)|Us], [C|Cs]) :-
	take_goals(Us, Gs, Rest),
	(   Gs == [] -> C = H ; goals_body(Gs, B), C = (H :- B) ),
	units_clauses(Rest, Cs).

take_goals([g(G)|Us], [G|Gs], R) :- !, take_goals(Us, Gs, R).
take_goals(Us, [], Us).

body_goals(B, [B]) :- var(B), !.
body_goals((A, B), Gs) :- !, body_goals(A, GA), body_goals(B, GB), append(GA, GB, Gs).
body_goals(true, []) :- !.
body_goals(G, [G]).

goals_body([], true).
goals_body([G], G) :- !.
goals_body([G|Gs], (G, B)) :- goals_body(Gs, B).

%!	clause_text(+Ground, -Text): print a clause in Lucian CI/CD's compact style.
clause_text(G, Text) :-
	format(string(Text), "~W.", [G, [quoted(true), numbervars(true),
					  portray(false), spacing(standard)]]).

term_text(G, Text) :-
	format(string(Text), "~W", [G, [quoted(true), numbervars(true),
					 portray(false)]]).

%!	pl_equivalent(+A, +B)
%	Two Prolog texts are equivalent when they have the same comments
%	(ignoring surrounding white space) and the same clauses as terms.
%	So "a:-not((b))." and "a:-not(b)." are equivalent.
pl_equivalent(A, B) :-
	pl_parse_safe(A, pl_file(IA, _)),
	pl_parse_safe(B, pl_file(IB, _)),
	maplist(item_norm, IA, NA),
	maplist(item_norm, IB, NB),
	NA == NB.

item_norm(item(comment(C), _, _), comment(N)) :- !, normalize_space(string(N), C).
item_norm(item(K, _, _), K).
