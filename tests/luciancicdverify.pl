% luciancicdverify.pl - the Lucian CI/CD test cases (1-23 unchanged from
% luciancicd), new Virtual File System tests (24-29) and language pack tests
% (30-37).
%
%% lc_test(Total,Score).    run all tests
%% lc_test1(N,Passed).      run test N
%
% lc_test0(N, At_start, Max, CICD, Start_files, End_files):
%   At_start  true - delete the last good version first, false - use the last test's
%   Max       fail_if_greater_than_n_changes1 overrider
%   CICD      i or d - ci (testing) or cd (changing)

lc_test(NTotal,Score) :-
 gh_init(false),
 findall(N,lc_test0(N,_,_,_,_,_),Ns),length(Ns,NTotal),
 nb_setval(lc_quiet,true),
 foldl([N,S0-L0,S1-L1]>>(lc_test1(N,P),(P==passed->S1 is S0+1;S1=S0),append(L0,[[lc_test,N,P]],L1)),
   Ns,0-[],Score-List),
 nb_setval(lc_quiet,false),
 forall(member(L,List),writeln(L)),
 !.

lc_test1(N,Passed) :-
 ((lc_test0(N,At_start,Max,CICD,Start_files,End_files),
   gh_init(At_start),
   catch(luciancicd(At_start,Max,CICD,Start_files,End_files),E,(print_message(error,E),fail)))
  ->(Passed=passed,writeln([lc_test,N,passed]));(Passed=failed,writeln([lc_test,N,failed]))),
 !.

lc_test0(1,true, % true - delete config, false - use last test's config
 7, % fail_if_greater_than_n_changes1 overrider
 i, % i or d - ci (testing) or cd (changing)
% Start_files
[["c/c.pl","%c(A).\n%A=1.\nc(1).\n%d(A).\n%A=1.\nd(A):-A=1."],
["c/main_file.txt","[[\"c.pl\",[[c,1],[d,1]]]]"]],
% End_files
[["c/c.pl","%c(A).\n%A=1.\nc(1).\n%d(A).\n%A=1.\nd(A):-A=1."],
["c/main_file.txt","[[\"c.pl\",[[c,1],[d,1]]]]"]]
).

%/*
lc_test0(2,true,7,i,
[["c/c.pl","%a([a,b,c],[],A).\n%A = [a, b, c].\na([],A,A):-!.\na(A,B,C):-A=[D|E],append(B,[D],F),a(E,F,C),!."],
["c/main_file.txt","[[\"c.pl\",[[a,3]]]]"]],
[["c/c.pl","%a([a,b,c],[],A).\n%A = [a, b, c].\na([],A,A):-!.\na(A,B,C):-A=[D|E],append(B,[D],F),a(E,F,C),!."],
["c/main_file.txt","[[\"c.pl\",[[a,3]]]]"]]
).
%*/

lc_test0(3,true,7,i,
[["c/c.pl","%a(A).\n%A=1.\na(1).\n%b(A).\n%A=1.\nb(1).\n%c(A).\n%A=1.\nc(1)."],
["c/main_file.txt","[[\"c.pl\",[[a,1],[b,1],[c,1]]]]"]],
[["c/c.pl","%a(A).\n%A=1.\na(1).\n%b(A).\n%A=1.\nb(1).\n%c(A).\n%A=1.\nc(1)."],
["c/main_file.txt","[[\"c.pl\",[[a,1],[b,1],[c,1]]]]"]]
).

lc_test0(4,true,7,i,
[["c/a.pl",":-include('b.pl').\n:-include('c.pl').\n%a(A).\n%A=1.\na(1)."],
["c/b.pl","%b(A).\n%A=1.\nb(1)."],
["c/c.pl","%c(A).\n%A=1.\nc(1)."],
["c/main_file.txt","[[\"a.pl\",[[a,1]]],[\"b.pl\",[[b,1]]],[\"c.pl\",[[c,1]]]]"]],
[["c/a.pl",":-include('b.pl').\n:-include('c.pl').\n%a(A).\n%A=1.\na(1)."],
["c/b.pl","%b(A).\n%A=1.\nb(1)."],
["c/c.pl","%c(A).\n%A=1.\nc(1)."],
["c/main_file.txt","[[\"a.pl\",[[a,1]]],[\"b.pl\",[[b,1]]],[\"c.pl\",[[c,1]]]]"]]
).

