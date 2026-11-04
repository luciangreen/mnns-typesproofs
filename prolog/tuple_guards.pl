/*  tuple_guards.pl -- delete guards that the rest of a rule body already guarantees,
    including guards on two or more arguments at once (tuple guards).

    A GUARD is a body literal that only checks something, e.g. a type check:
        trip(X, Z) :- road(X, Y), link(X, Y), road(Y, Z).
    Here link(X, Y) is a guard on the pair (X, Y). If link is defined by
        link(X, Y) :- road(X, Y).
    then whenever road(X, Y) holds, link(X, Y) holds too: the guard is IMPLIED and can be
    deleted without changing any answer, for every set of input facts.

    The test (implied/4): the guard G is implied by the other literals of the body when some
    clause defining G's predicate, renamed, has a head that matches G and a body whose every
    literal matches one of the other literals of the rule. Matching is one-way: it is done
    against a frozen copy of the rule (its variables made into constants), so only the
    defining clause's variables are filled in, never the rule's. Then any facts that make the
    rest of the rule true also make that clause's body true, so the clause proves G.

    This extends s2a2's types:implied_guard/4, which handles one-argument (unary) type
    guards through proved slot inclusions. A tuple guard relates arguments to each other
    (a relational type), which a set of slot types cannot express.

    Each deletion is also checked on data (check_on_inputs/4): the program before and after
    is run bottom-up on many random sets of input facts and the answers must be equal.

    Programs are lists of clauses Head-BodyList; facts have the body [].
*/
:- module(tuple_guards, [implied/4, delete_implied/3, least_model/2, check_on_inputs/4, examples/1,
                         run_examples/0, guards_table/0, forced_check/1]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(ordsets)).

% implied(+Program, +Rule, -Guard, -Why): Guard is a body literal of Rule (Head-Body)
% implied by the other body literals; Why is the defining clause used, as it matched.
implied(Prog, _H-Body, G, by(DefHead-DefBody)) :-
    select(G, Body, Rest),
    \+ G = (\+ _),
    term_variables(Rest, RV), term_variables(G, GV), subset_eq(GV, RV),   % the guard binds nothing
    % freeze a copy of the rule: its variables become constants, so matching can only fill
    % in the defining clause's variables (one-way), never bind or merge the rule's own
    copy_term(G-Rest, G1-Rest1), numbervars(G1-Rest1, 0, _),
    functor(G, P, N), functor(DH0, P, N),
    member(DH0-DB0, Prog), DB0 \== [],
    copy_term(DH0-DB0, DH-DB),
    DH = G1,
    match_all(DB, Rest1), !,
    DefHead-DefBody = DH-DB.

% every literal of the defining body matches some literal of the (frozen) rest of the rule;
% two of them may match the same literal
match_all([], _).
match_all([L|Ls], Rest) :- member(R, Rest), L = R, match_all(Ls, Rest).

subset_eq([], _).
subset_eq([V|Vs], Ws) :- member(W, Ws), W == V, !, subset_eq(Vs, Ws).

% delete_implied(+Prog, -NewProg, -Deleted): delete implied guards one at a time until none
% is left (a guard is never used to justify itself, and each deletion is re-checked on the
% current, shorter body)
delete_implied(Prog, New, Deleted) :- del_(Prog, Prog, New, [], Deleted).
del_([], Acc0, Acc, D, D) :- Acc = Acc0.
del_([C|Cs], Acc0, Acc, D0, D) :-
    (   C = H-B, B \== [], implied(Acc0, C, G, Why)
    ->  exclude(==(G), B, B1), replace_clause(Acc0, C, H-B1, Acc1),
        copy_term(C-G-Why, Shown), del_([H-B1|Cs], Acc1, Acc, [Shown|D0], D)
    ;   del_(Cs, Acc0, Acc, D0, D) ).
replace_clause([], _, _, []).
replace_clause([C0|Cs], C, N, [X|Xs]) :- ( C0 == C -> X = N, Xs = Cs ; X = C0, replace_clause(Cs, C, N, Xs) ).

% ---------------------------------------------------------------- bottom-up evaluation
% least_model(+Prog, -Atoms): apply the rules until nothing new is found (positive
% programs; enough for the guards studied here)
least_model(Prog, M) :-
    include([_-B]>>(B == []), Prog, Fs), maplist([H-_, H]>>true, Fs, M0), sort(M0, S0),
    exclude([_-B]>>(B == []), Prog, Rules),
    lm_(Rules, S0, M).
lm_(Rules, S0, M) :-
    findall(H, ( member(R, Rules), copy_term(R, H-B), body_true(B, S0) ), New0), sort(New0, New),
    ord_union(S0, New, S1),
    ( S1 == S0 -> M = S0 ; lm_(Rules, S1, M) ).
body_true([], _).
body_true([L|Ls], S) :- member(L, S), body_true(Ls, S).

% check_on_inputs(+Prog, +NewProg, +Inputs, -Result): Inputs is input(Preds, Constants, Trials);
% each trial draws a random set of input facts over the given predicates and constants,
% adds them to both programs and compares the least models. Result is
% same(Trials) or differ(Facts) with the first input set where they differ.
check_on_inputs(P0, P1, input(Preds, Consts, Trials), Result) :-
    set_random(seed(42)),
    (   between(1, Trials, _), random_facts(Preds, Consts, Fs),
        maplist([F, F-[]]>>true, Fs, FC), append(FC, P0, Q0), append(FC, P1, Q1),
        least_model(Q0, M0), least_model(Q1, M1), M0 \== M1
    ->  Result = differ(Fs)
    ;   Result = same(Trials) ).
