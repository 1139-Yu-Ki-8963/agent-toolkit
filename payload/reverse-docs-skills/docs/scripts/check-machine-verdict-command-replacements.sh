#!/usr/bin/env bash

set -eu

test -f generation-engine/samples/project-portal/diagrams/状態遷移図.html
test -f generation-engine/samples/project-portal/diagrams/ER図.html
test -f generation-engine/samples/project-portal/diagrams/画面遷移図.html
test -f generation-engine/samples/project-portal/index.html
bash generation-engine/scripts/verification/check-payload-references.sh

checker_count="$(LC_ALL=C grep -rlE '\[[A-Z-]+(-BLOCK)?\]' delivery-payload/templates/rules/checkers/*.sh 2>/dev/null | LC_ALL=C grep -c .)"
test "$checker_count" -ge 10

test_count="$(find delivery-payload/templates/rules/checkers -maxdepth 1 -type f -name '*.test.sh' -print | LC_ALL=C grep -c .)"
test "$test_count" -ge 10

contract_count="$(LC_ALL=C grep -rl '実装契約' delivery-payload/templates/リバース検証 2>/dev/null | LC_ALL=C grep -c .)"
test "$contract_count" -ge 5

bash generation-engine/scripts/rules/validate-rule-definitions.sh --self-test

layer_count="$(bash generation-engine/scripts/verification/run-layer-machine-checks.sh --list 2>/dev/null | LC_ALL=C grep -c .)"
test "$layer_count" -ge 148
