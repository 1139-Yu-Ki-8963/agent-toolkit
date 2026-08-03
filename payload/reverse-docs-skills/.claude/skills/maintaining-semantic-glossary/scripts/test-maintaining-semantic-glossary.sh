#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
guide="$skill_dir/references/maintaining-semantic-glossary-guide.html"

"$script_dir/check-skill-contract.test.sh"
grep -Eq '独立CRUD runner.*AIがRead/Grep/Bash/Write/Edit' "$guide"
grep -Fq 'verification/ai-forward-test.json' "$guide"
grep -Fq 'verify-ai-forward-test.py' "$guide"

repo_root="$(cd "$skill_dir/../../.." && pwd)"
python_bin="$repo_root/shared/scripts/glossary/.venv/bin/python"
record="$skill_dir/verification/ai-forward-test.json"
schema="$skill_dir/verification/ai-forward-test-record.schema.json"
negative_dir="$(mktemp -d "${TMPDIR:-/tmp}/maintaining-forward-negative.XXXXXX")"
trap 'rm -rf "$negative_dir"' EXIT
for mutation in exit status counts; do
  tampered="$negative_dir/$mutation.json"
  "$python_bin" - "$record" "$tampered" "$mutation" <<'PY'
import json, pathlib, sys
source, target, mutation = sys.argv[1:]
record = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
observed = record["scenarios"][0]["observed"]
if mutation == "exit":
    observed["validatorExit"] = 99
elif mutation == "status":
    observed["validatorStatus"] = "unavailable"
else:
    observed["counts"] = {"error": 999, "warning": 888, "review_required": 777}
pathlib.Path(target).write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
PY
  if "$python_bin" "$script_dir/verify-ai-forward-test.py" "$tampered" "$schema" "$repo_root" >/dev/null 2>&1; then
    printf 'FAIL: tampered observed.%s was accepted\n' "$mutation" >&2
    exit 1
  fi
done
printf 'PASS: maintaining-semantic-glossary rejects tampered recorded CLI observations\n'

printf 'PASS: maintaining-semantic-glossary deterministic CLI and static contract test\n'
