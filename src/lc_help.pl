% lc_help.pl - help utility
%
%   help.            topics
%   help(Topic).     e.g. help(instructions), help(tests), help(debug)
% The web chatbot answers from the same text.

:- module(lc_help, [ help/0, help/1, help_text/2, help_topics/1, mnn_rules/2 ]).

:- use_module(library(lists)).
:- use_module(lc_s2a2).
:- use_module(lc_packs).
:- use_module(lc_grammar).
:- use_module(lc_mnn).
:- use_module(lc_debug, [repair_mnn/1]).

%!	mnn_rules(+Which, -Text): an MNN (s2a2 or repair) as readable rules.
mnn_rules(Which, Text) :-
	(   Which == repair -> repair_mnn(mnn(_, Fs, Cs, Net)) ; s2a2_mnn(mnn(_, Fs, Cs, Net)) ),
	mnn_explain(Net, Fs, Cs, Rules),
	findall(S, ( member(R-Ws, Rules), format(string(S), "~q.   % influence ~w", [R, Ws]) ), Ss),
	atomic_list_concat(Ss, '\n', A), atom_string(A, Text).

help_topics([start, tests, ci, cd, vfs, packs, languages, s2a2, instructions, debug,
	     optimise, mnn, web, settings, commands]).

help :-
	help_topics(Ts),
	format("Lucian CI/CD 2.  help(Topic) for one of:~n  ~w~n", [Ts]),
	help_text(start, T), format("~n~w~n", [T]).

help(Topic) :-
	(   help_text(Topic, T) -> format("~w~n", [T])
	;   format("No help on ~w.  Try help.~n", [Topic])
	).

help_text(start,
"Lucian CI/CD 2 tests and integrates Prolog (and C, JavaScript, HTML and
Markdown) repositories.  Tests live in comments.  It finds which changes
since the last good version can be kept so that all tests pass.
  set_up_luciancicd.   record the repositories as the last good version
  luciancicd.          test and integrate changed repositories
  lc_test(N,S).        run the built-in test cases
  luciancicd_server(8000).   web interface and help chatbot at
                       http://localhost:8000/").

