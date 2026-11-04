/*  rtp.pl -- Relational Type Pruning (RTP) for two-step and three-step paths over a
    knowledge graph, with the measurements that show what it saves and what it loses.

    A PATH is a rule that joins relations on a shared middle entity:
        answer(X, Z) :- R1(X, Y), R2(Y, Z).
    To answer it, an engine takes every R1 fact (X, Y) and looks up the R2 facts that start
    at Y. Each lookup is a PROBE; each (X, Y, Z) found is a DERIVATION (an answer, counted
    with repeats). A path is EMPTY when no Y is both a tail of R1 and a head of R2.

    RTP decides, before any probing, that a path cannot have answers, using only TYPES:
    the kinds of entity each relation can take at each end. A path is pruned when the
    types at the meeting point cannot match. Three sources of types are compared:

      declared  the published schema: each relation's head type and tail type (Freebase);
                a path is kept when R1's tail type and R2's head type are the same, or some
                entity has both types. A relation without a signature is never pruned
                (open-world fallback).
      checked   the declared schema, trusted only at relation ends where every training
                fact obeyed it (elsewhere the open-world fallback keeps the path)
      learned   relational types learned from training data: for each relation, the set of
                (head category, tail category) pairs seen, e.g. hypernym: noun->noun.
                A path is kept when some category is a tail category of R1 and a head
                category of R2.
      snapshot  the paths that were non-empty in the training graph (data-level, frozen)
      exact     the actual sets of entities at each end of each relation in the graph
                (a data-level check, not a type: it is the reference that prunes exactly
                the empty paths of the graph it was computed on)

    Each source is also applied INSIDE kept paths (entity filter): a middle entity is
    probed only when its own type fits both relations.

    Main predicates
      profile/0                       index the loaded graph (counts per entity and end)
      path_stats(+R1, +R2, -K, -D)    K shared middle entities, D derivations (exact)
      keep(+Source, +R1, +R2)         RTP's decision: the path is kept (not pruned)
      entity_ok(+Source, +R1, +R2, +Y)  the entity filter
      evaluate(+Source, -Stats)       pruning, work and answers lost over all paths
      learn_types/0, rtype/2          learned relational types
*/
:- module(rtp, [profile/0, path_stats/4, keep/3, entity_ok/4, evaluate/3, learn_types/0, rtype/2,
                rel_n/2, compose/3, closure/3, top_entities/2, eval_join_count/3, evaluate_paths/4, decide_paths/3, run_paths/3, decide_kinds/2, run_kinds/3, decide_all_kinds/1, freeze_degrees/0,
                three_hop/2, rel_heads/2, rel_tails/2, types_overlap/2,
                take_snapshot/0, check_schema/0, two_step_vector/3, merge_count/6]).
:- use_module(kg).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(ordsets)).
:- use_module(library(rbtrees)).

:- dynamic deg_train/2, t_kind/3, overlap_memo/3, tail_obeys/1, head_obeys/1, seen_path/2, rel_n/2, rel_heads/2, rel_tails/2, od/3, rtype/2, type_ents/2, deg/2, keep_top/2.

