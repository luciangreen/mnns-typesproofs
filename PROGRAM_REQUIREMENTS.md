# Program requirements

## What the programs must do

1. Load the three benchmark knowledge graphs (FB15k-237, WN18RR, YAGO3-10) and their types, by
   split (training, all, held-out).
2. For every ordered pair (and, on WN18RR, triple) of relations, count exactly: the shared
   middle entities, the probes a join costs and the derivations it finds, without listing them.
3. Decide each path with each type source (none, declared, checked, learned, snapshot, exact)
   and, inside kept paths, each middle entity (the entity filter).
4. Report paths pruned, paths pruned that were not empty, probes saved and answers lost, with
   types learned on training facts and evaluated on all facts.
5. Compare with a score-based baseline (keep only the top P% of entities by degree).
6. Time the evaluation of every kept path, with and without pruning.
7. Compose relational types and compute their closure (a fixpoint).
8. Measure the size of manual neuronets built by pl2ann with and without types, and check the
   networks' answers against their programs.
9. Delete guards on one or more arguments when the rest of the body implies them, compare with
   s2a2's unary guard deletion, and check every deletion on random inputs.
10. Run all of this from one command and write every table as Markdown and CSV.

## Requirements to run

- SWI-Prolog 9.x (tested with 9.x on Linux), on the PATH as `swipl`.
- git, tar, unzip, bash.
- Network access to github.com for the first run (about 150 MB of downloads).
- About 2 GB of memory (YAGO3-10 has 1.09 million facts).

## Correctness checks

- `tests/run_tests.pl`: 17 tests with 68 checks (counting against brute force, pruning only
  empty paths with `exact`, learned types losing nothing on their own graph, closure, guard
  deletion keeping answers, matching never binding the rule's variables, a forced wrong
  deletion being caught).
- The zip count is cross-checked against an actual probing join (`eval_join_count/3`).
