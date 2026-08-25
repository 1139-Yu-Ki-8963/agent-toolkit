#!/usr/bin/env bash
# generating-feature-list-for-reverse-docs: 機能一覧.HTML 決定的生成
#
# Usage: build-feature-list.sh <manifest.json> <output-html-path> [--repo-root <パス>] [--source-file-root <パス>]
#        build-feature-list.sh --self-test
#   --repo-root <パス>: 元データの sourceDir を解決する基準にするディレクトリ。省略すると元データの所在から上へ辿って探す
#   --source-file-root <パス>: sourceDirを保持し、sourceFileの実在だけを対象プロジェクトルート基準で検査する
#
# unit_kind=feature のマニフェストJSONを厳密な契約として扱い、
# delivery-payload/templates/unit-list/feature-list-template.html を土台に決定的にHTMLを生成する。
# Claudeによる手作業のプレースホルダ置換は一切行わない(データ混入防止)。
# 設計判断の正本は generating-feature-list-for-reverse-docs/SKILL.md の「## 設計判断」にある。
#
# 入力JSONスキーマ(契約。unitKind=feature):
# {
#   "generatedAt": "...", "sourceDir": "...", "unitKind": "feature",
#   "strategy": {"extractionMethod": "...", "approvedByUser": true, "unitIdRegex": null, "excludePatterns": []},
#   "detectionSummary": {"unitCount": 0, "unresolvedCount": 0},
#   "units": [{
#     "unitKey": "...", "unitId": null, "unitNameGuess": "...", "kind": "feature|unresolved",
#     "category": "...", "identifier": "...", "sourceFile": "...", "summary": "...",
#     "relatedScreens": [], "relatedApis": [], "relatedTables": [], # relatedApis は API一覧manifest の units[].unitKey を参照する
#     "confidence": "high|medium|low", "fileCount": 0, "detectionMethod": "..."
#   }]
# }
#
# 出力: <output-html-path> に単一HTMLを書き出す。外部依存はMaterial Symbols OutlinedのGoogle Fonts CDNだけを許可する。
#   - kind!=unresolved の units は category(未指定は「未分類」)ごとに大分類セクションへ分けて出力
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - manifest.json の内容は <script type="application/json" id="unit-manifest"> にそのまま埋め込む

set -euo pipefail

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-feature-list-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/features"
  cat > "$tmp/src/features/user-list.ts" <<'EOF'