% ---------------------------------------------------------------- indexing the graph
% For each relation: its number of facts, and for each end the entities with their counts
% (how many facts have that entity at that end). od(R, Y, C): Y heads C facts of R.
profile :-
    retractall(rel_n(_, _)), retractall(rel_heads(_, _)), retractall(rel_tails(_, _)),
    retractall(od(_, _, _)), retractall(deg(_, _)), retractall(type_ents(_, _)), retractall(overlap_memo(_, _, _)),
    kg_relations(Rs),
    forall(member(R, Rs),
           ( findall(H, t(R, H, _), Hs0), findall(T, t(R, _, T), Ts0), length(Hs0, N),
             counts(Hs0, Hs), counts(Ts0, Ts),
             assertz(rel_n(R, N)), assertz(rel_heads(R, Hs)), assertz(rel_tails(R, Ts)),
             forall(member(Y-C, Hs), assertz(od(R, Y, C))) )),
    % degree of each entity over the whole graph (for the top-K baseline)
    findall(E, ( t(_, E, _) ; t(_, _, E) ), Es0), counts(Es0, Ds),
    forall(member(E-C, Ds), assertz(deg(E, C))),
    % entities of each declared type (for the overlap test)
    % (only entities of the loaded graph count as witnesses that two types overlap)
    findall(Ty-E, ( deg(E, _), etype(E, Ty) ), TE0), keysort(TE0, TE), group_pairs_by_key(TE, G),
    forall(member(Ty-Ents0, G), ( sort(Ents0, Ents), assertz(type_ents(Ty, Ents)) )),
    % facts grouped by the kind of their tail (graphs with kinds only): lets an engine read
    % just the R1 facts whose middle entity has a kind the entity filter allows
    retractall(t_kind(_, _, _)),
    % (a middle entity without a kind is filed under 'none' and always read: open world)
    (   cat(_, _)
    ->  forall(t(R, _, Y), ( cat(Y, C) -> assertz(t_kind(R, C, Y)) ; assertz(t_kind(R, none, Y)) ))
    ;   true ).

counts(L0, Pairs) :- msort(L0, L), clumped(L, Pairs).

% ---------------------------------------------------------------- exact join size
% Walk the tails of R1 and the heads of R2 together (both sorted): every shared middle
% entity Y gives (facts of R1 ending at Y) x (facts of R2 starting at Y) derivations.
path_stats(R1, R2, K, D) :-
    rel_tails(R1, T1), rel_heads(R2, H2), merge_count(T1, H2, 0, K, 0, D).
merge_count([], _, K, K, D, D) :- !.
merge_count(_, [], K, K, D, D) :- !.
merge_count([Y1-C1|T1], [Y2-C2|T2], K0, K, D0, D) :-
    compare(O, Y1, Y2),
    (   O == (=) -> K1 is K0 + 1, D1 is D0 + C1 * C2, merge_count(T1, T2, K1, K, D1, D)
    ;   O == (<) -> merge_count(T1, [Y2-C2|T2], K0, K, D0, D)
    ;   merge_count([Y1-C1|T1], T2, K0, K, D0, D) ).

% take_snapshot: remember which paths are non-empty in the loaded graph (the "snapshot"
% source then prunes every other path, even when the graph later grows)
take_snapshot :-
    retractall(seen_path(_, _)), kg_relations(Rs),
    forall(( member(R1, Rs), member(R2, Rs), path_stats(R1, R2, K, _), K > 0 ), assertz(seen_path(R1, R2))).

% check_schema: for each relation, does every fact in the loaded (training) graph give its
% head the declared head type (head_obeys) and its tail the declared tail type (tail_obeys)?
% The "checked" source trusts the schema only for those ends.
check_schema :-
    retractall(tail_obeys(_)), retractall(head_obeys(_)), kg_relations(Rs),
    forall(( member(R, Rs), sig(R, HT, _), \+ ( t(R, H, _), \+ etype(H, HT) ) ), assertz(head_obeys(R))),
    forall(( member(R, Rs), sig(R, _, TT), \+ ( t(R, _, T), \+ etype(T, TT) ) ), assertz(tail_obeys(R))).

% ---------------------------------------------------------------- learned relational types
% rtype(R, Pairs): the (head category - tail category) pairs seen in R's facts
learn_types :-
    retractall(rtype(_, _)),
    kg_relations(Rs),
    forall(member(R, Rs),
           ( findall(CH-CT, ( t(R, H, T), cat(H, CH), cat(T, CT) ), P0), sort(P0, P), assertz(rtype(R, P)) )).

% compose two relational types: (a,b) and (b,c) give (a,c)
compose(P1, P2, P) :- findall(A-C, ( member(A-B, P1), member(B-C, P2) ), P0), sort(P0, P).
% the relational type of R followed by itself any number of times (a fixpoint: it can only
% grow, and there are finitely many category pairs, so it stops)
closure(P0, P, Rounds) :- closure_(P0, P0, P, 0, Rounds).
closure_(Acc, P1, P, N0, N) :-
    compose(Acc, P1, New), ord_union(Acc, New, Acc1), N1 is N0 + 1,
    ( Acc1 == Acc -> P = Acc, N = N1 ; closure_(Acc1, P1, P, N1, N) ).

