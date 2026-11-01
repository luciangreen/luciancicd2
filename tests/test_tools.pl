% test_tools.pl - tests for the tools added in Lucian CI/CD 2:
% S2A2, the debugger, the optimiser, grammars and the chatbot.
%
%% lc_tool_tests(Total,Score).

lc_tool_tests(NTotal, Score) :-
	findall(N, tool_test(N, _, _), Ns), length(Ns, NTotal),
	nb_setval(lc_quiet, true),
	foldl([N, S0, S]>>( tool_test(N, Name, G),
			    ( catch(G, E, (print_message(error, E), fail)) -> R = passed, S is S0+1 ; R = failed, S = S0 ),
			    format("[tool_test,~w,~w,~w]~n", [N, Name, R]) ), Ns, 0, Score),
	nb_setval(lc_quiet, false).

tool_test(1, s2a2_search_map_sum,
	( s2a2(sum_squares, [[[[1,2,3]],14], [[[2]],4]], C), sub_string(C, _, _, _, "C is A*A") )).
tool_test(2, s2a2_search_strings,
	( s2a2(shout, [[["hi"],"HI!"], [["yo"],"YO!"]], C), sub_string(C, _, _, _, "string_upper") )).
tool_test(3, s2a2_two_inputs,
	( s2a2(plus2, [[[2,3],5], [[1,1],2]], C), sub_string(C, _, _, _, "C is A+B") )).
tool_test(4, s2a2_follow_instructions,
	( s2a2_instructions(g, "keep numbers greater than 2 then double each then reverse", [[[[1,3,4]],[8,6]]], C),
	  sub_string(C, _, _, _, "reverse") )).
tool_test(5, s2a2_complete_missing_predicate,
	( s2a2_complete("%inc([1,2],A).\n%A=[2,3].\n%inc([5],A).\n%A=[6].\n", T, _), sub_string(T, _, _, _, "inc(") )).
tool_test(6, debug_operator,
	( lc_debug("%c(A).\n%A=3.\nc(C):-A=1,B=2,C is A-B.", _, F), sub_string(F, _, _, _, "C is A+B") )).
tool_test(7, debug_base_case,
	( lc_debug("%f(3,A).\n%A=6.\n%f(0,A).\n%A=1.\nf(N,F):-N1 is N-1,f(N1,F1),F is N*F1.", _, F),
	  sub_string(F, _, _, _, "f(0,1).") )).
tool_test(8, debug_goal_order,
	( lc_debug("%count([a,b,c],A).\n%A=3.\ncount([],0).\ncount([_|T],N):-N is N0+1,count(T,N0).", _, F),
	  sub_string(F, _, _, _, "count(T,N0),N is N0+1") )).
tool_test(9, debug_untested_helper,
	( lc_debug("%ss([1,2,3],A).\n%A=14.\nss(L,S):-m(L,L2),sum_list(L2,S).\nm([],[]).\nm([A|B],[C|D]):-C is A+A,m(B,D).", _, F),
	  sub_string(F, _, _, _, "C is A*A") )).
tool_test(10, optimise_tabling,
	( lc_optimise("%fib(15,A).\n%A=610.\nfib(0,0).\nfib(1,1).\nfib(N,F):-N>1,N1 is N-1,N2 is N-2,fib(N1,F1),fib(N2,F2),F is F1+F2.", _, N),
	  sub_string(N, _, _, _, ":- table fib/2.") )).
tool_test(11, optimise_hoist,
	( lc_optimise("%pos([3,-1,4,-5],A).\n%A=[3,4].\npos([],[]).\npos([H|T],R):-pos(T,R0),H>0,R=[H|R0].\npos([H|T],R):-pos(T,R),H=<0.", _, N),
	  sub_string(N, _, _, _, "H>0,pos(T,R0)") )).
tool_test(12, recognise_c,
	( recognise_language("#include <stdio.h>\nint main(void) { printf(\"hi\"); return 0; }", c, _) )).
tool_test(13, recognise_html,
	( recognise_language("<html><body><h1>Hi</h1></body></html>", html, _) )).
tool_test(14, proof_rejects_unbalanced_html,
	( language(html, D), \+ prove_text(D, "<ul><li>a</ul></div>", _) )).
tool_test(15, learn_a_language,
	( learn_language(toy, ["; a comment\n(define x 1)", "(print \"hi\") ; done"], ["toy"], [], D),
	  memberchk(line_comment([";"]), D), memberchk(brackets(Bs), D), memberchk(["(", ")"], Bs) )).
tool_test(16, chatbot_generates,
	( lc_chat("make add3 that adds 3, e.g. 1 -> 4; 5 -> 8", reply(_, C)), sub_string(C, _, _, _, "B is A+3") )).
tool_test(17, chatbot_help,
	( lc_chat("help vfs", reply(T, _)), sub_string(T, _, _, _, "read_file_s") )).
tool_test(18, mnn_rules_readable,
	( mnn_rules(s2a2, R), sub_string(R, _, _, _, "prefers(") )).
