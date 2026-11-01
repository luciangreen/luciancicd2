% Language description for markdown, learnt by Lucian CI/CD 2 (lc_grammar).
% proof/1 holds a certificate (sample, sha1, parse size and depth)
% for every sample the description was proved on.

language(markdown,[extensions(["md","markdown"]),line_comment([]),block_comment([["<!--","-->"]]),tags(false),void_tags([]),raw_tags([]),brackets([["(",")"],["[","]"],["{","}"]]),terminator("."),keywords([]),test_marker("test:"),proof([sample(1,'359e9ff0c3dbbb1474edd185238ee314019782cf',proof(tokens(79),depth(1),nodes(75))),sample(2,c32b15c915f13c71ebbd0d8a71de9db57afe4c66,proof(tokens(43),depth(1),nodes(40)))])]).
