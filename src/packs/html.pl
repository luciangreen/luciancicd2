% Pack: HTML.  Tests in comments: <!-- test: valid -->,
% <!-- test: contains TEXT -->, <!-- test: count TAG N -->,
% <!-- test: title TEXT -->.  "valid" is a proof that tags balance
% under the learnt HTML language description.

lc_packs:pack_def(html, [extensions(["html", "htm"]), language(html)]).

lc_packs:pack_run(html, Tests, Text, _Ctx, Results) :-
	maplist([T, T-R]>>html_test(T, Text, R), Tests, Results).

html_test("valid", Text, R) :- !,
	( lc_packs:pack_valid(html, Text, _) -> R = pass ; R = fail(tags_do_not_balance) ).
html_test(T, Text, R) :- string_concat("contains ", X, T), !,
	( sub_string(Text, _, _, _, X) -> R = pass ; R = fail(missing(X)) ).
html_test(T, Text, R) :- string_concat("count ", Rest, T), !,
	split_string(Rest, " ", " ", [Tag, NS]), number_string(N, NS),
	string_lower(Text, L), string_lower(Tag, Tg),
	string_concat("<", Tg, Open),
	aggregate_all(count, ( sub_string(L, B, _, _, Open), B2 is B+1+_,
			      string_length(Open, OL), P is B+OL, sub_string(L, P, 1, _, C),
			      memberchk(C, [">", " ", "/", "\n"]), B2 >= 0 ), K),
	( K =:= N -> R = pass ; R = fail(count(Tag, K), expected(N)) ).
html_test(T, Text, R) :- string_concat("title ", X, T), !,
	(   sub_string(Text, B, _, _, "<title>"), S is B+7,
	    sub_string(Text, E, _, _, "</title>"), E > S, L is E-S,
	    sub_string(Text, S, L, _, Title0), normalize_space(string(Title), Title0)
	->  ( Title == X -> R = pass ; R = fail(title(Title)) )
	;   R = fail(no_title)
	).
html_test(T, _, fail(unknown_test(T))).
