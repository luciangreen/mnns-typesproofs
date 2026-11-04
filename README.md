# mnns-typesproofs

Expresses manual neuronets in terms of types: what types (declared, learned from data, or
proved) can safely remove from knowledge-graph reasoning and from the networks that manual
neuronets (MNNs) are compiled into, measured on real data.

Everything is SWI-Prolog. One command fetches the data and the other repositories, runs the
tests and every experiment, and writes the tables to `results/`:

```sh
./run.sh            # everything (30-60 minutes; YAGO3-10 is the slow part)
./run.sh quick      # FB15k-237 and WN18RR only, plus the guard and network experiments
./run.sh fetch      # tests and downloads only
./run.sh test       # unit tests only (no downloads)
```

Requirements: SWI-Prolog 9.x (`swipl`), `git`, `tar`, `unzip`, and access to github.com.
See [PROGRAM_REQUIREMENTS.md](PROGRAM_REQUIREMENTS.md).

## The idea in one paragraph

A two-step question over a knowledge graph, `answer(X, Z) :- R1(X, Y), R2(Y, Z)`, costs one
lookup (a *probe*) per fact of R1, whether or not anything is found. Most pairs of relations
never meet: no entity is both a tail of R1 and a head of R2 (88% of the 56,169 pairs in
FB15k-237). **Relational Type Pruning (RTP)** removes such a path before any lookup, when the
kinds of entity at the meeting point cannot match. This repository measures, on three
benchmark graphs, how much work each source of types saves and how many true answers it
costs, with types taken from the training facts and checked on all facts.

## Results (from `results/`)

| Graph | Type source | Paths pruned | Lookups saved | True answers lost |
| --- | --- | --- | --- | --- |
| FB15k-237 | declared Freebase schema | 78.1% | 70.1% | 0.7% |
| FB15k-237 | declared schema + entity filter | 78.1% | 92.6% | 0.9% |
| FB15k-237 | schema, checked against training facts | 32.7% | 18.5% | 0 |
| FB15k-237 | exact (reference: prunes exactly the empty paths) | 88.3% | 83.8% | 0 |
| WN18RR | learned part-of-speech types | 25.6% | 10.8% | 0 |
| WN18RR | learned types + entity filter | 25.6% | 35.0% | 0 |
| YAGO3-10 | exact (no types in the data) | 71.8% | 69.7% | 0 |

On WN18RR, keeping only the top 25% of middle entities by training degree (a stand-in for
top-K score pruning) saves 32.9% of lookups but loses 17.2% of the answers; learned types
with the entity filter save 35.0% and lose none. Running only the kept paths is 5.2x faster
on FB15k-237 with the exact reference, 2.9x with the declared schema, and 1.6x on WN18RR
with learned types and the entity filter (one CPU, median of five runs). In a manual neuronet built by pl2ann from a WN18RR slice, slot types
cut neurons by 59% and edges by 62% with the same answers (deleting the rules RTP prunes adds
nothing on top of slot types there, because pl2ann already intersects the slot domains). `prolog/tuple_guards.pl` deletes
guards on two or more arguments that s2a2's unary prover cannot.

All tables: `results/*.md` (and the same rows in `results/*.csv`). The full write-up is the
report "Relational Type Pruning: What Types Can Safely Remove from Knowledge-Graph
Reasoning".

## Files

