% lc_deps.pl - call graphs, includes and bottom-up order
%
% Predicates are processed bottom-up: callees before callers, with
% mutually recursive predicates (strongly connected components) handled as
% one group, as in luciancicd's "depth-first, post-order, or sets of clauses
% or predicates involved in loops".

:- module(lc_deps,
	  [ clause_calls/2,        % +GroundClause, -[N/A]
	    goal_calls/2,          % +GroundGoal, -[N/A]
	    directive_includes/2,  % +GroundDirective, -[RelPath]
	    bottom_up_groups/3     % +Roots, +Edges(K-[K]), -Groups
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).

clause_calls((_ :- B), Cs) :- !, goal_calls(B, Cs0), sort(Cs0, Cs).
clause_calls((_ --> B), Cs) :- !, dcg_calls(B, Cs0), sort(Cs0, Cs).
clause_calls(_, []).

goal_calls(G, Cs) :- phrase(calls(G), Cs).

calls(G) --> { var(G) ; G = '$VAR'(_) }, !.
calls(_:G) --> !, calls(G).
calls((A,B)) --> !, calls(A), calls(B).
calls((A;B)) --> !, calls(A), calls(B).
calls((A->B)) --> !, calls(A), calls(B).
calls((A*->B)) --> !, calls(A), calls(B).
calls(\+ A) --> !, calls(A).
calls(not(A)) --> !, calls(A).
calls(call(A)) --> !, calls(A).
calls(once(A)) --> !, calls(A).
calls(ignore(A)) --> !, calls(A).
calls(forall(A,B)) --> !, calls(A), calls(B).
calls(findall(_,A,_)) --> !, calls(A).
calls(findall(_,A,_,_)) --> !, calls(A).
calls(aggregate_all(_,A,_)) --> !, calls(A).
calls(bagof(_,A,_)) --> !, { strip_carets(A, A1) }, calls(A1).
calls(setof(_,A,_)) --> !, { strip_carets(A, A1) }, calls(A1).
calls(catch(A,_,B)) --> !, calls(A), calls(B).
calls(with_output_to(_,A)) --> !, calls(A).
calls(call_with_time_limit(_,A)) --> !, calls(A).
calls(G) -->
	{ compound(G), functor(G, F, N), meta_list(F, N, _), arg(1, G, (_>>B)) }, !,
	calls(B).
calls(G) -->
	{ compound(G), functor(G, F, N), meta_list(F, N, Extra), arg(1, G, P),
	  callable(P), P \= '$VAR'(_), P \= [_|_] }, !,
	{ functor(P, PN, PA), PA1 is PA+Extra }, [PN/PA1].
calls(G) --> { callable(G), G \= [_|_], functor(G, N, A) }, !, [N/A].
calls(_) --> [].

meta_list(maplist, N, E) :- N >= 2, E is N-1.
meta_list(include, 3, 1).
meta_list(exclude, 3, 1).
meta_list(partition, 4, 1).
meta_list(foldl, N, E) :- N >= 4, E is N-1.
meta_list(call, N, E) :- N >= 2, E is N-1.

strip_carets(_^G, G1) :- !, strip_carets(G, G1).
strip_carets(G, G).

dcg_calls(B, Cs) :- phrase(dcalls(B), Cs).
dcalls(G) --> { var(G) ; G = '$VAR'(_) }, !.
dcalls((A,B)) --> !, dcalls(A), dcalls(B).
dcalls((A;B)) --> !, dcalls(A), dcalls(B).
dcalls((A->B)) --> !, dcalls(A), dcalls(B).
dcalls({G}) --> !, calls(G).
dcalls(\+ A) --> !, dcalls(A).
dcalls(L) --> { is_list(L) ; string(L) ; L == ! }, !.
dcalls(call(_)) --> !.
dcalls(G) --> { callable(G), functor(G, N, A), A2 is A+2 }, [N/A2].

directive_includes(D, Fs) :- phrase(incl(D), Fs).
incl((A,B)) --> !, incl(A), incl(B).
incl(include(F)) --> !, file_spec(F).
incl(consult(F)) --> !, file_spec(F).
incl(ensure_loaded(F)) --> !, file_spec(F).
incl(use_module(F)) --> !, file_spec(F).
incl(use_module(F,_)) --> !, file_spec(F).
incl(L) --> { is_list(L) }, !, file_specs(L).
incl(_) --> [].
file_specs([]) --> [].
file_specs([F|Fs]) --> file_spec(F), file_specs(Fs).
file_spec(F) --> { atomic(F), \+ F = [] }, !, { atom_string(F, S) }, [S].
file_spec(_) --> [].

%!	bottom_up_groups(+Roots, +Edges, -Groups)
%	Edges is a list Key-Callees.  Groups is a list of lists of keys:
%	every group comes after the groups it calls.
bottom_up_groups(Roots0, Edges, Groups) :-
	pairs_keys(Edges, AllKeys),
	append(Roots0, AllKeys, Roots1),
	list_to_set(Roots1, Roots),
	include([K]>>memberchk(K-_, Edges), Roots, Roots2),
	foldl(post_order(Edges), Roots2, [], RevPost),   % RevPost: visited, reversed post-order
	reverse(RevPost, Post),
	scc_groups(Post, Edges, [], Groups).

post_order(Edges, K, Seen, Seen1) :-
	(   post_order_member(K, Seen) -> Seen1 = Seen
	;   Seen0 = [visiting(K)|Seen],
	    (   memberchk(K-Cs, Edges) -> true ; Cs = [] ),
	    foldl(post_order(Edges), Cs, Seen0, Seen2),
	    select(visiting(K), Seen2, Seen3),
	    Seen1 = [K|Seen3]
	).

post_order_member(K, Seen) :- memberchk(K, Seen) ; memberchk(visiting(K), Seen).

scc_groups([], _, _, []).
scc_groups([K|Ks], Edges, Done, Groups) :-
	(   memberchk(K, Done)
	->  scc_groups(Ks, Edges, Done, Groups)
	;   reachable(Edges, K, RK),
	    include([J]>>( J == K ; ( memberchk(J, RK), reachable(Edges, J, RJ), memberchk(K, RJ) ) ),
		    [K|Ks], Group0),
	    list_to_set(Group0, Group),
	    append(Group, Done, Done1),
	    Groups = [Group|Gs],
	    scc_groups(Ks, Edges, Done1, Gs)
	).

reachable(Edges, K, R) :- reach([K], Edges, [], R).
reach([], _, R, R).
reach([K|Ks], Edges, Acc, R) :-
	(   memberchk(K-Cs, Edges) -> true ; Cs = [] ),
	exclude([C]>>memberchk(C, Acc), Cs, New),
	append(Acc, New, Acc1),
	append(Ks, New, Ks1),
	reach(Ks1, Edges, Acc1, R).