random_facts(Preds, Consts, Fs) :-
    findall(G, ( member(P/N, Preds), length(As, N), maplist([A]>>member(A, Consts), As), G =.. [P|As], random(R), R < 0.35 ), Fs).

% ---------------------------------------------------------------- examples
% examples(-List): name-program-inputs, used by the tests and by the results table
examples([
    % a two-argument guard implied by one clause of its definition
    trip - [ link(X1, Y1)-[road(X1, Y1)], link(X2, Y2)-[rail(X2, Y2)],
             trip(X, Z)-[road(X, Y), link(X, Y), road(Y, Z)] ]
         - input([road/2, rail/2], [a, b, c], 300),
    % the same guard after rail: implied by the second clause
    trip_rail - [ link(X1, Y1)-[road(X1, Y1)], link(X2, Y2)-[rail(X2, Y2)],
                  trip(X, Z)-[rail(X, Y), link(X, Y), road(Y, Z)] ]
              - input([road/2, rail/2], [a, b, c], 300),
    % NOT implied: the guard asks for road, the body only has rail the other way round
    not_implied - [ link(X1, Y1)-[road(X1, Y1)],
                    trip(X, Z)-[rail(Y, X), link(X, Y), road(Y, Z)] ]
                - input([road/2, rail/2], [a, b, c], 300),
    % a relational type used as a guard: rt holds for the pairs a hyp-then-drf path can join
    relational_type - [ rt(X1, Z1)-[hyp(X1, Y1), drf(Y1, Z1)],
                        ans(X, Z)-[hyp(X, Y), drf(Y, Z), rt(X, Z)] ]
                    - input([hyp/2, drf/2], [a, b, c], 300),
    % a unary type guard (the case s2a2 already handles)
    unary - [ person(X1)-[parent(X1, _)],
              grand(X, Z)-[parent(X, Y), parent(Y, Z), person(X)] ]
          - input([parent/2], [a, b, c], 300),
    % a match that would have to bind the rule's own variable Y to c: NOT implied
    no_binding - [ d(A2)-[p(A2, B2), q(B2)],
                   h(X)-[p(X, Y), q(c), d(X)] ]
               - input([p/2, q/1], [a, b, c], 300),
    % a three-argument guard
    triple - [ ok(A1, B1, C1)-[edge(A1, B1), edge(B1, C1)],
               path3(A, D)-[edge(A, B), edge(B, C), ok(A, B, C), edge(C, D)] ]
           - input([edge/2], [a, b, c], 300)
]).

run_examples :-
    examples(Es),
    forall(member(Name-P-In, Es),
           ( delete_implied(P, P1, D), length(D, ND), check_on_inputs(P, P1, In, R),
             format("~w: ~d guard(s) deleted, check on random inputs: ~w~n", [Name, ND, R]),
             forall(member(C-G-by(W), D), ( numbervars(C-G, 0, _), format("   deleted ~p from ~p~n      because of the clause ~p~n", [G, C, W]) )) )).

% forced_check(-Result): delete the guard of the not_implied example anyway; the check on
% random inputs must find an input where the answers differ (it shows the check can fail)
forced_check(R) :-
    examples(Es), memberchk(not_implied-P-In, Es),
    P = [D, H-B], exclude([L]>>(L = link(_, _)), B, B1),
    check_on_inputs(P, [D, H-B1], In, R).

% guards_table: one row per example: what this module deletes, what s2a2's unary
% implied_guard/4 deletes, and the check on random inputs
guards_table :-
    s2a2_types_loaded,
    examples(Es),
    findall([Name, Guard, Ours, S2, Check],
            ( member(Name-P-In, Es), guard_of(P, Guard),
              delete_implied(P, P1, D), ( D == [] -> Ours = kept ; Ours = deleted ),
              ( s2a2_deletes(P) -> S2 = deleted ; S2 = kept ),
              check_on_inputs(P, P1, In, R), format(atom(Check), "~w", [R]) ),
            Rows0),
    forced_check(F), format(atom(FC), "~w", [F]),
    append(Rows0, [['not_implied, guard deleted by force', 'link(X,Y)', forced, '-', FC]], Rows),
    experiments:write_table(tuple_guards, ['Example', 'Guard', 'tuple_guards.pl', 's2a2 types:implied_guard (unary)', 'Answers on random inputs'], Rows).

% the guard of an example, written with the rule's variable names (A, B, C, ...): the
% literal of the last rule whose predicate the program defines by a rule
guard_of(P, G) :-
    last(P, R0), copy_term(R0, _-B), member(L, B), functor(L, F, N), functor(T0, F, N),
    member(T1-[_|_], P), T1 =@= T0, !, numbervars(B, 0, _), format(atom(G), "~p", [L]).

% s2a2 represents a program as prog(Facts, Rules), Rules = [Head-Body]
s2a2_deletes(P) :-
    length(P, N), nth1(N, P, _), Prog = prog([], P),
    nth1(I, P, _-B), B \== [], nth1(J, B, _), types:implied_guard(Prog, I, J, _), !.

% load s2a2's types.pl from S2A2 (a checkout of luciangreen/s2a2) or <repo>/deps/s2a2
s2a2_types_loaded :-
    (   current_predicate(types:implied_guard/4) -> true
    ;   ( getenv('S2A2', D) -> true ; repo_dir(R), atom_concat(R, '/deps/s2a2', D) ),
        atom_concat(D, '/prolog/types.pl', F), use_module(F, []) ).
:- prolog_load_context(directory, D), atom_concat(D, '/..', R0), absolute_file_name(R0, R),
   assertz(repo_dir(R)).
:- use_module(experiments, []).