| File | What it does |
| --- | --- |
| `run.sh` | The single command: unit tests, downloads into `deps/` and `data/`, experiments into `results/` |
| `prolog/kg.pl` | Loads a graph (`fb15k237`, `wn18rr`, `yago3_10`, `toy`) and split (`train`, `all`, `heldout`, `test`) as `t(Relation, Head, Tail)`, plus its types: `etype/2` and `sig/3` (Freebase, from TKRL) or `cat/2` (WordNet part of speech) |
| `prolog/rtp.pl` | Indexes the graph (`profile/0`), counts paths (`path_stats/4`), learns relational types (`learn_types/0`, `rtype/2`), composes and closes them (`compose/3`, `closure/3`), decides paths (`keep/3`) and middle entities (`entity_ok/4`), and accounts for work saved and answers lost (`evaluate/3`, `evaluate_paths/4`, `three_hop/2`) |
| `prolog/experiments.pl` | Experiments E1-E6 (`run_all/0`, `run_quick/0`), writing `results/` |
| `prolog/mnn_size.pl` | Network size with and without types: writes a WN18RR slice as four programs, converts each with pl2ann, runs each network and compares answers (`mnn_size/0`) |
| `prolog/tuple_guards.pl` | Deletes implied guards on any number of arguments (`implied/4`, `delete_implied/3`), checks deletions on random inputs (`check_on_inputs/4`), compares with s2a2 (`guards_table/0`) |
| `tests/run_tests.pl` | 17 PlUnit tests (68 checks) on `tests/toy_kg.txt` |
| `tests/toy_kg.txt` | A 10-fact WordNet-style graph used by the tests |
| `docs/ALGORITHMS.md` | Each algorithm described in words, with its formula |
| `results/` | Output tables (`.md` and `.csv`) |

Folders made by `run.sh` (not in git): `deps/pl2ann`, `deps/s2a2` (the other repositories),
`data/` (the graphs), `build/` (generated programs and networks).

## Type sources

| Source | Where the types come from | Keeps a path R1 then R2 when |
| --- | --- | --- |
| `none` | nowhere | always |
| `declared` | Freebase signatures (head type, tail type per relation) | R1's tail type = R2's head type, or some entity has both; no signature = keep |
| `checked` | declared, trusted only at relation ends every training fact obeys | as declared where trusted, otherwise keep |
| `learned` | (head kind, tail kind) pairs seen in training facts | a kind is a tail kind of R1 and a head kind of R2 |
| `snapshot` | the paths non-empty in the training graph | the path was non-empty in training |
| `exact` | the graph itself | some entity is a tail of R1 and a head of R2 |
| `top(P)` | entity degree (baseline) | always, but only the top P% of middle entities are probed |

## Running one part

```sh
swipl -g run_tests -t halt tests/run_tests.pl                       # tests
swipl -g "e2_pruning(wn18rr)" -t halt prolog/experiments.pl          # one experiment on one graph
swipl -g "e4_topk(fb15k237)" -t halt prolog/experiments.pl
swipl -g e5_closure -t halt prolog/experiments.pl
swipl -g e6_three_hop -t halt prolog/experiments.pl
swipl -g guards_table -t halt prolog/tuple_guards.pl
swipl -g run_examples -t halt prolog/tuple_guards.pl                 # prints each deleted guard and why
swipl -g mnn_size -t halt prolog/mnn_size.pl                         # needs deps/pl2ann (about 6 minutes)
```

Interactive use:

```prolog
?- [prolog/kg, prolog/rtp].
?- load_kg(wn18rr, train), profile, learn_types.
?- rtype('_similar_to', T).                 % T = [a-s, s-a]
?- keep(learned, '_similar_to', '_hypernym').   % false: pruned
?- path_stats('_hypernym', '_hypernym', SharedMiddles, Derivations).
?- evaluate(learned, yes, Stats).
```

Environment variables: `KG_DATA` (another data folder), `RTP_RESULTS` (another results
folder), `PL2ANN` and `S2A2` (other checkouts of those repositories).

## Data sources

- FB15k-237 (Toutanova et al., 2015) and YAGO3-10 (Mahdisoltani et al., 2015), as released
  with ConvE (Dettmers et al., 2018): https://github.com/TimDettmers/ConvE
- WN18RR with readable entity names: https://github.com/villmow/datasets_knowledge_embedding
- Freebase entity types and relation signatures from TKRL (Xie et al., 2016):
  https://github.com/thunlp/TKRL

## License

BSD 3-Clause, see [LICENSE](LICENSE).