help_text(tests,
"Write tests in comments, before or after the predicate:
  %a([a,b,c],[],A).
  %A = [a, b, c].
  %d.                (must succeed)
  %not(d(1)).        (must fail)
A test passes if some answer makes each variable a variant of its value.
Run the test cases with lc_test(Total,Score). or lc_test1(N,Passed).").

help_text(ci,
"luciancicd. finds repositories that changed since the last good version
(Github_lc2, beside the repositories folder) and the repositories that
include them.  Predicates are tested bottom-up (callees first; loops
together).  In mode i only the new version is tested; in mode d (default)
combinations of changes are tried.  The result goes to the output folder;
move_to_repository_or_back. copies it into the repositories (run again to
undo).  Each run writes a log and a diff to lc_logs.").

help_text(cd,
"Combining changes: the old and new versions of each predicate are diffed
goal by goal.  Candidates are tried with all changes first, then omitting
one change, two, ...  So if A=1,B=1 became A=2,B=2 and the test wants
C=A+B=3, Lucian CI/CD 2 keeps A=1,B=2.  If there are more changes than
fail_if_greater_than_n_changes1 (settings.pl), neighbouring changes are
grouped.").

help_text(vfs,
"Everything happens in a virtual file system in memory, so tests are fast
and never touch the disk.  Code under test can read data files of its
repository with read_file_s(Path,String), open_file_s(Path,Term) (reads a
term) and exists_file_s(Path); save_file_s(Path,X) writes to a scratch area
that is discarded after each test.").

help_text(packs, T) :-
	packs(Ps),
	findall(S, ( member(N-Es, Ps), format(string(S), "  ~w: ~w", [N, Es]) ), Ss),
	atomic_list_concat(Ss, '\n', L),
	format(string(T),
"Language packs (src/packs, or add your own in packs/):
~w
Tests are comment lines with test:
  // test: 2 3 => 5                 C: arguments => output (gcc)
  // test: add(2,3) => 5            JavaScript: expression => value (node)
  <!-- test: valid -->              HTML/Markdown: a proof the structure balances
  <!-- test: contains <h1>Hi</h1> -->
Comment lines always come from the new version; other lines are combined
like Prolog goals.", [L]).

help_text(languages, T) :-
	findall(N, language(N, _), Ns),
	format(string(T),
"Language descriptions (languages/*.pl): ~w.
learn_languages_from_samples(SamplesDir, OutDir) learns comment syntax,
strings, brackets, tags, terminators and keywords from sample files.  Each
feature is kept only if every sample can still be parsed (proved); the
proof certificates are saved with the description.
recognise_language(Text, Name, Score) picks the best description for a
file.  A file whose extension no pack claims gets a generic pack if a
learnt description covers its extension.", [Ns]).

help_text(s2a2,
"S2A2 writes Prolog by following instructions.
  s2a2_instructions(sum_squares, \"square each number then sum\", [], Code).
  s2a2(add3, [[[1],4],[[5],8]], Code).        finds the instructions itself
  s2a2_complete(Text, NewText, Report).       writes predicates that have
                                              tests but no clauses
An MNN ranks the instructions to try first.  Code is readable recursive
Prolog with tests in comments, and is run against its tests before it is
returned.  help(instructions) lists the instructions.").

help_text(instructions, T) :-
	findall(S, ( s2a2_instruction(I, In-Out, D, E),
		     format(string(S), "  ~w~t~22|~w -> ~w~t~40|~w  (e.g. ~w)", [I, In, Out, D, E]) ), Ss),
	atomic_list_concat(Ss, '\n', L),
	format(string(T),
"S2A2 instructions (k: a number or \"text\", i: an instruction, c: gt(N), lt(N), even, odd):
~w
Join steps with \"then\" or commas, e.g. \"keep numbers greater than 2 then
double each then reverse\".", [L]).

help_text(debug,
"lc_debug(Text, Report, Fixed) or lc_debug_file(File) repairs failing
tests.  For the lowest failing predicate it uses the proof of the failing
test: for an error, the goal that raised it; for a missing answer, the
first goal that fails; for a wrong answer, algorithmic debugging down the
proof tree, with the tests of called predicates as the oracle.  An MNN
(trained on bugs it planted itself) ranks repairs (swap an operator or
comparison, change a constant, swap goals or arguments, add a base case);
the first repair that passes the tests without breaking others is kept,
else S2A2 rewrites the predicate from its tests.").

help_text(optimise,
"lc_optimise(Text, Report, New) or lc_optimise_file(File) speeds up a tested
program.  Proofs that solve the same sub-goal repeatedly get tabling;
redundant goals are removed; comparisons move earlier.  A change is kept
only if the tests pass in fewer inferences.  It also hints at slow patterns.").

help_text(mnn,
"An MNN is a small neural network written out in Prolog (src/lc_mnn.pl).
S2A2 and lc_debug each train one on examples they generate, cached in
data/.  mnn_explain/4 prints a network as readable rules such as
prefers(reverse) :- feature(permutation), feature(same_length).").

help_text(web,
"luciancicd_server(8000). then open http://localhost:8000/ for the chatbot
and buttons (run tests, run CI/CD, logs, generate, debug, optimise).
http://localhost:8000/luciancicd lists logs and diffs as in luciancicd.
Ask the chatbot things like:
  run test 9
  make sum_squares that squares each number then sums them, e.g. [1,2,3] -> 14
  debug  (then paste code)
  what language is this  (then paste text)").

help_text(settings,
"settings.pl has the same format as luciancicd's: user/1,
repositories_paths1/1, omit_paths1/1, output_path1/1,
fail_if_greater_than_n_changes1/1, time_limit/1, and lc_mode/1 (d or i).").

help_text(commands,
"set_up_luciancicd.  luciancicd.  luciancicd(i).  move_to_repository_or_back.
lc_test(N,S).  lc_test1(N,P).  luciancicd_server(Port).
s2a2/3, s2a2_instructions/4, s2a2_complete/3, lc_debug/3, lc_debug_file/1,
lc_optimise/3, lc_optimise_file/1, learn_language/5, recognise_language/3,
help/0, help/1, lc_chat(Message, Reply).").
