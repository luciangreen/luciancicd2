% lc_web.pl - the Lucian CI/CD 2 web interface
%
% luciancicd_server(Port) starts it.
%   /             chat with the help chatbot; buttons for the common commands;
%                 a code box for generate / debug / optimise / recognise
%   /luciancicd   logs and diffs, as in luciancicd
%   /api/chat     POST {"message": ...}  ->  {"text": ..., "code": ...}
%   /api/logs     GET  -> [{"time":..., "passed":..., "text":...}]

:- module(lc_web, [ luciancicd_server/1, luciancicd_stop/1 ]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_client)).
:- use_module(library(http/html_write)).
:- use_module(library(lists)).
:- use_module(lc_chatbot).
:- use_module(lc_main).

:- http_handler(root(.), page, []).
:- http_handler(root(luciancicd), logs_page, []).
:- http_handler(root(api/chat), api_chat, [methods([post])]).
:- http_handler(root(api/logs), api_logs, []).

luciancicd_server(Port) :-
	http_server(http_dispatch, [port(Port)]),
	format("Lucian CI/CD 2 at http://localhost:~w/~n", [Port]).

luciancicd_stop(Port) :- http_stop_server(Port, []).

api_chat(Request) :-
	http_read_json_dict(Request, In),
	(   get_dict(message, In, M0) -> true ; M0 = "" ),
	(   get_dict(code, In, C0), C0 \== "" -> format(string(M), "~w~n```~n~w~n```", [M0, C0]) ; M = M0 ),
	lc_chat(M, reply(T, C)),
	reply_json_dict(_{text: T, code: C}).

api_logs(_) :-
	lc_logs(Ls),
	findall(_{time: S, passed: P, text: T}, ( member(S-St-T, Ls), ( St =:= 0 -> P = true ; P = false ) ), Ds),
	reply_json_dict(Ds).

%	Logs and diffs from this session and from lc_logs on disk.
logs_page(_) :-
	lc_logs(Mem),
	findall(S-St-T, member(S-St-T, Mem), L1),
	(   lc_home(H), directory_file_path(H, '../../lc_logs', D0), absolute_file_name(D0, D), exists_directory(D)
	->  directory_files(D, Fs),
	    findall(S-St-T, ( member(F, Fs), atom_concat(log, Rest, F), file_name_extension(S, txt, Rest),
			      directory_file_path(D, F, P), catch(( read_file_to_terms(P, [[St, T]], []) ), _, fail) ), L2)
	;   L2 = []
	),
	append(L1, L2, L), sort(0, @>=, L, Sorted),
	reply_html_page(title('Lucian CI/CD'),
			[ \style, h1('Lucian CI/CD logs'), p(a(href('/'), 'Chat and commands')),
			  \log_items(Sorted) ]).

log_items([]) --> [].
log_items([S-St-T|Ls]) -->
	{ ( St =:= 0 -> C = green, W = 'PASSED' ; C = red, W = 'FAILED' ) },
	html([ h3([span(style('color:~w'-[C]), W), ' - ', S]), pre(T) ]),
	log_items(Ls).

style --> html(style('body{font-family:sans-serif;max-width:60em;margin:auto;background:#ffefe3} pre{background:#fff;padding:.5em;white-space:pre-wrap}')).

page(_) :-
	format("Content-type: text/html; charset=UTF-8~n~n"),
	page_html(H),
	format("~w", [H]).

page_html('<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lucian CI/CD 2</title>
<style>
 body{font-family:system-ui,sans-serif;margin:0;background:#ffefe3;color:#222}
 header{background:#5a3e2b;color:#fff;padding:.8em 1.2em} header h1{margin:0;font-size:1.3em}
 main{display:grid;grid-template-columns:1fr 1fr;gap:1em;padding:1em;max-width:1200px;margin:auto}
 @media(max-width:800px){main{grid-template-columns:1fr}}
 .card{background:#fff;border-radius:10px;padding:1em;box-shadow:0 1px 3px #0002}
 #log{height:55vh;overflow:auto;font-size:.95em}
 .me{text-align:right;color:#5a3e2b;margin:.4em 0} .bot{white-space:pre-wrap;margin:.4em 0 1em}
 .bot pre{background:#f6f1ec;padding:.5em;border-radius:6px;overflow:auto}
 input,textarea{width:100%;box-sizing:border-box;font:inherit;padding:.5em;border:1px solid #caa;border-radius:6px}
 textarea{height:16em;font-family:ui-monospace,monospace;font-size:.9em}
 button{background:#5a3e2b;color:#fff;border:0;border-radius:6px;padding:.45em .8em;margin:.2em .2em .2em 0;cursor:pointer}
 button.alt{background:#a0785a}
</style></head><body>
<header><h1>Lucian CI/CD 2</h1></header>
<main>
<section class="card">
 <div>
  <button onclick="say(\'help\')">Help</button>
  <button onclick="say(\'run tests\')">Run all tests</button>
  <button onclick="say(\'run ci\')">Run CI/CD</button>
  <button onclick="say(\'show logs\')">Logs</button>
  <button onclick="say(\'set up\')" class="alt">Record as last good</button>
  <button onclick="say(\'move to repository or back\')" class="alt">Move result / undo</button>
  <button onclick="say(\'instructions\')" class="alt">S2A2 instructions</button>
  <button onclick="say(\'packs\')" class="alt">Language packs</button>
  <a href="/luciancicd">all logs</a>
 </div>
 <div id="log"></div>
 <form onsubmit="send();return false"><input id="msg" placeholder="Ask me, e.g. run test 9, or make add3 that adds 3, e.g. 1 -> 4" autocomplete="off"></form>
</section>
<section class="card">
 <b>Code</b> (Prolog with tests in comments, or any text)
 <textarea id="code" spellcheck="false">%sum_squares([1,2,3],A).
%A=14.
%sum_squares([2],A).
%A=4.
sum_squares(L,S):-sum_squares_map(L,L2),sum_list(L2,S).
sum_squares_map([],[]).
sum_squares_map([A|B],[C|D]):-C is A+A,sum_squares_map(B,D).</textarea>
 <button onclick="withCode(\'debug\')">Debug</button>
 <button onclick="withCode(\'optimise\')">Optimise</button>
 <button onclick="withCode(\'complete\')">Write missing predicates (S2A2)</button>
 <button onclick="withCode(\'what language is this\')" class="alt">Recognise language</button>
</section>
</main>
<script>
const log=document.getElementById("log");
function esc(s){return s.replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));}
function add(cls,html){const d=document.createElement("div");d.className=cls;d.innerHTML=html;log.appendChild(d);log.scrollTop=log.scrollHeight;return d;}
async function ask(message,code){
  add("me",esc(message));
  const w=add("bot","...");
  try{
    const r=await fetch("/api/chat",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({message,code:code||""})});
    const j=await r.json();
    w.innerHTML=esc(j.text)+(j.code?"<pre>"+esc(j.code)+"</pre>":"");
    if(j.code&&code!==undefined){document.getElementById("code").value=j.code;}
  }catch(e){w.textContent="Error: "+e;}
}
function say(m){ask(m);}
function send(){const i=document.getElementById("msg");if(i.value.trim()){ask(i.value);i.value="";}}
function withCode(m){ask(m,document.getElementById("code").value);}
add("bot","Hello! I am the Lucian CI/CD 2 help chatbot. Ask for help, press a button, or paste code on the right.");
</script></body></html>').