%*
lc_test0(5,true,7,i,
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A)."],
["e/e.pl","%e(A).\n%A=1.\ne(1)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]],
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A)."],
["e/e.pl","%e(A).\n%A=1.\ne(1)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]]
).
%*
lc_test0(6,true,7,i,
[["c/c.pl","%a(0,A).\n%A=1.\n%a(1,A).\n%A=1.\na(1,1):-!.\na(A,B):-b(A,B).\n%b(0,A).\n%A=1.\nb(A,B):-c(A,B).\n%c(0,A).\n%A=1.\nc(A,B):-C is A+1,a(C,B)."],
["c/main_file.txt","[[\"c.pl\",[[a,2]]]]"]],
[["c/c.pl","%a(0,A).\n%A=1.\n%a(1,A).\n%A=1.\na(1,1):-!.\na(A,B):-b(A,B).\n%b(0,A).\n%A=1.\nb(A,B):-c(A,B).\n%c(0,A).\n%A=1.\nc(A,B):-C is A+1,a(C,B)."],
["c/main_file.txt","[[\"c.pl\",[[a,2]]]]"]]
).
%*
lc_test0(7,true,7,i,
[["c/c.pl","%c(A).\n%A=1.\nc(1).\nc(2)."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]],
[["c/c.pl","%c(A).\n%A=1.\nc(1).\nc(2)."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]]
).

lc_test0(8,true,7,i,
[["c/c.pl","%c(A).\n%A=2.\nc(C):-A=1,B=1,C is A+B."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]],
[["c/c.pl","%c(A).\n%A=2.\nc(C):-A=1,B=1,C is A+B."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]]
).
%*

% Finds A=1,B=2 from A=2,B=2 and A=1,B=1 (test 8).

lc_test0(9,false,16,d,
[["c/c.pl","%c(A).\n%A=3.\nc(C):-A=2,B=2,C is A+B."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]],
[["c/c.pl","%c(A).\n%A=3.\nc(C):-A=1,B=2,C is A+B."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]]
).
%*/

lc_test0(10,true,7,i,
[["c/c.pl","%c1(A).\n%A=1.\nc1(C):-d(C).\n%c2(A).\n%A=2.\nc2(C):-d(C).\n%d(A).\n%A=1.\n%d(A).\n%A=2.\nd(1).\nd(2)."],
["c/main_file.txt","[[\"c.pl\",[[c1,1],[c2,1]]]]"]],
[["c/c.pl","%c1(A).\n%A=1.\nc1(C):-d(C).\n%c2(A).\n%A=2.\nc2(C):-d(C).\n%d(A).\n%A=1.\n%d(A).\n%A=2.\nd(1).\nd(2)."],
["c/main_file.txt","[[\"c.pl\",[[c1,1],[c2,1]]]]"]]
).

lc_test0(11,true,7,i,
[["c/c.pl","%c1(A).\n%A=1.\nc1(1).\n%c1(A).\n%A=2.\nc1(2)."],
["c/main_file.txt","[[\"c.pl\",[[c1,1]]]]"]],
[["c/c.pl","%c1(A).\n%A=1.\nc1(1).\n%c1(A).\n%A=2.\nc1(2)."],
["c/main_file.txt","[[\"c.pl\",[[c1,1]]]]"]]
).

lc_test0(12,true,7,i,
[["c/c.pl","%c(A).\n%A=1.\nc(1):-writeln(1),writeln(1)."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]],
[["c/c.pl","%c(A).\n%A=1.\nc(1):-writeln(1),writeln(1)."],
["c/main_file.txt","[[\"c.pl\",[[c,1]]]]"]]
).

lc_test0(13,true,7,i,
[["c/c.pl","%c1(1,A).\n%A=1.\n%c1(2,A).\n%A=2.\nc1(A,A)."],
["c/main_file.txt","[[\"c.pl\",[[c1,2]]]]"]],
[["c/c.pl","%c1(1,A).\n%A=1.\n%c1(2,A).\n%A=2.\nc1(A,A)."],
["c/main_file.txt","[[\"c.pl\",[[c1,2]]]]"]]
).

lc_test0(14,true,7,i,
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A)."],
["e/e.pl","%e(A).\n%A=1.\ne(A):-f(A).\n%f(A).\n%A=1.\nf(1)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]],
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A)."],
["e/e.pl","%e(A).\n%A=1.\ne(A):-f(A).\n%f(A).\n%A=1.\nf(1)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]]
).

lc_test0(15,true,7,i,
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A).\n%d(A).\n%A=2."],
["e/e.pl","%e(A).\n%A=1.\ne(A):-f(A).\n%f(A).\n%A=1.\nf(1).\n%f(A).\n%A=2.\nf(2)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]],
[["d/d.pl",":-include('../e/e.pl').\n%d(A).\n%A=1.\nd(A):-e(A).\n%d(A).\n%A=2."],
["e/e.pl","%e(A).\n%A=1.\ne(A):-f(A).\n%f(A).\n%A=1.\nf(1).\n%f(A).\n%A=2.\nf(2)."],
["d/main_file.txt","[[\"d.pl\",[[d,1]]]]"],
["e/main_file.txt","[]"]]
).

