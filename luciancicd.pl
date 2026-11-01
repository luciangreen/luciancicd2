% luciancicd.pl - Lucian CI/CD 2
%
% A rewrite of Lucian CI/CD (github.com/luciangreen/luciancicd) that keeps
% its commands, settings, test format and test cases, works on terms
% instead of strings, runs entirely in a virtual file system, and adds
% language packs, grammar learning, S2A2 code generation, proof-based
% debugging and optimisation, an MNN, and a help chatbot on the web.
%
% Load with:  swipl luciancicd.pl     then e.g.  lc_test(N,S).   help.

:- set_prolog_flag(double_quotes, string).

:- prolog_load_context(directory, D),
   asserta(user:file_search_path(lc2, D)),
   atom_concat(D, '/src', S), asserta(user:file_search_path(lc2src, S)).

:- use_module(lc2src(lc_vfs)).
:- use_module(lc2src(lc_parse)).
:- use_module(lc2src(lc_tests)).
:- use_module(lc2src(lc_deps)).
:- use_module(lc2src(lc_diff)).
:- use_module(lc2src(lc_grammar)).
:- use_module(lc2src(lc_packs)).
:- use_module(lc2src(lc_engine)).
:- use_module(lc2src(lc_main)).
:- use_module(lc2src(lc_proof)).
:- use_module(lc2src(lc_mnn)).
:- use_module(lc2src(lc_s2a2)).
:- use_module(lc2src(lc_debug)).
:- use_module(lc2src(lc_optimise)).
:- use_module(lc2src(lc_help)).
:- use_module(lc2src(lc_chatbot)).
:- use_module(lc2src(lc_web)).

:- include('settings.pl').
:- include('main.pl').
:- include('tests/luciancicdverify.pl').

% language descriptions (learnt, with proofs) and packs
:- prolog_load_context(directory, D),
   atom_concat(D, '/languages', L), load_languages(L),
   atom_concat(D, '/src/packs', P), load_packs(P),
   atom_concat(D, '/packs', P2), load_packs(P2).
