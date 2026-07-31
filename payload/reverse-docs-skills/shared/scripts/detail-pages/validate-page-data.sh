#!/usr/bin/env bash
# detail-pages系(用語辞書/技術スタック/画面遷移図/ER図/環境構築手順)共通エンジン:
# page-data.json の独立検証。正本スキーマは同ディレクトリの page-data-schema.md。
#
# Usage: validate-page-data.sh <page-data.json> [--target-repo <path>]
#
# 検査項目:
#   1. json構文        : 妥当なJSONであること
#   2. トップレベル必須キー : pageKind/generatedAt/title/description の存在
#   3. pageKind値        : glossary|techstack|transition|er|env のいずれか
#   4. 型別スロット      : pageKind別の必須キー(page-data-schema.mdの「型別スロット」節が正)の存在
#   5. 孤児参照(transition/erのみ): edges[].from/.to が nodes[].unitKey に、relations[].from/.to が
#      entities[].key にすべて存在すること(unresolved[]記載の参照は解決不能を明示する別経路のため対象外)
#   6. categorySrc整合性(transitionのみ): nodes[]にcategoryを持つノードが1件以上あれば、
#      全ノードのcategorySrcが非空であること(片方だけ付与された中途半端な状態を検出)
#   7. sourceRef実在・行番号(--target-repo指定時のみ):
#      rows/terms/edges/relations/allocations/unresolved の6キー配下の .sourceRef 値について、
#      パス部分(":"より前。文書参照形式.md#は対象外)のtest -f 実在確認と、行番号付与時は
#      そのファイルの総行数(wc -l)以内であることを検証する
#   8. columns型検証(erのみ): entities[].columns[]が存在する場合、name/typeがstring、
#      pk/fk/unique/nullableがboolean(いずれも存在時のみ)であることを検証する
#
# envのenvironment[]は任意フィールド(page-data-schema.mdのT5節が正)。get_slot_keysの必須
# キー(prerequisites/steps/allocations)には含めない。未知キーを拒否する仕組みは無いため、
# environment[]の有無・値は本スクリプトの検証対象外(存在しても失敗しない)。
#
# 違反は該当値の page-data.json 内での行番号(grep -nF で特定。特定不能時は「不明」)付きでstderrへ
# [PASS]/[FAIL] 項目名 — 詳細 の形式で列挙する。1件でもFAILがあればexit 1。全項目PASSでexit 0。
#
# Usage: validate-page-data.sh --self-test で回帰テストを実行する。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