lc_test0(16,true,7,i,
[["c/c.pl","%d(1,A,2,B).\n%A=1,B=2.\nd(A,A,B,B)."],
["c/main_file.txt","[[\"c.pl\",[[d,4]]]]"]],
[["c/c.pl","%d(1,A,2,B).\n%A=1,B=2.\nd(A,A,B,B)."],
["c/main_file.txt","[[\"c.pl\",[[d,4]]]]"]]
).

lc_test0(17,true,7,i,
[["c/c.pl","%d.\nd."],
["c/main_file.txt","[[\"c.pl\",[[d,0]]]]"]],
[["c/c.pl","%d.\nd."],
["c/main_file.txt","[[\"c.pl\",[[d,0]]]]"]]
).

lc_test0(18,true,7,i,
[["c/c.pl","%d(1).\nd(1)."],
["c/main_file.txt","[[\"c.pl\",[[d,1]]]]"]],
[["c/c.pl","%d(1).\nd(1)."],
["c/main_file.txt","[[\"c.pl\",[[d,1]]]]"]]
).

lc_test0(19,true,7,i,
[["c/c.pl","%not(d).\nd:-false."],
["c/main_file.txt","[[\"c.pl\",[[d,0]]]]"]],
[["c/c.pl","%not(d).\nd:-false."],
["c/main_file.txt","[[\"c.pl\",[[d,0]]]]"]]
).

%/*
lc_test0(20,true,7,i,
[["c/c.pl","%not(d(1)).\nd(1):-false."],
["c/main_file.txt","[[\"c.pl\",[[d,1]]]]"]],
[["c/c.pl","%not(d(1)).\nd(1):-false."],
["c/main_file.txt","[[\"c.pl\",[[d,1]]]]"]]
).
%*/

%/*
lc_test0(21,true,7,i,
[["c/c.pl","%a.\na:-d1(1).\na:-not(d2(1)).\n%d1(A).\n%A=1.\nd1(1).\n%not(d2(1)).\nd2(1):-false."],
["c/main_file.txt","[[\"c.pl\",[[a,0]]]]"]],
[["c/c.pl","%a.\na:-d1(1).\na:-not((d2(1))).\n%d1(A).\n%A=1.\nd1(1).\n%not(d2(1)).\nd2(1):-false."],
["c/main_file.txt","[[\"c.pl\",[[a,0]]]]"]]
).
%*/

lc_test0(22,true,7,i,
[["c/c.pl","%a(A).\n%A=[1].\na(A):-findall(B,b(B),A).\n%b(A).\n%A=1.\nb(1)."],
["c/main_file.txt","[[\"c.pl\",[[a,1]]]]"]],
[["c/c.pl","%a(A).\n%A=[1].\na(A):-findall(B,b(B),A).\n%b(A).\n%A=1.\nb(1)."],
["c/main_file.txt","[[\"c.pl\",[[a,1]]]]"]]
).

lc_test0(23,false,15,d,
[["c/c.pl","%a(A).\n%A=[2,1].\na(A):-findall(B,b(B),A).\n%b(A).\n%A=1.\n%b(A).\n%A=2.\nb(2)."],
["c/main_file.txt","[[\"c.pl\",[[a,1]]]]"]],
[["c/c.pl","%a(A).\n%A=[2,1].\na(A):-findall(B,b(B),A).\n%b(A).\n%A=1.\n%b(A).\n%A=2.\nb(2).\nb(1)."],
["c/main_file.txt","[[\"c.pl\",[[a,1]]]]"]]
).

% ---------------------------------------------------------------------------
% New Virtual File System tests.  Data files live in the VFS beside the code;
% read_file_s/2 and open_file_s/2 read them relative to the repository.

% Reads "A" (a string).
lc_test0(24,true,7,i,
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/a.txt\",A)."],
["c/data/a.txt","A"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]],
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/a.txt\",A)."],
["c/data/a.txt","A"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]]
).

