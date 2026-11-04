/*  kg.pl -- load a knowledge graph and its types.

    A knowledge graph is a set of triples: head entity, relation, tail entity, such as
    "Chatou  isLocatedIn  France". This module reads the tab-separated files of the
    benchmark graphs and the type files that come with them:

      fb15k237   FB15k-237 (Toutanova et al., 2015), with Freebase entity types and each
                 relation's declared head type and tail type (from the TKRL data; Xie et
                 al., 2016)
      wn18rr     WN18RR (Dettmers et al., 2018), whose entity names carry their WordNet
                 part of speech, e.g. dog.n.01 is a noun (n), run.v.01 a verb (v)
      yago3_10   YAGO3-10 (Mahdisoltani et al., 2015), which comes with no types

    Facts made here (one graph at a time):
      t(Relation, Head, Tail)              one per triple
      etype(Entity, Type)                  Freebase types (fb15k237 only)
      sig(Relation, HeadType, TailType)    declared Freebase signature (fb15k237 only)
      cat(Entity, Category)                part of speech (wn18rr only)
*/
:- module(kg, [load_kg/2, kg_files/3, data_dir/1, t/3, etype/2, sig/3, cat/2, kg_relations/1,
               kg_size/3, split_files/3]).
:- use_module(library(readutil)).
:- use_module(library(apply)).
:- use_module(library(lists)).

:- dynamic t/3, etype/2, sig/3, cat/2.

:- prolog_load_context(directory, D), atom_concat(D, '/..', R0), absolute_file_name(R0, R),
   assertz(repo_root(R)), atom_concat(R, '/data', DR), assertz(data_root(DR)).
data_dir(D) :- ( getenv('KG_DATA', D0) -> D = D0 ; data_root(D) ).

% the triple files of each graph and split
split_files(fb15k237, Split, Fs) :- data_dir(D), split_names(Split, Ns),
    findall(F, ( member(N, Ns), format(atom(F), '~w/kg/FB15k-237/~w.txt', [D, N]) ), Fs).
split_files(wn18rr, Split, Fs) :- data_dir(D), split_names(Split, Ns),
    findall(F, ( member(N, Ns), format(atom(F), '~w/villmow/WN18RR/text/~w.txt', [D, N]) ), Fs).
split_files(yago3_10, Split, Fs) :- data_dir(D), split_names(Split, Ns),
    findall(F, ( member(N, Ns), format(atom(F), '~w/kg/YAGO3-10/~w.txt', [D, N]) ), Fs).
split_files(toy, _, Fs) :- repo_root(R), format(atom(F), '~w/tests/toy_kg.txt', [R]), Fs = [F].
split_names(train, [train]).
split_names(all, [train, valid, test]).
split_names(test, [test]).
split_names(heldout, [valid, test]).

kg_files(Name, Split, Fs) :- split_files(Name, Split, Fs).

% load_kg(+Name, +Split): replace the loaded graph with Name's Split (train | all | heldout)
load_kg(Name, Split) :-
    retractall(t(_, _, _)),
    split_files(Name, Split, Fs),
    forall(member(F, Fs), load_triples(F)),
    load_types(Name).

load_triples(F) :-
    setup_call_cleanup(open(F, read, S, [encoding(utf8)]), read_triples(S), close(S)).
read_triples(S) :-
    read_line_to_string(S, L),
    (   L == end_of_file -> true
    ;   (   split_string(L, "\t", " \r", [H0, R0, T0]), H0 \== ""
        ->  atom_string(H, H0), atom_string(R, R0), atom_string(T, T0), assertz(t(R, H, T))
        ;   true ),
        read_triples(S) ).

load_types(fb15k237) :- !,
    retractall(etype(_, _)), retractall(sig(_, _, _)), retractall(cat(_, _)),
    data_dir(D),
    format(atom(ET), '~w/tkrl/entity2type.txt', [D]),
    format(atom(RT), '~w/tkrl/relationType.txt', [D]),
    read_rows(ET, Rows), forall(( member([E|Ts], Rows), member(T, Ts), T \== "" ),
                                ( atom_string(Ea, E), atom_string(Ta, T), assertz(etype(Ea, Ta)) )),
    read_rows(RT, RRows), forall(member([R, H, T|_], RRows),
                                 ( atom_string(Ra, R), atom_string(Ha, H), atom_string(Tb, T), assertz(sig(Ra, Ha, Tb)) )).
load_types(G) :- memberchk(G, [wn18rr, toy]), !,     % names carry the part of speech
    retractall(etype(_, _)), retractall(sig(_, _, _)), retractall(cat(_, _)),
    forall(( t(_, H, T), member(E, [H, T]) ), ( cat(E, _) -> true ; pos_of(E, C), assertz(cat(E, C)) )).
load_types(_) :- retractall(etype(_, _)), retractall(sig(_, _, _)), retractall(cat(_, _)).

% the part of speech is the second-last dot-separated field: dog.n.01 -> n
pos_of(E, C) :- atomic_list_concat(Parts, '.', E), append(_, [C0, _], Parts), !, atom_string(C, C0).
pos_of(_, unknown).

read_rows(F, Rows) :-
    read_file_to_string(F, S, [encoding(utf8)]), split_string(S, "\n", "\r", Ls),
    findall(Fs, ( member(L, Ls), L \== "", split_string(L, "\t", " ", Fs) ), Rows).

kg_relations(Rs) :- findall(R, t(R, _, _), R0), sort(R0, Rs).
kg_size(Triples, Entities, Relations) :-
    aggregate_all(count, t(_, _, _), Triples),
    findall(E, ( t(_, E, _) ; t(_, _, E) ), E0), sort(E0, Es), length(Es, Entities),
    kg_relations(Rs), length(Rs, Relations).
