/*  run_tests.pl -- unit tests for mnns-typesproofs (no downloads needed: uses tests/toy_kg.txt)
    swipl -g run_tests -t halt tests/run_tests.pl
*/
:- use_module('../prolog/kg').
:- use_module('../prolog/rtp').
:- use_module('../prolog/tuple_guards').
:- use_module(library(plunit)).
:- use_module(library(aggregate)).

setup :- load_kg(toy, all), profile, learn_types, take_snapshot.

% the derivation count of a path by brute force: every (X, Y, Z) with R1(X, Y), R2(Y, Z)
brute(R1, R2, K, D) :-
    aggregate_all(count, ( t(R1, _, Y), t(R2, Y, _) ), D),
    findall(Y, ( t(R1, _, Y), t(R2, Y, _) ), Ys0), sort(Ys0, Ys), length(Ys, K).

:- begin_tests(kg, [setup(setup)]).
test(size) :- kg_size(10, 12, 4).
test(category) :- cat('run.v.01', v), cat('fast.s.01', s).
:- end_tests(kg).

:- begin_tests(paths, [setup(setup)]).
test(path_stats_matches_brute_force, [forall(( kg_relations(Rs), member(R1, Rs), member(R2, Rs) ))]) :-
    path_stats(R1, R2, K, D), brute(R1, R2, K2, D2), K == K2, D == D2.
test(join_count_matches, [forall(( kg_relations(Rs), member(R1, Rs), member(R2, Rs) ))]) :-
    path_stats(R1, R2, _, D), eval_join_count(R1, R2, D1), D =:= D1.
test(exact_prunes_only_empty, [forall(( kg_relations(Rs), member(R1, Rs), member(R2, Rs) ))]) :-
    path_stats(R1, R2, K, _), ( keep(exact, R1, R2) -> K > 0 ; K =:= 0 ).
test(learned_never_loses_on_its_own_graph) :-
    evaluate(learned, yes, S), S.derivations_lost =:= 0, S.wrongly_pruned =:= 0.
test(learned_prunes_similar_then_hypernym) :-          % a>s, s>a cannot meet n>n, v>v
    \+ keep(learned, '_similar_to', '_hypernym').
test(learned_keeps_drf_then_hypernym) :- keep(learned, '_derivationally_related_form', '_hypernym').
test(none_keeps_everything) :- evaluate(none, no, S), S.pruned =:= 0.
test(three_hop_counts) :-
    three_hop(learned, S), S.derivations_lost =:= 0,
    findall(x, ( t(R1, _, Y), t(R2, Y, Z), t(R3, Z, _), atom(R1), atom(R2), atom(R3) ), L), length(L, N),
    S.derivations =:= N.
:- end_tests(paths).

:- begin_tests(types, [setup(setup)]).
test(rtype) :- rtype('_similar_to', P), P == [a-s, s-a].
test(compose) :- compose([a-s, s-a], [a-s, s-a], P), P == [a-a, s-s].
test(closure) :- closure([a-s, s-a], P, R), P == [a-a, a-s, s-a, s-s], R =:= 2.
:- end_tests(types).

:- begin_tests(guards).
test(examples_keep_answers, [forall(( examples(Es), member(Name-P-In, Es) ))]) :-
    delete_implied(P, P1, D), check_on_inputs(P, P1, In, same(_)),
    ( memberchk(Name, [not_implied, no_binding]) -> D == [] ; D = [_] ).
test(forced_deletion_is_caught) :- forced_check(differ(_)).
test(matching_never_binds_the_rule) :-             % one-way: Y must not become c
    R = h(X)-[p(X, Y), q(c), d(X)], copy_term(R, R0),
    \+ implied([d(A)-[p(A, B), q(B)], R], R, _, _), R =@= R0, var(Y).
test(no_self_justification) :-
    \+ implied([g(X)-[g(X)]], h(Y)-[g(Y)], _, _).
:- end_tests(guards).
