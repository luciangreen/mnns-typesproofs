# The algorithms, in words

Each algorithm is described by what it does to the data, then a short formula, then the
steps. Predicate names refer to `prolog/`.

## 1 Counting a two-step path (`rtp:path_stats/4`)

**What it measures.** For `answer(X, Z) :- R1(X, Y), R2(Y, Z)`: how many middle entities the
two relations share, and how many answers (derivations, counted with repeats) the join finds.

    derivations(R1, R2) = sum over Y of  (facts of R1 ending at Y) x (facts of R2 starting at Y)

**Steps.** Take R1's tail entities with their counts and R2's head entities with their
counts, both sorted (made once by `profile/0`). Walk the two lists together like a zip: when
the same entity is in both, multiply its counts and add; otherwise step the list that is
behind. No shared entity = an empty path.

## 2 Learning a relational type (`rtp:learn_types/0`)

**What it learns.** For each relation, the kinds of entity it connects, as (head kind, tail
kind) pairs. On WN18RR the kind is the part of speech in the entity's name (`dog.n.01` -> n).

**Steps.** For each relation, go through its training facts, write down (kind of head, kind
of tail) for each, and keep the distinct pairs.

## 3 Deciding a path (`rtp:keep/3`)

| Source | Keeps R1 then R2 when |
| --- | --- |
| learned | some kind is a tail kind of R1 and a head kind of R2 |
| declared | R1's tail type equals R2's head type, or some entity has both types; no signature: keep |
| checked | as declared, but only when every training fact of R1 obeys its tail type and every training fact of R2 obeys its head type; otherwise keep |
| snapshot | the path had a shared middle entity in the training graph |
| exact | the path has a shared middle entity now |

## 4 The entity filter (`rtp:entity_ok/4`)

**What it does.** Inside a kept path, skip a middle entity whose own kind cannot be at both
ends. An entity without a type is never skipped (open world).

## 5 Accounting (`rtp:evaluate/3`)

**Steps.** For every ordered pair of relations: count shared middles and derivations (1); the
probes the path costs are R1's number of facts. If the source prunes the path: add its probes
to "saved" and its derivations to "lost" (non-zero only when the path was not empty). If the
source keeps it and the entity filter is on: for each middle entity the filter rejects, add
its R1 facts to "saved" and (its R1 facts x its R2 facts) to "lost".

## 6 Composition and closure (`rtp:compose/3`, `rtp:closure/3`)

**What it computes.** The kinds a chain of relations can connect. (a, b) followed by (b, c)
gives (a, c). The closure of a type is what any number of repetitions can connect.

**Steps.** Start with the type. Compose the result so far with the type and add the new
pairs. Stop when a round adds nothing. It must stop: the pairs of kinds are finite and each
round only adds.

## 7 Counting three-step paths (`rtp:three_hop/2`)

**Steps.** For each pair R1, R2: go through R2's facts once; for each fact Y -> Z add to Z's
tally the number of R1 facts ending at Y. The tally says how many two-step routes reach each
Z. For each R3, zip the tally with R3's head counts as in (1). A path is pruned with learned
types when the composed type R1.R2.R3 is empty.

## 8 The top-K baseline (`rtp:top_entities/2`)

**Steps.** Rank all entities by degree (number of facts they are in). Keep the top P%. Inside
every path, probe only middle entities that are kept. This stands in for keeping the
highest-scoring entities of an embedding; no embedding is trained.

## 9 Network size (`mnn_size:mnn_size/0`)

**Steps.** Grow a connected slice of WN18RR training facts from a verb-group fact, taking the
five relations in turn. Write one rule per ordered pair of relations. Make four versions:
untyped; with a pl2ann domain file giving each argument position the entities of the kinds
seen there; with the rules RTP prunes deleted; and both. Convert each with pl2ann, count
`neuron/4` and `edge/3` facts, run the network once to its fixpoint, and compare its true
atoms with the program's answers.

## 10 Implied tuple guards (`tuple_guards:implied/4`)

**When a guard can go.** A guard G in a rule body is implied when some clause defining G's
predicate has a head that matches G and every body literal of that clause matches another
literal of the rule (two may match the same one). Matching is one way: it is done against a
frozen copy of the rule, whose variables are made into constants, so only the clause's
variables are filled in and the rule's own variables are never bound or merged. Then the rest of the
rule being true makes that clause prove G.

**Steps.** For each body literal G whose variables all appear elsewhere in the body: rename a
defining clause, freeze a copy of the rule, match the clause's head to the frozen G and each
of its body literals to a literal of the frozen rule; if all match, delete G and repeat on the shorter body. Check: run the program
before and after on 300 random input sets (`check_on_inputs/4`) and compare least models
(bottom-up: apply every rule to the known facts until nothing new appears).

## 11 Timing (`rtp:decide_paths/3`, `rtp:run_paths/3`, `rtp:decide_kinds/2`, `rtp:run_kinds/3`)

**What is timed.** Two steps, separately. *Deciding* is the analysis done once before any
query: going through every pair of relations and listing the paths the source keeps (for
`exact` this means comparing the entity lists, so it costs time; for type sources it is a
lookup in a small table). *Running* is the work every query pays: for each kept path, read
each R1 fact and look up how many R2 facts start at its middle entity. Running is repeated
five times and the median kept.

**With the entity filter.** When the graph has kinds, `profile/0` also groups each relation's
facts by the kind of their tail (`t_kind/3`). The filtered run then reads, for each kept path,
only the R1 facts whose middle entity has an allowed kind, so skipped entities cost nothing.