# --- --self-test モード ---
# (a) entities[].columns[]の型が正しいerフィクスチャで、本体がPASS(exit 0)することを検証する
# (b) columns[]内のいずれかのフィールド型が不正なerフィクスチャで、本体がFAIL(exit 1)することを検証する
# (c) 1-144: 存在しないnodes[].unitKeyをtoに持つ孤児edgeを含むtransitionフィクスチャがFAILすることを検証する
# (d) 1-144: manifestScreenCountとnodes[]+route空文字unresolved[]件数が一致しないtransitionフィクスチャがFAILすることを検証する
# (e) 1-144: manifestScreenCountが正しいtransitionフィクスチャがPASSすることを検証する(正常系対照)
# (f) 1-133: steps[].orderに欠番があるenvフィクスチャがFAILすることを検証する
# (g) 1-133: steps[].commandに句点を含む散文が混入したenvフィクスチャがFAILすることを検証する
# (i) 1-133: steps[].orderが連番でcommandが純粋なenvフィクスチャがPASSすることを検証する(正常系対照)
self_test() {
  local script_path="$0"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-page-data-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local data_ok="$tmp/page-data-columns-ok.json"
  jq -n '{
    pageKind: "er",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "ER図",
    description: "self-test用フィクスチャ(columns正常系)",
    legend: [],
    entities: [
      {key: "users", label: "ユーザー", columns: [
        {name: "id", type: "BIGINT", pk: true},
        {name: "role_id", type: "BIGINT", fk: true, nullable: true},
        {name: "email", type: "VARCHAR(255)", unique: true}
      ]},
      {key: "roles", label: "ロール"}
    ],
    relations: [{from: "users", to: "roles", cardinality: "N:1", sourceRef: "migrations/001_init.sql:1"}],
    unresolved: []
  }' > "$data_ok"

  if bash "$script_path" "$data_ok" >/dev/null 2>&1; then
    echo "  [PASS] ケースa: columns[]の型が正しいerフィクスチャでPASS"
  else
    echo "  [FAIL] ケースa: columns[]の型が正しいerフィクスチャが誤ってFAILした" >&2
    rc=1
  fi

  local data_bad="$tmp/page-data-columns-bad.json"
  jq -n '{
    pageKind: "er",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "ER図",
    description: "self-test用フィクスチャ(columns型不正)",
    legend: [],
    entities: [
      {key: "users", label: "ユーザー", columns: [
        {name: "id", type: "BIGINT", pk: "yes"}
      ]}
    ],
    relations: [],
    unresolved: []
  }' > "$data_bad"

  if bash "$script_path" "$data_bad" >/dev/null 2>&1; then
    echo "  [FAIL] ケースb: columns[]の型が不正なerフィクスチャが誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースb: columns[]の型が不正なerフィクスチャで正しくFAIL"
  fi

  # --- ケースc: 孤児edge(存在しないunitKeyへのto)を含むtransitionフィクスチャはFAIL(1-144) ---
  local data_orphan="$tmp/page-data-orphan.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a" * 64),
    manifestScreenCount: 2,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(孤児edge混入)",
    legend: [],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [{from: "home", to: "ghost", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high"}],
    unresolved: []
  }' > "$data_orphan"

  if bash "$script_path" "$data_orphan" >/dev/null 2>&1; then
    echo "  [FAIL] ケースc: 孤児edge混入のtransitionフィクスチャが誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースc: 孤児edge混入のtransitionフィクスチャで正しくFAIL"
  fi

  # --- ケースd: manifestScreenCountとnodes[]+route空文字unresolved件数が不一致ならFAIL(1-144) ---
  local data_count_bad="$tmp/page-data-count-bad.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a" * 64),
    manifestScreenCount: 3,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(ノード件数不一致)",
    legend: [],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [],
    unresolved: []
  }' > "$data_count_bad"

  if bash "$script_path" "$data_count_bad" >/dev/null 2>&1; then
    echo "  [FAIL] ケースd: manifestScreenCount不一致のtransitionフィクスチャが誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースd: manifestScreenCount不一致のtransitionフィクスチャで正しくFAIL"
  fi

  # --- ケースe: manifestScreenCountが正しいtransitionフィクスチャはPASS(正常系対照) ---
  local data_count_ok="$tmp/page-data-count-ok.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a" * 64),
    manifestScreenCount: 3,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(ノード件数一致。route空文字unresolved1件込み)",
    legend: [],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [{from: "home", to: "detail", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high"}],
    unresolved: [{label: "旧画面", reason: "routeが空文字列のため遷移解決不能"}]
  }' > "$data_count_ok"

  if bash "$script_path" "$data_count_ok" >/dev/null 2>&1; then
    echo "  [PASS] ケースe: manifestScreenCountがnodes[]+route空文字unresolved件数と一致するtransitionフィクスチャでPASS"
  else
    echo "  [FAIL] ケースe: manifestScreenCountが正しいtransitionフィクスチャが誤ってFAILした" >&2
    rc=1
  fi

  # --- ケースf: steps[].orderに欠番(1と3で2が欠番)があるenvフィクスチャはFAIL(1-133) ---
  local data_env_gap="$tmp/page-data-env-gap.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ(order欠番)",
    prerequisites: [],
    steps: [
      {order: 1, command: "npm install", note: "依存関係インストール"},
      {order: 3, command: "npm run start", note: "本番起動"}
    ],
    allocations: []
  }' > "$data_env_gap"

  if bash "$script_path" "$data_env_gap" >/dev/null 2>&1; then
    echo "  [FAIL] ケースf: order欠番(1,3)のenvフィクスチャが誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースf: order欠番(1,3)のenvフィクスチャで正しくFAIL"
  fi

  # --- ケースg: steps[].commandに句点を含む散文が混入したenvフィクスチャはFAIL(1-133) ---
  local data_env_prose="$tmp/page-data-env-prose.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ(command散文混入)",
    prerequisites: [],
    steps: [
      {order: 1, command: "リポジトリ全体を対象とする単一のビルドコマンドは検出されない。", note: "出所: アーキテクチャ調査書.md#§3"}
    ],
    allocations: []
  }' > "$data_env_prose"

  if bash "$script_path" "$data_env_prose" >/dev/null 2>&1; then
    echo "  [FAIL] ケースg: command欄に散文が混入したenvフィクスチャが誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースg: command欄に散文が混入したenvフィクスチャで正しくFAIL"
  fi

  # --- ケースi: orderが連番(1,2)でcommandが純粋、かつ"該当なし"も許容されるenvフィクスチャはPASS(正常系対照) ---
  local data_env_ok="$tmp/page-data-env-ok.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ(order連番・command純粋)",
    prerequisites: [],
    steps: [
      {order: 1, command: "該当なし", note: "リポジトリ全体を対象とする単一のビルドコマンドは検出されない(出所: アーキテクチャ調査書.md#§3)"},
      {order: 2, command: "npm run dev", note: "開発サーバー起動"}
    ],
    allocations: []
  }' > "$data_env_ok"

  if bash "$script_path" "$data_env_ok" >/dev/null 2>&1; then
    echo "  [PASS] ケースi: order連番・command純粋(該当なし含む)のenvフィクスチャでPASS"
  else
    echo "  [FAIL] ケースi: order連番・command純粋なenvフィクスチャが誤ってFAILした" >&2
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

