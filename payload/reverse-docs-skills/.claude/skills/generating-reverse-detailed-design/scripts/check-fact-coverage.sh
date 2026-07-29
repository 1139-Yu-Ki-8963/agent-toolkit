#!/usr/bin/env bash
set -euo pipefail

# check-fact-coverage.sh — facts.yml の「全項目が設計書へ転記済みか」を機械突合する完全性ゲート
#
# 使い方:
#   check-fact-coverage.sh <facts.yml> <画面詳細設計書.md> [<DESIGN.md> ...]
#   check-fact-coverage.sh --self-test
#
# 契約:
#   - facts.yml（shared/references/facts-schema.md 準拠。sections配下9キーの固定インデント構造）の
#     各セクション items[].key を抽出し、後続引数の設計書いずれかに固定文字列で言及されているか確認する。
#   - measurement_pending（⑨実測委譲）セクションの items[].key は、設計書に「実測委譲」の表記が
#     1箇所でもあれば転記済み扱いとする（個別キー一致は不要）。表記が無い場合のみ、他セクションと
#     同様に個別キー一致を要求する。
#   - 未転記が1件でもあれば exit 1（fail-closed）。全件転記済みで exit 0。
#   - **値レベル検証（トークン抽出方式・fail-closed）**: items[].value を全文一致で照合するのではなく、
#     value からコード的トークン（`obj.prop` 形式のドット付き識別子、または2桁以上の数値）を
#     `grep -oE '[A-Za-z_$][A-Za-z0-9_$]*\.[A-Za-z_$][A-Za-z0-9_$]*|[0-9]{2,}'` で抽出し、抽出前に
#     evidence 由来のファイルパス:行番号のようなコード座標ノイズ（例: `Foo.tsx:12`）を除去する。
#     抽出後の各トークンが設計書本文に1箇所も出現しない場合は「未転記トークン」として fail-closed
#     （exit 1）とする。measurement_pending / style セクション、および key に
#     `recount-false-positive` を含む項目は値レベル検証の対象外とする。
#   - --self-test は合成フィクスチャで陽性 exit 0・陰性 exit 1（未転記キー・未転記トークン）・
#     除外セクション/キーでの非検出・座標ノイズ除去の各ケースを自己検証する。
#   - 通常の run_check でも設計書の画面キャプチャ節と基本/詳細テンプレートを検査し、
#     内部語の混入、許可文言・placeholder class/styleの欠落を fail-closed で検出する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。facts.yml の書式・除外分類を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