export function userList() {}
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # sourceDir/sourceFileが絶対パス(1-102対応で正規化される)なマニフェストの期待値を、
  # 生成側と同じ規則(sourceDirはbasename・sourceFileはsourceDirプレフィックス除去)で
  # 正規化してから比較するためのヘルパー。相対パスの場合は無加工。
  expected_normalized_manifest() {
    jq -c -S '
      def normPath($origSd):
        if (type == "string") and startswith("/") then
          if startswith($origSd) then
            (.[($origSd | length):] | ltrimstr("/"))
          else
            (split("/") | last)
          end
        else
          .
        end;
      (.sourceDir // "") as $origSd
      | .sourceDir |= (if test("^/") then (split("/") | last) else . end)
      | .units |= (map(
          if has("sourceFile") then
            .sourceFile |= (if type == "array" then map(normPath($origSd)) else normPath($origSd) end)
          else . end
        ))
    ' "$1"
  }

  # --- ケースa: バックスラッシュ(正規表現風 \d+)を含むidentifier ---
  local manifest_a="$tmp/manifest-a.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    --arg identifier '/master/\d+' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: $identifier,
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_a"

  local out_a="$tmp/out-a.html"
  local _gt_out_a_run _gt_diff_a
  if _gt_out_a_run="$(bash "$script_path" "$manifest_a" "$out_a" 2>&1)"; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    # sourceDir/sourceFileは絶対パス(1-102対応で正規化される)なので、期待値も同じ正規化を適用してから比較する
    expected_normalized_manifest "$manifest_a" > "$expected_a"
    if _gt_diff_a="$(diff -u "$expected_a" "$embedded_a" 2>&1)"; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むidentifierでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むidentifierで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_diff_a" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out_a_run" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースb: 山括弧+実マーカー文字列そのものを含むunitNameGuess ---
  local manifest_b="$tmp/manifest-b.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    --arg unitNameGuess '</script><script>alert(1)</script><div>ユーザー一覧</div>{{MANIFEST_JSON}}<!--CATEGORY_SECTIONS-->' \
    --arg unitKey "'\" onmouseover=\"alert(1)'" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: $unitKey,
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: $unitNameGuess,
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_b"

  local out_b="$tmp/out-b.html"
  if bash "$script_path" "$manifest_b" "$out_b" >/dev/null 2>&1; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    # sourceDir/sourceFileは絶対パス(1-102対応で正規化される)なので、期待値も同じ正規化を適用してから比較する
    expected_normalized_manifest "$manifest_b" > "$expected_b"
    if diff -q "$embedded_b" "$expected_b" >/dev/null 2>&1; then
      if grep -Fq '</script><script>alert(1)</script>' "$out_b" \
        || ! grep -Fq '\u003c/script\u003e\u003cscript\u003ealert(1)\u003c/script\u003e' "$out_b" \
        || ! grep -Fq 'data-unit-key="&#39;&quot; onmouseover=&quot;alert(1)&#39;"' "$out_b" \
        || grep -Fq 'onmouseover="alert(1)' "$out_b"; then
        echo "  [FAIL] ケースb: 危険文字を含むunitNameGuessのapplication/json埋め込みが安全化されていない" >&2
        rc=1
      else
        echo "  [PASS] ケースb: 危険文字+実マーカー文字列衝突を含むunitNameGuessでも埋め込みJSONが原本と完全一致"
      fi
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 回帰確認: 通常マニフェスト(大分類2種・機能2件・unresolved 1件)の可視出力と
  #     validate-manifest.sh --unit-kind feature への影響なし ---
  mkdir -p "$tmp/src/features"
  cat > "$tmp/src/features/inventory-sync.ts" <<'EOF'
export function inventorySync() {}
EOF
  cat > "$tmp/src/features/legacy-batch.ts" <<'EOF'
export function legacyBatch() {}
EOF

  local manifest_normal="$tmp/manifest-normal.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFileA "$tmp/src/features/user-list.ts" \
    --arg sourceFileB "$tmp/src/features/inventory-sync.ts" \
    --arg sourceFileC "$tmp/src/features/legacy-batch.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 3, unresolvedCount: 1},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFileA,
          relatedScreens: ["user-list-screen"],
          relatedApis: ["users-list"],
          relatedTables: ["users"],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        },
        {
          unitKey: "inventory-sync-job",
          kind: "feature",
          category: "在庫管理",
          identifier: "/batch/inventory-sync",
          unitNameGuess: "在庫同期バッチ",
          summary: "在庫データを外部システムと同期する",
          sourceFile: $sourceFileB,
          relatedScreens: [],
          relatedApis: ["inventory-sync"],
          relatedTables: ["inventory", "inventory_log"],
          confidence: "medium",
          fileCount: 1,
          detectionMethod: "manual"
        },
        {
          unitKey: "unresolved-legacy-batch",
          kind: "unresolved",
          category: "未分類",
          identifier: "/batch/legacy",
          unitNameGuess: "旧バッチ処理(要確認)",
          summary: "用途が不明な旧バッチ",
          sourceFile: $sourceFileC,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "low",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_normal"

  local out_normal="$tmp/out-normal.html"
  local regression_ok=1
  if ! bash "$script_path" "$manifest_normal" "$out_normal" >/dev/null 2>&1; then
    regression_ok=0
  elif ! grep -q '在庫データを外部システムと同期する' "$out_normal"; then
    regression_ok=0
  elif ! grep -q 'data-unit-key="user-list-view"' "$out_normal"; then
    regression_ok=0
  elif ! bash "$script_dir/validate-manifest.sh" "$manifest_normal" --unit-kind feature >/dev/null 2>&1; then
    regression_ok=0
  elif ! jq -e '[.units[] | (.relatedApis // [])[]]
                | all(test("^[A-Z]+[[:space:]]+/") | not)' "$manifest_normal" >/dev/null 2>&1; then
    regression_ok=0
  fi

  # 4種類の末尾マーカーを除去し、語頭・語中のOKは保持する。
  local marker_manifest="$tmp/manifest-marker-forms.json" marker_out="$tmp/out-marker-forms.html"
  jq '
    .detectionSummary = {unitCount: 11, unresolvedCount: 0}
    | .units = [
        ["marker-space", "末尾空白 OK"],
        ["marker-paren", "半角括弧(OK)"],
        ["marker-id", "識別子付き(OK) FTR-001"],
        ["marker-wide", "全角括弧（補足）OK"],
        ["marker-leading", "OK処理"],
        ["marker-middle", "決済OK着地"],
        ["issue1-55-a", "名称A(OK) (identA)"],
        ["issue1-55-b", "名称F(OK) identF"],
        ["issue1-55-c", "名称B(OK)"],
        ["issue1-55-d", "名称C（内訳） OK"],
        ["issue1-55-e", "名称D OK"]
      ]
      | .units |= map({
          unitKey: .[0], unitId: null, unitNameGuess: .[1], kind: "feature",
          category: "マーカー検証", identifier: .[0], sourceFile: $sourceFile,
          summary: "表示名検証", relatedScreens: [], relatedApis: [], relatedTables: [],
          confidence: "high", fileCount: 1, detectionMethod: "manual"
        })
  ' --arg sourceFile "$tmp/src/features/user-list.ts" "$manifest_normal" > "$marker_manifest"
  if ! bash "$script_path" "$marker_manifest" "$marker_out" >/dev/null 2>&1 \
    || ! grep -q '<td>末尾空白</td>' "$marker_out" \
    || ! grep -q '<td>半角括弧</td>' "$marker_out" \
    || ! grep -q '<td>識別子付き</td>' "$marker_out" \
    || ! grep -q '<td>全角括弧（補足）</td>' "$marker_out" \
    || ! grep -q '<td>OK処理</td>' "$marker_out" \
    || ! grep -q '<td>決済OK着地</td>' "$marker_out" \
    || ! grep -q '<td>名称A</td>' "$marker_out" \
    || ! grep -q '<td>名称F</td>' "$marker_out" \
    || ! grep -q '<td>名称B</td>' "$marker_out" \
    || ! grep -q '<td>名称C（内訳）</td>' "$marker_out" \
    || ! grep -q '<td>名称D</td>' "$marker_out"; then
    regression_ok=0
  fi

  if [ "$regression_ok" -eq 1 ]; then
    echo "  [PASS] 回帰確認: 末尾4形式を除去し語頭・語中OKを保持、feature検証もPASS"
  else
    echo "  [FAIL] 回帰確認: 可視テーブル内容またはvalidate-manifest.shのPASSに退行が発生した" >&2
    rc=1
  fi

  # --- 1-83: 個別ページリンクのtitle/aria-labelが design-unit-layout.json の
  # kinds.feature.phases.basic(機能設計書.md)から導かれる。可視テキスト(個別ページ)は変えない ---
  local doc_label_manifest="$tmp/manifest-doc-label.json" doc_label_out="$tmp/out-doc-label.html"
  jq '.units[0].designDocPath = "../docs/user-list-view-basic.html"' "$manifest_normal" > "$doc_label_manifest"
  local doc_label_ok=1
  if ! bash "$script_path" "$doc_label_manifest" "$doc_label_out" >/dev/null 2>&1; then
    doc_label_ok=0
  elif ! LC_ALL=C grep -Fq "title = '機能設計書を開く';" "$doc_label_out" \
    || ! LC_ALL=C grep -Fq "aria-label', '機能設計書を開く'" "$doc_label_out" \
    || ! LC_ALL=C grep -Fq "link.textContent = '個別ページ';" "$doc_label_out"; then
    doc_label_ok=0
  fi
  if [ "$doc_label_ok" -eq 1 ]; then
    echo "  [PASS] 1-83: 個別ページリンクのtitle/aria-labelを「機能設計書」から導く(可視テキストは維持)"
  else
    echo "  [FAIL] 1-83: 個別ページリンクのラベルが種別ごとの文書名から導けていない" >&2
    rc=1
  fi

  # --- 1-102: sourceDirが絶対パスの場合、埋め込みJSON内でbasenameへ正規化されること ---
  local abs_manifest="$tmp/manifest-abs-sourcedir.json" abs_out="$tmp/manifest-abs-sourcedir.html"
  jq -n \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: "/tmp/fake-absolute-repo/src",
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$abs_manifest"

  if bash "$script_path" "$abs_manifest" "$abs_out" >/dev/null 2>&1; then
    local embedded_source_dir embedded_source_file
    embedded_source_dir="$(extract_manifest_json "$abs_out" | jq -r '.sourceDir' 2>/dev/null || echo "FAIL")"
    embedded_source_file="$(extract_manifest_json "$abs_out" | jq -r '.units[0].sourceFile' 2>/dev/null || echo "FAIL")"
    # sourceFileはsourceDir("/tmp/fake-absolute-repo/src")配下でない絶対パスのため、フォールバックのbasenameになる
    if [ "$embedded_source_dir" = "src" ] && [ "$embedded_source_file" = "user-list.ts" ]; then
      echo "  [PASS] 1-102: 絶対パスsourceDirがbasename(src)へ、sourceDir配下でない絶対パスsourceFileがbasename(user-list.ts)へ正規化される"
    else
      echo "  [FAIL] 1-102: 絶対パスの正規化に失敗(embedded sourceDir=${embedded_source_dir}, sourceFile=${embedded_source_file})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: 絶対パスsourceDirを持つマニフェストの生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 1-102: sourceFileがsourceDir配下の絶対パスの場合、sourceDirプレフィックスを除いた
  # 相対パスへ正規化されること(basenameへの過剰な切り詰めをしない) ---
  local prefix_manifest="$tmp/manifest-abs-sourcefile-prefix.json" prefix_out="$tmp/manifest-abs-sourcefile-prefix.html"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$prefix_manifest"

  if bash "$script_path" "$prefix_manifest" "$prefix_out" >/dev/null 2>&1; then
    local embedded_source_file_prefix
    embedded_source_file_prefix="$(extract_manifest_json "$prefix_out" | jq -r '.units[0].sourceFile' 2>/dev/null || echo "FAIL")"
    if [ "$embedded_source_file_prefix" = "features/user-list.ts" ]; then
      echo "  [PASS] 1-102: sourceDir配下の絶対パスsourceFileがsourceDirプレフィックス除去(features/user-list.ts)へ正規化される"
    else
      echo "  [FAIL] 1-102: sourceDir配下の絶対パスsourceFileの正規化に失敗(sourceFile=${embedded_source_file_prefix})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: sourceDir配下の絶対パスsourceFileを持つマニフェストの生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- --repo-root: 指定した基準ディレクトリで相対sourceDirを解決できること ---
  # sourceDirはmock-repo-root配下からの相対値のまま保持し、manifest自身は$tmp直下(mock-repo-rootの外)に置く。
  # .git祖先もgeneration-engine/DESIGN.mdもmock-repo-root配下には無いため、--repo-root省略時の
  # 既定解決(マニフェスト所在ディレクトリへのフォールバック)では実在確認が失敗するはずである。
  mkdir -p "$tmp/mock-repo-root/features"
  cat > "$tmp/mock-repo-root/features/order-list.ts" <<'EOF'
export function orderListFeature() {}
EOF
  local repo_root_manifest="$tmp/manifest-repo-root.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: "features",
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {
        unitKey: "order-list-view",
        kind: "feature",
        category: "注文管理",
        identifier: "/master/orders",
        unitNameGuess: "注文一覧表示",
        summary: "注文一覧を表示する",
        sourceFile: "order-list.ts",
        relatedScreens: [],
        relatedApis: [],
        relatedTables: [],
        confidence: "high",
        fileCount: 1,
        detectionMethod: "manual"
      }
    ]
  }' > "$repo_root_manifest"
  local repo_root_out="$tmp/out-repo-root.html" repo_root_default_out="$tmp/out-repo-root-default.html"
  local _rr_out_a
  if _rr_out_a="$(bash "$script_path" "$repo_root_manifest" "$repo_root_out" --repo-root "$tmp/mock-repo-root" 2>&1)"; then
    local _rr_out_b
    if _rr_out_b="$(bash "$script_path" "$repo_root_manifest" "$repo_root_default_out" 2>&1)"; then
      echo "  [FAIL] --repo-root指定: 省略時も成功してしまい、--repo-rootが解決基準を変えていることを確認できない" >&2
      printf '%s\n' "$_rr_out_b" | sed 's/^/    /' >&2
      rc=1
    else
      echo "  [PASS] --repo-root指定: 指定時は成功、省略時は既定の解決基準(マニフェスト所在ディレクトリ)で失敗する"
    fi
  else
    echo "  [FAIL] --repo-root指定: 指定した基準ディレクトリでの相対sourceDir解決に失敗した" >&2
    printf '%s\n' "$_rr_out_a" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- --source-file-root: feature専用生成器の再検証へ対象プロジェクトルートを透過すること ---
  mkdir -p "$tmp/source-file-root/src/features"
  printf '%s\n' 'export function orderListFeature() {}' > "$tmp/source-file-root/src/features/order-list.ts"
  local source_file_root_manifest="$tmp/manifest-source-file-root.json"
  jq '.sourceDir = "docs/design/features" | .units[0].sourceFile = "src/features/order-list.ts"' "$repo_root_manifest" > "$source_file_root_manifest"
  local source_file_root_out="$tmp/out-source-file-root.html" _sfr_out
  if _sfr_out="$(bash "$script_path" "$source_file_root_manifest" "$source_file_root_out" --source-file-root "$tmp/source-file-root" 2>&1)"; then
    echo "  [PASS] --source-file-root指定: feature再検証へ対象プロジェクトルートを透過"
  else
    echo "  [FAIL] --source-file-root指定: feature再検証へ対象プロジェクトルートを透過できない" >&2
    printf '%s\n' "$_sfr_out" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

