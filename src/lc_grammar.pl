% lc_grammar.pl - recognising languages, learning their grammars, and
% proving that files follow them.
%
% A language description is a list of features:
%   extensions(Exts), line_comment(Markers), block_comment([[Open,Close]]),
%   strings(Delims), brackets([[Open,Close]]), tags(Bool), void_tags(Names),
%   raw_tags(Names), terminator(T), keywords(Ws), test_marker(M), proof(Ps)
%
% prove_text/3 tokenises a text with a description and parses the tokens
% with a DCG for nested structure (brackets and tags must balance, strings
% and comments must end).  The parse tree is the proof; its size and depth
% are recorded as a certificate.
%
% learn_language/5 induces a description from sample files: each feature
% is a hypothesis that is kept only if every sample still has a proof.
% save_language/2 writes the description, with the proofs, to
% languages/<Name>.pl, and recognise_language/3 picks the best description
% for an unknown file.

:- module(lc_grammar,
	  [ prove_text/3,           % +Desc, +Text, -Proof
	    learn_language/5,       % +Name, +Samples, +Exts, +Hints, -Desc
	    save_language/2,        % +Dir, +language(Name,Desc)
	    load_languages/1,       % +Dir
	    language/2,             % ?Name, ?Desc
	    recognise_language/3,   % +Text, -Name, -Score
	    language_for_extension/2,
	    learn_languages_from_samples/2  % +SamplesDir, +OutDir
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(readutil)).

:- dynamic language/2.

feature(D, F, Default) :- ( memberchk(F, D) -> true ; arg(1, F, Default) ).

% ---------------------------------------------------------------- tokens

tokens(D, Text, Tokens) :-
	string_codes(Text, Cs),
	feature(D, line_comment(LC), []),
	feature(D, block_comment(BC), []),
	feature(D, strings(SD), []),
	feature(D, brackets(BR), []),
	feature(D, tags(Tags), false),
	feature(D, void_tags(Void), []),
	feature(D, raw_tags(Raw), []),
	maplist(string_codes, LC, LCc),
	maplist([[O,C],[Oc,Cc]]>>(string_codes(O,Oc), string_codes(C,Cc)), BC, BCc),
	maplist(string_codes, SD, SDc),
	maplist([[O,C],O1-C1]>>(string_codes(O,[O1]), string_codes(C,[C1])), BR, BRc),
	Cfg = cfg(LCc, BCc, SDc, BRc, Tags, Void, Raw),
	phrase(toks(Cfg, Tokens), Cs), !.

toks(_, []) --> [].
toks(Cfg, Ts) --> [C], { code_type(C, space) }, !, toks(Cfg, Ts).
toks(Cfg, [comment|Ts]) -->
	{ Cfg = cfg(_, BC, _, _, _, _, _), member(O-Cl, BC) }, prefix(O), !, upto(Cl), toks(Cfg, Ts).
toks(Cfg, [comment|Ts]) -->
	{ Cfg = cfg(LC, _, _, _, _, _, _), member(M, LC) }, prefix(M), !, rest_of_line, toks(Cfg, Ts).
toks(Cfg, Ts) -->
	{ Cfg = cfg(_, _, _, _, true, Void, Raw) }, "<", !, tag(Void, Raw, Ts0, Cfg), { append(Ts0, Ts1, Ts) }, toks(Cfg, Ts1).
toks(Cfg, [string|Ts]) -->
	{ Cfg = cfg(_, _, SD, _, _, _, _) }, [Q], { memberchk([Q], SD) }, !, str_body(Q), toks(Cfg, Ts).
toks(Cfg, [open(C)|Ts]) -->
	{ Cfg = cfg(_, _, _, BR, _, _, _) }, [C], { memberchk(C-_, BR) }, !, toks(Cfg, Ts).
toks(Cfg, [close(O)|Ts]) -->
	{ Cfg = cfg(_, _, _, BR, _, _, _) }, [C], { memberchk(O-C, BR) }, !, toks(Cfg, Ts).
toks(Cfg, [word(W)|Ts]) --> word_codes(Ws), { Ws \== [] }, !, { atom_codes(W, Ws) }, toks(Cfg, Ts).
toks(Cfg, [punct(C)|Ts]) --> [C], toks(Cfg, Ts).

prefix([]) --> [].
prefix([C|Cs]) --> [C], prefix(Cs).

upto(E) --> prefix(E), !.
upto(E) --> [_], upto(E).

rest_of_line --> [C], { C \== 0'\n }, !, rest_of_line.
rest_of_line --> [].

str_body(Q) --> [0'\\, _], !, str_body(Q).
str_body(Q) --> [Q], !.
str_body(Q) --> [C], { C \== 0'\n ; Q == 0'` }, str_body(Q).

word_codes([C|Cs]) --> [C], { code_type(C, csym) }, !, word_codes(Cs).
word_codes([]) --> [].

% tags: <name ...>, </name>, <name .../>, <!DOCTYPE ...>
tag(_, _, [leaf], _) --> "!", !, upto(">").
tag(_, _, [leaf], _) --> "?", !, upto("?>").
tag(_, _, [tag_close(N)], _) --> "/", tag_name(N), !, upto(">").
tag(Void, Raw, Ts, _) -->
	tag_name(N), !, tag_rest(SelfClose),
	(   { SelfClose == true ; memberchk(N, Void) }
	->  { Ts = [leaf] }
	;   { memberchk(N, Raw) }
	->  { atom_codes(N, NC), append(`</`, NC, End0), append(End0, `>`, End) },
	    upto_ci(End), { Ts = [tag_open(N), tag_close(N)] }
	;   { Ts = [tag_open(N)] }
	).
tag(_, _, [punct(0'<)], _) --> [].

tag_name(N) --> [C], { code_type(C, alpha) }, word_codes(Cs), { atom_codes(N0, [C|Cs]), downcase_atom(N0, N) }.

tag_rest(Self) --> "/>", !, { Self = true }.
tag_rest(false) --> ">", !.
tag_rest(S) --> [Q], { Q == 0'" ; Q == 0'' }, !, attr_str(Q), tag_rest(S).
tag_rest(S) --> [_], tag_rest(S).
attr_str(Q) --> [Q], !.
attr_str(Q) --> [_], attr_str(Q).

upto_ci(E) --> prefix_ci(E), !.
upto_ci(E) --> [_], upto_ci(E).
prefix_ci([]) --> [].
prefix_ci([C|Cs]) --> [D], { code_type(D, to_lower(L)), code_type(C, to_lower(L)) }, prefix_ci(Cs).

% ---------------------------------------------------------------- proofs

%!	prove_text(+Desc, +Text, -Proof) is semidet.
prove_text(D, Text, proof(tokens(N), depth(Depth), nodes(Nodes))) :-
	tokens(D, Text, Ts),
	length(Ts, N),
	phrase(doc(Tree), Ts), !,
	tree_stats(Tree, Depth, Nodes).

doc([I|Is]) --> item(I), !, doc(Is).
doc([]) --> [].

item(node(br(C), Ch)) --> [open(C)], !, doc(Ch), [close(C)].
item(node(tag(N), Ch)) --> [tag_open(N)], !, doc(Ch), ( [tag_close(N)] -> [] ; optional_close(N) ).
item(leaf) --> [T], { T \= close(_), T \= tag_close(_) }.

% Like HTML, <p> and <li> may be left open; nothing else may.
optional_close(N) --> { memberchk(N, [p, li, td, tr, th, option, dt, dd]) }.

tree_stats(Items, Depth, Nodes) :-
	foldl([I, D0-N0, D-N]>>( item_stats(I, DI, NI), D is max(D0, DI), N is N0+NI ),
	      Items, 0-0, Depth-Nodes).
item_stats(leaf, 0, 1).
item_stats(node(_, Ch), D, N) :- tree_stats(Ch, D0, N0), D is D0+1, N is N0+1.

% ---------------------------------------------------------------- learning

line_comment_candidates(["//", "#", "%", "--", ";"]).
block_comment_candidates([["/*", "*/"], ["<!--", "-->"], ["{-", "-}"], ["(*", "*)"]]).
string_candidates(["\"", "'", "`"]).
bracket_candidates([["(", ")"], ["[", "]"], ["{", "}"]]).

%!	learn_language(+Name, +Samples, +Exts, +Hints, -Desc)
%	Hints: not_line_comment(M), not_string(Q), raw_tags(Ts)
learn_language(Name, Samples, Exts, Hints, Desc) :-
	maplist([S, Ls]>>split_string(S, "\n", "", Ls), Samples, LineSets),
	append(LineSets, Lines),
	% line comments: marker at line start (or after code) followed by a space
	line_comment_candidates(LCC),
	findall(E-M, ( member(M, LCC), \+ memberchk(not_line_comment(M), Hints),
		       aggregate_all(count, ( member(L, Lines), comment_evidence(M, L) ), E), E > 0 ), LE),
	keysort(LE, LE1), reverse(LE1, LE2),
	( LE2 = [_-Best|_] -> LC = [Best] ; LC = [] ),
	block_comment_candidates(BCC),
	findall([O,C], ( member([O,C], BCC),
			 aggregate_all(count, ( member(S, Samples), sub_string(S, _, _, _, O) ), E), E > 0,
			 forall(( member(S, Samples), sub_string(S, B, _, _, O) ),
				( sub_string(S, B2, _, _, C), B2 > B )) ), BC),
	% markup?
	(   aggregate_all(count, ( member(S, Samples), sub_string(S, _, _, _, "</") ), TE), TE > 0
	->  Tags = true, void_tags(Samples, Void)
	;   Tags = false, Void = []
	),
	( memberchk(raw_tags(Raw), Hints) -> true ; ( Tags == true -> Raw = [script, style] ; Raw = [] ) ),
	D0 = [line_comment(LC), block_comment(BC), tags(Tags), void_tags(Void), raw_tags(Raw)],
	D0b = D0,
	% strings, then brackets: keep each only if every sample is still proved
	string_candidates(SC),
	foldl(try_string(Samples, Hints), SC, D0b, D1),
	bracket_candidates(BRC),
	foldl(try_bracket(Samples), BRC, D1, D2),
	(   all_prove(D2, Samples) -> D3 = D2
	;   D3 = [line_comment(LC), block_comment(BC), tags(Tags), void_tags(Void), raw_tags(Raw)]
	),
	terminator(Lines, LC, Term),
	keywords(Samples, Kws),
	findall(sample(I, H, Pr),
		( nth1(I, Samples, S), variant_sha1(S, H), prove_text(D3, S, Pr) ), Proofs),
	length(Samples, NS), length(Proofs, NP),
	(   NP =:= NS -> true
	;   format(user_error, "Warning: ~w of ~w samples of ~w have no proof~n", [NS-NP, NS, Name])
	),
	append([ [extensions(Exts)], D3,
		 [terminator(Term), keywords(Kws), test_marker("test:"), proof(Proofs)] ], Desc).

comment_evidence(M, L) :-
	normalize_space(string(T), L),
	(   string_concat(M, Rest, T), ( Rest == "" ; sub_string(Rest, 0, 1, _, " ") )
	;   string_concat(_, After, L), string_concat(" ", A2, After), string_concat(M, Rest, A2),
	    sub_string(Rest, 0, 1, _, " "), sub_string(L, 0, 1, _, F), F \== " "
	), !.

void_tags(Samples, Void) :-
	findall(N, ( member(S, Samples), string_codes(S, Cs), tag_open_name(Cs, N) ), Os),
	findall(N, ( member(S, Samples), string_codes(S, Cs), tag_close_name(Cs, N) ), Cl),
	sort(Os, O1), sort(Cl, C1),
	subtract(O1, C1, Void).

tag_open_name(Cs, N) :- append(_, [0'<|R], Cs), phrase(tag_name(N), R, _).
tag_close_name(Cs, N) :- append(_, [0'<, 0'/|R], Cs), phrase(tag_name(N), R, _).

try_string(Samples, Hints, Q, D, D1) :-
	(   \+ memberchk(not_string(Q), Hints),
	    once(( member(S, Samples), sub_string(S, _, _, _, Q) )),
	    feature(D, strings(Qs), []),
	    append(Qs, [Q], Qs1),
	    set_feature(D, strings(Qs1), D2),
	    all_prove(D2, Samples)
	->  D1 = D2
	;   D1 = D
	).

try_bracket(Samples, P, D, D1) :-
	(   feature(D, brackets(Bs), []),
	    append(Bs, [P], Bs1),
	    set_feature(D, brackets(Bs1), D2),
	    all_prove(D2, Samples)
	->  D1 = D2
	;   D1 = D
	).

set_feature(D, F, D1) :-
	functor(F, N, 1), functor(F0, N, 1),
	( selectchk(F0, D, D2) -> true ; D2 = D ),
	append(D2, [F], D1).

all_prove(D, Samples) :- forall(member(S, Samples), prove_text(D, S, _)).

terminator(Lines, LC, T) :-
	include([L]>>( normalize_space(string(N), L), N \== "",
		       \+ ( member(M, LC), string_concat(M, _, N) ) ), Lines, Code),
	length(Code, NC),
	(   NC =:= 0 -> T = none
	;   member(T0, [";", "."]),
	    aggregate_all(count, ( member(L, Code), normalize_space(string(N), L), string_concat(_, T0, N) ), K),
	    K * 10 >= NC * 3
	->  T = T0
	;   T = none
	).

keywords(Samples, Kws) :-
	findall(W, ( member(S, Samples), split_string(S, "\n", "", Ls), member(L, Ls),
		     split_string(L, " \t(){}<>;,.#=", " \t", Ws), member(W0, Ws), W0 \== "",
		     string_codes(W0, [C|_]), code_type(C, alpha), string_lower(W0, W) ), All),
	msort(All, Sorted), clumped_pairs(Sorted, Counts),
	include([_-N]>>(N >= 3), Counts, Freq),
	transpose_pairs(Freq, ByCount0), keysort(ByCount0, BC1), reverse(BC1, BC),
	pairs_values(BC, Ws1),
	( length(Kws, 15), append(Kws, _, Ws1) -> true ; Kws = Ws1 ).

clumped_pairs(L, Ps) :- clumped(L, Ps).

% ---------------------------------------------------------------- files

save_language(Dir, language(Name, Desc)) :-
	make_directory_path(Dir),
	format(atom(F), "~w/~w.pl", [Dir, Name]),
	setup_call_cleanup(
	    open(F, write, S, [encoding(utf8)]),
	    ( format(S, "% Language description for ~w, learnt by Lucian CI/CD 2 (lc_grammar).~n", [Name]),
	      format(S, "% proof/1 holds a certificate (sample, sha1, parse size and depth)~n", []),
	      format(S, "% for every sample the description was proved on.~n~n", []),
	      format(S, "~q.~n", [language(Name, Desc)]) ),
	    close(S)),
	retractall(language(Name, _)),
	assertz(language(Name, Desc)).

load_languages(Dir) :-
	(   exists_directory(Dir)
	->  directory_files(Dir, Fs),
	    forall(( member(F, Fs), file_name_extension(_, pl, F) ),
		   ( directory_file_path(Dir, F, P),
		     catch(( read_file_to_terms(P, Ts, []),
			     forall(member(language(N, D), Ts),
				    ( retractall(language(N, _)), assertz(language(N, D)) )) ),
			   _, true) ))
	;   true
	).

language_for_extension(Ext, Name) :-
	language(Name, D), feature(D, extensions(Es), []), memberchk(Ext, Es), !.

%!	recognise_language(+Text, -Name, -Score)
%	The language whose description proves Text with the most evidence.
recognise_language(Text, Name, Score) :-
	findall(Sc-N, ( language(N, D), prove_text(D, Text, _), evidence(D, Text, Sc) ), Ss),
	Ss \== [],
	keysort(Ss, S1), reverse(S1, [Score-Name|_]).

evidence(D, Text, Score) :-
	split_string(Text, "\n", "", Lines),
	feature(D, line_comment(LC), []),
	aggregate_all(count, ( member(M, LC), member(L, Lines), comment_evidence(M, L) ), E1),
	feature(D, block_comment(BC), []),
	aggregate_all(count, ( member([O,_], BC), sub_string(Text, _, _, _, O) ), E2),
	feature(D, keywords(Kw), []),
	string_lower(Text, Lower),
	split_string(Lower, " \t\n(){}<>;,.#=", " \t", Ws),
	aggregate_all(count, ( member(W, Ws), memberchk(W, Kw) ), E3),
	feature(D, tags(T), false),
	( T == true, sub_string(Text, _, _, _, "</") -> E4 = 5 ; T == true -> E4 = -5 ; E4 = 0 ),
	feature(D, terminator(Tm), none),
	( Tm \== none, aggregate_all(count, ( member(L, Lines), normalize_space(string(N), L), string_concat(_, Tm, N) ), E5) -> true ; E5 = 0 ),
	Score is 3*E1 + 3*E2 + E3 + E4 + E5.

%!	learn_languages_from_samples(+SamplesDir, +OutDir)
%	Each sub-directory is a language: its files are the samples and an
%	optional hints.pl holds extensions(Es) and hints.
learn_languages_from_samples(SDir, ODir) :-
	directory_files(SDir, Ls),
	forall(( member(L, Ls), \+ sub_atom(L, 0, 1, _, '.'),
		 directory_file_path(SDir, L, LD), exists_directory(LD) ),
	       ( directory_files(LD, Fs),
		 findall(T, ( member(F, Fs), \+ sub_atom(F, 0, 1, _, '.'), F \== 'hints.pl',
			      directory_file_path(LD, F, FP), read_file_to_string(FP, T, []) ), Samples),
		 directory_file_path(LD, 'hints.pl', HP),
		 ( exists_file(HP) -> read_file_to_terms(HP, HT, []) ; HT = [] ),
		 ( memberchk(extensions(Exts), HT) -> true ; Exts = [] ),
		 ( memberchk(hints(Hints), HT) -> true ; Hints = [] ),
		 learn_language(L, Samples, Exts, Hints, Desc),
		 save_language(ODir, language(L, Desc)),
		 length(Samples, NS),
		 format("Learnt ~w from ~w samples.~n", [L, NS]) )).
