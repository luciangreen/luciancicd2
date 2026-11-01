% s2a2_benchmark.pl - 200 input/output pairs for S2A2 (50 tasks x 4 pairs).
%
% s2a2_task(Name, Instructions, Pairs): Pairs = [[Inputs, Output], ...] in the
% Specs format of s2a2/3.  Instructions is the same task in English, for
% s2a2_instructions/4 and the chatbot.  The outputs were computed by
% reference implementations, not written by hand.  The last two tasks are
% beyond the current instruction set and are expected to be unsolved (their
% pairs are chosen so that simple numeric coincidences don't fit them).
%
%% s2a2_benchmark.            run both ways and print a score
%% s2a2_benchmark(Results).   [Name-FromExamples-FromInstructions]
%% s2a2_pairs(N).             N = 200

s2a2_task(add5, "add 5",
 [[[1],6],
  [[0],5],
  [[-3],2],
  [[20],25]]).

s2a2_task(sub3, "subtract 3",
 [[[10],7],
  [[3],0],
  [[0],-3],
  [[-2],-5]]).

s2a2_task(triple, "triple",
 [[[2],6],
  [[0],0],
  [[-4],-12],
  [[7],21]]).

s2a2_task(halve, "halve",
 [[[8],4],
  [[9],4],
  [[0],0],
  [[30],15]]).

s2a2_task(square_it, "square",
 [[[3],9],
  [[-2],4],
  [[0],0],
  [[11],121]]).

s2a2_task(negate_it, "negate",
 [[[4],-4],
  [[-7],7],
  [[0],0],
  [[15],-15]]).

s2a2_task(absolute_value, "absolute",
 [[[-5],5],
  [[5],5],
  [[0],0],
  [[-12],12]]).

s2a2_task(mod3, "mod 3",
 [[[7],1],
  [[9],0],
  [[2],2],
  [[13],1]]).

s2a2_task(square_plus1, "square then add 1",
 [[[2],5],
  [[0],1],
  [[-3],10],
  [[5],26]]).

s2a2_task(double_minus4, "double then subtract 4",
 [[[2],0],
  [[5],6],
  [[0],-4],
  [[10],16]]).

s2a2_task(add2_then_square, "add 2 then square",
 [[[1],9],
  [[-2],0],
  [[3],25],
  [[0],4]]).

s2a2_task(list_sum, "sum",
 [[[[1,2,3]],6],
  [[[10]],10],
  [[[]],0],
  [[[4,-4,7]],7]]).

s2a2_task(list_product, "product",
 [[[[1,2,3]],6],
  [[[5]],5],
  [[[2,2,2,2]],16],
  [[[3,0,9]],0]]).

s2a2_task(list_length, "count",
 [[[[a,b,c]],3],
  [[[]],0],
  [[[x]],1],
  [[[1,2,3,4,5]],5]]).

s2a2_task(list_max, "maximum",
 [[[[3,9,2]],9],
  [[[7]],7],
  [[[-1,-5]],-1],
  [[[4,4,1]],4]]).

s2a2_task(list_min, "minimum",
 [[[[3,9,2]],2],
  [[[7]],7],
  [[[-1,-5]],-5],
  [[[4,4,1]],1]]).

s2a2_task(first_item, "first",
 [[[[a,b,c]],a],
  [[[5]],5],
  [[[x,y]],x],
  [[[[1],[2]]],[1]]]).

s2a2_task(last_item, "last",
 [[[[a,b,c]],c],
  [[[5]],5],
  [[[x,y]],y],
  [[[1,2,3,4]],4]]).

s2a2_task(reverse_list, "reverse",
 [[[[1,2,3]],[3,2,1]],
  [[[]],[]],
  [[[a]],[a]],
  [[[x,y,z,w]],[w,z,y,x]]]).

s2a2_task(sort_list, "sort",
 [[[[3,1,2]],[1,2,3]],
  [[[5,5,1]],[1,5,5]],
  [[[]],[]],
  [[[9,-1,4,0]],[-1,0,4,9]]]).

s2a2_task(dedupe, "remove duplicates",
 [[[[3,1,3,2]],[1,2,3]],
  [[[a,a]],[a]],
  [[[]],[]],
  [[[5,4,5,4,1]],[1,4,5]]]).

s2a2_task(drop_first, "remove the first",
 [[[[1,2,3]],[2,3]],
  [[[a]],[]],
  [[[x,y]],[y]],
  [[[4,5,6,7]],[5,6,7]]]).

s2a2_task(double_each, "double each",
 [[[[1,2,3]],[2,4,6]],
  [[[]],[]],
  [[[0,-1]],[0,-2]],
  [[[10]],[20]]]).

s2a2_task(square_each, "square each",
 [[[[1,2,3]],[1,4,9]],
  [[[-2]],[4]],
  [[[]],[]],
  [[[4,5]],[16,25]]]).

s2a2_task(add10_each, "add 10 to each",
 [[[[1,2]],[11,12]],
  [[[0]],[10]],
  [[[]],[]],
  [[[-10,5,7]],[0,15,17]]]).

s2a2_task(keep_big, "keep numbers greater than 5",
 [[[[3,6,9,1]],[6,9]],
  [[[1,2]],[]],
  [[[10]],[10]],
  [[[5,6]],[6]]]).

s2a2_task(keep_small, "keep numbers less than 3",
 [[[[1,5,2,8]],[1,2]],
  [[[4]],[]],
  [[[0,-1]],[0,-1]],
  [[[3,2,3]],[2]]]).

s2a2_task(keep_even, "keep even numbers",
 [[[[1,2,3,4]],[2,4]],
  [[[5,7]],[]],
  [[[0,10]],[0,10]],
  [[[6]],[6]]]).

s2a2_task(keep_odd, "keep odd numbers",
 [[[[1,2,3,4]],[1,3]],
  [[[2,4]],[]],
  [[[7,9]],[7,9]],
  [[[11,12,13]],[11,13]]]).

s2a2_task(sum_of_squares, "square each then sum",
 [[[[1,2,3]],14],
  [[[2]],4],
  [[[]],0],
  [[[3,4]],25]]).

s2a2_task(count_big, "keep numbers greater than 2 then count",
 [[[[1,3,5]],2],
  [[[1,2]],0],
  [[[9,8,7]],3],
  [[[]],0]]).

s2a2_task(sorted_reverse, "sort then reverse",
 [[[[2,3,1]],[3,2,1]],
  [[[5]],[5]],
  [[[1,1,2]],[2,1,1]],
  [[[7,-2,4]],[7,4,-2]]]).

s2a2_task(max_doubled, "maximum then double",
 [[[[1,5,3]],10],
  [[[4]],8],
  [[[-3,-1]],-2],
  [[[10,2]],20]]).

s2a2_task(shout, "uppercase",
 [[["hello"],"HELLO"],
  [["Prolog"],"PROLOG"],
  [[""],""],
  [["ci cd"],"CI CD"]]).

s2a2_task(whisper, "lowercase",
 [[["HELLO"],"hello"],
  [["Prolog"],"prolog"],
  [["ABC def"],"abc def"],
  [[""],""]]).

s2a2_task(reverse_text, "reverse the string",
 [[["abc"],"cba"],
  [["level"],"level"],
  [[""],""],
  [["Lucian"],"naicuL"]]).

s2a2_task(exclaim, "append \"!\"",
 [[["hi"],"hi!"],
  [["wow"],"wow!"],
  [[""],"!"],
  [["Lucian CI/CD"],"Lucian CI/CD!"]]).

s2a2_task(greet, "prepend \"Hello, \"",
 [[["Lucian"],"Hello, Lucian"],
  [["world"],"Hello, world"],
  [[""],"Hello, "],
  [["Prolog"],"Hello, Prolog"]]).

s2a2_task(text_length, "length of the string",
 [[["abc"],3],
  [[""],0],
  [["hello world"],11],
  [["x"],1]]).

s2a2_task(split_commas, "split on \",\"",
 [[["a,b,c"],["a","b","c"]],
  [["x"],["x"]],
  [["1,2"],["1","2"]],
  [[",,"],["","",""]]]).

s2a2_task(words, "split into words",
 [[["the cat sat"],["the","cat","sat"]],
  [["one"],["one"]],
  [["a b"],["a","b"]],
  [["Lucian CI CD"],["Lucian","CI","CD"]]]).

s2a2_task(join_dashes, "join with \"-\"",
 [[[["a","b","c"]],"a-b-c"],
  [[["x"]],"x"],
  [[["2026","11","02"]],"2026-11-02"],
  [[["ci","cd"]],"ci-cd"]]).

s2a2_task(shout_exclaim, "uppercase then append \"!\"",
 [[["hi"],"HI!"],
  [["stop"],"STOP!"],
  [["ok go"],"OK GO!"],
  [[""],"!"]]).

s2a2_task(add_pair, "plus",
 [[[2,3],5],
  [[0,0],0],
  [[-1,5],4],
  [[10,20],30]]).

s2a2_task(times_pair, "times",
 [[[2,3],6],
  [[0,9],0],
  [[-2,4],-8],
  [[7,7],49]]).

s2a2_task(bigger, "larger",
 [[[2,9],9],
  [[5,1],5],
  [[-3,-8],-3],
  [[4,4],4]]).

s2a2_task(join_lists, "append lists",
 [[[[1,2],[3]],[1,2,3]],
  [[[],[a]],[a]],
  [[[x],[]],[x]],
  [[[1],[2,3,4]],[1,2,3,4]]]).

s2a2_task(join_strings, "concatenate",
 [[["ab","cd"],"abcd"],
  [["",""],""],
  [["Lucian ","Green"],"Lucian Green"],
  [["ci","cd"],"cicd"]]).

s2a2_task(is_palindrome_count, "1 if it reads the same backwards, else 0",
 [[["level"],1],
  [["abcde"],0],
  [["noon"],1],
  [["xy"],0]]).

s2a2_task(running_total, "running total",
 [[[[1,2,3]],[1,3,6]],
  [[[5]],[5]],
  [[[]],[]],
  [[[2,2,2,2]],[2,4,6,8]]]).

% ---------------------------------------------------------------- runner

s2a2_pairs(N) :- aggregate_all(sum(L), ( s2a2_task(_, _, Ps), length(Ps, L) ), N).

s2a2_benchmark(Results) :-
	findall(Name-E-I,
		( s2a2_task(Name, Instr, Pairs),
		  ( catch(s2a2(Name, Pairs, _), _, fail) -> E = solved ; E = unsolved ),
		  ( catch(s2a2_instructions(Name, Instr, Pairs, _), _, fail) -> I = solved ; I = unsolved ) ),
		Results).

s2a2_benchmark :-
	s2a2_benchmark(Rs),
	length(Rs, NT), s2a2_pairs(NP),
	aggregate_all(count, member(_-solved-_, Rs), NE),
	aggregate_all(count, member(_-_-solved, Rs), NI),
	aggregate_all(count, ( member(_-E-I, Rs), once(( E == solved ; I == solved )) ), NB),
	forall(member(N-E-I, Rs), format("~w~t~24|examples: ~w~t~44|instructions: ~w~n", [N, E, I])),
	format("~n~w tasks, ~w pairs.  From examples: ~w/~w.  From instructions: ~w/~w.  Either: ~w/~w.~n",
	       [NT, NP, NE, NT, NI, NT, NB, NT]).