MANIFEST="${1:?Usage: build-feature-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--catalog <file>] [--repo-root <パス>]}"
OUTPUT_HTML="${2:?Usage: build-feature-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--catalog <file>] [--repo-root <パス>]}"
shift 2 || true

PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
AXES_FILE=""
CATALOG_FILE=""
REPO_ROOT_ARG=""
SOURCE_FILE_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --portal-dir)
      PORTAL_DIR_ARG="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME_ARG="${2:-}"
      shift 2
      ;;
    --catalog)
      # ポータルカタログの JSON。省略時はリポジトリ既定を使う
      CATALOG_FILE="${2:-}"
      shift 2
      ;;
    --axes)
      AXES_FILE="${2:-}"
      shift 2
      ;;
    --repo-root)
      # 元データの sourceDir を解決する基準にするディレクトリ。省略すると元データの所在から上へ辿って探す
      REPO_ROOT_ARG="${2:-}"
      shift 2
      ;;
    --source-file-root)
      # sourceDirを保持し、sourceFileの実在だけを対象プロジェクトルート基準で検査する
      SOURCE_FILE_ROOT_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VALIDATE_FEATURE_CMD=("$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST" --unit-kind feature)
if [ -n "$REPO_ROOT_ARG" ]; then
  VALIDATE_FEATURE_CMD+=(--repo-root "$REPO_ROOT_ARG")
