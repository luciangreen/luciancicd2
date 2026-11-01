% Language description for c, learnt by Lucian CI/CD 2 (lc_grammar).
% proof/1 holds a certificate (sample, sha1, parse size and depth)
% for every sample the description was proved on.

language(c,[extensions(["c","h"]),line_comment(["//"]),block_comment([["/*","*/"]]),tags(false),void_tags([]),raw_tags([]),strings(["\"","'"]),brackets([["(",")"],["[","]"],["{","}"]]),terminator(";"),keywords(["int","return","sum","include","stdio","printf","main"]),test_marker("test:"),proof([sample(1,b834e93f6151fae1e0bafd9898d88b235feddd98,proof(tokens(95),depth(5),nodes(82))),sample(2,ffa73fb98fe26bbd6c6451b5c894dc185dcfd174,proof(tokens(24),depth(2),nodes(21))),sample(3,'3b5213cec056aac5b0cbe5f069e08067fc071f44',proof(tokens(131),depth(3),nodes(116)))])]).
