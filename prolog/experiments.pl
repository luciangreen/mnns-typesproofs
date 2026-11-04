/*  experiments.pl -- the measurements reported in the paper, written to results/.

    Each experiment loads a graph, runs the pruning analysis and writes a Markdown table
    (results/<name>.md) and the same rows as CSV (results/<name>.csv).

      e1_datasets      size of each graph and how well FB15k-237 follows its own schema
      e2_pruning       two-step paths: how many each type source prunes, and what is lost,
                       with types learned on the training split and checked on all splits
      e3_timing        time to evaluate every kept path, with and without pruning
      e4_topk          the heuristic baseline (keep only high-degree middle entities)
      e5_closure       the fixpoint of a relational type composed with itself
      e6_three_hop     three-step paths on WN18RR

    run_all/0 runs them in order. Each can be run alone, e.g.
        swipl -g "e2_pruning(wn18rr)" -t halt prolog/experiments.pl
*/
:- module(experiments, [run_all/0, run_quick/0, e1_datasets/1, e2_pruning/1, e3_timing/1, e4_topk/1,
                        e5_closure/0, e6_three_hop/0, results_dir/1, write_table/3]).
:- use_module(kg).
:- use_module(rtp).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(aggregate)).

:- prolog_load_context(directory, D), atom_concat(D, '/../results', R0), absolute_file_name(R0, R),
   assertz(results_root(R)).
results_dir(D) :- ( getenv('RTP_RESULTS', D0) -> D = D0 ; results_root(D) ), make_directory_path(D).

graphs([fb15k237, wn18rr, yago3_10]).
graph_name(fb15k237, 'FB15k-237').
graph_name(wn18rr, 'WN18RR').
graph_name(yago3_10, 'YAGO3-10').
graph_name(toy, toy).

run_all :-
    graphs(Gs),
    e1_datasets(Gs),
    forall(member(G, Gs), e2_pruning(G)),
    forall(member(G, Gs), e3_timing(G)),
    forall(member(G, Gs), e4_topk(G)),
    e5_closure, e6_three_hop.

% the same experiments on the two smaller graphs only (a few minutes)
run_quick :-
    e1_datasets([fb15k237, wn18rr]),
    forall(member(G, [fb15k237, wn18rr]), ( e2_pruning(G), e3_timing(G), e4_topk(G) )),
    e5_closure.

note(Fmt, Args) :- format(user_error, Fmt, Args), nl(user_error).

% ---------------------------------------------------------------- loading
% train: load the training split, index it, learn the types and remember its non-empty paths
prepare_train(G) :-
    load_kg(G, train), profile, learn_types, take_snapshot, check_schema, freeze_degrees.
% all: load every split (train + valid + test) and index it, keeping what was learned on train
prepare_all(G) :-
    load_kg(G, all), profile.

% ---------------------------------------------------------------- E1 datasets
e1_datasets(Gs) :-
    findall(Row, ( member(G, Gs), e1_row(G, Row) ), Rows),
    write_table(e1_datasets,
                ['Graph', 'Training facts', 'All facts', 'Entities (all)', 'Relations', 'Typed entities', 'Facts that follow the declared schema'],
                Rows).
e1_row(G, [Name, NTrain, NAll, NE, NR, Typed, Conf]) :-
    graph_name(G, Name), note("E1 ~w", [Name]),
    load_kg(G, train), kg_size(NTrain, _, _),
    ( G == fb15k237 -> conformance(C, CH, CT), format(atom(Conf), "~2f% (head ~2f%, tail ~2f%)", [C, CH, CT]) ; Conf = 'no schema' ),
    load_kg(G, all), kg_size(NAll, NE, NR),
    typed_entities(G, Typed).
% a fact follows the schema when its head has the relation's declared head type and its
% tail has the declared tail type
conformance(C, CH, CT) :-
    aggregate_all(count, t(_, _, _), N),
    aggregate_all(count, ( t(R, H, _), sig(R, HT, _), etype(H, HT) ), NH),
    aggregate_all(count, ( t(R, _, T), sig(R, _, TT), etype(T, TT) ), NT),
    aggregate_all(count, ( t(R, H, T), sig(R, HT, TT), etype(H, HT), etype(T, TT) ), NB),
    C is 100 * NB / N, CH is 100 * NH / N, CT is 100 * NT / N.
typed_entities(fb15k237, S) :- !,
    findall(E, ( t(_, E, _) ; t(_, _, E) ), E0), sort(E0, Es), length(Es, N),
    include([E]>>etype(E, _), Es, Ty), length(Ty, NT), format(atom(S), "~d of ~d (Freebase types)", [NT, N]).
