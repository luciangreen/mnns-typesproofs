/*  mnn_size.pl -- how much smaller a manual neuronet gets when types prune its rules.

    A small piece of WN18RR (a few related words) is written as a Prolog program with one
    rule per two-step path:
        p_hyp_drf(X, Z) :- hyp(X, Y), drf(Y, Z).
    The program is turned into a neural network by pl2ann (prolog2ann), which grounds every
    rule over the entities and makes one neuron per ground atom and per ground rule body.
    Four versions of the same program are converted:

      untyped        every variable ranges over every entity
      slot types     each argument position gets a domain: the parts of speech seen there
                     (pl2ann's domain file: domain(...) and type(Pred/2, Position, Domain))
      pruned rules   the rules whose relational types cannot meet are deleted (RTP)
      both           slot types and pruned rules

    For each version the table gives the network's neurons and edges, whether the atoms the
    network makes true (run forward to its fixpoint) are exactly the answers of its own
    program, and whether they are the same as the untyped program's answers.

    Requires pl2ann: <repo>/deps/pl2ann, or the PL2ANN environment variable.
*/
:- module(mnn_size, [mnn_size/0, slice/3, slice_program/4]).
:- use_module(kg).
:- use_module(rtp).
:- use_module(experiments, [write_table/3, results_dir/1]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(process)).
:- use_module(library(readutil)).

:- prolog_load_context(directory, D), atom_concat(D, '/..', R0), absolute_file_name(R0, R),
   assertz(repo_root(R)).
pl2ann_dir(D) :- ( getenv('PL2ANN', D0) -> D = D0 ; repo_root(R), atom_concat(R, '/deps/pl2ann', D) ).
build_dir(D) :- repo_root(R), atom_concat(R, '/build/mnn', D), make_directory_path(D).

% the relations of the slice and their short predicate names
rel_short('_hypernym', hyp).
rel_short('_derivationally_related_form', drf).
rel_short('_verb_group', vg).
rel_short('_similar_to', sim).
rel_short('_also_see', also).

mnn_size :-
    load_kg(wn18rr, train), profile, learn_types,
    slice(7, Facts, Ents),
    length(Facts, NF), length(Ents, NE), format(user_error, "slice: ~d facts, ~d entities~n", [NF, NE]),
    build_dir(B),
    findall(V, member(V, [untyped, slot_types, pruned_rules, both]), Vs),
    maplist(build_version(B, Facts, Ents), Vs, Rows0),
    % the untyped program's answers are the reference
    Rows0 = [row(_, _, _, _, _, Ref)|_],
    maplist([row(V, NR, Ne, Ed, Ver, Ans), [V, NR, Ne, Ed, Ver, Same]]>>( Ans == Ref -> length(Ans, NA), format(atom(Same), "yes (~d answers)", [NA]) ; Same = no ),
            Rows0, Rows),
    write_table(mnn_size, ['Version', 'Rules', 'Neurons', 'Edges', 'Network answers', 'Same answers as untyped'], Rows).

build_version(B, Facts, Ents, V, row(V, NR, Ne, Ed, Ver, Ans)) :-
    slice_program(V, Facts, Ents, prog(Lines, DomLines, NR)),
    format(atom(Src), "~w/~w.pl", [B, V]), format(atom(Dom), "~w/~w_domain.pl", [B, V]),
    format(atom(Net), "~w/net_~w.pl", [B, V]),
    write_lines(Src, Lines), write_lines(Dom, DomLines),
    ( DomLines == [] -> DomOpt = [] ; DomOpt = ['--domain', Dom] ),
    format(atom(Mod), "net_~w", [V]),
    append([convert, Src|DomOpt], ['--mode', step, '--limit', 2000000, '--out', Net, '--module', Mod], CArgs),
    pl2ann(CArgs, 0),
    count_facts(Net, neuron, Ne), count_facts(Net, edge, Ed),
    net_answers(Net, Mod, Ans),
    % the network is checked against its own program: the atoms it makes true are the
    % atoms the program proves (computed here by Prolog itself; the program has no
    % recursion, so plain Prolog finds every answer)
    program_answers(Src, V, PAns),
    ( Ans == PAns -> Ver = 'same as its program' ; Ver = 'DIFFERENT from its program' ).

program_answers(Src, V, Ans) :-
    format(atom(M), "prog_~w", [V]),
    forall(rel_short(_, P), M:dynamic(P/2)),    % a relation with no facts in the slice is empty
    load_files(M:Src, [silent(true)]),
    findall(G, ( M:current_predicate(P/2), sub_atom(P, 0, _, _, p_), functor(G, P, 2), M:G ), A0),
    sort(A0, Ans).

% count the lines of the network file that are facts of Name (neuron/4, edge/3)
count_facts(F, Name, N) :-
    atom_concat(Name, '(', Pre),
    setup_call_cleanup(open(F, read, S), count_lines(S, Pre, 0, N), close(S)).
count_lines(S, Pre, N0, N) :-
    read_line_to_string(S, L),
    (   L == end_of_file -> N = N0
    ;   ( string_concat(Pre, _, L) -> N1 is N0 + 1 ; N1 = N0 ), count_lines(S, Pre, N1, N) ).

% run pl2ann's command line; Status is its exit code (0 = success)
pl2ann(Args, Status) :-
    pl2ann_dir(D), atom_concat(D, '/bin/prolog2ann.pl', Bin),
    process_create(path(swipl), [Bin|Args], [stdout(null), stderr(pipe(E)), process(P)]),
    read_string(E, _, Err), close(E), process_wait(P, exit(St)),
    ( St == Status -> true ; format(user_error, "pl2ann ~w: exit ~w~n~w~n", [Args, St, Err]), fail ).

