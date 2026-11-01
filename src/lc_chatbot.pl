% lc_chatbot.pl - a help chatbot that also does things
%
% lc_chat(+Message, -Reply) with Reply = reply(Text, Code).
% It understands plain requests and runs the matching command, so the web
% interface needs only a chat box and a few buttons:
%   "help", "help debug", "what instructions are there"
%   "run tests", "run test 9", "run ci", "set up", "show logs", "undo move"
%   "make sum_squares that squares each number then sums, e.g. [1,2,3] -> 14"
%   "s2a2 add3: 1 -> 4; 5 -> 8"
%   "debug" / "optimise" / "complete" / "what language is this" + code
%   "packs", "languages"

:- module(lc_chatbot, [ lc_chat/2, chat/0 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lc_help).
:- use_module(lc_s2a2).
:- use_module(lc_debug).
:- use_module(lc_optimise).
:- use_module(lc_grammar).
:- use_module(lc_packs).
:- use_module(lc_main).

%!	chat: talk to the chatbot in the terminal ("bye" to stop).
chat :-
	format("Lucian CI/CD 2 chat.  Ask for help, or type bye.~n"),
	repeat,
	format("> "), flush_output,
	read_line_to_string(user_input, L),
	(   ( L == end_of_file ; string_lower(L, "bye") ) -> !
	;   lc_chat(L, reply(T, C)), format("~w~n", [T]), ( C \== "" -> format("~w~n", [C]) ; true ), fail
	).

lc_chat(Msg0, Reply) :-
	text_to_string(Msg0, Msg),
	split_message(Msg, First, Code),
	string_lower(First, Low),
	tokens(Low, Ws),
	(   catch(intent(Ws, Low, First, Code, Reply0), E,
		  ( message_to_codes(E, S), Reply0 = reply(S, "") ))
	->  Reply = Reply0
	;   fallback(Reply)
	).

message_to_codes(E, S) :- format(string(S), "Sorry, that went wrong: ~q", [E]).

%	The first line is the request; the rest (or a ``` block) is code.
split_message(Msg, First, Code) :-
	(   sub_string(Msg, B, _, _, "```")
	->  sub_string(Msg, 0, B, _, First0),
	    S is B+3, sub_string(Msg, S, _, 0, R0),
	    ( sub_string(R0, E, _, _, "```") -> sub_string(R0, 0, E, _, Code0) ; Code0 = R0 ),
	    strip_lang_tag(Code0, Code)
	;   sub_string(Msg, B, _, _, "\n")
	->  sub_string(Msg, 0, B, _, First0), S is B+1, sub_string(Msg, S, _, 0, Code)
	;   First0 = Msg, Code = ""
	),
	normalize_space(string(First), First0).

strip_lang_tag(C0, C) :-
	(   sub_string(C0, B, _, _, "\n"), sub_string(C0, 0, B, _, Tag), \+ sub_string(Tag, _, _, _, " "),
	    \+ sub_string(Tag, _, _, _, "(")
	->  S is B+1, sub_string(C0, S, _, 0, C)
	;   C = C0
	).

tokens(S, Ws) :-
	split_string(S, " \t,.?!:;", " \t,.?!:;", Ws0),
	exclude(==(""), Ws0, Ws1),
	maplist(atom_string, Ws, Ws1).

has(Ws, W) :- memberchk(W, Ws).
has_any(Ws, L) :- member(W, L), memberchk(W, Ws), !.

% ---------------------------------------------------------------- intents

intent(Ws, _, _, "", reply(T, "")) :-
	Ws = [W|_], memberchk(W, [hi, hello, hey, 'g\'day', greetings]), !,
	T = "Hello!  I can run Lucian CI/CD, its tests, and S2A2, and debug or optimise Prolog.  Try: help, run tests, make add3 that adds 3, e.g. 1 -> 4".

intent(Ws, _, _, _, reply(T, "")) :-
	has(Ws, mnn), \+ has(Ws, help), !,
	( has(Ws, repair) ; has(Ws, debug) -> W = repair ; W = s2a2 ),
	mnn_rules(W, R),
	format(string(T), "The ~w MNN, read back as rules (strongest positive influences):~n~w", [W, R]).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [instruction, instructions]), !,
	help_text(instructions, T).

