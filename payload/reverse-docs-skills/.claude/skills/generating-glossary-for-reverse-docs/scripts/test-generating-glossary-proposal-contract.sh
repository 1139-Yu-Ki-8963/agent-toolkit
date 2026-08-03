#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$skill_dir/../../.." && pwd)"
writer="$skill_dir/scripts/write-glossary-proposal-output.py"
receipt_verifier="$skill_dir/scripts/verify-glossary-proposal-receipt.py"
bundle_emitter="$skill_dir/scripts/emit-verified-glossary-proposal-bundle-entry.py"
bundle_validator="$skill_dir/scripts/validate-verified-glossary-proposal-bundle.py"
validator="$repo_root/shared/scripts/glossary/validate-semantic-glossary.sh"
source_proposal="$repo_root/shared/scripts/glossary/fixtures/valid-proposal.yaml"
source_diagnostics="$skill_dir/fixtures/detected-proposal-diagnostics.json"
registry="$repo_root/shared/scripts/glossary/fixtures/valid-glossary.yaml"
orchestrator="$repo_root/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md"
contract="$repo_root/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md"
readme="$repo_root/README.md"
delivery_layout="$repo_root/shared/references/納品物フォルダ体系.md"
extraction_guide="$skill_dir/references/glossary-extraction.md"
python_bin="$repo_root/shared/scripts/glossary/.venv/bin/python"
[ -x "$python_bin" ] || python_bin="python3"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/glossary-proposal-contract.XXXXXX")"
tmp="$(realpath "$tmp")"
trap 'rm -rf "$tmp"' EXIT
target="$tmp/target-repo"
external="$tmp/proposal-registry"
mkdir -p "$target" "$external"
chmod 700 "$external"
proposal_input="$tmp/proposal-input.yaml"
diagnostics_input="$tmp/diagnostics-input.json"
cp "$source_proposal" "$proposal_input"
cp "$source_diagnostics" "$diagnostics_input"

run_writer() {
  "$python_bin" "$writer" \
    --target-repo "$target" \
    --proposal-output "$1" \
    --proposal-input "$proposal_input" \
    --diagnostics-input "$diagnostics_input"
}

outside="$external/detected-proposal.yaml"
outside_receipt="$tmp/detected-proposal-receipt.json"
run_writer "$outside" >"$outside_receipt"
cmp -s "$proposal_input" "$outside"
cmp -s "$diagnostics_input" "$outside.diagnostics.json"
jq -e '
  .receiptVersion == "1.0.0" and
  .guarantee == "creation_transaction_and_receipt_issuance" and
  .proposal.name == "detected-proposal.yaml" and
  .diagnostics.name == "detected-proposal.yaml.diagnostics.json" and
  (.proposal.sha256 | test("^[a-f0-9]{64}$")) and
  (.diagnostics.sha256 | test("^[a-f0-9]{64}$")) and
  (.proposal.device | type == "number") and
  (.proposal.inode | type == "number")
' "$outside_receipt" >/dev/null
outside_bundle="$tmp/detected-proposal-bundle.json"
"$python_bin" "$receipt_verifier" \
  --receipt "$outside_receipt" \
  --output-directory "$external" >"$outside_bundle"
jq -e '
  .bundleVersion == "1.0.0" and
  .guarantee == "captured_verified_bytes_only" and
  (.sourceReceiptSha256 | test("^[a-f0-9]{64}$")) and
  (.proposal.contentBase64 | type == "string") and
  (.diagnostics.contentBase64 | type == "string")
' "$outside_bundle" >/dev/null
"$python_bin" "$bundle_emitter" --bundle "$outside_bundle" --entry proposal | cmp -s - "$proposal_input"
"$python_bin" "$bundle_emitter" --bundle "$outside_bundle" --entry diagnostics | cmp -s - "$diagnostics_input"

receipt_replaced="$external/receipt-replaced.yaml"
receipt_replaced_record="$tmp/receipt-replaced.json"
run_writer "$receipt_replaced" >"$receipt_replaced_record"
mv "$receipt_replaced" "$external/receipt-replaced.original.yaml"
printf 'receipt-mismatch\n' >"$receipt_replaced"
if "$python_bin" "$receipt_verifier" \
  --receipt "$receipt_replaced_record" \
  --output-directory "$external" >/dev/null 2>&1; then
  echo "FAIL: post-return path replacement matched the writer receipt" >&2
  exit 1
fi

during_output="$external/during-verification.yaml"
during_receipt="$tmp/during-verification-receipt.json"
run_writer "$during_output" >"$during_receipt"
"$python_bin" - "$receipt_verifier" "$during_receipt" "$external" "$during_output" "$proposal_input" <<'PY'
import base64, importlib.util, pathlib, sys
sys.dont_write_bytecode = True