MANIFEST="${1:-}"
if [ -z "$MANIFEST" ]; then
  echo "Usage: validate-page-data.sh <page-data.json> [--target-repo <path>]" >&2
  exit 1
fi
shift

TARGET_REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target-repo)
      TARGET_REPO="${2:-}"
      if [ -z "$TARGET_REPO" ]; then
        echo "Usage: validate-page-data.sh <page-data.json> [--target-repo <path>]" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Usage: validate-page-data.sh <page-data.json> [--target-repo <path>]" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: page-data not found: $MANIFEST" >&2
  exit 1
fi

# --- 1. json構文 ---
if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "[FAIL] json構文 — 妥当なJSONではありません" >&2
  exit 1
fi
echo "[PASS] json構文 — 妥当なJSON" >&2

overall_fail=0

# $1 の値(リテラル文字列)を page-data.json 内で grep -nF して最初にマッチした行番号を返す。
# 見つからなければ空文字。
line_of() {
  grep -nF -- "$1" "$MANIFEST" 2>/dev/null | head -1 | cut -d: -f1
}

# --- 2. トップレベル必須キー ---
missing_top="$(jq -r '["pageKind","generatedAt","title","description"] - keys | join(",")' "$MANIFEST")"
if [ -n "$missing_top" ]; then
  overall_fail=1
  echo "[FAIL] トップレベル必須キー — 欠落: ${missing_top}" >&2
else
  echo "[PASS] トップレベル必須キー — pageKind/generatedAt/title/descriptionすべて存在" >&2
fi

# --- 3. pageKind値 ---
PAGE_KIND="$(jq -r '.pageKind // ""' "$MANIFEST")"
case "$PAGE_KIND" in
  glossary|techstack|transition|er|env|entity-state|release-notes|design-system|component-inventory|icon-catalog)
    echo "[PASS] pageKind値 — '${PAGE_KIND}'は許可値" >&2
    ;;
  *)
    overall_fail=1
    ln="$(line_of "\"pageKind\"")"
    echo "[FAIL] pageKind値 — 不正な値: '${PAGE_KIND}'(行番号: ${ln:-不明})。glossary|techstack|transition|er|env|entity-state|release-notes|design-system|component-inventory|icon-catalogのいずれかである必要があります" >&2
    ;;
esac

