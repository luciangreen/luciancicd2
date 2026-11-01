# Lucian CI/CD 2

A complete rewrite of [Lucian CI/CD](https://github.com/luciangreen/luciancicd) in Prolog. It keeps the commands, settings, test format and test cases of luciancicd. The engine now works on terms instead of strings and runs entirely in a virtual file system. New features:

* language packs for **C, JavaScript, HTML and Markdown**
* **grammar learning**, which saves language descriptions together with proofs
* **S2A2**, which writes code by following instructions
* **automatic debugging and optimisation** of Prolog using proofs and MNNs
* a **help utility and web chatbot** that simplifies the web interface

```
swipl luciancicd.pl
?- lc_test(N, S).          % 38 CI/CD test cases (1-23 from luciancicd)
?- lc_tool_tests(N, S).    % 22 tests of the new tools
?- help.
?- luciancicd_server(8000).   % http://localhost:8000/
```

## Compatible with luciancicd

| luciancicd | Lucian CI/CD 2 |
|---|---|
| `settings.pl` (`repositories_paths1`, `omit_paths1`, `output_path1`, `fail_if_greater_than_n_changes1`, `time_limit`) | same file and format, plus `lc_mode(d)` |
| `main_file.txt` in each repository | same |
| tests in comments: `%c(A).` / `%A=1.`, `%d.`, `%not(d).` | same |
| `set_up_luciancicd.`, `luciancicd.`, `move_to_repository_or_back.` | same |
| `lc_test(NTotal,Score).`, `lc_test1(N,Passed).`, `lc_test0/6` cases | same; tests 1-23 are unchanged |
| `luciancicd_server(8000).`, `/luciancicd` logs page, `lc_logs` log files | same, plus a chat page at `/` |
| `luciancicd(At_start,Max,CICD,Start_files,End_files)` | same |

Test 21 of luciancicd expects the output `not((d2(1)))`. Lucian CI/CD 2 compares Prolog files as terms, with their comments in order, so `not((d2(1)))` and `not(d2(1))` are equal. It also keeps the original text of every unchanged clause, so in practice the output is formatted like the input. This fixes luciancicd's caveat that generated code lost its formatting.

## How it works

The code is in `src/`.

* **`lc_vfs`: Virtual File System.** Repositories, the last good version (the store), the output, and data files read by tests all live in memory. Disk is touched only when loading the repositories and saving the result. This avoids the disk pauses luciancicd worked around, and running the tests never leaves files behind.
* **`lc_parse`: terms, not strings.** A file becomes a list of comments, directives and clauses. Each clause is a ground term whose variables are `'$VAR'(Name)`. Diffing, comparing and rebuilding are plain term operations.
* **`lc_engine`: CI/CD.** It finds the changed repositories and those that include them, and groups Prolog files into programs connected by `include`/`consult`. Then it works bottom-up through the predicates: callees come first, and mutually recursive predicates are handled together. Each group's old and new versions are diffed goal by goal. Combinations of changes are tried with all changes first, then omitting one, then two, and so on, until the group's tests pass. So when `A=1,B=1` became `A=2,B=2` and the test wants `C is A+B` to be 3, it keeps `A=1,B=2` (test 9). With more changes than `fail_if_greater_than_n_changes1`, neighbouring changes are grouped.
* **`lc_tests`: sandbox.** Each candidate is loaded into a temporary module with a time limit. Output is captured, and a file API (`read_file_s/2`, `open_file_s/2`, `save_file_s/2`, `exists_file_s/1`, and luciancicd's `vfs_` names) reads from the VFS.

## Virtual File System tests

Tests 24-30 are new. Data files sit in the VFS beside the code:

* 24 reads `"A"` (a string) with `read_file_s/2`
* 25 reads a compound term `f(a,[b,"c"],g(1,Y),Y)` with `open_file_s/2`; the shared variable is checked as a variant
* 26 and 27 are luciancicd's disabled tests 24 (nested folder) and 25 (compound ground test), now enabled
* 28 and 29 cover CD with the VFS: the new version reads the wrong file, and the old read is kept
* 30 writes to the scratch area during a test; the write doesn't appear in the result

## Language packs

Tests 31-38 cover the packs. Tests are comment lines containing `test:`. Comment lines always come from the new version; other lines are combined like Prolog goals.

```c
// test: 2 3 => 5                      C: arguments => output (compiled with gcc)
```
```js
// test: add(2,3) => 5                 JavaScript: expression => value (node)
```
```html
<!-- test: valid -->                   HTML/Markdown: a proof that tags/fences balance
<!-- test: contains <h1>Hello</h1> -->
```

The packs are in `src/packs/`. To add one, drop a file defining `lc_packs:pack_def/2` and `lc_packs:pack_run/5` into `packs/`.

## Recognising grammars and saving language descriptions with proofs

`lc_grammar` learns a language description from sample files. The description covers comment markers, block comments, string delimiters, brackets, markup tags (void and raw), terminators and keywords. Each feature is a hypothesis, and it is kept only if every sample can still be parsed. The parse tree is the proof, and a certificate is saved with the description: the sample's SHA-1, the number of tokens and the parse depth.

```prolog
?- learn_languages_from_samples('languages/samples', 'languages').
?- recognise_language("<ul><li>a</li></ul>", Name, Score).   % Name = html
```

For example, `'` is rejected as a string delimiter for Markdown because "it's" would leave a string open. The descriptions in `languages/` were learnt from `languages/samples/`. A file with an unknown extension that a learnt description covers gets a generic pack.

## S2A2: code produced by following instructions

S2A2 has a typed instruction vocabulary; `help(instructions).` lists it. It covers numbers, lists, strings, `map`, `filter`, `join`, `split` and two-input instructions. Generated code is readable recursive Prolog with luciancicd test comments. It is loaded and run against those tests before it is returned.

```prolog
?- s2a2_instructions(g, "keep numbers greater than 2 then double each then reverse", [], C).
g(A,B):-g_filter(A,C),g_map1(C,D),reverse(D,B).
g_filter([],[]).
g_filter([A|B],C):-(A>2->C=[A|D];C=D),g_filter(B,D).
g_map1([],[]).
g_map1([A|B],[C|D]):-C is A*2,g_map1(B,D).

?- s2a2(shout, [[["hi"],"HI!"], [["yo"],"YO!"]], C).      % finds the instructions itself
shout(A,B):-string_upper(A,C),string_concat(C,"!",B).
```

* Without instructions, it searches pipelines of up to three instructions. Constants are taken from the examples, and an MNN ranks which instruction to try first.
* `s2a2_complete(Text, New, Report)` writes every predicate that has tests but no clauses.
* `tests/s2a2_benchmark.pl` has 200 input/output pairs (50 tasks × 4) with English instructions; `s2a2_benchmark.` scores S2A2 both from the examples and from the instructions.

## Automatic debugging with proofs and MNNs

`lc_proof` is a meta-interpreter that returns proof trees and handles cut exactly. `lc_debug(Text, Report, Fixed)` (or `lc_debug_file(File)`) works on the lowest failing predicate:

1. **It diagnoses the failure from the proof:**
   * an error: the goal that raised it
   * a missing answer: the first failing goal of the clause that fits the intended answer
   * a wrong answer: algorithmic debugging down the proof tree, with the tests of the called predicates as the oracle
2. **An MNN ranks the kinds of repair:** operator swap, comparison swap, constant, goal order, argument order, base case, deleting a goal. The MNN was trained on bugs the system planted in correct programs itself.
3. **Repairs are tried** at the diagnosed clause first, then in untested predicates it calls. The first repair that passes the tests without breaking others is kept. If none works, S2A2 rewrites the predicate from its tests.

```
Failing: ss([1,2,3],A) -> A=14 (fail(no_matching_solution)).
Diagnosis (from the proof): wrong_answer in ss/2, clause 1 got [12-14].
Repair (op_swap in m/2, called by ss/2 and without tests of its own; ...):
  m([A|B],[C|D]):-C is A+A,m(B,D).  ->  m([A|B],[C|D]):-C is A*A,m(B,D).
All 1 tests pass.
```

## Optimising with proofs

`lc_optimise(Text, Report, New)` (or `lc_optimise_file(File)`) makes these changes:

* adds `:- table p/n.` where proofs solve the same sub-goal again and again (naive Fibonacci: 47,821 → 913 inferences)
* removes redundant goals
* moves comparisons and type tests earlier

A change is kept only if the tests pass in fewer *measured* inferences. It also reports hints for slow patterns, such as `append/3` to add one item in a loop.

## MNN

An MNN is a small manual neural network written in pure Prolog (`lc_mnn`): one hidden tanh layer and a softmax output, trained with SGD. Weights are cached in `data/`. `mnn_rules(s2a2, R)` reads a network back as Prolog rules, in the spirit of reverse-engineering networks into code:

```
prefers(add):-feature(const_diff),feature(out_greater),feature(out_sorted).
prefers(square):-feature(out_square),feature(out_greater),feature(same_length).
```

## Help utility and web chatbot

`help.` and `help(Topic).` cover start, tests, ci, cd, vfs, packs, languages, s2a2, instructions, debug, optimise, mnn, web, settings and commands. `chat.` talks in the terminal.

`luciancicd_server(8000).` serves a single page with a chatbot, buttons and a code box:

* **Buttons:** Help, Run all tests, Run CI/CD, Logs, Record as last good, Move result / undo, S2A2 instructions, Language packs
* **Code box:** Debug, Optimise, Write missing predicates, Recognise language

The chatbot understands requests such as:

* `run test 9` (it replays test 8 first)
* `run ci`
* `make sum_squares that squares each number then sums them, e.g. [1,2,3] -> 14`
* `s2a2 add3: 1 -> 4; 5 -> 8`
* `help debug`, `what instructions are there`, `show the repair mnn`

The API is `POST /api/chat {"message","code"}` and `GET /api/logs`. `/luciancicd` lists logs and diffs, as in luciancicd.

## Installing

Install [SWI-Prolog](https://www.swi-prolog.org/) 9. Optionally install `gcc` and `node` for the C and JavaScript packs; without them, those packs fall back to `valid`/`contains` tests. Then clone this repository and run `swipl luciancicd.pl`. It has no other dependencies.

To use it on your repositories, put them in the folder named in `settings.pl` (default `../../GitHub2/`), each with a `main_file.txt`. Run `set_up_luciancicd.` once, then `luciancicd.` after changes. The last good version is kept in `Github_lc2` beside the repositories, and logs go to `../../lc_logs/`.

## Files

```
luciancicd.pl            loader          settings.pl   main.pl
src/lc_vfs.pl            virtual file system
src/lc_parse.pl          Prolog text <-> ground terms, layout-preserving
src/lc_tests.pl          tests in comments, sandbox
src/lc_deps.pl           call graph, includes, bottom-up groups
src/lc_diff.pl           LCS diff, combinations of changes
src/lc_engine.pl         CI/CD engine
src/lc_main.pl           luciancicd commands, logs, disk mode, test entry point
src/lc_packs.pl          language packs (src/packs/: c, javascript, html, markdown)
src/lc_grammar.pl        grammar learning, proofs, recognition
src/lc_proof.pl          proof trees
src/lc_mnn.pl            MNN
src/lc_s2a2.pl           S2A2
src/lc_debug.pl          automatic debugging
src/lc_optimise.pl       optimisation
src/lc_help.pl           help utility
src/lc_chatbot.pl        chatbot
src/lc_web.pl            web interface
languages/               learnt language descriptions (+ samples/)
data/                    MNN weights
tests/                   luciancicdverify.pl (CI/CD cases), test_tools.pl
```

## Authors

Lucian Green - Lucian CI/CD - [Lucian Academy](https://www.lucianacademy.com/). Rewritten as Lucian CI/CD 2 with Claude.

## License

BSD 3-Clause; see [LICENSE](LICENSE).
