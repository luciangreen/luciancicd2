% Language description for prolog, learnt by Lucian CI/CD 2 (lc_grammar).
% proof/1 holds a certificate (sample, sha1, parse size and depth)
% for every sample the description was proved on.

language(prolog,[extensions(["pl","pro","lp"]),line_comment(["%"]),block_comment([["/*","*/"]]),tags(false),void_tags([]),raw_tags([]),strings(["\"","'"]),brackets([["(",")"],["[","]"],["{","}"]]),terminator("."),keywords([]),test_marker("test:"),proof([sample(1,f82a86b957c3aa46f2fd52a077901c52e132d1af,proof(tokens(117),depth(2),nodes(102))),sample(2,c5d636859b70c7adf1724b9f0f58ec4d7bb427ba,proof(tokens(409),depth(7),nodes(340)))])]).
