% family.pl
:- dynamic(seen/1).
name_of(X, 'Lucian') :- X == me.
%parent(albert,A).
%A=bob.
parent(albert, bob).
parent(bob, carol).
/* grandparent */
grandparent(A, C) :- parent(A, B), parent(B, C).
greeting(S) :- atom_string(hello, S0), string_concat(S0, " world", S).
count([], 0).
count([_|T], N) :- count(T, N0), N is N0+1.
