#!/usr/bin/env bash
# run.sh -- the single command: fetch everything, run the tests and every experiment.
#
#   ./run.sh           everything (about 30-60 minutes; YAGO3-10 is the slow part)
#   ./run.sh quick     FB15k-237 and WN18RR only, plus the guard and network experiments
#   ./run.sh test      the unit tests only (no downloads)
#   ./run.sh fetch     the unit tests and the downloads, no experiments
#
# Needs: SWI-Prolog 9 (swipl), git, tar, unzip, and network access to github.com.
# Everything is written inside this folder: deps/ (the other repositories), data/ (the
# graphs) and results/ (the tables, as .md and .csv).
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-all}"

clone() {  # clone <url> <dir>: a shallow copy, once
  [ -d "$2/.git" ] || git clone --depth 1 "$1" "$2"
}

echo "== unit tests"
swipl -g run_tests -t halt tests/run_tests.pl
[ "$MODE" = test ] && exit 0

echo "== other repositories (deps/)"
mkdir -p deps
clone https://github.com/luciangreen/pl2ann deps/pl2ann     # Prolog -> neural network
clone https://github.com/luciangreen/s2a2   deps/s2a2       # proof/types (unary guards)

echo "== knowledge graphs (data/)"
mkdir -p data/raw data/kg data/tkrl
# FB15k-237 and YAGO3-10 as released with ConvE (Dettmers et al., 2018)
clone https://github.com/TimDettmers/ConvE data/raw/ConvE
for g in FB15k-237 YAGO3-10; do
  if [ ! -f "data/kg/$g/train.txt" ]; then
    mkdir -p "data/kg/$g"
    tar -xzf "data/raw/ConvE/$g.tar.gz" -C "data/kg/$g"
  fi
done
# WN18RR with readable entity names (dog.n.01 instead of 02084071), which carry the part
# of speech
clone https://github.com/villmow/datasets_knowledge_embedding data/villmow
# Freebase entity types and relation signatures (TKRL; Xie et al., 2016)
if [ ! -f data/tkrl/relationType.txt ]; then
  clone https://github.com/thunlp/TKRL data/raw/TKRL
  rm -rf data/raw/tkrl_unzip && mkdir -p data/raw/tkrl_unzip
  unzip -q -o data/raw/TKRL/data.zip 'data/TKRL-all-input-v2.zip' -d data/raw/tkrl_unzip
  unzip -q -o data/raw/tkrl_unzip/data/TKRL-all-input-v2.zip entity2type.txt relationType.txt -d data/tkrl
fi

[ "$MODE" = fetch ] && exit 0

echo "== experiments (results/)"
if [ "$MODE" = quick ]; then
  swipl -g run_quick -t halt prolog/experiments.pl
else
  swipl -g run_all -t halt prolog/experiments.pl
fi
swipl -g guards_table -t halt prolog/tuple_guards.pl
swipl -g mnn_size -t halt prolog/mnn_size.pl
echo "== done: see results/"
