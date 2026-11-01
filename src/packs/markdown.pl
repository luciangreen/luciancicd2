% Pack: Markdown.  Tests in HTML comments: <!-- test: valid -->,
% <!-- test: heading TEXT -->, <!-- test: contains TEXT -->,
% <!-- test: links N -->.  "valid" proves that code fences close and that
% [link](targets) and inline HTML balance.

lc_packs:pack_def(markdown, [extensions(["md", "markdown"]), language(markdown)]).

lc_packs:pack_run(markdown, Tests, Text, _Ctx, Results) :-
	maplist([T, T-R]>>md_test(T, Text, R), Tests, Results).

md_test("valid", Text, R) :- !,
	(   md_fences_balanced(Text), lc_packs:pack_valid(markdown, Text, _)
	->  R = pass ; R = fail(not_well_formed)
	).
md_test(T, Text, R) :- string_concat("heading ", X, T), !,
	split_string(Text, "\n", "", Ls0),
	outside_fences(Ls0, out, Ls),
	(   member(L, Ls), string_concat("#", _, L),
	    split_string(L, "#", " ", Parts), last(Parts, H), H == X
	->  R = pass ; R = fail(no_heading(X))
	).
md_test(T, Text, R) :- string_concat("contains ", X, T), !,
	( sub_string(Text, _, _, _, X) -> R = pass ; R = fail(missing(X)) ).
md_test(T, Text, R) :- string_concat("links ", NS, T), !,
	number_string(N, NS),
	aggregate_all(count, sub_string(Text, _, _, _, "]("), K),
	( K =:= N -> R = pass ; R = fail(links(K), expected(N)) ).
md_test(T, _, fail(unknown_test(T))).

md_fences_balanced(Text) :-
	split_string(Text, "\n", "", Ls),
	aggregate_all(count, ( member(L, Ls), normalize_space(string(N), L), string_concat("```", _, N) ), K),
	K mod 2 =:= 0.

%	Lines that are not inside ``` code fences.
outside_fences([], _, []).
outside_fences([L|Ls], S, Out) :-
	normalize_space(string(N), L),
	(   string_concat("```", _, N)
	->  ( S == out -> S1 = in ; S1 = out ), Out = Out1
	;   S1 = S, ( S == out -> Out = [L|Out1] ; Out = Out1 )
	),
	outside_fences(Ls, S1, Out1).