typed_entities(wn18rr, S) :- !,
    findall(E, ( t(_, E, _) ; t(_, _, E) ), E0), sort(E0, Es), length(Es, N),
    include([E]>>( cat(E, C), C \== unknown ), Es, Ty), length(Ty, NT),
    format(atom(S), "~d of ~d (part of speech)", [NT, N]).
typed_entities(_, 'none').

% ---------------------------------------------------------------- E2 pruning
% Sources compared on the graph with all splits, types learned on train:
%   none       nothing pruned (the work an engine does without RTP)
%   declared   Freebase schema (FB15k-237 only)
%   checked    the Freebase schema where the training facts obeyed it (FB15k-237 only)
%   learned    learned relational types (WN18RR only)
%   snapshot   the paths that were non-empty on train
%   exact      the paths non-empty on the full graph (the reference: prunes exactly the empty ones)
% each with and without the entity filter.
sources(fb15k237, [none, declared, checked, snapshot, exact]).
sources(wn18rr, [none, learned, snapshot, exact]).
sources(yago3_10, [none, snapshot, exact]).
sources(toy, [none, learned, snapshot, exact]).

e2_pruning(G) :-
    graph_name(G, Name), note("E2 ~w", [Name]),
    prepare_train(G), prepare_all(G), sources(G, Srcs),
    findall(Row, ( member(S, Srcs), member(F, [no, yes]), \+ ( F == yes, memberchk(S, [none, exact, snapshot]) ),
                   evaluate(S, F, St), e2_row(St, Row) ), Rows),
    atom_concat(e2_pruning_, G, File),
    write_table(File,
                ['Type source', 'Entity filter', 'Paths', 'Pruned', 'Pruned but not empty', 'Truly empty', 'Empty but kept',
                 'Probes saved', 'Answers (derivations)', 'Answers lost'],
                Rows).
e2_row(St, [S, F, P, Pr, W, E, M, Saved, Dv, Lost]) :-
    S = St.source, F = St.entity_filter, P = St.paths, E = St.empty, M = St.missed,
    pct(St.pruned, P, Pr), pct(St.wrongly_pruned, P, W),
    pct(St.probes_saved, St.probes, Saved), Dv = St.derivations, pct(St.derivations_lost, Dv, Lost).
pct(A, B, S) :- ( B =:= 0 -> P = 0 ; P is 100 * A / B ), format(atom(S), "~d (~1f%)", [A, P]).

% ---------------------------------------------------------------- E3 timing
% Two steps are timed separately. Deciding which paths to keep is done once, before any
% query (like compiling); running is the probing of every kept path. Running is timed five
% times and the median reported; the speed-up compares running times with "none".
e3_timing(G) :-
    graph_name(G, Name), note("E3 ~w", [Name]),
    prepare_train(G), prepare_all(G), sources(G, Srcs),
    findall(S-r(Dec, Run, NP, D), ( member(S, Srcs), time_source(S, Dec, Run, NP, D) ), Res0),
    (   memberchk(learned, Srcs)
    ->  decide_all_kinds(KA), length(KA, NPA), median_of(5, run_kinds(KA), RunA, DA),
        decide_kinds(KK, DecK), length(KK, NPK), median_of(5, run_kinds(KK), RunK, DK),
        append(Res0, ['none, facts read by kind'-r(0, RunA, NPA, DA), 'learned + entity filter (read by kind)'-r(DecK, RunK, NPK, DK)], Res)
    ;   Res = Res0 ),
    memberchk(none-r(_, T0, _, D0), Res),
    findall([S, NP, Ds, DecS, RunS, Speed, Kept],
            ( member(S-r(Dec, T, NP, D), Res),
              format(atom(DecS), "~3f", [Dec]), format(atom(RunS), "~3f", [T]),
              % the filtered run is compared with the unpruned run on the same (by-kind) index
              ( sub_atom(S, _, _, _, 'by kind') -> memberchk('none, facts read by kind'-r(_, TB, _, _), Res) ; TB = T0 ),
              ( T > 0 -> X is TB / T, format(atom(Speed), "~2fx", [X]) ; Speed = '-' ),
              format(atom(Ds), "~d", [D]), pct(D, D0, Kept) ),
            Rows),
    atom_concat(e3_timing_, G, File),
    write_table(File, ['Type source', 'Paths run', 'Answers found', 'Deciding (s, once)', 'Running (s, median of 5)',
                       'Running speed-up', 'Answers kept'], Rows).
time_source(S, Dec, Run, NP, D) :-
    decide_paths(S, Kept, Dec), length(Kept, NP),
    median_of(5, run_paths(Kept), Run, D).
