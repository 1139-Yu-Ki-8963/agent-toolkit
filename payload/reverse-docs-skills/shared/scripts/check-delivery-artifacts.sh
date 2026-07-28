#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$ROOT/shared/references/delivery-reverse-manifest.yml"
python3 "$ROOT/shared/scripts/validate-delivery-folder-catalog.py"
python3 "$ROOT/shared/scripts/validate-skill-surfaces.py"
for skill in surveying-rule-sources-for-reverse-docs classifying-rule-evidence-for-reverse-docs generating-category-rules-for-reverse-docs generating-coding-rules-for-reverse-docs generating-naming-rules-for-reverse-docs generating-placement-rules-for-reverse-docs generating-component-rules-for-reverse-docs generating-unit-designs-for-reverse-docs generating-test-case-list-for-reverse-docs; do
  test -f "$ROOT/.claude/skills/$skill/SKILL.md"
  test -f "$ROOT/.claude/skills/$skill/references/$skill-guide.html"
  rg -q '^name: ' "$ROOT/.claude/skills/$skill/SKILL.md"
  rg -q '^description: \|' "$ROOT/.claude/skills/$skill/SKILL.md"
  rg -q '^invocation: ' "$ROOT/.claude/skills/$skill/SKILL.md"
  rg -q '^type: ' "$ROOT/.claude/skills/$skill/SKILL.md"
done
for sample in レビュー観点表.html テスト方針書.html; do
  python3 "$ROOT/shared/scripts/validate-template-only.py" \
    --sample-output "$ROOT/shared/samples/プロジェクト共通/$sample"
