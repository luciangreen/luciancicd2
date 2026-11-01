% lc_proof.pl - proofs of Prolog goals
%
% prove(M, Goal, Proof) solves Goal in module M like call/1 and returns the
% proof tree:
%   node(Goal, ClauseNo, BodyProof)   a user predicate, solved by clause n
%   and(P1, P2) | left(P) | right(P) | then(PC, PT) | else(PE)
%   not(Goal)                         negation as failure succeeded
%   all(Goal, [Proof, ...])           findall/3 and friends
%   cut | true | builtin(Goal)
% Cut is handled exactly (prolog_cut_to/1), so the proofs are those of the
% real program.  The trees are used by lc_debug (algorithmic debugging:
% which clause made a wrong answer, which goal failed) and lc_optimise
% (repeated sub-proofs suggest tabling; bindings show where tests can move).

:- module(lc_proof,
	  [ prove/3,            % +M, :Goal, -Proof
	    prove/4,            % +M, :Goal, -Proof, +MaxDepth
	    proof_nodes/2,      % +Proof, -[node(Goal,Clause)]
	    proof_size/2,
	    proof_depth/2,
	    user_pred/2,        % +M, +Goal
	    print_proof/1
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).

prove(M, G, P) :- prove(M, G, P, 2000).
prove(M, G, P, Max) :- nb_setval(lc_proof_max, Max), p(M, G, P, 0).

user_pred(M, G) :-
	callable(G),
	predicate_property(M:G, dynamic),
	\+ predicate_property(M:G, imported_from(_)).

p(_, V, _, _) :- var(V), !, throw(error(instantiation_error, prove/3)).
p(_, true, true, _) :- !.
p(_, M2:G, P, D) :- !, p(M2, G, P, D).
p(M, (A, B), and(PA, PB), D) :- !, p(M, A, PA, D), p(M, B, PB, D).
p(M, (C -> T ; E), P, D) :- !,
	(   p(M, C, PC, D) -> p(M, T, PT, D), P = then(PC, PT) ; p(M, E, PE, D), P = else(PE) ).
p(M, (C *-> T ; E), P, D) :- !,
	(   p(M, C, PC, D) *-> p(M, T, PT, D), P = then(PC, PT) ; p(M, E, PE, D), P = else(PE) ).
p(M, (A ; B), P, D) :- !, ( p(M, A, PA, D), P = left(PA) ; p(M, B, PB, D), P = right(PB) ).
p(M, (C -> T), then(PC, PT), D) :- !, ( p(M, C, PC, D) -> p(M, T, PT, D) ).
p(M, \+ G, not(G), D) :- !, \+ p(M, G, _, D).
p(M, not(G), not(G), D) :- !, \+ p(M, G, _, D).
p(M, call(G), P, D) :- !, p(M, G, P, D).
p(M, once(G), P, D) :- !, once(p(M, G, P, D)).
p(M, ignore(G), P, D) :- !, ( p(M, G, P, D) -> true ; P = true ).
p(M, findall(T, G, L), all(G, Ps), D) :- !,
	findall(T-P0, p(M, G, P0, D), Pairs), pairs(Pairs, L0, Ps), L = L0.
p(M, forall(C, A), all(forall(C, A), []), D) :- !, \+ ( p(M, C, _, D), \+ p(M, A, _, D) ).
p(_, !, cut, _) :- !.
p(M, G, P, D) :-
	user_pred(M, G), !,
	nb_getval(lc_proof_max, Max),
	D1 is D+1,
	(   D1 > Max -> throw(lc_proof_depth_exceeded(G)) ; true ),
	prolog_current_choice(Ch),
	clause(M:G, B, Ref),
	clause_no(Ref, N),
	body(M, B, PB, Ch, D1),
	P = node(G, N, PB).
p(M, G, builtin(G), _) :- call(M:G).

body(_, !, cut, Ch, _) :- !, prolog_cut_to(Ch).
body(M, (A, B), and(PA, PB), Ch, D) :- !, body(M, A, PA, Ch, D), body(M, B, PB, Ch, D).
body(M, (C -> T ; E), P, Ch, D) :- !,
	(   p(M, C, PC, D) -> body(M, T, PT, Ch, D), P = then(PC, PT) ; body(M, E, PE, Ch, D), P = else(PE) ).
body(M, (A ; B), P, Ch, D) :- !,
	( body(M, A, PA, Ch, D), P = left(PA) ; body(M, B, PB, Ch, D), P = right(PB) ).
body(M, G, P, _, D) :- p(M, G, P, D).

clause_no(Ref, N) :- ( clause_property(Ref, _), nth_clause(_, N, Ref) -> true ; N = 0 ).

pairs([], [], []).
pairs([T-P|Ps], [T|Ts], [P|Qs]) :- pairs(Ps, Ts, Qs).

%!	proof_nodes(+Proof, -Nodes): user-predicate nodes, pre-order.
proof_nodes(P, Ns) :- phrase(nodes(P), Ns).
nodes(node(G, N, B)) --> !, [node(G, N)], nodes(B).
nodes(and(A, B)) --> !, nodes(A), nodes(B).
nodes(left(A)) --> !, nodes(A).
nodes(right(A)) --> !, nodes(A).
nodes(then(A, B)) --> !, nodes(A), nodes(B).
nodes(else(A)) --> !, nodes(A).
nodes(all(_, Ps)) --> !, nodes_list(Ps).
nodes(_) --> [].
nodes_list([]) --> [].
nodes_list([P|Ps]) --> nodes(P), nodes_list(Ps).

proof_size(P, N) :- proof_nodes(P, Ns), length(Ns, N).

proof_depth(node(_, _, B), D) :- !, proof_depth(B, D0), D is D0+1.
proof_depth(P, D) :-
	compound(P), P =.. [F|As], memberchk(F, [and, left, right, then, else]), !,
	maplist(proof_depth, As, Ds), max_list([0|Ds], D).
proof_depth(all(_, Ps), D) :- !, maplist(proof_depth, Ps, Ds), max_list([0|Ds], D).
proof_depth(_, 0).

print_proof(P) :- print_proof(P, 0).
print_proof(node(G, N, B), I) :- !,
	tab(I), format("~q   [clause ~w]~n", [G, N]), I1 is I+2, print_proof(B, I1).
print_proof(and(A, B), I) :- !, print_proof(A, I), print_proof(B, I).
print_proof(left(A), I) :- !, print_proof(A, I).
print_proof(right(A), I) :- !, print_proof(A, I).
print_proof(then(A, B), I) :- !, print_proof(A, I), print_proof(B, I).
print_proof(else(A), I) :- !, print_proof(A, I).
print_proof(all(G, Ps), I) :- !,
	tab(I), format("all solutions of ~q:~n", [G]), I1 is I+2, forall(member(P, Ps), print_proof(P, I1)).
print_proof(builtin(G), I) :- !, tab(I), format("~q~n", [G]).
print_proof(not(G), I) :- !, tab(I), format("not ~q~n", [G]).
print_proof(_, _).
