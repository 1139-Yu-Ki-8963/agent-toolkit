#!/usr/bin/env bash
# 検査: generation-engine/scripts/ 配下の .sh が `jq --argjson <名前> "<値>"` で
# コマンドライン引数へ直接渡している値のうち、既知の安全な用法(許可リスト)に
# 無いものを違反として検出する。
#
# 背景(改善課題1-52の残件): テーブルのメタ情報抽出(extract-table-metadata.sh)で
# 列名一覧を `--argjson` へ直接展開しており、実行環境の引数長上限(Linuxで
# 131,071バイト)を超える900列規模のテーブルで `Argument list too long` により
# 失敗していた。コミット970a9cc(7/29)で一時ファイル+`--slurpfile`へ対策済み
# だったが、コミットac9c6df(8/11)の書き直しで同箇所が `--argjson m
# "$main_cols_json"` の直渡しへ回帰し、対策が消えたことに誰も気付かないまま
# 次の検証で同じ指摘が再度出た。この回帰は本スクリプトが新設される直接の理由
# であり、「対策を入れる」だけでは同じ経路が再び壊れても気付けないことを示す
# 実例である。現物の修正はeff91aa（一時ファイル+`--slurpfile`への再対策)で
# 完了済みだが、対策が消えたことを機械で検知する仕組みがまだ無かった。
#
# 実行時の再現は環境に依存する(macOSにはこの引数長上限が無く、対象OSの
# Linuxにはある)。だがコードの「値を直接argjsonへ渡す形」自体は環境に
# よらず静的に検査できる。実行環境を選ばずCIで機械強制できることが、
# 静的検査として実装した理由である。
#
# 採った方式: 方式B(許可リスト方式・default-deny)。
#   検討した方式A(変数名の規則で「可変長らしい」名前を検出する。例:
#   *cols*/*rows*/*list*/*items* を含む変数名)は単純だが、今回まさに
#   実際に起きた回帰(`main_cols_json`という「らしい」名前から、
#   `mainColumns`というjq側の別名を経由して`--argjson m`という抽象的な
#   1文字名で渡される)のような、キーワードを含まない別名での再導入を
#   確実には拾えない。名前の規則をどれだけ広げても「新しい可変長の値が
#   別の名前で増えたとき」の取りこぼしが理論上常に残る。
#   方式B(許可リスト)は、現存する`--argjson`の使用箇所を全件洗い出し、
#   ファイルパス・jq側の引数名・渡している値(シェル変数参照や式)の3つ組を
#   キーとして許可リストへ登録する。未登録の組み合わせは(それが実際に
#   安全な固定長の値であっても)問答無用で違反として報告し、許可リストへの
#   追記という明示的な判断を要求する。取りこぼしが理論上存在しない
#   (未知の組み合わせは全て検出対象になる)ことを優先し、方式Bを採る。
#   保守コストは許可リストの追記作業として発生するが、追記の要否そのものを
#   機械が毎回問うため、今回のような「対策の消滅に誰も気付かない」事故を
#   構造的に防げる。
#
# 判定できないもの: ある`--argjson`の値が実行時に何バイトになるかは静的には
# わからない。許可リストは「レビュー済みで現時点は問題ない」という記録で
# あり、「未来にわたって安全であることの証明」ではない。許可リストに
# 登録済みの値であっても、渡す実データの性質が変わった場合は改めて
# `--slurpfile`化を検討する必要がある。
#
# 対処法(違反を修正する場合): 値を一時ファイルへ書き出し、
# `jq --slurpfile <名前> <一時ファイル>` で渡す。`extract-table-metadata.sh`の
# `mainColumns`(columnCount/mainColumnsの付与箇所)を参考実装とする。
#
# Usage:
#   check-argjson-unbounded-value.sh [--target <generation-engine/scripts のパス>]
#   check-argjson-unbounded-value.sh --self-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_TARGET="$(cd "$SCRIPT_DIR/.." && pwd)"

