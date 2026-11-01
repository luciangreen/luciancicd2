% lc_proc.pl - run external tools (compilers, interpreters) for packs,
% with a time limit, in a temporary directory that is removed afterwards.

:- module(lc_proc, [ tool_available/1, run_tool/5, with_tmp_dir/2 ]).

:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(time)).
:- use_module(library(filesex)).

:- meta_predicate with_tmp_dir(-, 0).

tool_available(Exe) :-
	catch(absolute_file_name(path(Exe), _, [access(execute), file_errors(fail)]), _, fail).

%!	run_tool(+Exe, +Args, +Seconds, -Exit, -Output)
%	Exe is a tool on the PATH (atom) or a file path (string).
run_tool(Exe, Args, Secs, Exit, Out) :-
	(   atom(Exe) -> Prog = path(Exe) ; Prog = file(Exe) ),
	process_create(Prog, Args, [stdout(pipe(O)), stderr(pipe(E)), stdin(null), process(Pid)]),
	(   catch(call_with_time_limit(Secs,
		  ( read_string(O, _, Out0), read_string(E, _, Err0) )), time_limit_exceeded,
		  ( process_kill(Pid), Out0 = "", Err0 = "time limit exceeded" ))
	->  true ; Out0 = "", Err0 = "" ),
	close(O, [force(true)]), close(E, [force(true)]),
	process_wait(Pid, Status),
	(   Status = exit(Exit) -> true ; Exit = Status ),
	(   Exit == 0 -> Out = Out0 ; string_concat(Out0, Err0, Out) ).

with_tmp_dir(Dir, Goal) :-
	tmp_file(lc2, Dir0), atom_string(Dir0, Dir),
	make_directory(Dir),
	call_cleanup(Goal, catch(delete_directory_and_contents(Dir), _, true)).