verifier_path, receipt_path, directory, proposal_path, expected_path = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("proposal_receipt_verifier_race", verifier_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
original_read = module.os.read
changed = False
def racing_read(file_fd, size):
    global changed
    if not changed:
        changed = True
        proposal_path.rename(proposal_path.with_suffix(".captured.yaml"))
        proposal_path.write_text("replacement-must-not-reach-bundle\n", encoding="utf-8")
    return original_read(file_fd, size)
module.os.read = racing_read
args = type("Args", (), {"receipt": receipt_path, "output_directory": directory})()
bundle = module.verify(args)
captured = base64.b64decode(bundle["proposal"]["contentBase64"], validate=True)
assert captured == expected_path.read_bytes()
assert proposal_path.read_text(encoding="utf-8") == "replacement-must-not-reach-bundle\n"
PY

mv "$outside" "$external/detected-proposal.after-bundle.yaml"
printf 'post-verification-proposal-replacement\n' >"$outside"
mv "$outside.diagnostics.json" "$external/detected-proposal.after-bundle.diagnostics.json"
printf '{"postVerificationReplacement":true}\n' >"$outside.diagnostics.json"

report="$external/validation-report.json"
"$python_bin" "$bundle_validator" \
  --bundle "$outside_bundle" \
  --validator "$validator" \
  --registry "$registry" \
  --report "$report" >/dev/null
jq -e '.status == "valid" and .sourceKind == "proposal" and .counts.error == 0' "$report" >/dev/null
proposal_status="$("$python_bin" "$bundle_emitter" --bundle "$outside_bundle" --entry proposal | \
  "$python_bin" -c 'import sys, yaml; print(yaml.safe_load(sys.stdin.read())["proposal"]["approval"]["status"])')"
[ "$proposal_status" = "detected" ]
"$python_bin" "$bundle_emitter" --bundle "$outside_bundle" --entry diagnostics | \
  jq -e '.status == "needs_review" and .proposalStatus == "detected"' >/dev/null

assert_rejected() {
  local output="$1"
  if run_writer "$output" >/dev/null 2>&1; then
    printf 'FAIL: unsafe or existing output was accepted: %s\n' "$output" >&2
    exit 1
  fi
}

assert_rejected "relative-proposal.yaml"
assert_rejected "$target/in-repo.yaml"
ln -s "$target" "$tmp/target-link"
assert_rejected "$tmp/target-link/via-symlink.yaml"
insecure="$tmp/insecure-output"
mkdir "$insecure"
chmod 777 "$insecure"
assert_rejected "$insecure/insecure.yaml"

existing="$external/existing.yaml"
printf 'preserve-proposal\n' >"$existing"
assert_rejected "$existing"
grep -q '^preserve-proposal$' "$existing"
test ! -e "$existing.diagnostics.json"

sidecar_existing="$external/sidecar-existing.yaml"
printf 'preserve-sidecar\n' >"$sidecar_existing.diagnostics.json"
assert_rejected "$sidecar_existing"
test ! -e "$sidecar_existing"
grep -q '^preserve-sidecar$' "$sidecar_existing.diagnostics.json"

printf 'protected-proposal\n' >"$target/protected-proposal.yaml"
hardlink_output="$external/hardlink-output.yaml"
ln "$target/protected-proposal.yaml" "$hardlink_output"
assert_rejected "$hardlink_output"
grep -q '^protected-proposal$' "$target/protected-proposal.yaml"

printf 'protected-sidecar\n' >"$target/protected-sidecar.json"
hardlink_sidecar="$external/hardlink-sidecar.yaml"
ln "$target/protected-sidecar.json" "$hardlink_sidecar.diagnostics.json"
assert_rejected "$hardlink_sidecar"
test ! -e "$hardlink_sidecar"
grep -q '^protected-sidecar$' "$target/protected-sidecar.json"

"$python_bin" - "$writer" "$target" "$tmp" "$proposal_input" "$diagnostics_input" <<'PY'
import importlib.util, os, pathlib, sys
sys.dont_write_bytecode = True
writer_path, target_arg, root_arg, proposal_arg, diagnostics_arg = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("proposal_writer", writer_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
parent = root_arg / "race-parent"
moved = root_arg / "race-parent-moved"
parent.mkdir()
parent.chmod(0o700)
args = type("Args", (), {
    "target_repo": target_arg,
    "proposal_output": parent / "race.yaml",
    "proposal_input": proposal_arg,
    "diagnostics_input": diagnostics_arg,
})()
original = module.create_file
calls = 0
def racing_create(directory_fd, name, content):
    global calls
    created = original(directory_fd, name, content)
    calls += 1
    if calls == 1:
        parent.rename(moved)
        parent.symlink_to(target_arg, target_is_directory=True)
    return created
module.create_file = racing_create
try:
    module.write_outputs(args)
except ValueError:
    pass
else:
    raise SystemExit("parent replacement race was accepted")
assert not (target_arg / "race.yaml").exists()
assert not (target_arg / "race.yaml.diagnostics.json").exists()
assert not (moved / "race.yaml").exists()
assert not (moved / "race.yaml.diagnostics.json").exists()
PY

"$python_bin" - "$writer" "$target" "$tmp" "$proposal_input" "$diagnostics_input" <<'PY'
import importlib.util, os, pathlib, sys
sys.dont_write_bytecode = True

writer_path, target_arg, root_arg, proposal_arg, diagnostics_arg = map(pathlib.Path, sys.argv[1:])

def load_writer(suffix):
    spec = importlib.util.spec_from_file_location(f"proposal_writer_{suffix}", writer_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module

def args_for(parent, name):
    return type("Args", (), {
        "target_repo": target_arg,
        "proposal_output": parent / name,
        "proposal_input": proposal_arg,
        "diagnostics_input": diagnostics_arg,
    })()

first_parent = root_arg / "first-output-replaced"
first_parent.mkdir()
first_parent.chmod(0o700)
first_protected = target_arg / "first-protected.yaml"
first_protected.write_text("first-protected\n", encoding="utf-8")
first_module = load_writer("first")
first_original = first_module.create_file
first_calls = 0
def replace_first(directory_fd, name, content):
    global first_calls
    created = first_original(directory_fd, name, content)
    first_calls += 1
    if first_calls == 1:
        os.rename(name, "first-created-moved.yaml", src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.link(first_protected, first_parent / name)
    return created
first_module.create_file = replace_first
try:
    first_module.write_outputs(args_for(first_parent, "first.yaml"))
except OSError:
    pass
else:
    raise SystemExit("first output rename/hardlink replacement was accepted")
assert (first_parent / "first.yaml").read_text(encoding="utf-8") == "first-protected\n"
assert (first_parent / "first-created-moved.yaml").read_bytes() == proposal_arg.read_bytes()
assert not (first_parent / "first.yaml.diagnostics.json").exists()
assert first_protected.read_text(encoding="utf-8") == "first-protected\n"

second_parent = root_arg / "second-output-replaced"
second_parent.mkdir()
second_parent.chmod(0o700)
second_protected = target_arg / "second-protected.json"
second_protected.write_text("second-protected\n", encoding="utf-8")
second_module = load_writer("second")
second_original = second_module.create_file
second_calls = 0
def replace_second(directory_fd, name, content):
    global second_calls
    created = second_original(directory_fd, name, content)
    second_calls += 1
    if second_calls == 2:
        os.rename(name, "second-created-moved.json", src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.link(second_protected, second_parent / name)
    return created
second_module.create_file = replace_second
try:
    second_module.write_outputs(args_for(second_parent, "second.yaml"))
except OSError:
    pass
else:
    raise SystemExit("second output rename/hardlink replacement was accepted")
assert not (second_parent / "second.yaml").exists()
assert (second_parent / "second.yaml.diagnostics.json").read_text(encoding="utf-8") == "second-protected\n"
assert (second_parent / "second-created-moved.json").read_bytes() == diagnostics_arg.read_bytes()
assert second_protected.read_text(encoding="utf-8") == "second-protected\n"
PY

if rg -n 'build-detail-page\.sh|--page glossary|<output_dir>/用語辞書\.html' "$skill_dir/SKILL.md" >/dev/null; then
  echo "FAIL: 互換Skillに直接HTML生成経路が再導入された" >&2
  exit 1
fi
rg -n 'write-glossary-proposal-output\.py' "$skill_dir/SKILL.md" >/dev/null
if rg -n 'proposal\.observations' "$extraction_guide" >/dev/null; then
  echo "FAIL: 抽出ガイドに旧proposal.observationsが残っている" >&2
  exit 1
fi
rg -n 'proposal\.extracted_facts\[\]' "$extraction_guide" >/dev/null
if rg -n '既定値で自動承認|候補の全採用|自動承認したものとして扱う' "$skill_dir/SKILL.md" "$contract" >/dev/null; then
  echo "FAIL: headless自動承認が再導入された" >&2
  exit 1
fi
if rg -n 'generating-glossary-for-reverse-docs.*<output_dir>/用語辞書\.html|generating-glossary-for-reverse-docs（.*二段承認' "$orchestrator" "$contract" >/dev/null; then
  echo "FAIL: orchestratorに旧HTML正規経路が再導入された" >&2
  exit 1
fi
if rg -n 'generating-glossary-for-reverse-docs.*用語辞書\.html|用語辞書\.html.*generating-glossary-for-reverse-docs' "$readme" "$delivery_layout" >/dev/null; then
  echo "FAIL: READMEまたは納品体系に旧HTML正規経路が再導入された" >&2
  exit 1
fi

printf 'PASS: safe writer created and validated external detected proposal plus diagnostics\n'
printf 'PASS: relative, in-repo, symlink, existing, hardlink, and parent replacement cases fail closed\n'
printf 'PASS: first/second output rename-hardlink replacement fails closed without unlinking replacements\n'
printf 'PASS: owner-only output and post-return receipt revalidation contract\n'
printf 'PASS: verification-time and post-verification path replacement cannot alter captured consumer bundle bytes\n'
printf 'PASS: direct glossary HTML and headless auto-approval routes are absent\n'
