% Language description for javascript, learnt by Lucian CI/CD 2 (lc_grammar).
% proof/1 holds a certificate (sample, sha1, parse size and depth)
% for every sample the description was proved on.

language(javascript,[extensions(["js","mjs","cjs"]),line_comment(["//"]),block_comment([["/*","*/"]]),tags(false),void_tags([]),raw_tags([]),strings(["\"","'","`"]),brackets([["(",")"],["[","]"],["{","}"]]),terminator(";"),keywords(["const"]),test_marker("test:"),proof([sample(1,'083e6aef7487f8ffb0aa088c234ad3931f21ebe0',proof(tokens(63),depth(3),nodes(57))),sample(2,ed4c67f6fe9b38e47872e0dc0b899c51f3374432,proof(tokens(84),depth(3),nodes(71)))])]).
