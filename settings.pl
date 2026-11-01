% settings.pl - same format as luciancicd's settings.pl

user("luciangreen").

% Note: the following may or may not end in "/".

repositories_paths1([
"../../GitHub2/"
]).

omit_paths1([
"private2"
%"b" % omits GitHub2/b/
]).

output_path1([
"../../GitHub2o/"
]).

fail_if_greater_than_n_changes1(%7
20
).

time_limit(1).

% New in Lucian CI/CD 2: default mode for luciancicd/0:
% d - find a working combination of changes (deployment), i - only test
lc_mode(d).