fi
if [ -n "$SOURCE_FILE_ROOT_ARG" ]; then
  VALIDATE_FEATURE_CMD+=(--source-file-root "$SOURCE_FILE_ROOT_ARG")
fi
if ! "${VALIDATE_FEATURE_CMD[@]}"; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

TEMPLATE="$SCRIPT_DIR/../../../delivery-payload/templates/unit-list/feature-list-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../../delivery-payload/templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- HTMLエスケープ(& < > " '。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

# --- 1-83: JS単一引用符文字列リテラルへの埋め込み用エスケープ(\ を最初に処理する)。
# DOC_LABEL_BASIC は HTML属性値ではなく <script> 内のJS文字列リテラルとして埋め込むため、
# html_escape ではなくこちらを使う。
js_escape() {
  printf '%s' "$1" | sed -e "s/\\\\/\\\\\\\\/g" -e "s/'/\\\\'/g"
}

# --- 1-83: 個別ページリンクのtitle/aria-labelを design-unit-layout.json の
# kinds.feature.phases.basic から解決する。宣言が無ければ既定値「機能設計書」へフォールバックする。
DESIGN_UNIT_LAYOUT_FILE="$SCRIPT_DIR/../../../delivery-payload/references/design-unit-layout.json"
doc_label_basic="機能設計書"
if [ -f "$DESIGN_UNIT_LAYOUT_FILE" ]; then
  _feature_basic_filename="$(jq -r '(.kinds.feature.phases.basic[0]) // empty' "$DESIGN_UNIT_LAYOUT_FILE" 2>/dev/null)"
  [ -n "$_feature_basic_filename" ] && doc_label_basic="${_feature_basic_filename%.md}"