% ---------------------------------------------------------------- the pruning decision
keep(none, _, _) :- !.
keep(top(_), _, _) :- !.                          % the baseline prunes no whole path
keep(exact, R1, R2) :- !, path_stats(R1, R2, K, _), K > 0.
keep(snapshot, R1, R2) :- !, seen_path(R1, R2).   % non-empty in the graph it was taken from
keep(learned, R1, R2) :- !,
    ( rtype(R1, P1), rtype(R2, P2) -> member(_-C, P1), memberchk(C-_, P2), ! ; true ).
keep(checked, R1, R2) :- !,                      % declared, used only where the data obeyed it
    ( tail_obeys(R1), head_obeys(R2) -> keep(declared, R1, R2) ; true ).
keep(declared, R1, R2) :- !,
    (   sig(R1, _, Tail1), sig(R2, Head2, _)
    ->  ( Tail1 == Head2 -> true ; types_overlap(Tail1, Head2) )
    ;   true ).                                   % open-world fallback: no signature
types_overlap(T1, T2) :-
    (   overlap_memo(T1, T2, B) -> B == true
    ;   ( type_ents(T1, E1), type_ents(T2, E2), \+ ord_disjoint(E1, E2) -> B = true ; B = false ),
        assertz(overlap_memo(T1, T2, B)), B == true ).

% the entity filter inside a kept path: is the middle entity Y allowed?
entity_ok(none, _, _, _) :- !.
entity_ok(exact, _, _, _) :- !.
entity_ok(snapshot, _, _, _) :- !.
entity_ok(learned, R1, R2, Y) :- !,
    (   cat(Y, C), rtype(R1, P1), rtype(R2, P2) -> memberchk(_-C, P1), memberchk(C-_, P2) ; true ).
entity_ok(checked, R1, R2, Y) :- !,
    ( tail_obeys(R1), head_obeys(R2) -> entity_ok(declared, R1, R2, Y) ; true ).
entity_ok(declared, R1, R2, Y) :- !,
    (   \+ etype(Y, _) -> true                    % untyped entity: open-world fallback
    ;   sig(R1, _, Tail1), sig(R2, Head2, _) -> etype(Y, Tail1), etype(Y, Head2)
    ;   true ).
entity_ok(top(_), _, _, Y) :- keep_top(Y, _).    % baseline: only high-degree middle entities