% the p_ atoms the NETWORK makes true (run forward to its fixpoint)
net_answers(Net, Mod, Ans) :-
    pl2ann_dir(D), atom_concat(D, '/prolog', Lib),
    ( user:file_search_path(library, Lib) -> true ; asserta(user:file_search_path(library, Lib)) ),
    load_files(Net, [silent(true), imports([])]),
    Mod:ann_run(Atoms, _Steps, true),           % one forward run to the fixpoint
    findall(G, ( member(G, Atoms), functor(G, P, 2), sub_atom(P, 0, _, _, p_) ), A0),
    sort(A0, Ans).

write_lines(F, Lines) :-
    setup_call_cleanup(open(F, write, S), forall(member(L, Lines), format(S, "~w~n", [L])), close(S)).

% ---------------------------------------------------------------- the slice
% slice(+Max, -Facts, -Entities): grow a connected set of at most Max entities from a
% verb-group fact, adding facts of the chosen relations that touch the set, taking the
% relations in turn so each one is represented
slice(Max, Facts, Ents) :-
    findall(R, rel_short(R, _), Rs),
    once(( t('_verb_group', A, B), t('_derivationally_related_form', A, _) )),
    grow(Rs, Rs, Max, [A, B], [f('_verb_group', A, B)], 0, Facts0, Ents0),
    % close the set: every fact of the chosen relations between entities of the set
    sort(Ents0, Ents),
    findall(f(R, H, T), ( member(R, Rs), t(R, H, T), ord_memberchk(H, Ents), ord_memberchk(T, Ents) ), F1),
    append(Facts0, F1, F2), sort(F2, Facts).
grow(_, _, Max, E, F, _, F, E) :- length(E, N), N >= Max, !.
grow(_, _, _, E, F, Stall, F, E) :- Stall > 10, !.
grow([], All, Max, E, F, S, Fo, Eo) :- !, grow(All, All, Max, E, F, S, Fo, Eo).
grow([R|Rs], All, Max, E, F, S, Fo, Eo) :-
    (   member(X, E), ( t(R, X, Y) ; t(R, Y, X) ), \+ memberchk(Y, E)
    ->  grow(Rs, All, Max, [Y|E], [f(R, X, Y)|F], 0, Fo, Eo)
    ;   S1 is S + 1, grow(Rs, All, Max, E, F, S1, Fo, Eo) ).

% ---------------------------------------------------------------- writing the program
% slice_program(+Version, +Facts, +Entities, -prog(SourceLines, DomainLines, NumberOfRules))
slice_program(V, Facts, Ents, prog(Lines, Dom, NR)) :-
    findall(L, ( member(f(R, H, T), Facts), rel_short(R, P), const(H, CH), const(T, CT), format(atom(L), "~w(~w, ~w).", [P, CH, CT]) ), FL),
    findall(R1-R2, ( rel_short(R1, _), rel_short(R2, _), ( prunes(V) -> keep(learned, R1, R2) ; true ) ), Paths),
    findall(L, ( member(R1-R2, Paths), rel_short(R1, P1), rel_short(R2, P2),
                 format(atom(L), "p_~w_~w(X, Z) :- ~w(X, Y), ~w(Y, Z).", [P1, P2, P1, P2]) ), RL),
    length(RL, NR),
    append(FL, RL, Lines),
    ( typed(V) -> domain_lines(Facts, Ents, Paths, Dom) ; Dom = [] ).
prunes(pruned_rules). prunes(both).
typed(slot_types). typed(both).

% a constant for an entity: dog.n.01 -> dog_n_01 (letters, digits and _ only)
const(E, C) :-
    atom_codes(E, Cs0), maplist([X, Y]>>( code_type(X, alnum), X < 128 -> Y = X ; Y = 0'_ ), Cs0, Cs1),
    atom_codes(A, Cs1), downcase_atom(A, A1), atom_concat(e_, A1, C).

% The domain of an argument position is the set of entities whose part of speech is one
% seen at that position (over the whole training graph, from the learned relational type).
domain_lines(_Facts, Ents, Paths, Lines) :-
    findall(S, ( rel_short(R, P), member(End, [1, 2]), slot_domain(R, End, Ents, Cs, Members), slot_line(P, End, Cs, Members, S) ), L1),
    findall(S, ( member(R1-R2, Paths), rel_short(R1, P1), rel_short(R2, P2), format(atom(Q), "p_~w_~w", [P1, P2]),
                 ( slot_domain(R1, 1, Ents, Cs, M), slot_line(Q, 1, Cs, M, S)
                 ; slot_domain(R2, 2, Ents, Cs, M), slot_line(Q, 2, Cs, M, S) ) ), L2),
    append(L1, L2, L3), sort(L3, Lines).
slot_domain(R, End, Ents, Cs, Members) :-
    rtype(R, Pairs), findall(C, ( member(A-B, Pairs), ( End == 1 -> C = A ; C = B ) ), C0), sort(C0, Cs),
    findall(K, ( member(E, Ents), cat(E, C), memberchk(C, Cs), const(E, K) ), M0), sort(M0, Members).
slot_line(P, End, Cs, Members, S) :-
    atomic_list_concat(Cs, '_', CN), format(atom(Name), "pos_~w", [CN]),
    (   format(atom(S), "domain(~w, ~w).", [Name, Members])
    ;   format(atom(S), "type(~w/2, ~d, ~w).", [P, End, Name]) ).