if [ "$PAGE_KIND" = "transition" ]; then
  manifest_hash="$(jq -r '.manifestContentHash // ""' "$MANIFEST")"
  if ! printf '%s' "$manifest_hash" | grep -Eq '^[0-9a-f]{64}$'; then
    overall_fail=1
    echo "[FAIL] manifestContentHash — transitionでは64桁lowercase hexが必須" >&2
  else
    echo "[PASS] manifestContentHash — 64桁lowercase hex" >&2
  fi

  # --- manifestScreenCount必須 + ノード件数整合(1-144) ---
  # nodes[]件数 + unresolved[](routeが空文字列のため遷移解決不能)件数が、raw manifestの
  # 全screens件数(manifestScreenCount)と一致することを検証する。入力マニフェストの画面が
  # ノードにもroute空文字unresolvedにも現れず欠落する事故(1-144)を機械検知する。
  has_screen_count="$(jq -r 'has("manifestScreenCount")' "$MANIFEST")"
  if [ "$has_screen_count" != "true" ]; then
    overall_fail=1
    echo "[FAIL] manifestScreenCount — transitionでは必須キーです(欠落)" >&2
  else
    screen_count_type="$(jq -r '.manifestScreenCount | type' "$MANIFEST")"
    if [ "$screen_count_type" != "number" ]; then
      overall_fail=1
      echo "[FAIL] manifestScreenCount — 数値ではありません(型: ${screen_count_type})" >&2
    else
      node_count_check="$(jq -r '
        (.manifestScreenCount) as $declared
        | ((.nodes // []) | length) as $nodeCount
        | ([(.unresolved // [])[] | select(.reason == "routeが空文字列のため遷移解決不能")] | length) as $routeEmptyCount
        | ($nodeCount + $routeEmptyCount) as $actual
        | if $actual == $declared then "PASS" else "FAIL:\($declared):\($actual)" end
      ' "$MANIFEST")"
      case "$node_count_check" in
        PASS)
          echo "[PASS] ノード件数整合 — nodes[]件数+route空文字unresolved件数がmanifestScreenCountと一致" >&2
          ;;
        FAIL:*)
          overall_fail=1
          declared_val="$(printf '%s' "$node_count_check" | cut -d: -f2)"
          actual_val="$(printf '%s' "$node_count_check" | cut -d: -f3)"
          echo "[FAIL] ノード件数整合 — manifestScreenCount(${declared_val})とnodes[]+route空文字unresolved件数(${actual_val})が不一致。画面がノードから欠落している可能性があります" >&2
          ;;
      esac
    fi
  fi
fi

if [ "$PAGE_KIND" = "env" ]; then
  # --- steps[].order 連番性(1-133) ---
  order_check="$(jq -r '
    (.steps // []) as $steps
    | ($steps | length) as $n
    | if $n == 0 then "PASS" else
        ([$steps[].order] | sort) as $sorted
        | ([range(1; $n + 1)]) as $expected
        | if $sorted == $expected then "PASS" else "FAIL:\($sorted | tostring)" end
      end
  ' "$MANIFEST" 2>/dev/null)"
  case "$order_check" in
    PASS)
      echo "[PASS] steps[].order連番性 — 1..N(欠番・重複なし)、またはsteps[]が空" >&2
      ;;
    FAIL:*)
      overall_fail=1
      actual_orders="$(printf '%s' "$order_check" | cut -d: -f2-)"
      echo "[FAIL] steps[].order連番性 — 1..Nの連番になっていません(実際の値: ${actual_orders})" >&2
      ;;
    *)
      overall_fail=1
      echo "[FAIL] steps[].order連番性 — 検証に失敗しました(不正なorder値の可能性)" >&2
      ;;
  esac

  # --- steps[].command 純度(散文混入検知。1-133) ---
  prose_commands="$(jq -r '[(.steps // [])[] | select((.command // "") | contains("。"))] | length' "$MANIFEST" 2>/dev/null)"
  if [ "${prose_commands:-0}" -gt 0 ] 2>/dev/null; then
    overall_fail=1
    echo "[FAIL] steps[].command純度 — command欄に句点「。」を含む行が${prose_commands}件あります(散文混入。実行不可能なコマンドは\"該当なし\"としnoteへ説明を移すこと)" >&2
  else
    echo "[PASS] steps[].command純度 — command欄に句点「。」を含む行はありません" >&2
  fi
fi

# --- 4. 型別スロット ---
get_slot_keys() { case "$1" in glossary) echo "categories terms";; techstack) echo "tiles columns rows";; transition) echo "legend nodes edges";; er) echo "legend entities relations";; env) echo "prerequisites steps allocations";; entity-state) echo "legend nodes edges";; release-notes) echo "releases";; design-system) echo "tokens";; component-inventory) echo "components";; icon-catalog) echo "icons";; esac; }

if [ -n "$(get_slot_keys "$PAGE_KIND")" ]; then
  missing_slots=""
  for key in $(get_slot_keys "$PAGE_KIND"); do
    exists="$(jq -r --arg k "$key" 'has($k)' "$MANIFEST")"
    if [ "$exists" != "true" ]; then
      missing_slots="${missing_slots}${key} "
    fi
  done
  if [ -n "$missing_slots" ]; then
    overall_fail=1
    echo "[FAIL] 型別スロット — pageKind='${PAGE_KIND}'に必須のキーが欠落: ${missing_slots}" >&2
  else
    echo "[PASS] 型別スロット — pageKind='${PAGE_KIND}'の必須キーはすべて存在" >&2
  fi