intent(Ws, _, _, _, reply(T, "")) :-
	( has(Ws, help) ; has(Ws, how) ; Ws = [what, can|_] ; has(Ws, explain) ), !,
	(   help_topics(Ts), member(Tp, Ts), topic_word(Tp, W), has(Ws, W)
	->  help_text(Tp, T)
	;   help_text(start, S), help_topics(Ts),
	    format(string(T), "~w~n~nAsk \"help\" with one of: ~w", [S, Ts])
	).

intent(Ws, _, _, Code, reply(T, Fixed)) :-
	has_any(Ws, [debug, fix, repair]), !,
	(   Code == "" -> T = "Paste the Prolog (with tests in comments) on the lines after \"debug\".", Fixed = ""
	;   lc_debug(Code, Report, Fixed), atomic_list_concat(Report, '\n', A), atom_string(A, T)
	).

intent(Ws, _, _, Code, reply(T, New)) :-
	has_any(Ws, [optimise, optimize, faster, speed]), !,
	(   Code == "" -> T = "Paste the Prolog (with passing tests) on the lines after \"optimise\".", New = ""
	;   lc_optimise(Code, Report, New), atomic_list_concat(Report, '\n', A), atom_string(A, T)
	).

intent(Ws, _, _, Code, reply(T, New)) :-
	has_any(Ws, [complete, fill]), Code \== "", !,
	s2a2_complete(Code, New, Report), atomic_list_concat(Report, '\n', A), atom_string(A, T).

intent(Ws, _, _, Code, reply(T, "")) :-
	has_any(Ws, [language, recognise, recognize, detect]), Code \== "", !,
	(   recognise_language(Code, N, S)
	->  format(string(T), "That looks like ~w (evidence score ~w; its grammar description proves the text).", [N, S])
	;   T = "No language description proves that text."
	).

intent(Ws, Low, Orig, _, Reply) :-
	( Ws = [W|_], memberchk(W, [make, write, create, generate, s2a2, build]) ; has(Ws, s2a2) ), !,
	generate_reply(Ws, Low, Orig, Reply).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [run, test, tests]), has_any(Ws, [test, tests]),
	\+ has_any(Ws, [ci, cicd, luciancicd]), !,
	(   member(W, Ws), atom_number(W, N), integer(N)
	->  test_chain(N, Ns),
	    with_output_to(string(Out), ( forall(member(N0, Ns), user:lc_test1(N0, _)), user:lc_test1(N, P) -> true ; P = failed )),
	    last_lines(Out, 12, Tail),
	    format(string(T), "Test ~w ~w.~n~w", [N, P, Tail])
	;   with_output_to(string(Out), ( user:lc_test(NT, S) -> true ; NT = 0, S = 0 )),
	    findall(L, ( split_string(Out, "\n", "", Ls), member(L, Ls), sub_string(L, _, _, _, failed) ), Fs),
	    atomic_list_concat(Fs, '\n', FT),
	    format(string(T), "~w of ~w tests passed.~n~w", [S, NT, FT])
	).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [setup, set]), has_any(Ws, [up, setup, record]), !,
	with_output_to(string(Out), catch(set_up_luciancicd, E, print_message(error, E))),
	format(string(T), "~w", [Out]).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [ci, cd, cicd, luciancicd, integrate, deploy]), \+ has_any(Ws, [help, how, what]), !,
	( has(Ws, i) -> M = i ; M = d ),
	with_output_to(string(Out), ( catch(luciancicd(M), E, print_message(error, E)) -> R = passed ; R = failed )),
	lc_main:lc_logs(Logs),
	( last(Logs, _-_-LT) -> true ; LT = "" ),
	format(string(T), "Lucian CI/CD (mode ~w) ~w.~n~w~n~w", [M, R, LT, Out]).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [log, logs, results, result, failed, last]), !,
	lc_main:lc_logs(Logs),
	(   Logs == [] -> T = "No runs yet in this session.  Older runs are listed at /luciancicd."
	;   findall(S, ( member(St-Status-Txt, Logs),
			 ( Status =:= 0 -> P = "PASSED" ; P = "FAILED" ),
			 last_lines(Txt, 6, Tl),
			 format(string(S), "~w ~w~n~w", [St, P, Tl]) ), Ss),
	    atomic_list_concat(Ss, '\n\n', A), atom_string(A, T)
	).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [undo, move]), !,
	with_output_to(string(T), catch(move_to_repository_or_back, E, print_message(error, E))).