fi

strip_ok_marker() {
  printf '%s' "$1" | sed -E '
    s/[[:space:]]*\(OK\)[[:space:]]+\([^()]+\)[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*$//
    s/(）)OK[[:space:]]*$/\1/
    s/[[:space:]]+OK[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]*$//
  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# render_template — 共通関数を source（generation-engine/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"
if [ -f "$SCRIPT_DIR/../shell-injection.sh" ]; then
  . "$SCRIPT_DIR/../shell-injection.sh"
fi
. "$SCRIPT_DIR/../unit-axes.sh"

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
tile_unit_count="$(jq -r '.detectionSummary.unitCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

# --- emptyRelation(1-152)。検出できなかった事実として比率を集計しHTMLへ必ず表示する(0件でも表示) ---
empty_relation_diagnostics_json="$(jq -c '
  .detectionSummary.diagnostics.emptyRelation //
  ( [.units[]? | select(.kind == "feature")] as $f
    | ($f | length) as $total
    | ($f | map(select(((.relatedApis // []) | length) == 0 and ((.relatedTables // []) | length) == 0)) | length) as $count
    | {count: $count, total: $total,
       ratio: (if $total > 0 then ($count / $total) else 0 end),
       threshold: 0.5,
       warning: (if $total > 0 then (($count / $total) > 0.5) else false end)}
  )
' "$MANIFEST")"
tile_empty_relation_count="$(jq -r '.count' <<<"$empty_relation_diagnostics_json")"
tile_empty_relation_ratio_pct="$(jq -r '(.ratio * 1000 | round) / 10' <<<"$empty_relation_diagnostics_json")"
empty_relation_warning="$(jq -r '.warning' <<<"$empty_relation_diagnostics_json")"
empty_relation_message="関連空機能 <strong>${tile_empty_relation_count}</strong> / ${tile_unit_count} 件（${tile_empty_relation_ratio_pct}%）が関連API・関連テーブルの両方とも空です。"
if [ "$empty_relation_warning" = "true" ]; then
  extra_diagnostics_html="<div class=\"pt-callout pt-callout--warning\"><span class=\"material-symbols-outlined pt-callout__icon\" aria-hidden=\"true\">warning</span>${empty_relation_message}</div>"
else
  extra_diagnostics_html="<p class=\"note\">${empty_relation_message}</p>"
fi

# --- 1機能分の <tr> を生成する ---
# 行データはjqの@tsv+bash readではなく、1行1JSONオブジェクト(jq -c)を個別に
# jq -r抽出する方式を採る。@tsv+IFS=タブのreadはタブがPOSIX上「IFS空白」に
# 分類されるため、unitId等の空フィールドが連続すると先頭の空フィールドが
# 消失し列がずれる(実測済みの既知不具合)。build-screen-list.shのrow_html()と
# 同じ「1行分のJSONを丸ごと受け取りjqで各フィールドを引く」方式に統一する。
row_html() {
  local row="$1"
  local unit_id unit_key unit_name summary kind
  local kind_class kind_label

  unit_id="$(jq -r '.unitId // empty' <<<"$row")"
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  unit_name="$(jq -r '.unitNameGuess // ""' <<<"$row")"
  unit_name="$(strip_ok_marker "$unit_name")"
  summary="$(jq -r '.summary // ""' <<<"$row")"
  kind="$(jq -r '.kind // ""' <<<"$row")"

  case "$kind" in
    unresolved) kind_class="kind-unresolved"; kind_label="要確認" ;;
    *)          kind_class="kind-generic";    kind_label="機能" ;;
  esac

  # unitId/unitKey は表示列から外したが、展開行JSのユニット特定(findUnit等)のため
  # trの data-unit-id / data-unit-key 属性として保持する(3セルの制約には抵触しない)。
  printf '<tr data-unit-id="%s" data-unit-key="%s">\n' "$(html_escape "$unit_id")" "$(html_escape "$unit_key")"
  printf '<td>%s</td>\n' "$(html_escape "$unit_name")"
  printf '<td>%s</td>\n' "$(html_escape "$summary")"
  printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  printf '</tr>\n'
}

thead_html() {
  cat <<'EOF'
<thead>
<tr>
<th data-key="unitNameGuess">機能名</th><th data-key="summary">概要</th><th data-key="kind">区分</th>
</tr>
</thead>
EOF
}

# --- 大分類の抽出(初出順を保って重複排除。unresolvedは対象外) ---
categories=""
while IFS= read -r cat; do
  [ -z "$cat" ] && continue
  categories="${categories}${cat}"$'\n'
done < <(jq -r '[.units[] | select(.kind != "unresolved") | (.category // "未分類")] | reduce .[] as $c ([]; if index($c) then . else . + [$c] end) | .[]' "$MANIFEST")

category_count=0
category_sections=""
unresolved_rows=""

if [ -n "$categories" ]; then
  while IFS= read -r cat; do
    [ -z "$cat" ] && continue
    category_count=$((category_count + 1))
    cat_esc="$(html_escape "$cat")"

    cat_rows=""
    cat_feature_count=0
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      cat_feature_count=$((cat_feature_count + 1))
      cat_rows="${cat_rows}$(row_html "$row")"
    done < <(jq -c --arg cat "$cat" '.units[] | select(.kind != "unresolved") | select((.category // "未分類") == $cat)' "$MANIFEST")

    # summary内の .cat-name / .cat-count span は一覧制御JS(カテゴリチップ・
    # カテゴリフィルタ・CSVのカテゴリ列)が参照する契約構造。省略するとチップが出ない
    category_sections="$(cat <<EOF
${category_sections}<details class="module-group" open>
<summary class="cat-header"><span class="cat-name">${cat_esc}</span><span class="cat-count">${cat_feature_count} 機能</span></summary>
<table class="units" data-unit-table>
$(thead_html)
<tbody>
${cat_rows}
</tbody>
</table>
</details>
EOF
)"
  done <<< "$categories"
fi

if [ "$category_count" -eq 0 ]; then
  category_sections='<p class="note">なし</p>'
else
  # build-screen-list.sh の分割ON出力と同じ形(<div class="table-area" data-split-axis="...">
  # でdetails群を包む)に揃える。details.module-groupを使うページは分割軸の宣言を
  # 必須とする規約(一覧-分割軸マーカー)を満たすため。
  category_sections="<div class=\"table-area\" data-split-axis=\"category\">${category_sections}</div>"
fi

while IFS= read -r row; do
  [ -z "$row" ] && continue
  unresolved_rows="${unresolved_rows}$(row_html "$row")"
done < <(jq -c '.units[] | select(.kind == "unresolved")' "$MANIFEST")

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
  unresolved_class="empty"
else
  unresolved_section="$(cat <<EOF
<table class="units" id="unresolved-table" data-unit-table>
$(thead_html)
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
  unresolved_class="has-items pt-callout pt-callout--warning"
fi

# --- sourceDir/sourceFileの絶対パス正規化(1-102): 生成HTMLへ実行環境の絶対パスを焼き込まないため、
# 埋め込み直前にsourceDirが絶対パス(/始まり)ならbasenameへ正規化した一時コピーを作り、
# 以降の埋め込み処理はこちらを参照する。units[].sourceFile(string または string[])が
# sourceDir配下の絶対パスであれば、sourceDirプレフィックスを除いた相対パスへ正規化する
# (原本ファイルへの手がかりを保つため単純basenameにはしない)。sourceDir配下でない
# 想定外の絶対パスはbasenameへフォールバックする。相対パスの場合は無加工(既存の完全一致
# 自己テストへの影響なし)。既存フィクスチャは相対パス("$tmp/src"等)のため退行しない
EMBED_MANIFEST="$MANIFEST"
_manifest_source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
case "$_manifest_source_dir" in
  /*)
    _normalized_source_dir="$(basename "$_manifest_source_dir")"
    # mktempのテンプレートへ直接".json"を後置する形(XXXXXX.json)は乱数展開が
    # 効かない環境があり、コミット93eb2d6793dd30f0ae8320b372c823177c8f301c
    # 「一時ファイル名の乱数展開を効かせる」で拡張子なしのmktemp+mvの2段へ改めた。
    # 単純化して1回のmktempへ戻すな。
    _embed_manifest_base="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0" .sh)-normalized.XXXXXX")"
    EMBED_MANIFEST="${_embed_manifest_base}.json"
    mv "$_embed_manifest_base" "$EMBED_MANIFEST"
    trap 'rm -f "$EMBED_MANIFEST"' EXIT
    jq --arg sd "$_normalized_source_dir" --arg origSd "$_manifest_source_dir" '
      def normPath:
        if (type == "string") and startswith("/") then
          if startswith($origSd) then
            (.[($origSd | length):] | ltrimstr("/"))
          else
            (split("/") | last)
          end
        else
          .
        end;
      .sourceDir = $sd
      | .units |= (map(
          if has("sourceFile") then
            .sourceFile |= (if type == "array" then map(normPath) else normPath end)
          else . end
        ))
    ' "$MANIFEST" > "$EMBED_MANIFEST"
    ;;
esac

# application/json のraw text要素では文字列中の </script> が要素を閉じるため、
# JSON値を変えずにHTML構文上の危険文字だけをJSONエスケープへ正規化する。
unit_manifest_json="$(jq -c . "$EMBED_MANIFEST" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"

# --- ポータルへの相対パス算出 ---
# 正本レイアウト（delivery-payload/references/output-layout.json）: ポータルは <output_dir>/index.html、
# 機能一覧HTMLは <output_dir>/<unitListHtml>（既定 <output_dir>/project-portal/lists/features/機能一覧.html）。
# この2階層は output_dir からの深さが異なるため、呼び出し元は必ず --portal-dir <output_dir> を渡すこと。
# --portal-dir 未指定時のフォールバックは旧2階層レイアウト（<output_dir>/一覧/機能一覧/）を前提とした
# 後方互換値であり、現行レイアウトでは誤ったリンクになる。
if [ -n "$PORTAL_DIR_ARG" ]; then
  portal_relative="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$(dirname "$OUTPUT_HTML")'))" 2>/dev/null || echo "..")/index.html"
else
  portal_relative="../../index.html"
fi

# --- 分類軸・任意列の宣言を解決して注入用 JSON を作る ---
axes_resolved="$(resolve_unit_axes "$MANIFEST" "$AXES_FILE")" || exit 1
column_spec_json="$(unit_axes_script_safe "$(unit_axes_for_kind "$axes_resolved" "feature")")"

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# マニフェストJSONのマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=(
  "{{PROJECT_NAME}}" "$(html_escape "$PROJECT_NAME_ARG")"
  "{{DOC_LABEL_BASIC}}" "$(js_escape "$doc_label_basic")"
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{CATEGORY_COUNT}}" "$category_count"
  "{{UNIT_COUNT}}" "$tile_unit_count"
  "{{UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "{{EMPTY_RELATION_COUNT}}" "$tile_empty_relation_count"
  "<!--EXTRA_DIAGNOSTICS-->" "$extra_diagnostics_html"
  "<!--CATEGORY_SECTIONS-->" "$category_sections"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{PORTAL_RELATIVE}}" "$portal_relative"
  "{{MANIFEST_JSON}}" "$unit_manifest_json"
  "<!--COLUMN_SPEC_JSON-->" "$column_spec_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../../delivery-payload/templates" "$catalog_path" "$portal_relative" "$PROJECT_NAME_ARG" "$generated_at" "" "generation-engine/scripts/unit-list/build-feature-list.sh" "list"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

# 宣言が非空なのに column-spec が出力に無ければ、テンプレートのマーカー欠落。fail-closed。
case "$out" in
  *'id="column-spec"'*) : ;;
  *)
    echo "ERROR: column-spec が出力に注入されていません（テンプレートの <!--COLUMN_SPEC_JSON--> マーカー欠落）" >&2
    exit 1 ;;
esac

# 1-83: 未置換のDOC_LABELマーカーがHTMLへ漏れていないか。fail-closed。
case "$out" in
  *'{{DOC_LABEL_'*)
    echo "ERROR: 資料ラベルのプレースホルダが未置換のまま残っています（{{DOC_LABEL_...}}）" >&2
    exit 1 ;;
esac

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
