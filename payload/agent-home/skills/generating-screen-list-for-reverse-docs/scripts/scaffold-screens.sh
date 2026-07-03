#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 2 スキャフォールド展開
#
# Usage: scaffold-screens.sh <manifest-path> <output-root>
#
# templates/reverse-docs/02_画面基本設計/ の4ファイルセットを
# <output-root>/docs/02_画面基本設計/screen-<画面キー>/ へ複製し、
# frontmatterの機械欄(doc_id/target_screen/route/updated)のみ書き換える。
# §1〜§16本文は一切創作しない(既存 screen-<キー>/ は無条件スキップ、非破壊優先)。
#
# 依存: jq (マニフェストJSONのパースに必須)

set -euo pipefail

MANIFEST="${1:?Usage: scaffold-screens.sh <manifest-path> <output-root>}"
OUTPUT_ROOT="${2:?Usage: scaffold-screens.sh <manifest-path> <output-root>}"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

TEMPLATE_DIR="$HOME/agent-home/templates/reverse-docs/02_画面基本設計"
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: template dir not found: $TEMPLATE_DIR" >&2
  exit 1
fi

DOCS_DIR="$OUTPUT_ROOT/docs/02_画面基本設計"
mkdir -p "$DOCS_DIR"

# README.md (1回のみ・既存なら上書きしない)
if [ ! -f "$DOCS_DIR/README.md" ]; then
  cp "$TEMPLATE_DIR/README.md" "$DOCS_DIR/README.md"
fi

# _共通/ (1回のみ・既存なら上書きしない・0バイトのまま)
if [ ! -d "$DOCS_DIR/_共通" ]; then
  mkdir -p "$DOCS_DIR/_共通"
  cp "$TEMPLATE_DIR/_共通/共通設計書.md" "$DOCS_DIR/_共通/共通設計書.md"
  cp "$TEMPLATE_DIR/_共通/メッセージ定義書.md" "$DOCS_DIR/_共通/メッセージ定義書.md"
fi

today="$(date +%Y-%m-%d)"
screen_count="$(jq '.screens | length' "$MANIFEST")"

# scaffoldStatus 更新後のマニフェストを別ファイルへ書き出す(元マニフェストは検出結果として不変に保つ)
UPDATED_MANIFEST="${MANIFEST%.json}.scaffolded.json"
cp "$MANIFEST" "$UPDATED_MANIFEST"

insert_review_row() {
  # $1: 対象ファイル, $2: 意味キー, $3: 日付, $4: 理由
  local target="$1" key="$2" date="$3" reason="$4"
  awk -v key="$key" -v today="$date" -v reason="$reason" '
    BEGIN{in16=0; wrote=0}
    /^## §16/{print; in16=1; next}
    in16 && /^##[ ]/ && !/^## §16/{in16=0}
    in16 && /^\|---/ && wrote==0 {
      print
      print "| " key " | " today " | " reason " | §1,§3 | 目視確認と手動修正 |"
      wrote=1
      next
    }
    {print}
  ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
}

fill_file_list() {
  # $1: 対象ファイル(画面基本設計書.md), $2: 改行区切りのファイルパス一覧
  local target="$1" filelist="$2"
  [ -z "$filelist" ] && return 0
  # 複数行の値を awk -v へ渡すと macOS標準awk(BSD/one-true-awk)が
  # "newline in string" で即死するため、一時ファイル+getlineで渡す(bash側のみでportable)
  local filesfile
  filesfile="$(mktemp)"
  printf '%s\n' "$filelist" > "$filesfile"
  awk -v filesfile="$filesfile" '
    BEGIN{
      n = 0
      while ((getline line < filesfile) > 0) { n++; arr[n] = line }
      close(filesfile)
      in151=0; wrote=0
    }
    /^### 15\.1/{print; in151=1; next}
    in151 && /^###[ ]/{in151=0}
    in151 && /^\|---/ && wrote==0 {
      print
      for (i=1; i<=n; i++) {
        if (arr[i] != "") {
          print "| " arr[i] " | <export名> | <種別> |"
        }
      }
      wrote=1
      next
    }
    {print}
  ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  rm -f "$filesfile"
}

for i in $(seq 0 $((screen_count - 1))); do
  key="$(jq -r ".screens[$i].screenKey" "$MANIFEST")"
  route="$(jq -r ".screens[$i].route" "$MANIFEST")"
  name_guess="$(jq -r ".screens[$i].screenNameGuess" "$MANIFEST")"
  confidence="$(jq -r ".screens[$i].confidence" "$MANIFEST")"
  files_list="$(jq -r ".screens[$i].files[]" "$MANIFEST" 2>/dev/null || true)"

  screen_dir="$DOCS_DIR/screen-$key"

  if [ -d "$screen_dir" ]; then
    echo "SKIP(existing): $screen_dir" >&2
    jq --argjson idx "$i" '.screens[$idx].scaffoldStatus = "skipped-existing"' "$UPDATED_MANIFEST" > "${UPDATED_MANIFEST}.tmp" && mv "${UPDATED_MANIFEST}.tmp" "$UPDATED_MANIFEST"
    continue
  fi

  mkdir -p "$screen_dir"
  cp "$TEMPLATE_DIR/画面基本設計書.md" "$screen_dir/画面基本設計書.md"
  cp "$TEMPLATE_DIR/単体テスト観点表.md" "$screen_dir/単体テスト観点表.md"
  cp "$TEMPLATE_DIR/結合テスト観点表.md" "$screen_dir/結合テスト観点表.md"

  sed -i '' \
    -e "s|^doc_id: .*|doc_id: screen-$key|" \
    -e "s|^target_screen: .*|target_screen: $name_guess|" \
    -e "s|^route: .*|route: $route|" \
    -e "s|^updated: .*|updated: $today|" \
    "$screen_dir/画面基本設計書.md"

  sed -i '' \
    -e "s|^doc_id: .*|doc_id: unit-test-$key|" \
    -e "s|^target_screen: .*|target_screen: $name_guess|" \
    -e "s|^updated: .*|updated: $today|" \
    "$screen_dir/単体テスト観点表.md"

  sed -i '' \
    -e "s|^doc_id: .*|doc_id: integration-test-$key|" \
    -e "s|^target_screen: .*|target_screen: $name_guess|" \
    -e "s|^updated: .*|updated: $today|" \
    "$screen_dir/結合テスト観点表.md"

  # §15.1 ファイルパス列の機械記入
  fill_file_list "$screen_dir/画面基本設計書.md" "$files_list"

  # confidence が low の画面は §16 要確認事項一覧へ追記
  if [ "$confidence" = "low" ]; then
    insert_review_row "$screen_dir/画面基本設計書.md" "画面境界-自動判定信頼度低" "$today" \
      "画面境界の自動判定信頼度が低い(confidence=low)。ルーティング検出/慣習ディレクトリ検出のいずれも直接一致せず推測を含む"
  fi

  jq --argjson idx "$i" '.screens[$idx].scaffoldStatus = "created"' "$UPDATED_MANIFEST" > "${UPDATED_MANIFEST}.tmp" && mv "${UPDATED_MANIFEST}.tmp" "$UPDATED_MANIFEST"

  echo "CREATED: $screen_dir" >&2
done

echo "OK: scaffold complete -> $DOCS_DIR" >&2
echo "MANIFEST_UPDATED: $UPDATED_MANIFEST" >&2