# 許可リスト: <相対パス(target基点)>\t<jq側の引数名>\t<渡している値の生テキスト>
# 2026-08-16時点でgeneration-engine/scripts/配下に存在する全`--argjson`使用箇所を
# 洗い出して登録した(104件。2026-08-18時点でrules/build-derived-rules.shの
# newPre/newStop/newを--slurpfile化し、旧登録の誤記3件をmatcher_json 1件へ整理した)。
# 新しい`--argjson`が増えた場合、この一覧に
# 該当する行が無ければ本検査はFAILする。安全な固定長の値だと判断した
# 場合のみ、レビューのうえで行を追記する。
ALLOWLIST_TSV="$(cat <<'EOF'
build-deliverable-inventory.sh	ex	$excluded_json
build-deliverable-inventory.sh	keys	$required_layout_keys
verification/check-coverage.sh	dropped	$dropped_json
verification/prepare-verification-input.sh	ex	$kinds_json
build-deliverable-inventory.sh	layout	$layout_json
build-deliverable-inventory.sh	p	$jq_path_json
build-portal.sh	be	$be_lines
build-portal.sh	behind	$freshness_behind
build-portal.sh	density	$density
build-portal.sh	fe	$fe_lines
build-portal.sh	files	$total_files
build-portal.sh	freshness	$freshness_json
build-portal.sh	kinds	$kinds_json
build-portal.sh	previous	$previous_json
build-portal.sh	scale	$scale_json
build-portal.sh	tests	$tests_json
build-portal.sh	total	$total_lines
detail-pages/build-detail-pages-from-screen-manifest.sh	edgesArg	$existing_edges
extract/aggregate-test-cases.sh	excludedExampleRows	{\"unit\":$excluded_unit,\"integration\":$excluded_integration,\"scenario\":$excluded_scenario}
extract/aggregate-test-cases.sh	scannedByTestType	{\"unit\":$scanned_unit,\"integration\":$scanned_integration,\"scenario\":$scanned_scenario}
extract/aggregate-test-cases.sh	units	$units_json
extract/aggregate-test-viewpoints.sh	units	$units_json
extract/build-matrix-data.sh	hasFeatures	$HAS_FEATURES
extract/build-matrix-data.sh	hasTables	$HAS_TABLES
extract/build-matrix-data.sh	roles	$ROLES_JSON
extract/build-matrix-data.sh	targetTables	$unresolved_tables_value
extract/convert-message-doc-to-manifest.sh	units	$units_json
extract/extract-ai-assets.sh	hooks	$(jq -s -c . "$work/hooks.jsonl")
extract/extract-ai-assets.sh	mechanicalEnforcement	$mechanical
extract/extract-ai-assets.sh	phaseCount	${phase_count:-0}
extract/extract-ai-assets.sh	rules	$(jq -s -c . "$work/rules.jsonl")
extract/extract-ai-assets.sh	skills	$(jq -s -c . "$work/skills.jsonl")
extract/extract-ai-assets.sh	subagents	$(jq -s -c . "$work/subagents.jsonl")
extract/extract-ai-assets.sh	tags	$tags
extract/extract-api-metadata.sh	callers	$callers_json
extract/extract-api-metadata.sh	count	$fallback_count
extract/extract-api-metadata.sh	fb	$fallback_diagnostics_json
extract/extract-api-metadata.sh	tables	$tables_json
extract/extract-api-metadata.sh	total	$total_count
extract/extract-batch-metadata.sh	c	$def_missing
extract/extract-batch-metadata.sh	d	$downstream_json
extract/extract-batch-metadata.sh	diag	$diagnostics_json
extract/extract-batch-metadata.sh	t	$def_total
extract/extract-batch-metadata.sh	t	$tables_json
extract/extract-design-tokens-from-designmd.sh	skippedTables	$SKIPPED_TABLE_COUNT
extract/extract-external-metadata.sh	c	$decl_only
extract/extract-external-metadata.sh	c	$def_missing
extract/extract-external-metadata.sh	diag	$diagnostics_json
extract/extract-external-metadata.sh	t	$decl_total
extract/extract-external-metadata.sh	t	$def_total
extract/extract-feature-metadata.sh	er	$empty_relation_json
extract/extract-feature-metadata.sh	legacy_argument_order	$LEGACY_ARGUMENT_ORDER
extract/extract-feature-metadata.sh	t	$found_tables
extract/extract-icon-usage.sh	dynamicRefCount	$DYNAMIC_REF_COUNT
extract/extract-screen-metadata.sh	add	$add
extract/extract-screen-metadata.sh	i	$index
extract/extract-screen-metadata.sh	paths	$paths_json
extract/extract-screen-metadata.sh	v	$related_json
extract/extract-screen-metadata.sh	v	$roles_json
extract/extract-table-metadata.sh	f	$fk_keys
extract/extract-table-metadata.sh	largeCount	$large_count
extract/extract-table-metadata.sh	n	$col_count
extract/extract-table-metadata.sh	n	$large_count
extract/finalize-extension-manifest.sh	rules	$RULES_JSON
portal-input/build-manifests-from-docs.sh	u	$unit_obj
portal-input/build-manifests-from-docs.sh	unitCount	$unit_count
portal-input/build-manifests-from-docs.sh	units	$units_json
portal-input/build-manifests-from-docs.sh	unresolvedCount	$unresolved_count
rules/build-derived-rules.sh	e	$matcher_json
rules/build-rule-flow-map.sh	known	$known_json
shell-injection.sh	counts	$shell_counts_json
unit-axes.sh	detectAxes	$detect_axes
unit-list/build-screen-list.sh	declared	$split_declared_keys_json
unit-list/check-excluded-kinds-consistency.sh	excluded	$excluded_json
unit-list/check-excluded-kinds-consistency.sh	present	$present_json
unit-list/check-screen-manifest-consistency.sh	allowed	$allowed
unit-list/detect-screens.sh	apiC	$api_cnt
unit-list/detect-screens.sh	axisSum	$axis_sum
unit-list/detect-screens.sh	axisWeight	$axis_weight
unit-list/detect-screens.sh	constC	$const_cnt
unit-list/detect-screens.sh	diagnostics	$diagnostics_json
unit-list/detect-screens.sh	exportC	$export_type_cnt
unit-list/detect-screens.sh	handlerC	$handler_cnt
unit-list/detect-screens.sh	importC	$import_cnt
unit-list/detect-screens.sh	jsxC	$jsx_cnt
unit-list/detect-screens.sh	keys	$sampled_json
unit-list/detect-screens.sh	layers	$layers_json
unit-list/detect-screens.sh	loc	$loc
unit-list/detect-screens.sh	locWeight	$loc_weight
unit-list/detect-screens.sh	n	$layer_n
unit-list/detect-screens.sh	n	$n
unit-list/detect-screens.sh	q1	$q1
unit-list/detect-screens.sh	q2	$q2
unit-list/detect-screens.sh	q3	$q3
unit-list/detect-screens.sh	q4	$q4
unit-list/detect-screens.sh	q5	$q5
unit-list/detect-screens.sh	quantiles	$quantiles_json
unit-list/detect-screens.sh	sampleK	$k
unit-list/detect-screens.sh	score	$score
unit-list/detect-screens.sh	screens	$screens_n12
unit-list/detect-screens.sh	screens	$screens_tie
unit-list/detect-screens.sh	stateC	$state_cnt
unit-list/detect-screens.sh	stratified	$stratified
unit-list/detect-screens.sh	styleC	$style_cnt
unit-list/validate-manifest.sh	allowed	$account_group_values_json
unit-list/validate-manifest.sh	allowed	$account_sub_type_values_json
unit-list/validate-manifest.sh	allowed	$axis_values_json
unit-list/validate-manifest.sh	allowed	$screen_type_values_json
unit-list/validate-manifest.sh	missing	$missing_keys_json
unit-list/validate-manifest.sh	relaxFlag	$shared_with_relax_flag
unit-list/validate-manifest.sh	req	$ITEM_REQUIRED_JSON
unit-list/validate-manifest.sh	req	$TOP_REQUIRED_JSON
verification/check-coverage.sh	exclude	$LIST_EXCLUDE_JSON
EOF
)"

declare -A ALLOWLIST=()

load_allowlist() {
  local file name value key
  while IFS=$'\t' read -r file name value; do
    [ -z "$file" ] && continue
    key="$file"$'\x01'"$name"$'\x01'"$value"
    ALLOWLIST["$key"]=1
  done <<<"$ALLOWLIST_TSV"
}

# 1本の .sh から `--argjson <名前> "<値>"` の出現を全て抜き出し、
# "<行番号>\t<名前>\t<値>" を1出現1行で出力する。値は `$(...)` による
# コマンド置換(内部に二重引用符を含みうる)を1〜2階層まで正しく1個の値として
# 捉える。単純な `[^"]*` では `$(jq ... "$file")` のような入れ子引用符を
# 途中で終端してしまうため、括弧の対応を数える正規表現を使う。
scan_file() {
  local file="$1"
  ARGJSON_SCAN_FILE="$file" perl -ne '
    my $paren = qr/\((?:[^()]|\([^()]*\))*\)/;
    my $val = qr/(?:[^"\\()]|\\.|$paren)*/;
    while (/--argjson\s+(\S+)\s+"($val)"/g) {
      print "$.\t$1\t$2\n";
    }
  ' "$file"
}

# target_dir配下の .sh を全件走査し、許可リストに無い --argjson 使用を
# 違反として報告する。違反0件ならexit 0、1件以上ならexit 1。
# 本スクリプト自身は対象から除く。--argjson の用例を挙げるコメントや
# self_test の合成フィクスチャ(ヒアドキュメント)を、自らへの違反として
# 誤検出してしまうため(check-argjson-unbounded-value自身を自己参照検査
# しない判断はrun-layer-machine-checks.shの自己除外と同じ考え方に倣う)。
run_check() {
  local target_dir_in="$1"
  local target_dir file rel line name value key violations=0
  local self_abs
  target_dir="$(cd "$target_dir_in" && pwd)"
  self_abs="$(cd "$SCRIPT_DIR" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"

  while IFS= read -r file; do
    [ "$file" = "$self_abs" ] && continue
    rel="${file#"$target_dir"/}"
    while IFS=$'\t' read -r line name value; do
      [ -z "$name" ] && continue
      key="$rel"$'\x01'"$name"$'\x01'"$value"
      if [ -z "${ALLOWLIST[$key]:-}" ]; then
        violations=$((violations + 1))
        echo "FAIL: ${rel}:${line}: --argjson ${name} \"${value}\" は許可リストに無い使用である" >&2
        echo "  可変長になりうる値(列・行・要素の一覧等)の直接渡しでないか確認せよ" >&2
        echo "  対処: 値を一時ファイルへ書き出し、jq --slurpfile ${name} <一時ファイル> で渡す" >&2
        echo "  安全な固定長の値だと判断した場合は、check-argjson-unbounded-value.sh の" >&2
        echo "  ALLOWLIST_TSV へ「${rel}<TAB>${name}<TAB>${value}」を追記する" >&2
      fi
    done < <(scan_file "$file")
  done < <(find "$target_dir" -type f -name '*.sh' | sort)

  if [ "$violations" -gt 0 ]; then
    echo "FAIL: 許可リスト外の --argjson 使用が ${violations} 件見つかった" >&2
    return 1
  fi
  echo "PASS: 許可リスト外の --argjson 使用は無い"
  return 0
}

self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-argjson-unbounded-value-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  load_allowlist

  mkdir -p "$tmp/mixed"
  # 実際の回帰(ac9c6dbでの再発)を模した合成データ。$col_count は許可リストに
  # 一時登録して「既知の安全な用法」として通過させ、$main_cols_json は
  # 登録しないことで「未登録の可変長になりうる値」を検出できるかを確認する。
  # run_check には $tmp を渡すため、許可リストのキーは $tmp からの相対パス
  # (mixed/fake-extract.sh)で登録する。
  cat > "$tmp/mixed/fake-extract.sh" <<'EOF'
#!/usr/bin/env bash
add="$(jq -c --argjson n "$col_count" --argjson mainColumns "$main_cols_json" \
  '. + {columnCount: $n, mainColumns: $mainColumns}' <<<"$add")"
EOF

  # $col_count のキーだけ一時的に許可リストへ登録する(本番のALLOWLIST_TSVは
  # 汚さない。self_test関数を抜けるとプロセス終了までALLOWLISTは残るが、
  # 以降の「現行リポジトリ」検査は対象パスが違うため影響しない)。
  ALLOWLIST["mixed/fake-extract.sh"$'\x01'"n"$'\x01'"\$col_count"]=1

  local out rc_run
  out="$(run_check "$tmp" 2>&1)" && rc_run=0 || rc_run=$?

  if [ "$rc_run" -ne 0 ]; then
    echo "  [PASS] 合成データ(未登録のmainColumns): 検出してexit 1"
  else
    echo "  [FAIL] 合成データ(未登録のmainColumns): 検出できずexit 0で通過した" >&2
    rc=1
  fi
  if printf '%s\n' "$out" | grep -qE ':2: --argjson mainColumns'; then
    echo "  [PASS] 合成データ: FAIL報告に mainColumns:2行目 が含まれる"
  else
    echo "  [FAIL] 合成データ: FAIL報告に mainColumns:2行目 が含まれない" >&2
    rc=1
  fi
  if printf '%s\n' "$out" | grep -q -- '--slurpfile'; then
    echo "  [PASS] 合成データ: 対処法(--slurpfile)が出力に含まれる"
  else
    echo "  [FAIL] 合成データ: 対処法(--slurpfile)が出力に含まれない" >&2
    rc=1
  fi
  if printf '%s\n' "$out" | grep -qE 'argjson n "\$col_count"'; then
    echo "  [FAIL] 誤検出: 許可リストへ一時登録した n(\$col_count) が違反として報告された" >&2
    rc=1
  else
    echo "  [PASS] 誤検出防止: 許可リストへ一時登録した n(\$col_count) は違反として報告されない"
  fi
  if printf '%s\n' "$out" | grep -qE '許可リスト外の --argjson 使用が 1 件見つかった'; then
    echo "  [PASS] 合成データ: 違反件数が想定どおり1件(mainColumnsのみ)"
  else
    echo "  [FAIL] 合成データ: 違反件数が想定(1件)と異なる" >&2
    rc=1
  fi
  unset 'ALLOWLIST[mixed/fake-extract.sh'$'\x01''n'$'\x01''$col_count]'

  # 許可リスト内の用法だけを持つ合成データが単独でも exit 0 になることを
  # 確認する(許可リスト方式が「登録すれば通る」ことの裏取り)。こちらは
  # run_check にディレクトリ自体を渡すため、キーはそのディレクトリ内での
  # 相対パス(fake-extract.sh)で登録する。
  mkdir -p "$tmp/safe-only"
  cat > "$tmp/safe-only/fake-extract.sh" <<'EOF'
#!/usr/bin/env bash
add="$(jq -c --argjson n "$col_count" '. + {columnCount: $n}' <<<"$add")"
EOF
  ALLOWLIST["fake-extract.sh"$'\x01'"n"$'\x01'"\$col_count"]=1
  if _gt_out1="$(run_check "$tmp/safe-only" 2>&1)"; then
    echo "  [PASS] 合成データ(登録済みのnのみ): 違反なしでexit 0"
  else
    echo "  [FAIL] 合成データ(登録済みのnのみ): 違反0件のはずがexit 1になった" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    rc=1
  fi
  unset 'ALLOWLIST[fake-extract.sh'$'\x01''n'$'\x01''$col_count]'

  # 現行リポジトリ(generation-engine/scripts/配下)を対象にした実データ検査。
  # 許可リストは105件の既存使用箇所を反映済みのため、違反0件で通るはず。
  if _gt_out2="$(run_check "$DEFAULT_TARGET" 2>&1)"; then
    echo "  [PASS] 現行リポジトリ: generation-engine/scripts/配下に許可リスト外の --argjson 使用は無い"
  else
    echo "  [FAIL] 現行リポジトリ: 許可リスト外の --argjson 使用が見つかった" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

TARGET="$DEFAULT_TARGET"

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") : ;;
  --target)
    while [ $# -gt 0 ]; do
      case "$1" in
        --target) TARGET="${2:?}"; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
      esac
    done
    ;;
  *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
esac

load_allowlist
run_check "$TARGET"