done
if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  python3 "$ROOT/shared/scripts/validate-skill-surfaces.py" --self-test
  python3 "$ROOT/shared/scripts/validate-delivery-folder-catalog.py" --self-test
  python3 "$ROOT/shared/scripts/validate-facts-schema.py" --self-test
  python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" --self-test-owner-paths
  printf '{"deliverables":[]}' > "$tmp/invalid.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/invalid.yml"; then
    echo "self-test expected invalid manifest to fail" >&2; exit 1
  fi
  printf '{"deliverables":[null]}' > "$tmp/invalid-type.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/invalid-type.yml"; then
    echo "self-test expected invalid row type to fail" >&2; exit 1
  fi
  printf '{"deliverables":[{"id":"x","category":"x","title":"x","classification":"template-only","owner":"template-only/missing.html","inputs":[],"outputs":["x"],"validator":"check-delivery-artifacts.sh","prerequisites":[],"stop_conditions":["x"],"publish_status":"implemented","evidence_fields":["x"]}]}' > "$tmp/fabricated-template.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/fabricated-template.yml"; then
    echo "self-test expected fabricated template to fail" >&2; exit 1
  fi
  jq '.deliverables += [.deliverables[0] | .id="duplicate-output"]' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/duplicate-output.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/duplicate-output.yml"; then
    echo "self-test expected duplicate output to fail" >&2; exit 1
  fi
  jq '.deliverables[0].owner="missing-skill-owner"' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/broken-owner.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/broken-owner.yml"; then
    echo "self-test expected broken owner to fail" >&2; exit 1
  fi
  jq '.deliverables[0].owner="generating-glossary-for-reverse-docs"' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/wrong-existing-owner.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/wrong-existing-owner.yml"; then
    echo "self-test expected tech-stack/glossary owner swap to fail" >&2; exit 1
  fi
  jq '.deliverables[0].inputs=["fabricated simultaneous input"]' \
    "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/double-tamper-manifest.yml"
  jq '(.contracts[] | select(.id=="tech-stack") | .inputs)=["fabricated simultaneous input"]' \
    "$ROOT/shared/references/delivery-owner-contracts.json" > "$tmp/double-tamper-registry.json"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" \
    "$tmp/double-tamper-manifest.yml" --owner-registry "$tmp/double-tamper-registry.json"; then
    echo "self-test expected simultaneous manifest/registry tamper to fail against SKILL body" >&2; exit 1
  fi
  jq '.deliverables[0].outputs=["wrong.html"]' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/portal-mismatch.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/portal-mismatch.yml"; then
    echo "self-test expected canonical/portal mismatch to fail" >&2; exit 1
  fi
  jq '.deliverables[0].outputs += ["orphan-unpublished.html"]' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/orphan-output.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/orphan-output.yml"; then
    echo "self-test expected orphan HTML output to fail" >&2; exit 1
  fi
  jq '.deliverables[0].publish_status="unimplemented"' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/unimplemented-card.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/unimplemented-card.yml"; then
    echo "self-test expected unimplemented portal card to fail" >&2; exit 1
  fi
  jq '.deliverables[0].publish_status="invented"' "$ROOT/shared/references/delivery-reverse-manifest.yml" > "$tmp/invalid-publish-status.yml"
  if python3 "$ROOT/shared/scripts/validate-delivery-reverse-manifest.py" "$tmp/invalid-publish-status.yml"; then
    echo "self-test expected invalid publish_status to fail" >&2; exit 1
  fi
  mkdir -p "$tmp/template"
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</body>", "<p>株式会社青空の売上を20%増加する。</p></body>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected fabricated valid-template copy to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/requirements-business-overview.html" "$tmp/template/requirements-business-overview.html"
  printf '<p>株式会社青空の売上を20%%増加する。</p>\n' >> "$tmp/template/requirements-business-overview.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/requirements-business-overview.html"; then
    echo "self-test expected trailing fabricated content to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("<body>", "<body><!-- 株式会社青空の売上を20%増加する。 -->"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected concrete HTML comment to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("<table>", "<table data-customer=\"株式会社青空\">"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected concrete HTML attribute to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</head>", "<script>window.customer=\"青空\"</script></head>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected head script to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("<meta charset=\"utf-8\">", "<meta charset=\"utf-8\"><meta name=customer content=青空>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected unquoted meta value to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</style>", ".leak::after{content:\"青空\"}</style>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected CSS content string to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("<table>", "<table data-customer=青空>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected unquoted data attribute to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</head>", "<svg><text>株式会社青空の売上を20%増加する。</text></svg></head>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected concrete head SVG to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</head>", "<link href=\"customer.css\"></head>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected head link to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/review-checklist.html" "$tmp/template/review-checklist.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("</main>", "<custom>株式会社青空</custom></main>"))' "$tmp/template/review-checklist.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/review-checklist.html"; then
    echo "self-test expected custom tag to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/templates/template-only/batch-requirements.md" "$tmp/template/batch-requirements.md"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("|---|---|", "|---株式会社青空|---|", 1))' "$tmp/template/batch-requirements.md"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" "$tmp/template/batch-requirements.md"; then
    echo "self-test expected fabricated Markdown separator cell to fail" >&2; exit 1
  fi
  cp "$ROOT/shared/samples/プロジェクト共通/レビュー観点表.html" "$tmp/レビュー観点表.html"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace(">プロジェクト<", ">サンプルプロジェクト<").replace(">更新日<", ">更新: 2026-07-23<"))' "$tmp/レビュー観点表.html"
  if python3 "$ROOT/shared/scripts/validate-template-only.py" --sample-output "$tmp/レビュー観点表.html"; then
    echo "self-test expected fabricated sample project/date to fail" >&2; exit 1
  fi
  for stack in typescript-ui python-api-batch sql-data; do
    fixture="$ROOT/shared/references/gold-standard/stacks/$stack"
    python3 "$ROOT/shared/scripts/evaluate-delivery-gold.py" "$fixture"
  done
  cp -R "$ROOT/shared/references/gold-standard/stacks/python-api-batch" "$tmp/gold-broken"
  python3 -c 'import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["unit_artifact_sha256"].pop(next(iter(d["unit_artifact_sha256"]))); p.write_text(json.dumps(d, ensure_ascii=False))' "$tmp/gold-broken/expected-deliverables.json"
  if python3 "$ROOT/shared/scripts/evaluate-delivery-gold.py" "$tmp/gold-broken"; then
    echo "self-test expected independent gold artifact corruption to fail" >&2; exit 1
  fi
  if python3 "$ROOT/shared/scripts/evaluate-delivery-gold.py" \
    "$ROOT/shared/references/gold-standard/stacks/python-api-batch" \
    --inject-extra-content; then
    echo "self-test expected one-byte/full-content gold mismatch to fail" >&2; exit 1
  fi
  cp -R "$ROOT/shared/references/gold-standard/stacks/python-api-batch" "$tmp/gold-false-claim"
  jq '.coverage_matrix += [{"claim":"unexecuted-generator","generated_by":"shared/scripts/not-executed.py","validated_by":"none","decision_source":"fixture"}]' \
    "$tmp/gold-false-claim/expected-deliverables.json" > "$tmp/gold-false-claim/tampered.json"
  mv "$tmp/gold-false-claim/tampered.json" "$tmp/gold-false-claim/expected-deliverables.json"
  if python3 "$ROOT/shared/scripts/evaluate-delivery-gold.py" "$tmp/gold-false-claim"; then
    echo "self-test expected unexecuted generator claim to fail" >&2; exit 1
  fi
  mkdir -p "$tmp/repo/src"; printf 'MUST use kebab-case\nGET /health\n# self-test: DELETE /health\nreturn 1\n' > "$tmp/repo/src/evidence.txt"
  printf 'MUST use kebab-case\n' > "$tmp/repo/README.md"
  printf '{"observed_practices":[],"approved_norms":[{"statement":"MUST use kebab-case","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case"}],"evidence_paths":["src/evidence.txt"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":true}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo"
  printf '{"observed_practices":[],"approved_norms":[{"statement":"invented norm","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case"}],"evidence_paths":["src/evidence.txt"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":true}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected fabricated norm to fail" >&2; exit 1; }
  printf '{"observed_practices":[],"approved_norms":[{"statement":"MUST","evidence_path":"src/evidence.txt","excerpt":"MUST"}],"evidence_paths":["src/evidence.txt"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":true}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected one-word normative fragment to fail" >&2; exit 1; }
  printf '{"observed_practices":[],"approved_norms":[{"statement":"MUST use kebab-case","evidence_path":"README.md","excerpt":"MUST use kebab-case"}],"evidence_paths":["README.md"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":true}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected non-normative README fragment to fail" >&2; exit 1; }
  printf '{"observed_practices":[],"approved_norms":[{"statement":"MUST use kebab-case","evidence_path":"../escape","excerpt":"MUST use kebab-case"}],"evidence_paths":["../escape"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":true}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected evidence escape to fail" >&2; exit 1; }
  printf '{"observed_practices":[],"approved_norms":[],"evidence_paths":"src/evidence.txt","observation_count":"one","exceptions":[],"confidence":"unknown","uncertainties":[],"rule_md_generated":false}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected evidence type violations to fail" >&2; exit 1; }
  evidence_sha="$(shasum -a 256 "$tmp/repo/src/evidence.txt" | awk '{print $1}')"
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[{"field":"route","observed_value":"GET /health","source_path":"src/evidence.txt","source_excerpt":"GET /health","source_line":2,"source_sha256":"%s"}],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo"
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected empty structure to fail" >&2; exit 1; }
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[{"field":"route","observed_value":"a","source_path":"src/evidence.txt","source_excerpt":"GET /health","source_line":2,"source_sha256":"%s"}],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected one-character observed value to fail" >&2; exit 1; }
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[{"field":"route","observed_value":"DELETE /health","source_path":"src/evidence.txt","source_excerpt":"# self-test: DELETE /health","source_line":3,"source_sha256":"%s"}],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected self-test-only DELETE value to fail" >&2; exit 1; }
  printf '{"status":"STOPPED","source_paths":[],"structure":[],"uncertainties":["unit evidenceなし"],"unit_kind":"api","unit_id":"api-1"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo"
  printf '{"status":"STOPPED","source_paths":[],"structure":[],"uncertainties":"unit evidenceなし","unit_kind":"garbage"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected malformed STOPPED schema to fail" >&2; exit 1; }
  printf '{"status":"STOPPED","source_paths":[],"structure":[],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected STOPPED without reason to fail" >&2; exit 1; }
  printf '{"status":"STOPPED","source_paths":["src/evidence.txt"],"structure":[],"uncertainties":[],"unit_kind":"api","unit_id":"api-1"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected STOPPED with evidence to fail" >&2; exit 1; }
  state_input='{"units":[{"kind":"batch","id":"b1"}]}'
  state="$(printf '%s' "$state_input" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/state-verification" --output-dir "$tmp/state-output")"
  test "$state" = D3 || { echo "self-test expected missing non-screen facts to return D3" >&2; exit 1; }
  mkdir -p "$tmp/state-verification/batch-b1/facts"
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[{"field":"entry","observed_value":"GET /health","source_path":"src/evidence.txt","source_excerpt":"GET /health","source_line":2,"source_sha256":"%s"}],"uncertainties":[],"unit_kind":"batch","unit_id":"b1"}' "$evidence_sha" > "$tmp/state-verification/batch-b1/facts/unit-facts.json"
  state="$(printf '%s' "$state_input" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/state-verification" --output-dir "$tmp/state-output")"
  test "$state" = D4 || { echo "self-test expected facts-complete design-missing unit to return D4" >&2; exit 1; }
  cp -R "$tmp/state-verification/batch-b1" "$tmp/state-verification/batch-b2"
  copied_state='{"units":[{"kind":"batch","id":"b2"}]}'
  state="$(printf '%s' "$copied_state" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/state-verification" --output-dir "$tmp/state-output")"
  test "$state" = D3 || { echo "self-test expected b1 facts copied to b2 path to return D3" >&2; exit 1; }
  mkdir -p "$tmp/empty-state-output/バッチ/b1/詳細設計"
  : > "$tmp/empty-state-output/バッチ/b1/詳細設計/バッチ詳細設計書.md"
  state="$(printf '%s' "$state_input" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/state-verification" --output-dir "$tmp/empty-state-output")"
  test "$state" = D4 || { echo "self-test expected empty detailed design to return D4" >&2; exit 1; }
  python3 "$ROOT/shared/scripts/generate-unit-designs.py" \
    --target-repo "$tmp/repo" \
    --facts "$tmp/state-verification/batch-b1/facts/unit-facts.json" \
    --output-dir "$tmp/generated-state-output"
  mkdir -p "$tmp/state-output/バッチ/b1/詳細設計"
  cp "$tmp/generated-state-output/バッチ/b1/詳細設計/バッチ詳細設計書.md" \
    "$tmp/state-output/バッチ/b1/詳細設計/バッチ詳細設計書.md"
  state="$(printf '%s' "$state_input" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/state-verification" --output-dir "$tmp/state-output")"
  test "$state" = D6 || { echo "self-test expected design-complete basic-missing unit to return D6" >&2; exit 1; }
  mkdir -p "$tmp/wrong-kind-verification/batch-b1/facts"
  printf '{"status":"DONE","source_paths":["src/evidence.txt"],"structure":[{"field":"entry","observed_value":"GET /health","source_path":"src/evidence.txt","source_excerpt":"GET /health","source_line":2,"source_sha256":"%s"}],"uncertainties":[],"unit_kind":"api","unit_id":"b1"}' "$evidence_sha" > "$tmp/wrong-kind-verification/batch-b1/facts/unit-facts.json"
  state="$(printf '%s' "$state_input" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/wrong-kind-verification" --output-dir "$tmp/state-output")"
  test "$state" = D3 || { echo "self-test expected batch path with api facts to return D3" >&2; exit 1; }
  mkdir -p "$tmp/screen-verification/screen-home/facts/run-1"
  printf 'not-a-seal\n' > "$tmp/screen-verification/screen-home/facts/run-1/facts.lock"
  screen_state='{"units":[{"kind":"screen","id":"home"}]}'
  state="$(printf '%s' "$screen_state" | python3 "$ROOT/shared/scripts/check-static-delivery-state.py" --target-repo "$tmp/repo" --verification-dir "$tmp/screen-verification" --output-dir "$tmp/state-output")"
  test "$state" = D3 || { echo "self-test expected unverified screen lock to return D3" >&2; exit 1; }
  mkdir -p "$tmp/garbage-screen-verification/screen-home/facts/run-1"
  printf 'garbage: sealed-but-invalid\n' > "$tmp/garbage-screen-verification/screen-home/facts/run-1/facts.yml"
  if bash "$ROOT/shared/scripts/seal-facts.sh" seal "$tmp/garbage-screen-verification/screen-home/facts/run-1" >/dev/null 2>&1; then
    echo "self-test expected screen schema validation before seal" >&2; exit 1
  fi
  printf '{"source_paths":["src/evidence.txt"],"business_purpose":"invented"}' | python3 "$ROOT/shared/scripts/check-unit-design-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected invented unit field to fail" >&2; exit 1; }
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s"}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode survey --target-repo "$tmp/repo"
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s"},{"id":"r2","evidence_path":"src/evidence.txt","excerpt":"GET /health","evidence_kind":"observed_practice","source_sha256":"%s"}]}' "$evidence_sha" "$evidence_sha" > "$tmp/survey-ledger.json"
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s","primary_category":"naming","layer_or_kind":"all","dedupe_key":"naming-kebab","references":[]}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode classification --survey-ledger "$tmp/survey-ledger.json" --target-repo "$tmp/repo"
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"invented excerpt","evidence_kind":"explicit_norm","source_sha256":"%s"}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode survey --target-repo "$tmp/repo" && { echo "self-test expected fabricated survey excerpt to fail" >&2; exit 1; }
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s","primary_category":"invented","layer_or_kind":"all","dedupe_key":"x","references":[]}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode classification --survey-ledger "$tmp/survey-ledger.json" --target-repo "$tmp/repo" && { echo "self-test expected unknown classification category to fail" >&2; exit 1; }
  printf '{"records":[{"id":"r2","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s","primary_category":"naming","layer_or_kind":"all","dedupe_key":"same","references":["missing"]}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode classification --survey-ledger "$tmp/survey-ledger.json" --target-repo "$tmp/repo" && { echo "self-test expected broken classification ID/reference to fail" >&2; exit 1; }
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"MUST use kebab-case","evidence_kind":"explicit_norm","source_sha256":"%s","primary_category":"naming","layer_or_kind":"all","dedupe_key":"same","references":[]},{"id":"r2","evidence_path":"src/evidence.txt","excerpt":"GET /health","evidence_kind":"observed_practice","source_sha256":"%s","primary_category":"coding","layer_or_kind":"all","dedupe_key":"same","references":[]}]}' "$evidence_sha" "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode classification --survey-ledger "$tmp/survey-ledger.json" --target-repo "$tmp/repo" && { echo "self-test expected duplicate classification key to fail" >&2; exit 1; }
  printf '{"records":[{"id":"r1","evidence_path":"src/evidence.txt","excerpt":"GET /health","evidence_kind":"explicit_norm","source_sha256":"%s","primary_category":"naming","layer_or_kind":"all","dedupe_key":"rewrite","references":[]}]}' "$evidence_sha" | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --mode classification --survey-ledger "$tmp/survey-ledger.json" --target-repo "$tmp/repo" && { echo "self-test expected classification evidence rewrite to fail" >&2; exit 1; }
  printf '{"observed_practices":[{"statement":"invented observation","evidence_path":"src/evidence.txt","excerpt":"GET /health"}],"approved_norms":[],"evidence_paths":["src/evidence.txt"],"observation_count":1,"exceptions":[],"confidence":"high","uncertainties":[],"rule_md_generated":false}' | python3 "$ROOT/shared/scripts/check-rule-reverse-evidence.py" --target-repo "$tmp/repo" && { echo "self-test expected fabricated observation to fail" >&2; exit 1; }
  mkdir -p "$tmp/repo/画面/screen-home/テスト項目書" "$tmp/repo/一覧"
  printf '%s\n' '---' 'type: unit-test-spec' '---' '# test' 'GET /health' > "$tmp/repo/画面/screen-home/テスト項目書/単体テスト仕様書.md"
  printf '%s\n' 'screens:' '  - id: screen-home' '    path: 画面/screen-home' > "$tmp/repo/一覧/reverse-screen-registry.yml"
  spec_sha="$(shasum -a 256 "$tmp/repo/画面/screen-home/テスト項目書/単体テスト仕様書.md" | awk '{print $1}')"
  done_cases="$(printf '{"status":"DONE","records":[{"case_id":"TC-1","screen_id":"screen-home","level":"unit","preconditions":[],"steps":["GET /health"],"expected_result":"GET /health","source_path":"画面/screen-home/テスト項目書/単体テスト仕様書.md","source_excerpt":"GET /health","input_kind":"test-spec","screen_registry_path":"一覧/reverse-screen-registry.yml","source_test_spec_path":"画面/screen-home/テスト項目書/単体テスト仕様書.md","source_test_spec_sha256":"%s"}]}' "$spec_sha")"
  stopped_cases='{"status":"STOPPED","records":[]}'
  printf '%s' "$done_cases" | python3 "$ROOT/shared/scripts/generate-test-case-list.py" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html"
  printf '%s' "$stopped_cases" | python3 "$ROOT/shared/scripts/generate-test-case-list.py" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-stopped.html"
  printf '%s' "$done_cases" | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html"
  operation_unit_cases="${done_cases//\"level\":\"unit\"/\"level\":\"operation\"}"
  printf '%s' "$operation_unit_cases" | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html" && { echo "self-test expected operation level with unit spec to fail" >&2; exit 1; }
  bad_screen_cases="${done_cases//screen-home/screen-missing}"
  printf '%s' "$bad_screen_cases" | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html" && { echo "self-test expected nonexistent screen identity to fail" >&2; exit 1; }
  runtime_cases="${done_cases//単体テスト仕様書.md/runtime.py}"
  printf '%s' "$runtime_cases" | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html" && { echo "self-test expected runtime source instead of test spec to fail" >&2; exit 1; }
  printf '%s' "$stopped_cases" | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-stopped.html"
  printf '{"status":"STOPPED","records":[]}' | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" && { echo "self-test expected missing output to fail" >&2; exit 1; }
  printf '{"status":"STOPPED","records":[]}' | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$ROOT/shared/templates/test-case-list.html" && { echo "self-test expected template path as output to fail" >&2; exit 1; }
  printf '{"status":"DONE","records":[{"case_id":"TC-2","screen_id":"screen-home","level":"operation","preconditions":[],"steps":["invented"],"expected_result":"invented","source_path":"src/evidence.txt","source_excerpt":"invented"}]}' | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html" && { echo "self-test expected fabricated test case to fail" >&2; exit 1; }
  printf '{"status":"DONE","records":[{"case_id":"TC-3","screen_id":"screen-home","level":"operation","preconditions":[],"steps":["GET /health"],"expected_result":"GET /health","source_path":"src/evidence.txt","source_excerpt":"return 1"}]}' | python3 "$ROOT/shared/scripts/check-test-case-list-evidence.py" --target-repo "$tmp/repo" --template "$ROOT/shared/templates/test-case-list.html" --output "$tmp/test-case-done.html" && { echo "self-test expected unrelated return 1 excerpt to fail" >&2; exit 1; }
  python3 "$ROOT/shared/scripts/validate-delivery-traceability.py" --self-test
fi
echo "PASS: delivery artifact contracts"
