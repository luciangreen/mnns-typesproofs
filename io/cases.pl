% The predicates whose inputs and outputs are recorded in io/ios.txt (see io/ios_engine.pl).
:- ios_engine:load_repo('prolog/tuple_guards').
:- ios_engine:load_repo('prolog/rtp').
:- use_module(library(random)).

io_title('mnns-typesproofs').

io_cases([delete_implied, implied, least_model, check_on_inputs, compose, closure]).

% the repo's own example programs, and the facts to run them on
program(K, Name, Prog, In) :- tuple_guards:examples(Es), pick(K, 1, Es, Name-Prog-In).
% input facts over the example's own input predicates and constants
facts(K, input(Preds, Consts, _), Fs) :-
    findall(G, ( member(P/N, Preds), length(As, N), maplist([A]>>member(A, Consts), As), G =.. [P | As] ), All),
    pick_n(K, 2, 7, All, Fs0), sort(Fs0, Fs1), findall(F-[], member(F, Fs1), Fs).
cats([person, place, thing, event]).
pairs(K, Salt, Ps) :- cats(Cs), pick_n(K, Salt, 4, Cs, As), pick_n(K, Salt + 1, 4, Cs, Bs), findall(A-B, (nth1(I, As, A), nth1(I, Bs, B)), Ps0), sort(Ps0, Ps).

io_input(delete_implied, K, [Name, Prog]) :- program(K, Name, Prog, _).
io_input(implied, K, [Name, Prog, Rule]) :- program(K, Name, Prog, _), last(Prog, Rule).
io_input(least_model, K, [Name, Prog, Facts]) :- program(K, Name, Prog, In), facts(K, In, Facts).
io_input(check_on_inputs, K, [Name, Prog, input(Preds, Consts, 50), K]) :- program(K, Name, Prog, input(Preds, Consts, _)).
io_input(compose, K, [P1, P2]) :- pairs(K, 3, P1), pairs(K, 5, P2).
io_input(closure, K, [P]) :- pairs(K, 7, P).

io_run(delete_implied, [_, Prog], [program(New), deleted(D)]) :- delete_implied(Prog, New, D).
io_run(implied, [_, Prog, Rule], Gs) :- findall(G-Why, implied(Prog, Rule, G, Why), Gs).
io_run(least_model, [_, Prog, Facts], M) :- append(Prog, Facts, P), tuple_guards:least_model(P, M0), sort(M0, M).
% random inputs, from a seed set by the example number, so the answer is the same each time
io_run(check_on_inputs, [_, Prog, In, Seed], Result) :- set_random(seed(Seed)), delete_implied(Prog, New, _), check_on_inputs(Prog, New, In, Result).
io_run(compose, [P1, P2], P) :- rtp:compose(P1, P2, P).
io_run(closure, [P0], [P, rounds(N)]) :- rtp:closure(P0, P, N).