% Reads a compound term.
lc_test0(25,true,7,i,
[["c/c.pl","%vfs_term(A).\n%A=f(a,[b,\"c\"],g(1,X),X).\nvfs_term(A):-open_file_s(\"data/term.txt\",A)."],
["c/data/term.txt","f(a,[b,\"c\"],g(1,Y),Y)."],
["c/main_file.txt","[[\"c.pl\",[[vfs_term,1]]]]"]],
[["c/c.pl","%vfs_term(A).\n%A=f(a,[b,\"c\"],g(1,X),X).\nvfs_term(A):-open_file_s(\"data/term.txt\",A)."],
["c/data/term.txt","f(a,[b,\"c\"],g(1,Y),Y)."],
["c/main_file.txt","[[\"c.pl\",[[vfs_term,1]]]]"]]
).

% Reads a number from a nested folder (luciancicd's disabled test 24).
lc_test0(26,true,7,i,
[["c/c.pl","%vfs_nested(A)\n%A=1\nvfs_nested(A):-exists_file_s(\"data/nested/input.txt\"),read_file_s(\"data/nested/input.txt\",A1),number_string(A,A1)."],
["c/data/nested/input.txt","1"],
["c/main_file.txt","[[\"c.pl\",[[vfs_nested,1]]]]"]],
[["c/c.pl","%vfs_nested(A)\n%A=1\nvfs_nested(A):-exists_file_s(\"data/nested/input.txt\"),read_file_s(\"data/nested/input.txt\",A1),number_string(A,A1)."],
["c/data/nested/input.txt","1"],
["c/main_file.txt","[[\"c.pl\",[[vfs_nested,1]]]]"]]
).

% A ground test with a compound argument (luciancicd's disabled test 25).
lc_test0(27,true,7,i,
[["c/c.pl","%server_api_payload(api_call(\"/luciancicd\",[read_file_s(\"data/server/input.txt\",\"x\")])).\nserver_api_payload(api_call(\"/luciancicd\",[read_file_s(\"data/server/input.txt\",\"x\")])):-read_file_s(\"data/server/input.txt\",\"x\")."],
["c/data/server/input.txt","x"],
["c/main_file.txt","[[\"c.pl\",[[server_api_payload,1]]]]"]],
[["c/c.pl","%server_api_payload(api_call(\"/luciancicd\",[read_file_s(\"data/server/input.txt\",\"x\")])).\nserver_api_payload(api_call(\"/luciancicd\",[read_file_s(\"data/server/input.txt\",\"x\")])):-read_file_s(\"data/server/input.txt\",\"x\")."],
["c/data/server/input.txt","x"],
["c/main_file.txt","[[\"c.pl\",[[server_api_payload,1]]]]"]]
).

% CD with the VFS, set up: reads data/a.txt.
lc_test0(28,true,7,i,
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/a.txt\",A)."],
["c/data/a.txt","A"],
["c/data/b.txt","B"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]],
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/a.txt\",A)."],
["c/data/a.txt","A"],
["c/data/b.txt","B"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]]
).

% CD with the VFS: the new version reads the wrong file; the old read is kept.
lc_test0(29,false,7,d,
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/b.txt\",A)."],
["c/data/a.txt","A"],
["c/data/b.txt","B"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]],
[["c/c.pl","%vfs_string(A).\n%A=\"A\".\nvfs_string(A):-read_file_s(\"data/a.txt\",A)."],
["c/data/a.txt","A"],
["c/data/b.txt","B"],
["c/main_file.txt","[[\"c.pl\",[[vfs_string,1]]]]"]]
).

% Writes made while testing go to a scratch area, not to the result.
lc_test0(30,true,7,i,
[["c/c.pl","%vfs_round_trip(A).\n%A=g(\"A\").\nvfs_round_trip(A):-save_file_s(\"data/out.txt\",g(\"A\")),open_file_s(\"data/out.txt\",A)."],
["c/main_file.txt","[[\"c.pl\",[[vfs_round_trip,1]]]]"]],
[["c/c.pl","%vfs_round_trip(A).\n%A=g(\"A\").\nvfs_round_trip(A):-save_file_s(\"data/out.txt\",g(\"A\")),open_file_s(\"data/out.txt\",A)."],
["c/main_file.txt","[[\"c.pl\",[[vfs_round_trip,1]]]]"]]
).


% ---------------------------------------------------------------------------
% Language pack tests.  Tests are in comments after "test:".  Comment lines
% always come from the new version; other lines are combined as for Prolog.

% C: "// test: ARGS => STDOUT", compiled with gcc.
lc_test0(31,true,7,i,
[["cc/sum.c","// test: 2 3 => 5\n#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) {\n  printf(\"%d\\n\", atoi(argv[1]) + atoi(argv[2]));\n  return 0;\n}"],
["cc/main_file.txt","[]"]],
[["cc/sum.c","// test: 2 3 => 5\n#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) {\n  printf(\"%d\\n\", atoi(argv[1]) + atoi(argv[2]));\n  return 0;\n}"],
["cc/main_file.txt","[]"]]
).