else
  echo "[SKIP] 型別スロット — pageKind '${PAGE_KIND}' のスロット定義なし（検査スキップ）" >&2
fi

# --- 5. 孤児参照(transition/erのみ) ---
# edges[].from/.to は nodes[].unitKey に、relations[].from/.to は entities[].key に
# すべて存在すること(page-data-schema.mdの型別スロット節が正)。unresolved[]は解決不能を
# 明示する別経路であり、from/toを持たないため本検査の対象外(自然に除外される)。
case "$PAGE_KIND" in
  transition)
    orphan_refs="$(jq -r '
      ([(.nodes // [])[]?.unitKey] | map(select(. != null))) as $keys
      | [(.edges // [])[]? | select(
          ((.from as $f | $keys | index($f)) == null)
          or (
            ((.triggerType // "") != "ブラウザバック" or (.to // "") != "")
            and ((.to as $t | $keys | index($t)) == null)
          )
        )]
      | .[] | "\(.from)->\(.to)"
    ' "$MANIFEST" 2>/dev/null)"
    if [ -n "$orphan_refs" ]; then
      overall_fail=1
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        ln="$(line_of "\"${ref%%->*}\"")"
        echo "[FAIL] 孤児参照 — edgeの参照先がnodes[].unitKeyに存在しません: ${ref}(行番号: ${ln:-不明})" >&2
      done <<< "$orphan_refs"
    else
      echo "[PASS] 孤児参照 — edges[].from/.toはすべてnodes[].unitKeyに存在" >&2
    fi
    ;;
  er)
    orphan_refs="$(jq -r '
      ([(.entities // [])[]?.key] | map(select(. != null))) as $keys
      | [(.relations // [])[]? | select(((.from as $f | $keys | index($f)) == null) or ((.to as $t | $keys | index($t)) == null))]
      | .[] | "\(.from)->\(.to)"
    ' "$MANIFEST" 2>/dev/null)"
    if [ -n "$orphan_refs" ]; then
      overall_fail=1
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        ln="$(line_of "\"${ref%%->*}\"")"
        echo "[FAIL] 孤児参照 — relationの参照先がentities[].keyに存在しません: ${ref}(行番号: ${ln:-不明})" >&2
      done <<< "$orphan_refs"
    else
      echo "[PASS] 孤児参照 — relations[].from/.toはすべてentities[].keyに存在" >&2
    fi
    ;;
  entity-state)
    orphan_refs="$(jq -r '
      ([(.nodes // [])[]?.key] | map(select(. != null))) as $keys
      | [(.edges // [])[]? | select(((.from as $f | $keys | index($f)) == null) or ((.to as $t | $keys | index($t)) == null))]
      | .[] | "\(.from)->\(.to)"
    ' "$MANIFEST" 2>/dev/null)"
    if [ -n "$orphan_refs" ]; then
      overall_fail=1
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        ln="$(line_of "\"${ref%%->*}\"")"
        echo "[FAIL] 孤児参照 — edgeの参照先がnodes[].keyに存在しません: ${ref}(行番号: ${ln:-不明})" >&2
      done <<< "$orphan_refs"
    else
      echo "[PASS] 孤児参照 — edges[].from/.toはすべてnodes[].keyに存在" >&2
    fi
    ;;
esac

# --- 6. categorySrc整合性(transitionのみ) ---
# nodes[]にcategoryを持つノードが1件以上あれば、全ノードのcategorySrcが
# 非空であることを検査する(片方だけ付与された中途半端な状態を検出する)。
if [ "$PAGE_KIND" = "transition" ]; then
  has_category="$(jq -r '[(.nodes // [])[]? | select((.category // "") != "")] | length > 0' "$MANIFEST")"
  if [ "$has_category" = "true" ]; then
    missing_category_src="$(jq -r '[(.nodes // [])[]? | select((.categorySrc // "") == "") | .unitKey] | join(",")' "$MANIFEST")"
    if [ -n "$missing_category_src" ]; then
      overall_fail=1
      echo "[FAIL] categorySrc整合性 — categoryを持つノードがある一方、categorySrcが空のノードがあります: ${missing_category_src}" >&2
    else
      echo "[PASS] categorySrc整合性 — categoryを持つ全ノードのcategorySrcが非空" >&2
    fi
  else
    echo "[PASS] categorySrc整合性 — categoryを持つノードなし(検査対象外)" >&2
  fi
fi

# --- 7. sourceRef実在・行番号(--target-repo指定時のみ) ---
if [ -n "$TARGET_REPO" ]; then
  if [ ! -d "$TARGET_REPO" ]; then
    overall_fail=1
    echo "[FAIL] sourceRef実在 — --target-repoディレクトリが存在しません: ${TARGET_REPO}" >&2
  else
    # columns.sourceRef(techstackの列見出しラベル)は「値」であり参照ではないため対象外とする。
    # 実データの参照とみなすのは rows[]/terms[]/edges[]/relations[]/allocations[]/unresolved[] の
    # sourceRefのみ(page-data-schema.mdの型別スロット節が正)。
    source_refs="$(jq -r '[
      (.rows // [])[]?.sourceRef?,
      (.terms // [])[]?.sourceRef?,
      (.edges // [])[]?.sourceRef?,
      (.relations // [])[]?.sourceRef?,
      (.allocations // [])[]?.sourceRef?,
      (.unresolved // [])[]?.sourceRef?
    ] | map(select(. != null)) | .[]' "$MANIFEST" 2>/dev/null)"
    ref_fail=0
    if [ -n "$source_refs" ]; then
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        case "$ref" in
          *.md#*)
            continue
            ;;
        esac
        ref_path="${ref%%:*}"
        ref_line=""
        case "$ref" in
          *:*) ref_line="${ref##*:}" ;;
        esac
        full_path="${TARGET_REPO%/}/$ref_path"
        ln="$(line_of "\"${ref}\"")"
        if [ ! -f "$full_path" ]; then
          overall_fail=1
          ref_fail=1
          echo "[FAIL] sourceRef実在 — パス不在: ${ref}(行番号: ${ln:-不明})" >&2
          continue
        fi
        if [ -n "$ref_line" ]; then
          case "$ref_line" in
            ''|*[!0-9]*)
              overall_fail=1
              ref_fail=1
              echo "[FAIL] sourceRef行番号 — 数値でない行番号: ${ref}(行番号: ${ln:-不明})" >&2
              continue
              ;;
          esac
          total_lines="$(wc -l < "$full_path" | tr -d ' ')"
          if [ "$ref_line" -gt "$total_lines" ]; then
            overall_fail=1
            ref_fail=1
            echo "[FAIL] sourceRef行番号 — 総行数(${total_lines})超過: ${ref}(行番号: ${ln:-不明})" >&2
          fi
        fi
      done <<< "$source_refs"
    fi
    if [ "$ref_fail" -eq 0 ]; then
      echo "[PASS] sourceRef実在・行番号 — --target-repo(${TARGET_REPO})基点ですべて検証済み" >&2
    fi
  fi
fi

# --- 8. columns型検証(erのみ・entities[].columns[]が存在する場合) ---
if [ "$PAGE_KIND" = "er" ]; then
  columns_errors="$(jq -r '
    [(.entities // [])[]? | . as $e | ($e.columns // [])[]? as $c
      | [
          (if ($c | has("name")) and (($c.name | type) != "string") then "name" else empty end),
          (if ($c | has("type")) and (($c.type | type) != "string") then "type" else empty end),
          (if ($c | has("pk")) and (($c.pk | type) != "boolean") then "pk" else empty end),
          (if ($c | has("fk")) and (($c.fk | type) != "boolean") then "fk" else empty end),
          (if ($c | has("unique")) and (($c.unique | type) != "boolean") then "unique" else empty end),
          (if ($c | has("nullable")) and (($c.nullable | type) != "boolean") then "nullable" else empty end)
        ] as $bad
      | select(($bad | length) > 0)
      | "\($e.key // "?"):\($c.name // "?") 不正フィールド=\($bad | join(","))"
    ]
    | .[]
  ' "$MANIFEST" 2>/dev/null)"
  if [ -n "$columns_errors" ]; then
    overall_fail=1
    while IFS= read -r err; do
      [ -z "$err" ] && continue
      echo "[FAIL] columns型検証 — ${err}" >&2
    done <<< "$columns_errors"
  else
    echo "[PASS] columns型検証 — entities[].columns[]の型はすべて正しい(該当データなしを含む)" >&2
  fi
fi

if [ "$overall_fail" -eq 0 ]; then
  echo "[OK] validate-page-data: 全項目PASS" >&2
  exit 0
fi

exit 1