% freeze_degrees: remember the degrees of the loaded (training) graph, so the baseline's
% ranking does not see valid or test facts
freeze_degrees :- retractall(deg_train(_, _)), forall(deg(E, C), assertz(deg_train(E, C))).
% the top P percent of entities by degree (the heuristic baseline's "high scores"); training
% degrees when frozen
top_entities(P, N) :-
    retractall(keep_top(_, _)),
    ( deg_train(_, _) -> findall(C-E, deg_train(E, C), CE0) ; findall(C-E, deg(E, C), CE0) ), keysort(CE0, CE1), reverse(CE1, CE), length(CE, All),
    N is max(1, round(All * P / 100)), length(Top, N), append(Top, _, CE),
    forall(member(C-E, Top), assertz(keep_top(E, C))).

% ---------------------------------------------------------------- evaluation over all paths
% evaluate(+Source, +EntityFilter, -Stats) over every ordered pair of relations (R1, R2):
%   paths, pruned, wrongly_pruned (pruned but not empty), empty (truly empty), missed
%   (empty but kept), probes (|R1| for every path), probes_saved, derivations,
%   derivations_lost, middle_checked, middle_dropped
evaluate(Source, Filter, S) :-
    kg_relations(Rs),
    foldl(eval_r1(Source, Filter, Rs), Rs, s(0,0,0,0,0,0,0,0,0), s(P, Pr, W, E, M, Pb, PbS, Dv, DvL)),
    S = _{source:Source, entity_filter:Filter, paths:P, pruned:Pr, wrongly_pruned:W, empty:E, missed:M,
          probes:Pb, probes_saved:PbS, derivations:Dv, derivations_lost:DvL}.
eval_r1(Src, F, Rs, R1, S0, S) :- rel_n(R1, N1), foldl(eval_path(Src, F, R1, N1), Rs, S0, S).
eval_path(Src, F, R1, N1, R2, s(P0, Pr0, W0, E0, M0, Pb0, PbS0, Dv0, DvL0), s(P, Pr, W, E, M, Pb, PbS, Dv, DvL)) :-
    path_stats(R1, R2, K, D),
    P is P0 + 1, Pb is Pb0 + N1, Dv is Dv0 + D,
    ( K =:= 0 -> E is E0 + 1 ; E = E0 ),
    (   keep(Src, R1, R2)
    ->  Pr = Pr0, W = W0, ( K =:= 0 -> M is M0 + 1 ; M = M0 ),
        (   F == yes
        ->  filter_loss(Src, R1, R2, SavedP, LostD), PbS is PbS0 + SavedP, DvL is DvL0 + LostD
        ;   PbS = PbS0, DvL = DvL0 )
    ;   Pr is Pr0 + 1, ( K > 0 -> W is W0 + 1 ; W = W0 ), M = M0,
        PbS is PbS0 + N1, DvL is DvL0 + D ).

% probes saved and derivations lost by the entity filter in one kept path: every R1 fact
% whose middle entity is dropped is not probed; if that entity also starts R2 facts, the
% derivations through it are lost
filter_loss(Src, R1, R2, Saved, Lost) :-
    rel_tails(R1, T1), filter_loss_(T1, Src, R1, R2, 0, Saved, 0, Lost).
filter_loss_([], _, _, _, S, S, L, L).
filter_loss_([Y-C1|T], Src, R1, R2, S0, S, L0, L) :-
    (   entity_ok(Src, R1, R2, Y) -> S1 = S0, L1 = L0
    ;   S1 is S0 + C1, ( od(R2, Y, C2) -> L1 is L0 + C1 * C2 ; L1 = L0 ) ),
    filter_loss_(T, Src, R1, R2, S1, S, L1, L).

% evaluate the join of every path by actually probing (scan R1, look up R2's count at Y);
% used to time the engine with and without pruning, and to check path_stats/4
eval_join_count(R1, R2, D) :-
    aggregate_all(sum(C), ( t(R1, _, Y), od(R2, Y, C) ), D).
% decide_paths(+Source, -Kept, -Seconds): the analysis step, done once before any query:
% the list of R1-R2 paths the source keeps, and the time the decisions took
decide_paths(Src, Kept, Secs) :-
    kg_relations(Rs),
    statistics(cputime, T0),
    findall(R1-R2, ( member(R1, Rs), member(R2, Rs), keep(Src, R1, R2) ), Kept),
    statistics(cputime, T1), Secs is T1 - T0.
% run_paths(+Kept, -Seconds, -Derivations): evaluate the kept paths by probing
run_paths(Kept, Secs, DTot) :-
    statistics(cputime, T0),
    aggregate_all(sum(D), ( member(R1-R2, Kept), eval_join_count(R1, R2, D) ), DTot),
    statistics(cputime, T1), Secs is T1 - T0.
% decide_kinds(-Kept, -Seconds): with learned types and the entity filter, each kept path
% also gets the middle kinds it allows (tail kinds of R1 that are head kinds of R2)
decide_kinds(Kept, Secs) :-
    kg_relations(Rs),
    statistics(cputime, T0),
    findall(R1-R2-Ks, ( member(R1, Rs), member(R2, Rs), keep(learned, R1, R2), allowed_kinds(R1, R2, Ks) ), Kept),
    statistics(cputime, T1), Secs is T1 - T0.
allowed_kinds(R1, R2, Ks) :-
    (   rtype(R1, P1), rtype(R2, P2)
    ->  findall(C, ( member(_-C, P1), memberchk(C-_, P2) ), K0), sort([none|K0], Ks)
    ;   all_kinds(Ks) ).
all_kinds(Ks) :- findall(C, t_kind(_, C, _), K0), sort([none|K0], Ks).
% decide_all_kinds(-Kept): every path, reading every kind (the unpruned engine on the same
% index, to compare the entity filter with like for like)
decide_all_kinds(Kept) :-
    kg_relations(Rs), all_kinds(Ks), findall(R1-R2-Ks, ( member(R1, Rs), member(R2, Rs) ), Kept).
% run_kinds(+Kept, -Seconds, -Derivations): probe only from R1 facts whose middle entity
% has an allowed kind
run_kinds(Kept, Secs, DTot) :-
    statistics(cputime, T0),
    aggregate_all(sum(C), ( member(R1-R2-Ks, Kept), member(K, Ks), t_kind(R1, K, Y), od(R2, Y, C) ), DTot),
    statistics(cputime, T1), Secs is T1 - T0.

% evaluate_paths(+Source, -Seconds, -Paths, -Derivations): decide, then run every kept path
% (Seconds is the running time only)
evaluate_paths(Src, Secs, NP, DTot) :-
    decide_paths(Src, Kept, _), length(Kept, NP), run_paths(Kept, Secs, DTot).

% ---------------------------------------------------------------- three-step paths
% answer(X, W) :- R1(X, Y), R2(Y, Z), R3(Z, W) over every triple of relations.
% Exact count: c(Z) = number of (X, Y) routes into Z through R1 then R2; derivations are
% the sum over Z of c(Z) times the R3 facts starting at Z. The learned types prune a path
% when the composed relational type R1.R2.R3 is empty.
three_hop(Source, S) :-
    kg_relations(Rs),
    findall(R1-R2, ( member(R1, Rs), member(R2, Rs) ), Pairs),
    th_pairs(Pairs, Source, Rs, s(0, 0, 0, 0, 0, 0), s(P, Pr, W, E, D, L)),
    S = _{source:Source, paths:P, pruned:Pr, wrongly_pruned:W, empty:E, derivations:D, derivations_lost:L}.
th_pairs([], _, _, S, S).
th_pairs([R1-R2|Ps], Src, Rs, S0, S) :-
    two_step_vector(R1, R2, V),
    th_r3(Rs, Src, R1, R2, V, S0, S1),
    th_pairs(Ps, Src, Rs, S1, S).
th_r3([], _, _, _, _, S, S).
th_r3([R3|Rs], Src, R1, R2, V, s(P0, Pr0, W0, E0, D0, L0), S) :-
    rel_heads(R3, H3), merge_count(V, H3, 0, K, 0, Dv),
    P1 is P0 + 1, D1 is D0 + Dv, ( K =:= 0 -> E1 is E0 + 1 ; E1 = E0 ),
    (   keep3(Src, R1, R2, R3) -> Pr1 = Pr0, W1 = W0, L1 = L0
    ;   Pr1 is Pr0 + 1, ( K > 0 -> W1 is W0 + 1 ; W1 = W0 ), L1 is L0 + Dv ),
    th_r3(Rs, Src, R1, R2, V, s(P1, Pr1, W1, E1, D1, L1), S).

% (plain recursion, not a lambda: a lambda holding the large tree In would be scanned on
% every call)
two_step_vector(R1, R2, V) :-
    rel_tails(R1, T1), list_to_rbtree(T1, In),
    findall(Y-Z, t(R2, Y, Z), Edges),
    rb_empty(E0), add_routes(Edges, In, E0, Acc),
    rb_visit(Acc, V).
add_routes([], _, A, A).
add_routes([Y-Z|Es], In, A0, A) :-
    (   rb_lookup(Y, C, In)
    ->  ( rb_lookup(Z, C0, A0) -> C1 is C0 + C, rb_update(A0, Z, C1, A1) ; rb_insert_new(A0, Z, C, A1) )
    ;   A1 = A0 ),
    add_routes(Es, In, A1, A).

keep3(none, _, _, _) :- !.
keep3(learned, R1, R2, R3) :- !,
    (   rtype(R1, P1), rtype(R2, P2), rtype(R3, P3)
    ->  compose(P1, P2, P12), compose(P12, P3, P), P \== []
    ;   true ).                                   % a relation never seen in training: keep
keep3(S, _, _, _) :- domain_error(three_hop_source, S).
