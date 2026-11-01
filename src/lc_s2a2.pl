% lc_s2a2.pl - S2A2: Spec to Algorithm 2
%
% S2A2 writes Prolog predicates by following instructions.  The
% instructions are a small, typed vocabulary (help(instructions) lists
% them) such as reverse, sum, add(3), map(square), filter(gt(2)), join(",").
%
%   s2a2_instructions(+Name, +Text, +Specs, -Code)
%       follow instructions given in English: "square each number then sum"
%   s2a2(+Name, +Specs, -Code)
%       find the instructions: search pipelines of up to three instructions
%       that turn every input into its output, trying first the
%       instructions an MNN ranks highest for the spec's features
%   s2a2_complete(+PrologText, -NewText, -Report)
%       write code for every predicate that has tests in comments but no
%       clauses (the tests are the spec)
%
% Specs are [[Inputs, Output], ...], e.g. [[[[1,2,3]], 14], [[[2]], 4]].
% Generated code is readable recursive Prolog with luciancicd test comments,
% and is checked by loading it and running those tests before it is
% returned, so what S2A2 writes is proved against its spec.

:- module(lc_s2a2,
	  [ s2a2/3,
	    s2a2/4,                  % +Name, +Specs, -Code, +Options (max_depth(D))
	    s2a2_instructions/4,
	    s2a2_complete/3,
	    s2a2_instruction/4,      % ?Id, ?In-Out types, ?Description, ?Example
	    parse_instructions/2,    % +Text, -[[Alternative instructions]]
	    spec_features/2,
	    s2a2_mnn/1,
	    s2a2_train/0
	  ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(random)).
:- use_module(lc_parse).
:- use_module(lc_tests).
:- use_module(lc_mnn).

:- dynamic mnn_cache/1.

% ---------------------------------------------------------------- vocabulary

%	s2a2_instruction(Template, InType-OutType, Description, Example)
s2a2_instruction(add(k),          num-num,   "add a number",              "add 3").
s2a2_instruction(subtract(k),     num-num,   "subtract a number",         "subtract 1").
s2a2_instruction(multiply(k),     num-num,   "multiply by a number",      "multiply by 2, double").
s2a2_instruction(divide(k),       num-num,   "integer divide by a number","divide by 2, halve").
s2a2_instruction(mod(k),          num-num,   "remainder after dividing",  "mod 3").
s2a2_instruction(square,          num-num,   "square",                    "square").
s2a2_instruction(negate,          num-num,   "change the sign",           "negate").
s2a2_instruction(absolute,        num-num,   "absolute value",            "absolute").
s2a2_instruction(sum,             list-num,  "add up a list",             "sum, total").
s2a2_instruction(product,         list-num,  "multiply a list together",  "product").
s2a2_instruction(length,          list-num,  "count the items",           "count, length").
s2a2_instruction(maximum,         list-num,  "largest item",              "maximum, largest").
s2a2_instruction(minimum,         list-num,  "smallest item",             "minimum, smallest").
s2a2_instruction(first,           list-any,  "first item",                "first").
s2a2_instruction(last,            list-any,  "last item",                 "last").
s2a2_instruction(reverse,         list-list, "reverse a list",            "reverse").
s2a2_instruction(sort,            list-list, "sort, keeping duplicates",  "sort").
s2a2_instruction(unique,          list-list, "sort and remove duplicates","remove duplicates").
s2a2_instruction(tail,            list-list, "drop the first item",       "remove the first").
s2a2_instruction(map(i),          list-list, "do an instruction to each item", "square each, add 1 to each").
s2a2_instruction(filter(c),       list-list, "keep items: gt(N), lt(N), even, odd", "keep numbers greater than 2").
s2a2_instruction(upper,           str-str,   "upper case",                "uppercase").
s2a2_instruction(lower,           str-str,   "lower case",                "lowercase").
s2a2_instruction(reverse_string,  str-str,   "reverse a string",          "reverse the string").
s2a2_instruction(append_text(k),  str-str,   "add text at the end",       "append \"!\"").
s2a2_instruction(prepend_text(k), str-str,   "add text at the start",     "prepend \"Dear \"").
s2a2_instruction(string_length,   str-num,   "length of a string",        "length of the string").
s2a2_instruction(to_number,       str-num,   "string to number",          "to number").
s2a2_instruction(split(k),        str-list,  "split a string at a separator", "split on \",\", split into words").
s2a2_instruction(chars,           str-list,  "characters of a string",    "characters").
s2a2_instruction(join(k),         list-str,  "join items with a separator","join with \"-\"").
s2a2_instruction(to_string,       num-str,   "number to string",          "to string").
s2a2_instruction(plus,            num2-num,  "add two numbers",           "plus").
s2a2_instruction(minus,           num2-num,  "first minus second",        "minus").
s2a2_instruction(times,           num2-num,  "multiply two numbers",      "times").
s2a2_instruction(max2,            num2-num,  "larger of two",             "larger").
s2a2_instruction(min2,            num2-num,  "smaller of two",            "smaller").
s2a2_instruction(append2,         list2-list,"join two lists",            "append").
s2a2_instruction(concat2,         str2-str,  "join two strings",          "concatenate").

families(Fs) :- findall(F, ( s2a2_instruction(T, _, _, _), functor(T, F, _) ), Fs).

% ---------------------------------------------------------------- execution

type_of(X, num) :- number(X), !.
type_of(X, str) :- string(X), !.
type_of(X, list) :- is_list(X), !.
type_of(_, any).

compatible(any, _) :- !.
compatible(_, any) :- !.
compatible(T, T).

run(add(K), X, Y) :- number(X), Y is X+K.
run(subtract(K), X, Y) :- number(X), Y is X-K.
run(multiply(K), X, Y) :- number(X), Y is X*K.
run(divide(K), X, Y) :- integer(X), K =\= 0, Y is X//K.
run(mod(K), X, Y) :- integer(X), K =\= 0, Y is X mod K.
run(square, X, Y) :- number(X), Y is X*X.
run(negate, X, Y) :- number(X), Y is -X.
run(absolute, X, Y) :- number(X), Y is abs(X).
run(sum, X, Y) :- is_list(X), maplist(number, X), sum_list(X, Y).
run(product, X, Y) :- is_list(X), maplist(number, X), foldl([A,B0,B]>>(B is A*B0), X, 1, Y).
run(length, X, Y) :- is_list(X), length(X, Y).
run(maximum, X, Y) :- is_list(X), X \== [], maplist(number, X), max_list(X, Y).
run(minimum, X, Y) :- is_list(X), X \== [], maplist(number, X), min_list(X, Y).
run(first, [Y|_], Y).
run(last, X, Y) :- is_list(X), last(X, Y).
run(reverse, X, Y) :- is_list(X), reverse(X, Y).
run(sort, X, Y) :- is_list(X), msort(X, Y).
run(unique, X, Y) :- is_list(X), sort(X, Y).
run(tail, [_|Y], Y).
run(map(I), X, Y) :- is_list(X), maplist(run(I), X, Y).
run(filter(C), X, Y) :- is_list(X), include(cond(C), X, Y).
run(upper, X, Y) :- string(X), string_upper(X, Y).
run(lower, X, Y) :- string(X), string_lower(X, Y).
run(reverse_string, X, Y) :- string(X), string_chars(X, Cs), reverse(Cs, Rs), string_chars(Y, Rs).
run(append_text(K), X, Y) :- string(X), string_concat(X, K, Y).
run(prepend_text(K), X, Y) :- string(X), string_concat(K, X, Y).
run(string_length, X, Y) :- string(X), string_length(X, Y).
run(to_number, X, Y) :- string(X), catch(number_string(Y, X), _, fail).
run(split(K), X, Y) :- string(X), split_string(X, K, "", Y).
run(chars, X, Y) :- string(X), string_chars(X, Y).
run(join(K), X, Y) :- is_list(X), X \== [], catch(atomic_list_concat(X, K, A), _, fail), atom_string(A, Y).
run(to_string, X, Y) :- number(X), number_string(X, Y).

run2(plus, A, B, Y) :- number(A), number(B), Y is A+B.
run2(minus, A, B, Y) :- number(A), number(B), Y is A-B.
run2(times, A, B, Y) :- number(A), number(B), Y is A*B.
run2(max2, A, B, Y) :- number(A), number(B), Y is max(A,B).
run2(min2, A, B, Y) :- number(A), number(B), Y is min(A,B).
run2(append2, A, B, Y) :- is_list(A), is_list(B), append(A, B, Y).
run2(concat2, A, B, Y) :- string(A), string(B), string_concat(A, B, Y).

cond(gt(K), X) :- number(X), X > K.
cond(lt(K), X) :- number(X), X < K.
cond(even, X) :- integer(X), X mod 2 =:= 0.
cond(odd, X) :- integer(X), X mod 2 =:= 1.

run_pipeline([], X, X).
run_pipeline([I|Is], X, Y) :- catch(run(I, X, Z), _, fail), run_pipeline(Is, Z, Y).

% ---------------------------------------------------------------- following instructions

%!	parse_instructions(+Text, -Steps)
%	Steps is a list of steps, each a list of alternative instructions
%	(e.g. "add 1" is add(1) or map(add(1)); the types decide).
parse_instructions(Text0, Steps) :-
	text_to_string(Text0, L),
	split_steps(L, Parts),
	maplist(step_alternatives, Parts, Steps0),
	exclude(==([]), Steps0, Steps).

%	Separators inside "quoted text" (e.g. prepend "Hello, ") don't split.
split_steps(L, Parts) :-
	string_codes(L, Cs),
	quote_segments(Cs, Segs),
	maplist(split_segment, Segs, Marked),
	atomic_list_concat(Marked, '', A1),
	atomic_list_concat(Ps1, '\u0001', A1),
	maplist([P, S]>>( atom_string(P, S0), normalize_space(string(S), S0) ), Ps1, Ps2),
	exclude(==(""), Ps2, Parts).

quote_segments([], []).
quote_segments([Q|Cs], [q([Q|Qs])|Segs]) :-
	( Q == 0'" ; Q == 0'' ), !,
	quoted(Q, Cs, Qs, Rest), quote_segments(Rest, Segs).
quote_segments(Cs, [u(U)|Segs]) :-
	unquoted(Cs, U, Rest), U \== [], quote_segments(Rest, Segs).

quoted(Q, [Q|Rest], [Q], Rest) :- !.
quoted(Q, [C|Cs], [C|Qs], Rest) :- !, quoted(Q, Cs, Qs, Rest).
quoted(_, [], [], []).

unquoted([C|Cs], [C|U], Rest) :- C \== 0'", C \== 0'', !, unquoted(Cs, U, Rest).
unquoted(Rest, [], Rest).

split_segment(q(Cs), A) :- atom_codes(A, Cs).
split_segment(u(Cs), A) :-
	atom_codes(A0, Cs),
	foldl([Sep, X0, X]>>( atomic_list_concat(Xs, Sep, X0), atomic_list_concat(Xs, '\u0001', X) ),
	      [' and then ', ', then ', ' then ', ';', '. ', ', and ', ','], A0, A).

step_alternatives(S, Alts) :-
	tokens(S, Ts),
	findall(I, phrase(instr(I), Ts, _), Is0),
	(   Is0 == [] -> Alts = []
	;   list_to_set(Is0, Is1),
	    findall(Alt, ( member(I, Is1), ( Alt = I ; functor(I, F, _), mappable(F), Alt = map(I) ) ), A0),
	    list_to_set(A0, Alts)
	).

mappable(F) :- s2a2_instruction(T, num-num, _, _), functor(T, F, _), !.
mappable(F) :- s2a2_instruction(T, str-str, _, _), functor(T, F, _), !.

%	Words, numbers and "quoted text".
tokens(S, Ts) :- string_codes(S, Cs), phrase(toks(Ts), Cs).
toks(Ts) --> [C], { code_type(C, space) }, !, toks(Ts).
toks([str(S)|Ts]) --> [Q], { Q == 0'" ; Q == 0'' }, !, qstr(Q, Cs), { string_codes(S, Cs) }, toks(Ts).
toks([N|Ts]) --> num(Cs), { Cs \== [] }, !, { number_codes(N, Cs) }, toks(Ts).
toks([W|Ts]) --> wchars(Cs), { Cs \== [] }, !, { atom_codes(W0, Cs), downcase_atom(W0, W1), stem(W1, W) }, toks(Ts).
toks(Ts) --> [_], !, toks(Ts).
toks([]) --> [].
%	"adds", "squares", "multiplies" ... -> add, square, multiply
stem(W, S) :- stem_(W, S), !.
stem(W, W).
stem_(multiplies, multiply).
stem_(halves, halve).
stem_(W, S) :- atom_concat(S, s, W), atom_length(S, L), L >= 3,
	memberchk(S, [add, square, sum, reverse, sort, double, triple, divide, subtract, negate,
		      count, join, split, keep, filter, remove, drop, append, prepend, uppercase,
		      lowercase, total, increment, decrement, select, order, concatenate]).

qstr(Q, []) --> [Q], !.
qstr(Q, [C|Cs]) --> [C], qstr(Q, Cs).
num([0'-|Ds]) --> "-", digits(Ds), { Ds \== [] }, !.
num(Ds) --> digits(Ds).
digits([D|Ds]) --> [D], { code_type(D, digit) }, !, digits(Ds).
digits([]) --> [].
wchars([C|Cs]) --> [C], { code_type(C, alpha) }, !, wchars(Cs).
wchars([]) --> [].

%	Not greedy: "reverse the string" needs "string" after skipping "the".
skip --> [].
skip --> [W], { filler(W) }, skip.
filler(W) :- memberchk(W, [the, a, an, each, every, all, of, it, list, number, numbers,
			    item, items, element, elements, to, by, from, and, then, value, values,
			    string, text, in, its, with, on, into, at]).

instr(I) --> skip, instr1(I), !.
instr(I) --> [_], instr(I).

instr1(add(N)) --> ( [add] ; [plus] ; [increase] ), skip, [N], { number(N) }.
instr1(add(1)) --> ( [increment] ; [add], skip, [one] ).
instr1(subtract(N)) --> ( [subtract] ; [minus] ; [take], [away] ; [decrease] ), skip, [N], { number(N) }.
instr1(subtract(1)) --> [decrement].
instr1(multiply(N)) --> ( [multiply] ; [times] ), skip, [N], { number(N) }.
instr1(multiply(2)) --> [double].
instr1(multiply(3)) --> [triple].
instr1(divide(N)) --> [divide], skip, [N], { number(N) }.
instr1(divide(2)) --> ( [halve] ; [half] ).
instr1(mod(N)) --> ( [mod] ; [modulo] ; [remainder] ), skip, [N], { number(N) }.
instr1(square) --> ( [square] ; [squared] ).
instr1(negate) --> ( [negate] ; [change], skip, [sign] ).
instr1(absolute) --> ( [absolute] ; [abs] ).
instr1(sum) --> ( [sum] ; [total] ; [add], skip, [up] ; [add], [them] ; [them], [up] ).
instr1(product) --> [product].
instr1(string_length) --> [length], skip, [string].
instr1(length) --> ( [length] ; [count] ; [how], [many] ).
instr1(maximum) --> ( [maximum] ; [max] ; [largest] ; [biggest] ; [greatest] ).
instr1(minimum) --> ( [minimum] ; [min] ; [smallest] ; [least] ).
instr1(tail) --> ( [remove] ; [drop] ), skip, [first].
instr1(first) --> ( [first] ; [head] ).
instr1(last) --> [last].
instr1(reverse_string) --> [reverse], skip, [string].
instr1(reverse) --> ( [reverse] ; [backwards] ).
instr1(unique) --> ( [remove], skip, [duplicates] ; [unique] ; [deduplicate] ).
instr1(sort) --> ( [sort] ; [order] ).
instr1(filter(gt(N))) --> keep, skip, gtw, skip, [N], { number(N) }.
instr1(filter(lt(N))) --> keep, skip, ltw, skip, [N], { number(N) }.
instr1(filter(even)) --> keep, skip, [even].
instr1(filter(odd)) --> keep, skip, [odd].
instr1(upper) --> ( [uppercase] ; [upper], [case] ; [upper] ; [capitalise] ; [capitalize] ).
instr1(lower) --> ( [lowercase] ; [lower], [case] ; [lower] ).
instr1(append_text(S)) --> ( [append] ; [add] ; [end] ), skip, [str(S)].
instr1(prepend_text(S)) --> ( [prepend] ; [start] ; [begin] ), skip, [str(S)].
instr1(to_number) --> [to], [number] ; [convert], skip, [number].
instr1(to_string) --> [to], [string] ; [convert], skip, [string].
instr1(split(" ")) --> [split], skip, [words].
instr1(split(S)) --> [split], skip, [str(S)].
instr1(chars) --> ( [characters] ; [chars] ; [letters] ).
instr1(join(S)) --> [join], skip, [str(S)].
instr1(join("")) --> [join].
instr1(plus) --> [plus] ; [add], skip, [together].
instr1(times) --> [times].
instr1(minus) --> [minus].
instr1(max2) --> [larger] ; [bigger] ; [greater].
instr1(min2) --> [smaller] ; [lesser].
instr1(times) --> [multiply], skip, [together].
instr1(append2) --> [append], skip, [lists].
instr1(concat2) --> [concatenate] ; [join], skip, [strings].

keep --> [keep] ; [filter] ; [select] ; [only] ; [include].
gtw --> ( [greater] ; [more] ; [bigger] ; [larger] ; [above] ; [over] ), opt_than.
ltw --> ( [less] ; [smaller] ; [fewer] ; [below] ; [under] ), opt_than.
opt_than --> [than] -> [] ; [].

%!	s2a2_instructions(+Name, +Text, +Specs, -Code)
s2a2_instructions(Name, Text, Specs, Code) :-
	parse_instructions(Text, Steps),
	Steps \== [],
	spec_arity(Specs, NIn),
	(   NIn =:= 1
	->  choose_steps(Steps, Specs, Pipeline)
	;   Steps = [Alts|Rest], member(B, Alts), binary(B),
	    choose_steps(Rest, [], Post), Pipeline = [B|Post],
	    forall(member([[A1,A2], Y], Specs), ( run2(B, A1, A2, Z), run_pipeline(Post, Z, Y) ))
	),
	generate(Name, Pipeline, Specs, Code).

binary(B) :- memberchk(B, [plus, minus, times, max2, min2, append2, concat2]).

%	Pick one alternative per step so that the types chain and every spec
%	is met.
choose_steps(Steps, Specs, Pipeline) :-
	maplist([Alts, I]>>member(I, Alts), Steps, Pipeline),
	types_chain(Pipeline, _),
	forall(member([[X], Y], Specs), run_pipeline(Pipeline, X, Y)),
	!.

%	types_chain(+Pipeline, ?InType): each step's output fits the next input.
types_chain([], _).
types_chain([I|Is], In) :-
	instr_type(I, In0-Out),
	( var(In) -> In = In0 ; compatible(In, In0) ),
	types_chain(Is, Out).

instr_type(map(I), list-list) :- !, instr_type(I, _).
instr_type(I, T) :- functor(I, F, A), functor(Tm, F, A), s2a2_instruction(Tm, T, _, _), !.

spec_arity([], 1) :- !.
spec_arity([[Ins, _]|_], N) :- length(Ins, N).

% ---------------------------------------------------------------- search

%!	s2a2(+Name, +Specs, -Code)
s2a2(Name, Specs, Code) :- s2a2(Name, Specs, Code, []).

s2a2(Name, Specs, Code, Opts) :-
	Specs \== [],
	( memberchk(max_depth(MD), Opts) -> true ; MD = 3 ),
	MD >= 1,
	spec_arity(Specs, NIn),
	(   NIn =:= 1 -> search1(Specs, MD, P)
	;   NIn =:= 2 -> MD2 is MD-1, search2(Specs, MD2, P)
	),
	generate(Name, P, Specs, Code).

search1(Specs, MD, Pipeline) :-
	ranked_families(Specs, Fam),
	Specs = [[[X0], Y0]|_],
	consts(Specs, Ks),
	between(1, MD, Depth),
	length(Pipeline, Depth),
	pipeline(Pipeline, Fam, Ks, X0, Y0),
	forall(member([[X], Y], Specs), run_pipeline(Pipeline, X, Y)),
	!.

search2(Specs, MD, [B|Post]) :-
	member(B, [plus, minus, times, max2, min2, append2, concat2]),
	Specs = [[[A0,B0], Y0]|_],
	run2(B, A0, B0, Z0),
	consts(Specs, Ks),
	ranked_families(Specs, Fam),
	between(0, MD, D), length(Post, D),
	pipeline(Post, Fam, Ks, Z0, Y0),
	forall(member([[A1,A2], Y], Specs), ( run2(B, A1, A2, Z), run_pipeline(Post, Z, Y) )),
	!.

%	pipeline(-Instrs, +Families, +Consts, +X, +Y): build left to right on
%	the first example, so impossible steps are pruned early.
pipeline([], _, _, X, Y) :- X =@= Y.
pipeline([I|Is], Fam, Ks, X, Y) :-
	member(F, Fam),
	instance_of(F, Ks, X, I),
	catch(run(I, X, Z), _, fail),
	pipeline(Is, Fam, Ks, Z, Y).

instance_of(F, Ks, X, I) :-
	s2a2_instruction(T, _, _, _), functor(T, F, Ar), !,
	(   Ar =:= 0 -> I = F
	;   F == map -> member(F2, [add, subtract, multiply, divide, mod, square, negate, absolute,
				   upper, lower, reverse_string, append_text, prepend_text, to_number, to_string,
				   string_length]),
	    X = [X1|_], instance_of(F2, Ks, X1, I2), I = map(I2)
	;   F == filter -> ( member(K, Ks), number(K), I = filter(gt(K)) ; member(K, Ks), number(K), I = filter(lt(K))
			    ; I = filter(even) ; I = filter(odd) )
	;   memberchk(F, [append_text, prepend_text, split, join]) -> member(K, Ks), string(K), I =.. [F, K]
	;   member(K, Ks), number(K), K =\= 0, I =.. [F, K]
	).

%	Constants worth trying: small numbers, differences and ratios of the
%	examples, and the pieces of text that outputs add to inputs.
consts(Specs, Ks) :-
	findall(K, ( member([Ins, Y], Specs), member(X, Ins), const_from(X, Y, K) ), K0),
	numlist(1, 10, Small),
	append([K0, Small, [" ", ",", "", "-"]], K1),
	list_to_set(K1, Ks).

const_from(X, Y, K) :- number(X), number(Y), ( K is Y-X ; K is X-Y ; X =\= 0, 0 =:= Y mod X, K is Y // X ; Y =\= 0, integer(X), integer(Y), 0 =:= X mod Y, K is X // Y ).
const_from(X, Y, K) :- is_list(X), is_list(Y), X = [A|_], Y = [B|_], number(A), number(B), const_from(A, B, K).
const_from(X, Y, K) :- string(X), string(Y),
	member(T, [=, string_upper, string_lower]), call(T, X, X1),
	( string_concat(X1, K, Y) ; string_concat(K, X1, Y) ), K \== "".
const_from(X, Y, K) :- string(X), is_list(Y), member(Sep, [",", " ", "-", ";", ":"]), sub_string(X, _, _, _, Sep), K = Sep.
const_from(X, Y, K) :- is_list(X), string(Y), member(Sep, [",", " ", "-", ";", ""]), K = Sep.
const_from(X, Y, K) :- number(Y), is_list(X), member(K, X), number(K).

ranked_families(Specs, Ranked) :-
	families(All),
	(   s2a2_mnn(mnn(_, _, Classes, Net)),
	    spec_features(Specs, F)
	->  mnn_rank(Net, F, Classes, R0),
	    include([C]>>memberchk(C, All), R0, Ranked0),
	    subtract(All, Ranked0, Rest), append(Ranked0, Rest, Ranked)
	;   Ranked = All
	).

% ---------------------------------------------------------------- features

feature_names([in_num, in_list, in_str, out_num, out_list, out_str, two_inputs,
	       same_length, shorter, longer, permutation, out_sorted, out_reversed,
	       out_member, out_is_sum, out_is_length, out_greater, out_less,
	       const_diff, const_ratio, out_subset, out_upper, out_lower, out_contains_in,
	       out_square, out_negative]).

spec_features(Specs, Fs) :-
	feature_names(Ns),
	maplist([N, V]>>( catch(feature(N, Specs), _, fail) -> V = 1.0 ; V = 0.0 ), Ns, Fs).

all_ex(Specs, G) :- Specs \== [], forall(member([[X|_], Y], Specs), call(G, X, Y)).

feature(in_num, S) :- all_ex(S, [X,_]>>number(X)).
feature(in_list, S) :- all_ex(S, [X,_]>>is_list(X)).
feature(in_str, S) :- all_ex(S, [X,_]>>string(X)).
feature(out_num, S) :- all_ex(S, [_,Y]>>number(Y)).
feature(out_list, S) :- all_ex(S, [_,Y]>>is_list(Y)).
feature(out_str, S) :- all_ex(S, [_,Y]>>string(Y)).
feature(two_inputs, [[[_,_],_]|_]).
feature(same_length, S) :- all_ex(S, [X,Y]>>( len(X, L), len(Y, L) )).
feature(shorter, S) :- all_ex(S, [X,Y]>>( len(X, L1), len(Y, L2), L2 < L1 )).
feature(longer, S) :- all_ex(S, [X,Y]>>( len(X, L1), len(Y, L2), L2 > L1 )).
feature(permutation, S) :- all_ex(S, [X,Y]>>( is_list(X), is_list(Y), msort(X, M), msort(Y, M) )).
feature(out_sorted, S) :- all_ex(S, [_,Y]>>( is_list(Y), msort(Y, Y) )).
feature(out_reversed, S) :- all_ex(S, [X,Y]>>( is_list(X), reverse(X, Y) )).
feature(out_member, S) :- all_ex(S, [X,Y]>>( is_list(X), memberchk(Y, X) )).
feature(out_is_sum, S) :- all_ex(S, [X,Y]>>( is_list(X), maplist(number, X), sum_list(X, Y) )).
feature(out_is_length, S) :- all_ex(S, [X,Y]>>( is_list(X), length(X, Y) )).
feature(out_greater, S) :- all_ex(S, [X,Y]>>( number(X), number(Y), Y > X )).
feature(out_less, S) :- all_ex(S, [X,Y]>>( number(X), number(Y), Y < X )).
feature(const_diff, S) :- S = [_,_|_], findall(D, ( member([[X|_],Y], S), number(X), number(Y), D is Y-X ), [D0|Ds]), length(Ds, N), N >= 1, maplist(=:=(D0), Ds).
feature(const_ratio, S) :- S = [_,_|_], findall(R, ( member([[X|_],Y], S), number(X), number(Y), X =\= 0, R is Y/X ), [R0|Rs]), Rs \== [], maplist(=:=(R0), Rs).
feature(out_subset, S) :- all_ex(S, [X,Y]>>( is_list(X), is_list(Y), forall(member(E, Y), memberchk(E, X)) )).
feature(out_upper, S) :- all_ex(S, [_,Y]>>( string(Y), string_upper(Y, Y) )).
feature(out_lower, S) :- all_ex(S, [_,Y]>>( string(Y), string_lower(Y, Y) )).
feature(out_contains_in, S) :- all_ex(S, [X,Y]>>( string(X), string(Y), sub_string(Y, _, _, _, X) )).
feature(out_square, S) :- all_ex(S, [X,Y]>>( number(X), number(Y), Y =:= X*X )).
feature(out_negative, S) :- all_ex(S, [_,Y]>>( number(Y), Y < 0 )).

len(X, L) :- is_list(X), !, length(X, L).
len(X, L) :- string(X), string_length(X, L).

% ---------------------------------------------------------------- MNN

%	The MNN is trained on a corpus S2A2 makes itself: run each instruction
%	(and some two-step pipelines) on random inputs, and learn which
%	instruction comes first from the features of the result.
s2a2_mnn(M) :- mnn_cache(M), !.
s2a2_mnn(M) :-
	mnn_file(F), mnn_load(F, M), !,
	assertz(mnn_cache(M)).
s2a2_mnn(M) :-
	s2a2_train, mnn_cache(M).

mnn_file(F) :-
	module_property(lc_s2a2, file(Src)), file_directory_name(Src, D),
	atomic_list_concat([D, '/../data/mnn_s2a2.pl'], F).

s2a2_train :-
	set_random(seed(1)),
	families(Classes),
	feature_names(Fs),
	findall(X-Y, ( corpus_example(Classes, Specs, Y), spec_features(Specs, X) ), Data),
	length(Fs, NIn), length(Classes, NOut),
	mnn_new(NIn, 24, NOut, 7, Net0),
	mnn_train(Net0, Data, 80, 0.05, Net),
	mnn_accuracy(Net, Data, Acc),
	length(Data, ND),
	format(user_error, "S2A2 MNN trained on ~w examples, accuracy ~2f~n", [ND, Acc]),
	M = mnn(s2a2, Fs, Classes, Net),
	retractall(mnn_cache(_)), assertz(mnn_cache(M)),
	mnn_file(File), file_directory_name(File, Dir), make_directory_path(Dir),
	catch(mnn_save(File, M), _, true).

corpus_example(Classes, Specs, Y) :-
	member(T, [add(3), subtract(2), multiply(2), divide(2), mod(3), square, negate, absolute,
		   sum, product, length, maximum, minimum, first, last, reverse, sort, unique, tail,
		   map(add(1)), map(square), map(multiply(3)), filter(gt(2)), filter(even),
		   upper, lower, reverse_string, append_text("!"), prepend_text("Hi "), string_length,
		   to_number, split(","), chars, join("-"), to_string]),
	between(1, 6, _),
	( Post = [] ; T \= map(_), follow_up(T, Post) ),
	findall([[X], Y0], ( between(1, 3, _), random_input(T, X),
			      run_pipeline([T|Post], X, Y0) ), Specs),
	Specs = [_,_|_],
	functor(T, F, _), nth1(Y, Classes, F).

follow_up(T, [sum]) :- s2a2_instruction(T0, list-list, _, _), functor(T0, F, _), functor(T, F, _), !.
follow_up(T, [add(1)]) :- s2a2_instruction(T0, list-num, _, _), functor(T0, F, _), functor(T, F, _), !.

random_input(T, X) :-
	s2a2_instruction(T0, In-_, _, _), functor(T0, F, _), functor(T, F, _), !,
	random_value(In, T, X).
random_value(num, T, X) :- ( T = to_string -> random_between(-20, 99, X) ; random_between(-9, 30, X) ).
random_value(list, T, X) :-
	(   T == join("-") -> X = ["a", "bc", "d"]
	;   random_between(2, 6, N), length(X, N), maplist([E]>>random_between(0, 9, E), X)
	).
random_value(str, T, X) :-
	(   T == to_number -> random_between(1, 999, N), number_string(N, X)
	;   T == split(",") -> random_member(X, ["a,b", "x,y,z", "1,2"])
	;   random_member(X, ["abc", "Hello", "prolog", "Lucian", "ci cd"])
	).

% ---------------------------------------------------------------- code

%!	generate(+Name, +Pipeline, +Specs, -Code)
%	Readable Prolog with the specs as tests, checked before it is returned.
generate(Name, Pipeline, Specs, Code) :-
	spec_arity(Specs, NIn),
	numlist(1, NIn, Is),
	maplist([I, '$VAR'(V)]>>( C is 0'A+I-1, char_code(V, C) ), Is, InVars),
	Next0 is 0'A+NIn,
	(   Pipeline = [B|Post], binary(B)
	->  InVars = [V1, V2], fresh(Next0, Z, N1),
	    binary_goal(B, V1, V2, Z, G0), Goals0 = [G0], Start = Z, Steps = Post
	;   InVars = [Start], N1 = Next0, Goals0 = [], Steps = Pipeline
	),
	foldl(step_code(Name), Steps, Start-N1-[]-[], Out-_-Goals1-Helpers),
	append(Goals0, Goals1, Goals),
	append(InVars, [Out], Args),
	Head =.. [Name|Args],
	goals_body(Goals, Body),
	( Body == true -> Clause = Head ; Clause = (Head :- Body) ),
	tests_text(Name, Specs, Tests),
	maplist([C0, T]>>( tidy_vars(C0, C1), clause_text(C1, T) ), [Clause|Helpers], Texts),
	atomic_list_concat([Tests|Texts], '\n', A),
	atom_string(A, Code),
	verify(Name, Code, NIn).

fresh(N, '$VAR'(V), N1) :- char_code(V, N), N1 is N+1.

step_code(Name, I, In-N0-G0-H0, Out-N-G-H) :-
	fresh(N0, Out, N1),
	instr_code(Name, I, In, Out, N1, N, Gs, Hs, H0),
	append(G0, Gs, G), append(H0, Hs, H).

% instr_code(+Name, +Instr, +In, +Out, +N0, -N, -Goals, -HelperClauses, +HelpersSoFar)
instr_code(_, add(K), X, Y, N, N, [Y is X+K], [], _).
instr_code(_, subtract(K), X, Y, N, N, [Y is X-K], [], _).
instr_code(_, multiply(K), X, Y, N, N, [Y is X*K], [], _).
instr_code(_, divide(K), X, Y, N, N, [Y is X//K], [], _).
instr_code(_, mod(K), X, Y, N, N, [Y is X mod K], [], _).
instr_code(_, square, X, Y, N, N, [Y is X*X], [], _).
instr_code(_, negate, X, Y, N, N, [Y is -X], [], _).
instr_code(_, absolute, X, Y, N, N, [Y is abs(X)], [], _).
instr_code(_, sum, X, Y, N, N, [sum_list(X, Y)], [], _).
instr_code(Name, product, X, Y, N, N, [P], Hs, H0) :-
	helper_name(Name, product, H0, PN), P =.. [PN, X, Y],
	A = '$VAR'('A'), B = '$VAR'('B'), C = '$VAR'('C'), D = '$VAR'('D'),
	H1 =.. [PN, [], 1], H2h =.. [PN, [A|B], C], H2r =.. [PN, B, D],
	Hs = [H1, (H2h :- H2r, C is A*D)].
instr_code(_, length, X, Y, N, N, [length(X, Y)], [], _).
instr_code(_, maximum, X, Y, N, N, [max_list(X, Y)], [], _).
instr_code(_, minimum, X, Y, N, N, [min_list(X, Y)], [], _).
instr_code(_, first, X, Y, N, N, [X = [Y|'$VAR'('_')]], [], _).
instr_code(_, last, X, Y, N, N, [last(X, Y)], [], _).
instr_code(_, reverse, X, Y, N, N, [reverse(X, Y)], [], _).
instr_code(_, sort, X, Y, N, N, [msort(X, Y)], [], _).
instr_code(_, unique, X, Y, N, N, [sort(X, Y)], [], _).
instr_code(_, tail, X, Y, N, N, [X = ['$VAR'('_')|Y]], [], _).
instr_code(Name, map(I), X, Y, N, N, [P], Hs, H0) :-
	helper_name(Name, map, H0, PN), P =.. [PN, X, Y],
	A = '$VAR'('A'), B = '$VAR'('B'), C = '$VAR'('C'), D = '$VAR'('D'),
	instr_code(Name, I, A, C, 0'E, _, Gs, Hs0, H0),
	H1 =.. [PN, [], []], H2h =.. [PN, [A|B], [C|D]], H2r =.. [PN, B, D],
	append(Gs, [H2r], Body), goals_body(Body, BodyT),
	append([H1, (H2h :- BodyT)], Hs0, Hs).
instr_code(Name, filter(Cn), X, Y, N, N, [P], Hs, H0) :-
	helper_name(Name, filter, H0, PN), P =.. [PN, X, Y],
	A = '$VAR'('A'), B = '$VAR'('B'), C = '$VAR'('C'), D = '$VAR'('D'),
	cond_goal(Cn, A, CG),
	H1 =.. [PN, [], []], H2h =.. [PN, [A|B], C], H2r =.. [PN, B, D],
	Hs = [H1, (H2h :- ( CG -> C = [A|D] ; C = D ), H2r)].
instr_code(_, upper, X, Y, N, N, [string_upper(X, Y)], [], _).
instr_code(_, lower, X, Y, N, N, [string_lower(X, Y)], [], _).
instr_code(_, reverse_string, X, Y, N0, N, [string_chars(X, C1), reverse(C1, C2), string_chars(Y, C2)], [], _) :-
	fresh(N0, C1, N1), fresh(N1, C2, N).
instr_code(_, append_text(K), X, Y, N, N, [string_concat(X, K, Y)], [], _).
instr_code(_, prepend_text(K), X, Y, N, N, [string_concat(K, X, Y)], [], _).
instr_code(_, string_length, X, Y, N, N, [string_length(X, Y)], [], _).
instr_code(_, to_number, X, Y, N, N, [number_string(Y, X)], [], _).
instr_code(_, split(K), X, Y, N, N, [split_string(X, K, "", Y)], [], _).
instr_code(_, chars, X, Y, N, N, [string_chars(X, Y)], [], _).
instr_code(_, join(K), X, Y, N0, N, [atomic_list_concat(X, K, A), atom_string(A, Y)], [], _) :- fresh(N0, A, N).
instr_code(_, to_string, X, Y, N, N, [number_string(X, Y)], [], _).

%	Name variables A, B, C, ... in order of first appearance.
tidy_vars(C0, C) :-
	findall(N, ( sub_term(S, C0), compound(S), S = '$VAR'(N), atom(N), N \== '_' ), Ns0),
	list_to_set(Ns0, Ns),
	length(Ns, L), ( L =:= 0 -> Is = [] ; numlist(1, L, Is) ),
	maplist([N, I, N-V]>>( Code is 0'A+I-1, char_code(V, Code) ), Ns, Is, Map),
	rename(C0, Map, C).
rename('$VAR'(N), Map, '$VAR'(V)) :- atom(N), memberchk(N-V, Map), !.
rename(T, _, T) :- \+ compound(T), !.
rename(T, Map, T1) :- T =.. [F|As], maplist([A, B]>>rename(A, Map, B), As, Bs), T1 =.. [F|Bs].

cond_goal(gt(K), A, A > K).
cond_goal(lt(K), A, A < K).
cond_goal(even, A, 0 =:= A mod 2).
cond_goal(odd, A, 1 =:= A mod 2).

binary_goal(plus, A, B, Z, Z is A+B).
binary_goal(minus, A, B, Z, Z is A-B).
binary_goal(times, A, B, Z, Z is A*B).
binary_goal(max2, A, B, Z, Z is max(A,B)).
binary_goal(min2, A, B, Z, Z is min(A,B)).
binary_goal(append2, A, B, Z, append(A, B, Z)).
binary_goal(concat2, A, B, Z, string_concat(A, B, Z)).

helper_name(Name, Kind, H0, PN) :-
	aggregate_all(count, ( member(H, H0), H \= (_ :- _) ), N),
	( N =:= 0 -> format(atom(PN), "~w_~w", [Name, Kind]) ; format(atom(PN), "~w_~w~w", [Name, Kind, N]) ).

tests_text(Name, Specs, Text) :-
	findall(T, ( member([Ins, Y], Specs),
		     append(Ins, ['$VAR'('A')], Args), G =.. [Name|Args],
		     term_text(G, GT), term_text(Y, YT),
		     format(string(T), "%~w.~n%A=~w.", [GT, YT]) ), Ts),
	atomic_list_concat(Ts, '\n', A), atom_string(A, Text).

%	Load the generated code and run its tests: the code is returned only
%	if it is proved against the spec.
verify(Name, Code, NIn) :-
	pl_parse(Code, pl_file(Items, _)),
	findall(G, member(item(clause(_,G),_,_), Items), Cls),
	findall(K, member(item(clause(K,_),_,_), Items), Ks0), sort(Ks0, Ks),
	comment_tests(Items, Ks, Tests),
	NA is NIn+1, memberchk(Name/NA, Ks),
	with_program(Cls, [], "/", [M]>>forall(member(T, Tests), run_test(M, T, pass))).

% ---------------------------------------------------------------- completing files

%!	s2a2_complete(+Text, -NewText, -Report)
%	Predicates with tests but no clauses are written by S2A2 from their
%	tests and added after the tests.
s2a2_complete(Text, NewText, Report) :-
	pl_parse(Text, pl_file(Items, _)),
	findall(K, member(item(clause(K,_),_,_), Items), Def0), sort(Def0, Defined),
	findall(N/A, ( member(item(comment(C),_,_), Items), comment_goal_key(C, N/A) ), Wanted0),
	sort(Wanted0, Wanted),
	subtract(Wanted, Defined, Missing),
	comment_tests(Items, Missing, Tests),
	foldl(complete_one(Tests), Missing, Text-[], NewText-Report).

comment_goal_key(C, N/A) :-
	sub_string(C, 0, 1, _, "%"), sub_string(C, 1, _, 0, S0), normalize_space(string(S), S0),
	catch(term_string(T, S), _, fail), callable(T), T \= (_=_), T \= (_,_),
	functor(T, N, A), A >= 2.

complete_one(Tests, N/A, T0-R0, T-R) :-
	findall([Ins, Y], ( member(test(N/A, G0, bindings([V-Y0])), Tests),
			    unground(G0-Y0, G-Y), G =.. [_|Args], append(Ins, [Out], Args),
			    var(Out), ground(Ins), ground(Y), V \== '' ), Specs),
	(   Specs \== [], s2a2(N, Specs, Code0)
	->  split_string(Code0, "\n", "", Ls),
	    exclude([L]>>sub_string(L, 0, 1, _, "%"), Ls, CodeLs),
	    atomic_list_concat(CodeLs, '\n', CA),
	    format(string(T), "~w~n~w", [T0, CA]),
	    format(string(Msg), "S2A2 wrote ~w/~w from ~w tests:~n~w", [N, A, Specs, CA]),
	    append(R0, [Msg], R)
	;   T = T0,
	    format(string(Msg), "S2A2 could not find instructions for ~w/~w.", [N, A]),
	    append(R0, [Msg], R)
	).