# facts.yml から「セクション名<TAB>キー<TAB>値」を1行ずつ抽出する。値フィールドが
# 無いitems（evidenceのみ等）は値列が空文字になる。
# 固定インデント契約（shared/references/facts-schema.md）:
#   sections配下のキー(2段目)  = 2スペース
#   items配下の "- key:"(4段目) = 6スペース
#   items配下の "value:"(4段目、keyと同じ項目内) = 8スペース
extract_section_keys() {
  awk '
    function flush_item() {
      if (key != "") print section "\t" key "\t" value
    }
    /^  [a-z_]+:[ \t]*$/ {
      flush_item()
      s = $0
      sub(/^  /, "", s)
      sub(/:[ \t]*$/, "", s)
      section = s
      key = ""
      value = ""
      next
    }
    /^      - key:/ {
      flush_item()
      k = $0
      sub(/^      - key:[ \t]*/, "", k)
      gsub(/^"/, "", k)
      gsub(/"$/, "", k)
      gsub(/^[ \t]+/, "", k)
      gsub(/[ \t]+$/, "", k)
      key = k
      value = ""
      next
    }
    /^        value:/ {
      v = $0
      sub(/^        value:[ \t]*/, "", v)
      gsub(/^"/, "", v)
      gsub(/"$/, "", v)
      gsub(/^[ \t]+/, "", v)
      gsub(/[ \t]+$/, "", v)
      value = v
      next
    }
    END { flush_item() }
  ' "$1"
}

# evidence由来のファイルパス:行番号のようなコード座標ノイズをvalueから除去する。
# 除去しないと「Foo.tsx」「12」のような座標断片がコード的トークンとして誤抽出され、
# 設計書本文に転記されるはずのない座標値の不在で誤って fail-closed になる。
strip_coordinate_noise() {
  # 拡張子の列挙に依存しない。英数字とドットからなる拡張子 + :行番号の形を
  # コード座標とみなし、Python/Java/Ruby/Go等の追加プロファイルでも同じ規則を使う。
  printf '%s' "$1" | sed -E 's#[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+##g'
}

# facts.yml の複数行literal（value内の改行保持形式）が `\n`（バックスラッシュ+nの2文字）
# エスケープとして保存されている場合、トークン抽出時にこれを跨いで前後の識別子が連結し
# 「nfoo.bar」のような存在しない偽トークンが生成される。空白へ置換して連結を断つ。
strip_newline_escapes() {
  printf '%s' "$1" | sed -E 's/\\n/ /g'
}

# コード的トークン（`obj.prop` 形式のドット付き識別子、または2桁以上の数値）を抽出する。
extract_value_tokens() {
  printf '%s' "$1" | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*\.[A-Za-z_$][A-Za-z0-9_$]*|[0-9]{2,}' || true
}

extract_capture_section() {
  awk '
    /^### 画面キャプチャ[[:space:]]*$/ { inside = 1; next }
    inside && /^### / { exit }
    inside { print }
  ' "$1"
}

extract_visible_capture_section() {
  extract_capture_section "$1" | awk '
    /<!--[[:space:]]*.*-->[[:space:]]*$/ { next }
    /<!--[[:space:]]*$/ { comment = 1; next }
    /-->/ { comment = 0; next }
    !comment { print }
  '
}

check_screen_capture_contract() {
  doc="$1"
  [ -f "$doc" ] || return 0
  section="$(extract_visible_capture_section "$doc")"
  [ -z "$section" ] && return 0

  if printf '%s\n' "$section" | grep -Eq '実測委譲|measurement_pending'; then
    echo "  禁止語: 画面キャプチャ節に内部語があります: $doc" >&2
    return 1
  fi

  has_placeholder=0
  if printf '%s\n' "$section" | grep -Fq 'class="screen-capture-placeholder"'; then
    has_placeholder=1
    if ! printf '%s\n' "$section" | grep -Fq '画面キャプチャは未取得です。後続の画面確認で追加します。'; then
      echo "  契約違反: 読者向け未取得文言がありません: $doc" >&2
      return 1
    fi
    if ! printf '%s\n' "$section" | grep -Eq 'color:[[:space:]]*#64748b.*background:[[:space:]]*#f8fafc.*border:[[:space:]]*2px[[:space:]]+dashed[[:space:]]+#94a3b8'; then
      echo "  契約違反: placeholderの灰色・点線枠styleがありません: $doc" >&2
      return 1
    fi
  fi

  if [ "$has_placeholder" -eq 1 ] && printf '%s\n' "$section" | grep -Eq '!\[[^]]*\]\([^)]*\)'; then
    echo "  契約違反: placeholderと画像参照が同時にあります: $doc" >&2
    return 1
  fi
  if [ "$has_placeholder" -eq 0 ] && ! printf '%s\n' "$section" | grep -Eq '!\[[^]]*\]\([^)]*\)'; then
    echo "  契約違反: 画面画像または読者向けplaceholderがありません: $doc" >&2
    return 1
  fi
  return 0
}

check_screen_capture_templates() {
  script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  repo_root="$(CDPATH= cd -- "$script_dir/../../../.." && pwd)"
  basic="$repo_root/shared/templates/リバース検証/画面/基本設計/画面基本設計書.md"
  detail="$repo_root/shared/templates/リバース検証/画面/詳細設計/画面詳細設計書.md"
  for template in "$basic" "$detail"; do
    if ! check_screen_capture_contract "$template"; then
      return 1
    fi
  done
  return 0
}

# facts.yml と設計書群を突合する。未転記があれば return 1。
# 値レベル検証は、value からコード的トークンを抽出し、そのトークンが設計書本文に
# 1箇所も出現しなければ「未転記トークン」としてfail-closed（exit 1）とする。
# measurement_pending / style セクション、および key に recount-false-positive を
# 含む項目は値レベル検証の対象外とする（measurement_pendingは実測委譲設計のため、
# styleは値の厳密転記を要求しない設計慣行のため、recount-false-positiveは既知の
# 誤検知回避のための明示的除外キー）。
run_check() {
  facts_yml="$1"
  shift
  missing=0
  total=0
  token_missing=0

  for doc in "$@"; do
    if ! check_screen_capture_contract "$doc"; then
      return 1
    fi
  done
  if ! check_screen_capture_templates; then
    return 1
  fi

  has_delegation_note=0
  for doc in "$@"; do
    if grep -q "実測委譲" "$doc" 2>/dev/null; then
      has_delegation_note=1
      break
    fi
  done

  rows="$(extract_section_keys "$facts_yml")"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    section="$(printf '%s' "$row" | cut -f1)"
    key="$(printf '%s' "$row" | cut -f2)"
    value="$(printf '%s' "$row" | cut -f3)"
    total=$((total + 1))

    if [ "$section" = "measurement_pending" ] && [ "$has_delegation_note" -eq 1 ]; then
      continue
    fi

    found=0
    esc_key="$(printf '%s' "$key" | sed -E 's/([.[\*^$()+?{}|\\])/\\\1/g')"
    for doc in "$@"; do
      if grep -qE -- "(^|[^A-Za-z0-9_-])${esc_key}([^A-Za-z0-9_-]|\$)" "$doc" 2>/dev/null; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "  未転記: ${key}（分類: ${section}）" >&2
      missing=$((missing + 1))
    fi

    if [ "$section" = "measurement_pending" ] || [ "$section" = "style" ]; then
      continue
    fi
    case "$key" in
      *recount-false-positive*) continue ;;
    esac
    if [ -n "$value" ]; then
      cleaned_value="$(strip_coordinate_noise "$value")"
      cleaned_value="$(strip_newline_escapes "$cleaned_value")"
      tokens="$(extract_value_tokens "$cleaned_value")"
      if [ -n "$tokens" ]; then
        while IFS= read -r token; do
          [ -z "$token" ] && continue
          token_found=0
          for doc in "$@"; do
            if grep -qF -- "$token" "$doc" 2>/dev/null; then
              token_found=1
              break
            fi
          done
          if [ "$token_found" -eq 0 ]; then
            echo "  未転記トークン: ${key} の値中のトークン「${token}」が設計書本文に見当たりません（分類: ${section}）" >&2
            token_missing=$((token_missing + 1))
          fi
        done <<TOKENS
$tokens
TOKENS
      fi
    fi
  done <<EOF
$rows
EOF

  if [ "$missing" -gt 0 ]; then
    echo "完全性ゲート失敗: facts.yml $total 件中 $missing 件が設計書に未転記です（fail-closed）" >&2
    return 1
  fi
  if [ "$token_missing" -gt 0 ]; then
    echo "完全性ゲート失敗: 値レベル検証で $token_missing 件のトークンが設計書に未転記です（fail-closed）" >&2
    return 1
  fi
  echo "完全性ゲート通過: facts.yml $total 件すべてが設計書に転記済みです（値レベル検証含む）"
  return 0
}

screen_capture_placeholder_self_test() {
  tmp="$1"
  script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  repo_root="$(CDPATH= cd -- "$script_dir/../../../.." && pwd)"
  template="$repo_root/shared/templates/リバース検証/画面/詳細設計/画面詳細設計書.md"
  facts="$tmp/screen-capture-facts.yml"
  positive="$tmp/screen-capture-positive.md"
  negative="$tmp/screen-capture-negative.md"
  template_section="$(extract_visible_capture_section "$template")"
  [ -n "$template_section" ] || return 1
  cat > "$facts" <<'YML'
sections:
  import:
    reason: ""
    items:
      - key: capture-fixture-key
        value: ""
YML

  {
    printf '%s\n' '## §3 画面構造' '' '### 画面キャプチャ'
    printf '%s\n' "$template_section"
    printf '%s\n' '' '### 部品構成' '' 'capture-fixture-key'
  } > "$positive"
  printf '%s\n' "$template_section" | sed 's/画面キャプチャは未取得です。後続の画面確認で追加します。/実測委譲/g' | {
    printf '%s\n' '## §3 画面構造' '' '### 画面キャプチャ'
    cat
    printf '%s\n' '' '### 部品構成' '' 'capture-fixture-key'
  } > "$negative"

  if run_check "$facts" "$positive" >/dev/null 2>&1; then
    echo "  [PASS] 画面キャプチャplaceholder: 通常run_checkで実テンプレート由来の許可文言・style"
  else
    echo "  [FAIL] 画面キャプチャplaceholder: 通常run_checkの実テンプレート由来fixtureが不合格" >&2
    return 1
  fi
  if run_check "$facts" "$negative" >/dev/null 2>&1; then
    echo "  [FAIL] 画面キャプチャplaceholder: 通常run_checkで禁止語再混入を検出できない" >&2
    return 1
  else
    echo "  [PASS] 画面キャプチャplaceholder: 通常run_checkで実テンプレート由来fixtureの禁止語再混入を検出"
  fi
}

# 合成フィクスチャによる自己テスト。
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-fact-coverage-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # 陽性フィクスチャ: ①import は設計書に言及され、⑨measurement_pendingは
  # 「実測委譲」表記があるため個別キー一致なしでも転記済み扱いになる。
  cat > "$tmp/facts-pos.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  cat > "$tmp/design-pos.md" <<'MD'
# 画面詳細設計書
## §15.3 依存（import）一覧
import-react-useState を使用する。

## §9 領域別仕様
初期表示件数は実測委譲（画面単位検証で確定）。
MD

  # 陰性フィクスチャ1: import-axios-client が未転記。
  cat > "$tmp/facts-neg1.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
      - key: import-axios-client
        value: "axios から client"
        evidence: "src/screens/Foo/Foo.tsx:2"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  # 陰性フィクスチャ2: measurement_pendingが「実測委譲」表記なし・個別キーも未転記。
  cat > "$tmp/facts-neg2.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  cat > "$tmp/design-neg2.md" <<'MD'
# 画面詳細設計書
## §15.3 依存（import）一覧
import-react-useState を使用する。
MD

  rc=0

  if run_check "$tmp/facts-pos.yml" "$tmp/design-pos.md" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 転記済み+実測委譲表記ありで exit 0"
  else
    echo "  [FAIL] 陽性: 転記済みなのに非0で終了した" >&2
    rc=1
  fi

  if run_check "$tmp/facts-neg1.yml" "$tmp/design-pos.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性1: import未転記1件ありなのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 陰性1: import未転記1件で exit 1"
  fi

  if run_check "$tmp/facts-neg2.yml" "$tmp/design-neg2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性2: 実測委譲表記なし・個別キー未転記なのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 陰性2: 実測委譲表記なし・個別キー未転記で exit 1"
  fi

  # 値レベル検証（トークン抽出方式）フィクスチャ: キーは転記済みだが value 中の
  # コード的トークン（2桁以上の数値）が設計書本文に出現しない（固定props値の
  # 値未転記）ケース。fail-closed のため exit 1 になることを確認する。
  cat > "$tmp/facts-value.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  const:
    reason: ""
    items:
      - key: const-max-count
        value: "MAX_COUNT=100"
        evidence: "src/screens/Foo/Foo.tsx:5"
YML

  cat > "$tmp/design-value-missing.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-max-count を使用する。
MD

  cat > "$tmp/design-value-present.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-max-count を使用する（MAX_COUNT=100）。
MD

  if run_check "$tmp/facts-value.yml" "$tmp/design-value-missing.md" >/dev/null 2>&1; then
    echo "  [FAIL] 値レベル検証陰性: トークン未転記(100)なのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 値レベル検証陰性: トークン未転記(100)で exit 1（fail-closed）"
  fi

  if run_check "$tmp/facts-value.yml" "$tmp/design-value-present.md" >/dev/null 2>&1; then
    echo "  [PASS] 値レベル検証陽性: トークン(100)転記済みで exit 0"
  else
    echo "  [FAIL] 値レベル検証陽性: トークン転記済みなのに非0で終了した" >&2
    rc=1
  fi

  # ドット付き識別子トークン（obj.prop 形式）の陽性・陰性フィクスチャ。
  cat > "$tmp/facts-dotted.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  state:
    reason: ""
    items:
      - key: state-filter-location
        value: "location.state から絞込条件を復元"
        evidence: "src/screens/Foo/Foo.tsx:20"
YML

  cat > "$tmp/design-dotted-present.md" <<'MD'
# 画面詳細設計書
## §4 業務ルール
state-filter-location は location.state を参照して絞込条件を復元する。
MD

  cat > "$tmp/design-dotted-missing.md" <<'MD'
# 画面詳細設計書
## §4 業務ルール
state-filter-location は遷移元の状態から絞込条件を復元する。
MD

  if run_check "$tmp/facts-dotted.yml" "$tmp/design-dotted-present.md" >/dev/null 2>&1; then
    echo "  [PASS] ドット付きトークン陽性: location.state 転記済みで exit 0"
  else
    echo "  [FAIL] ドット付きトークン陽性: 転記済みなのに非0で終了した" >&2
    rc=1
  fi

  if run_check "$tmp/facts-dotted.yml" "$tmp/design-dotted-missing.md" >/dev/null 2>&1; then
    echo "  [FAIL] ドット付きトークン陰性: location.state 未転記なのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] ドット付きトークン陰性: location.state 未転記で exit 1（fail-closed）"
  fi

  # 除外セクション（measurement_pending / style）はトークン未転記でも
  # fail-closed の対象外であることを確認する。
  cat > "$tmp/facts-excluded-section.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        value: "上限200件を実測委譲で確定"
        evidence: "src/screens/Foo/Foo.tsx:12"
  style:
    reason: ""
    items:
      - key: style-max-width
        value: "max-width: 480px"
        evidence: "src/screens/Foo/Foo.tsx:30"
YML

  cat > "$tmp/design-excluded-section.md" <<'MD'
# 画面詳細設計書
## §9 領域別仕様
初期表示件数は実測委譲（画面単位検証で確定）。

## §11 スタイル方針
style-max-width の幅で表示する。
MD

  if run_check "$tmp/facts-excluded-section.yml" "$tmp/design-excluded-section.md" >/dev/null 2>&1; then
    echo "  [PASS] 除外セクション: measurement_pending/style はトークン未転記(200/480)でも exit 0"
  else
    echo "  [FAIL] 除外セクション: measurement_pending/style なのに非0で終了した" >&2
    rc=1
  fi

  # recount-false-positive を含むキーはトークン未転記でも対象外であることを確認する。
  cat > "$tmp/facts-excluded-key.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  const:
    reason: ""
    items:
      - key: const-recount-false-positive-max
        value: "MAX=999"
        evidence: "src/screens/Foo/Foo.tsx:8"
YML

  cat > "$tmp/design-excluded-key.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-recount-false-positive-max を使用する。
MD

  if run_check "$tmp/facts-excluded-key.yml" "$tmp/design-excluded-key.md" >/dev/null 2>&1; then
    echo "  [PASS] 除外キー: recount-false-positive を含むキーはトークン未転記(999)でも exit 0"
  else
    echo "  [FAIL] 除外キー: recount-false-positive を含むキーなのに非0で終了した" >&2
    rc=1
  fi

  # コード座標ノイズ除去フィクスチャ: value に「Foo.tsx:12」のような evidence 由来の
  # 座標断片が混入していても、それ自体をトークンとして要求しないことを確認する。
  cat > "$tmp/facts-noise.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  const:
    reason: ""
    items:
      - key: const-max-count-noisy
        value: "src/screens/Foo/Foo.tsx:12 で MAX_COUNT=100 と定義"
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  cat > "$tmp/design-noise.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-max-count-noisy を使用する（MAX_COUNT=100）。
MD

  if run_check "$tmp/facts-noise.yml" "$tmp/design-noise.md" >/dev/null 2>&1; then
    echo "  [PASS] 座標ノイズ除去: Foo.tsx:12 断片を要求せず exit 0"
  else
    echo "  [FAIL] 座標ノイズ除去: 座標断片をトークンとして誤要求し非0で終了した" >&2
    rc=1
  fi

  # 1-36: 特定の5拡張子に固定せず、同じ「パス.拡張子:行番号」構文を除去する。
  for ext in py rb java go cs rs kt; do
    noisy="src/domain/Worker.${ext}:123 で service.execute=100 と定義"
    cleaned="$(strip_coordinate_noise "$noisy")"
    if printf '%s' "$cleaned" | grep -qF "Worker.${ext}:123"; then
      echo "  [FAIL] 1-36: .${ext} の座標断片が残った" >&2
      rc=1
    fi
  done
  if [ "$rc" -eq 0 ]; then
    echo "  [PASS] 1-36: 7拡張子の座標断片を構文規則で除去"
  fi

  # \n エスケープ除去フィクスチャ: value が複数行literalの改行保持形式（`\n`エスケープ、
  # バックスラッシュ+nの2文字）を含む場合、\n を跨いで前後の識別子が連結し
  # 「nfoo.bar」のような存在しない偽トークンが抽出されるバグが無いことを確認する。
  # store.save と foo.bar が個別に転記済みであれば exit 0 になり、偽トークン
  # 「nfoo.bar」は要求されない。
  cat > "$tmp/facts-newline-escape.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  handler:
    reason: ""
    items:
      - key: handler-store-save
        value: "store.save\nfoo.bar"
        evidence: "src/screens/Foo/Foo.tsx:40"
YML

  cat > "$tmp/design-newline-escape.md" <<'MD'
# 画面詳細設計書
## §5 イベントハンドラ
handler-store-save は store.save と foo.bar を呼び出す。
MD

  if run_check "$tmp/facts-newline-escape.yml" "$tmp/design-newline-escape.md" >/dev/null 2>&1; then
    echo "  [PASS] \\n エスケープ除去: store.save/foo.bar 転記済み・偽トークン nfoo.bar 非要求で exit 0"
  else
    echo "  [FAIL] \\n エスケープ除去: 偽トークン nfoo.bar を要求し非0で終了した" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    if screen_capture_placeholder_self_test "$tmp"; then
      :
    else
      rc=1
    fi
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

facts_yml="${1:?引数1 facts.yml が必要です}"
shift || true
if [ "$#" -lt 1 ]; then
  echo "エラー: 設計書を 1 つ以上指定してください（使い方: check-fact-coverage.sh <facts.yml> <画面詳細設計書.md> [<DESIGN.md> ...]）" >&2
  exit 2
fi
for f in "$facts_yml" "$@"; do
  if [ ! -f "$f" ]; then
    echo "エラー: ファイルが見つかりません: $f" >&2
    exit 2
  fi
done

run_check "$facts_yml" "$@"