% C, CD: the new version multiplies; the tests need the old sum.
lc_test0(32,false,7,d,
[["cc/sum.c","// test: 2 3 => 5\n// test: 10 5 => 15\n#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) {\n  printf(\"%d\\n\", atoi(argv[1]) * atoi(argv[2]));\n  return 0;\n}"],
["cc/main_file.txt","[]"]],
[["cc/sum.c","// test: 2 3 => 5\n// test: 10 5 => 15\n#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) {\n  printf(\"%d\\n\", atoi(argv[1]) + atoi(argv[2]));\n  return 0;\n}"],
["cc/main_file.txt","[]"]]
).

% JavaScript: "// test: EXPRESSION => VALUE", run with node.
lc_test0(33,true,7,i,
[["js/add.js","// test: add(2,3) => 5\n// test: double([1,2]) => [2,4]\nfunction add(a, b) {\n  return a + b;\n}\nconst double = xs => xs.map(x => x * 2);"],
["js/main_file.txt","[]"]],
[["js/add.js","// test: add(2,3) => 5\n// test: double([1,2]) => [2,4]\nfunction add(a, b) {\n  return a + b;\n}\nconst double = xs => xs.map(x => x * 2);"],
["js/main_file.txt","[]"]]
).

% JavaScript, CD: of two changed lines, only the one the tests allow is kept.
lc_test0(34,false,7,d,
[["js/add.js","// test: add(2,3) => 5\n// test: double([1,2]) => [2,4]\n// test: add(1,1) => 2\nfunction add(a, b) {\n  return a - b;\n}\nconst double = xs => xs.map(x => x + x);"],
["js/main_file.txt","[]"]],
[["js/add.js","// test: add(2,3) => 5\n// test: double([1,2]) => [2,4]\n// test: add(1,1) => 2\nfunction add(a, b) {\n  return a + b;\n}\nconst double = xs => xs.map(x => x + x);"],
["js/main_file.txt","[]"]]
).

% HTML: "valid" is a proof that the tags balance.
lc_test0(35,true,7,i,
[["web/index.html","<html>\n<body>\n<!-- test: valid -->\n<!-- test: contains <h1>Hello</h1> -->\n<h1>Hello</h1>\n<ul>\n<li>a</li>\n</ul>\n</body>\n</html>"],
["web/main_file.txt","[]"]],
[["web/index.html","<html>\n<body>\n<!-- test: valid -->\n<!-- test: contains <h1>Hello</h1> -->\n<h1>Hello</h1>\n<ul>\n<li>a</li>\n</ul>\n</body>\n</html>"],
["web/main_file.txt","[]"]]
).

% HTML, CD: the new heading is kept, the lost </ul> is put back.
lc_test0(36,false,7,d,
[["web/index.html","<html>\n<body>\n<!-- test: valid -->\n<!-- test: contains <h1>Hello there</h1> -->\n<h1>Hello there</h1>\n<ul>\n<li>a</li>\n</body>\n</html>"],
["web/main_file.txt","[]"]],
[["web/index.html","<html>\n<body>\n<!-- test: valid -->\n<!-- test: contains <h1>Hello there</h1> -->\n<h1>Hello there</h1>\n<ul>\n<li>a</li>\n</ul>\n</body>\n</html>"],
["web/main_file.txt","[]"]]
).

% Markdown.
lc_test0(37,true,7,i,
[["md/README.md","# Lucian CI/CD\n<!-- test: valid -->\n<!-- test: heading Lucian CI/CD -->\n\n```\nswipl luciancicd.pl\n```"],
["md/main_file.txt","[]"]],
[["md/README.md","# Lucian CI/CD\n<!-- test: valid -->\n<!-- test: heading Lucian CI/CD -->\n\n```\nswipl luciancicd.pl\n```"],
["md/main_file.txt","[]"]]
).

% Markdown, CD: a new section is kept and the dropped closing fence restored.
lc_test0(38,false,7,d,
[["md/README.md","# Lucian CI/CD\n<!-- test: valid -->\n<!-- test: heading Lucian CI/CD -->\n<!-- test: heading Tests -->\n\n```\nswipl luciancicd.pl\n## Tests\nlc_test(N,S)."],
["md/main_file.txt","[]"]],
[["md/README.md","# Lucian CI/CD\n<!-- test: valid -->\n<!-- test: heading Lucian CI/CD -->\n<!-- test: heading Tests -->\n\n```\nswipl luciancicd.pl\n```\n## Tests\nlc_test(N,S)."],
["md/main_file.txt","[]"]]
).