% median_of(+N, +Goal, -MedianSeconds, -Derivations): call Goal(T, D) N times (N odd)
median_of(N, G, T, D) :-
    findall(Ti-Di, ( between(1, N, _), garbage_collect, call(G, Ti, Di) ), L),
    msort(L, S), M is N // 2, nth0(M, S, T-D).

% ---------------------------------------------------------------- E4 top-K baseline
% Keep only middle entities in the top P% by degree (a stand-in for "keep the top-K
% scoring entities"); every path is kept. Reported: probes saved and answers lost.
e4_topk(G) :-
    graph_name(G, Name), note("E4 ~w", [Name]),
    prepare_train(G), prepare_all(G),
    findall([Label, Saved, Lost],
            ( member(P, [90, 75, 50, 25, 10, 1]), top_entities(P, N), format(atom(Label), "top ~d% (~d entities)", [P, N]),
              evaluate(top(P), yes, St), pct(St.probes_saved, St.probes, Saved), pct(St.derivations_lost, St.derivations, Lost) ),
            Rows0),
    sources(G, Srcs),
    findall([Label, Saved, Lost],
            ( member(S, Srcs), S \== none, member(F, [no, yes]), \+ ( F == yes, memberchk(S, [exact, snapshot]) ),
              evaluate(S, F, St), format(atom(Label), "~w types, entity filter ~w", [S, F]),
              pct(St.probes_saved, St.probes, Saved), pct(St.derivations_lost, St.derivations, Lost) ),
            Rows1),
    append(Rows0, Rows1, Rows),
    atom_concat(e4_topk_, G, File),
    write_table(File, ['Method', 'Probes saved', 'Answers lost'], Rows).

% ---------------------------------------------------------------- E5 closure
% The relational type of a relation followed by itself any number of times, on WN18RR train.
e5_closure :-
    note("E5", []),
    load_kg(wn18rr, train), learn_types,
    findall([R, P0s, Ps, Rounds],
            ( member(R, ['_hypernym', '_derivationally_related_form', '_also_see', '_verb_group', '_similar_to']),
              rtype(R, P0), closure(P0, P, Rounds), pairs_text(P0, P0s), pairs_text(P, Ps) ),
            Rows),
    write_table(e5_closure, ['Relation', 'Category pairs seen', 'After composing with itself until nothing new', 'Rounds'], Rows).
pairs_text(P, S) :- maplist([A-B, T]>>format(atom(T), "~w>~w", [A, B]), P, Ts), atomic_list_concat(Ts, ' ', S).

% ---------------------------------------------------------------- E6 three-step paths
e6_three_hop :-
    note("E6", []),
    findall([Split, S, P, Pr, W, E, D, L],
            ( member(Split-Prep, [train-prepare_train(wn18rr), all-(prepare_train(wn18rr), prepare_all(wn18rr))]), call(Prep),
              member(S, [learned]), three_hop(S, St),
              P = St.paths, E = St.empty, D = St.derivations,
              pct(St.pruned, P, Pr), pct(St.wrongly_pruned, P, W), pct(St.derivations_lost, D, L) ),
            Rows),
    write_table(e6_three_hop_wn18rr, ['Graph', 'Type source', 'Paths', 'Pruned', 'Pruned but not empty', 'Truly empty', 'Answers', 'Answers lost'], Rows).

% ---------------------------------------------------------------- output
write_table(Name, Header, Rows) :-
    results_dir(D),
    format(atom(MD), "~w/~w.md", [D, Name]), format(atom(CSV), "~w/~w.csv", [D, Name]),
    setup_call_cleanup(open(MD, write, S, [encoding(utf8)]),
        ( md_row(S, Header), length(Header, N), length(Sep, N), maplist(=('---'), Sep), md_row(S, Sep),
          forall(member(R, Rows), md_row(S, R)) ), close(S)),
    setup_call_cleanup(open(CSV, write, C, [encoding(utf8)]),
        ( csv_row(C, Header), forall(member(R, Rows), csv_row(C, R)) ), close(C)),
    note("wrote ~w", [MD]).
md_row(S, Cells) :- atomic_list_concat(Cells, ' | ', L), format(S, "| ~w |~n", [L]).
csv_row(S, Cells) :- maplist(csv_cell, Cells, Cs), atomic_list_concat(Cs, ',', L), format(S, "~w~n", [L]).
csv_cell(X, Q) :- format(atom(A), "~w", [X]), atomic_list_concat(Parts, '"', A), atomic_list_concat(Parts, '""', E),
                  format(atom(Q), "\"~w\"", [E]).
