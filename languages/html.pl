% Language description for html, learnt by Lucian CI/CD 2 (lc_grammar).
% proof/1 holds a certificate (sample, sha1, parse size and depth)
% for every sample the description was proved on.

language(html,[extensions(["html","htm"]),line_comment([]),block_comment([["<!--","-->"]]),tags(true),void_tags([br,hr,img,input,link,meta]),raw_tags([script,style]),brackets([["(",")"],["[","]"],["{","}"]]),terminator(none),keywords(["html","body"]),test_marker("test:"),proof([sample(1,'07d6a4c46d64eaf5a83b91a8134bfed019b06527',proof(tokens(32),depth(5),nodes(21))),sample(2,'8ef92ac58d99e3e8f348629f50986c783e9da336',proof(tokens(48),depth(4),nodes(38)))])]).