intent(Ws, _, _, _, reply(T, "")) :-
	has_any(Ws, [pack, packs, languages, language]), !,
	help_text(packs, T1), help_text(languages, T2),
	format(string(T), "~w~n~n~w", [T1, T2]).


%	Tests with At_start = false start from the previous test's result.
test_chain(N, Ns) :-
	(   N > 1, catch(user:lc_test0(N, false, _, _, _, _), _, fail)
	->  N1 is N-1, test_chain(N1, Ns0), append(Ns0, [N1], Ns)
	;   Ns = []
	).

topic_word(Tp, Tp).
topic_word(optimise, optimize).
topic_word(s2a2, generate).
topic_word(packs, pack).
topic_word(languages, language).
topic_word(tests, test).
topic_word(ci, integrate).
topic_word(cd, deploy).
topic_word(vfs, files).
topic_word(web, server).

fallback(reply(T, "")) :-
	T = "I'm not sure what you mean.  I can: run tests (\"run test 9\"), run CI/CD (\"run ci\"), show logs, write code (\"make add3 that adds 3, e.g. 1 -> 4\"), debug or optimise code (put it on the next lines), list instructions, or explain (\"help debug\").".

last_lines(S, N, T) :-
	split_string(S, "\n", "", Ls0), exclude(==(""), Ls0, Ls),
	length(Ls, L), Skip is max(0, L-N), length(Pre, Skip), append(Pre, Last, Ls),
	atomic_list_concat(Last, '\n', A), atom_string(A, T).

% ---------------------------------------------------------------- generating code

%	"make NAME that INSTRUCTIONS, e.g. IN -> OUT; IN -> OUT"
%	"s2a2 NAME: IN -> OUT; IN -> OUT"
generate_reply(Ws, _Low, Orig, reply(T, Code)) :-
	name_from(Ws, Name),
	examples(Orig, Specs),
	instructions_part(Orig, Instr),
	(   Instr \== "", s2a2_instructions(Name, Instr, Specs, Code)
	->  format(string(T), "S2A2 followed the instructions \"~w\" and checked the code against its tests:", [Instr])
	;   Specs \== [], s2a2(Name, Specs, Code)
	->  T = "S2A2 found instructions that turn every example input into its output (code checked against the tests):"
	;   Code = "",
	    T = "S2A2 couldn't do that.  Give instructions from \"instructions\" and/or examples like: e.g. [1,2,3] -> 6; [4] -> 4"
	).

name_from(Ws, Name) :-
	(   append(_, [K, N|_], Ws), memberchk(K, [make, write, create, generate, s2a2, called, named, build, predicate]),
	    \+ memberchk(N, [a, an, the, predicate, code, that, to, which, called, named, me, s2a2]),
	    atom_codes(N, [C|_]), code_type(C, lower)
	->  Name = N
	;   Name = generated
	).

instructions_part(S0, I) :-
	(   member(Sep, [" that ", " which ", " to ", " so it ", ": "]), sub_string(S0, B, L, _, Sep)
	->  E is B+L, sub_string(S0, E, _, 0, R)
	;   R = ""
	),
	(   member(X, [", e.g.", " e.g.", "e.g.", ", for example", " for example", ", like ", " examples", ";"]),
	    sub_string(R, B2, _, _, X)
	->  sub_string(R, 0, B2, _, I0)
	;   I0 = R
	),
	(   sub_string(I0, _, _, _, "->") -> I = "" ; normalize_space(string(I), I0) ).

%	Examples "IN -> OUT" separated by ";" (IN may be several arguments).
examples(S, Specs) :-
	(   sub_string(S, B, _, _, "->")
	->  ( member(X, ["e.g.", "for example", "examples", "like", ": "]), sub_string(S, BX, LX, _, X), BX < B
	    -> P is BX+LX, sub_string(S, P, _, 0, R) ; R = S ),
	    split_string(R, ";", " ", Parts),
	    findall([Ins, Out], ( member(Pt, Parts), sub_string(Pt, PB, 2, PA, "->"),
				  sub_string(Pt, 0, PB, _, L0), sub_string(Pt, _, PA, 0, R0),
				  normalize_space(string(L), L0), normalize_space(string(Rt), R0),
				  string_concat("[", L, L1), string_concat(L1, "]", L2),
				  catch(term_string(Ins, L2), _, fail), catch(term_string(Out, Rt), _, fail),
				  ground(Ins-Out) ), Specs)
	;   Specs = []
	).
