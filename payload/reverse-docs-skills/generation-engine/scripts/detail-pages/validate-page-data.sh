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
#      rows/terms/edges/relations/allocations/unresolved の6キー配下の .sourceRef 値、
#      および components[].file・icons[].files[](component-inventory/icon-catalogの証跡パス。
#      改善課題: 証跡パス-絶対パスの混入)について、パス部分(":"より前。文書参照形式.md#は対象外)の
#      test -f 実在確認と、行番号付与時はそのファイルの総行数(wc -l)以内であることを検証する
#   8. columns型検証(erのみ): entities[].columns[]が存在する場合、name/typeがstring、
#      pk/fk/unique/nullableがboolean(いずれも存在時のみ)であることを検証する
#   9. edgesStatus値(transitionのみ): edgesStatusキーが存在する場合、値が「未抽出」または
#      「抽出済み」のいずれかであることを検証する。未指定は後方互換のため許容する
#
# envのenvironment[]は任意フィールド(page-data-schema.mdのT5節が正)。get_slot_keysの必須
# キー(prerequisites/steps/allocations)には含めない。未知キーを拒否する仕組みは無いため、
# environment[]の有無・値は本スクリプトの検証対象外(存在しても失敗しない)。
#
# 違反は該当値の page-data.json 内での行番号(grep -nF で特定。特定不能時は「不明」)付きでstderrへ
# [PASS]/[FAIL] 項目名 — 詳細 の形式で列挙する。1件でもFAILがあればexit 1。全項目PASSでexit 0。
#
# Usage: validate-page-data.sh --self-test で回帰テストを実行する。

# 素直な形(set -euo pipefail)を避け、-e を持たない。本体は1〜9の検査すべてを
# overall_fail フラグで積算し、途中でFAILしても最後まで全項目を実行してから
# まとめてexitする設計(1件のFAILで即終了すると残りの検査結果を報告できない)。
# 個々の検査は `[ -n "$x" ]`・grep・jqの終了コードを直接条件式で使うため、
# -e を有効にすると最初に非0を返した検査でスクリプト自体が落ちてしまい、
# 「全項目PASS/FAILを列挙する」という本体の役割(ヘッダ30〜31行目)と両立しない。
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
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-page-data-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
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

  if _gt_out2="$(bash "$script_path" "$data_ok" 2>&1)"; then
    echo "  [PASS] ケースa: columns[]の型が正しいerフィクスチャでPASS"
  else
    echo "  [FAIL] ケースa: columns[]の型が正しいerフィクスチャが誤ってFAILした" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
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

  if _gt_out3="$(bash "$script_path" "$data_bad" 2>&1)"; then
    echo "  [FAIL] ケースb: columns[]の型が不正なerフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
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

  if _gt_out4="$(bash "$script_path" "$data_orphan" 2>&1)"; then
    echo "  [FAIL] ケースc: 孤児edge混入のtransitionフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
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

  if _gt_out5="$(bash "$script_path" "$data_count_bad" 2>&1)"; then
    echo "  [FAIL] ケースd: manifestScreenCount不一致のtransitionフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
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

  if _gt_out6="$(bash "$script_path" "$data_count_ok" 2>&1)"; then
    echo "  [PASS] ケースe: manifestScreenCountがnodes[]+route空文字unresolved件数と一致するtransitionフィクスチャでPASS"
  else
    echo "  [FAIL] ケースe: manifestScreenCountが正しいtransitionフィクスチャが誤ってFAILした" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
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

  if _gt_out7="$(bash "$script_path" "$data_env_gap" 2>&1)"; then
    echo "  [FAIL] ケースf: order欠番(1,3)のenvフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
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

  if _gt_out8="$(bash "$script_path" "$data_env_prose" 2>&1)"; then
    echo "  [FAIL] ケースg: command欄に散文が混入したenvフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out8" | sed 's/^/    /' >&2
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

  if _gt_out9="$(bash "$script_path" "$data_env_ok" 2>&1)"; then
    echo "  [PASS] ケースi: order連番・command純粋(該当なし含む)のenvフィクスチャでPASS"
  else
    echo "  [FAIL] ケースi: order連番・command純粋なenvフィクスチャが誤ってFAILした" >&2
    printf '%s\n' "$_gt_out9" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースj: legacy glossaryはexit 0を維持しつつ移行warningを返す ---
  local data_glossary_legacy="$tmp/page-data-glossary-legacy.json"
  local legacy_stderr="$tmp/glossary-legacy.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"legacy warning確認",
    categories:[{key:"domain",label:"業務"}],
    terms:[{term:"顧客",definition:"商品を購入する主体",codeRefs:["Customer"],category:"domain",sourceRef:"src/customer.ts:1"}]
  }' > "$data_glossary_legacy"
  if bash "$script_path" "$data_glossary_legacy" >/dev/null 2>"$legacy_stderr" && grep -q '^\[WARN\].*legacy.*次major' "$legacy_stderr"; then
    echo "  [PASS] ケースj: legacy glossaryはexit 0と移行warningを返す"
  else
    echo "  [FAIL] ケースj: legacy glossaryのexit 0または移行warningが欠落" >&2
    rc=1
  fi

  # --- ケースk: semantic v0.2 glossaryはlegacy warningを返さない ---
  local data_glossary_semantic="$tmp/page-data-glossary-semantic.json"
  local semantic_stderr="$tmp/glossary-semantic.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"semantic warning確認",
    projectionVersion:"0.2", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"1.0.0",
    categories:[{key:"entity",label:"エンティティ"}],
    terms:[{key:"customer",term_ja:"顧客",term_en:"Customer",definition:"商品を購入する主体",scope:"sales",category:"entity",code_name:"customer",type_name:"Customer",db_name:"customers",api_name:"customer",ui_label:"顧客",allowed_values:[],status:"active",notes:"",representations:[],sourceRefs:[]}]
  }' > "$data_glossary_semantic"
  if bash "$script_path" "$data_glossary_semantic" >/dev/null 2>"$semantic_stderr" && ! grep -q '^\[WARN\].*legacy' "$semantic_stderr"; then
    echo "  [PASS] ケースk: semantic v0.2 glossaryはlegacy warningなしでPASS"
  else
    echo "  [FAIL] ケースk: semantic glossaryがFAILまたはlegacy warningを誤出力" >&2
    rc=1
  fi

  # --- ケースl: legacyとsemanticの同一terms[]混在はerror ---
  local data_glossary_mixed="$tmp/page-data-glossary-mixed.json"
  local mixed_stderr="$tmp/glossary-mixed.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"混在拒否確認",
    projectionVersion:"0.1", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"1.0.0",
    categories:[{key:"business",label:"業務"}],
    terms:[
      {term:"顧客",definition:"商品を購入する主体",codeRefs:["Customer"],category:"domain",sourceRef:"src/customer.ts:1"},
      {key:"order",label:"注文",definition:"顧客の購入意思",kind:"entity",category:"business",representations:[],status:"active",sourceRefs:[]}
    ]
  }' > "$data_glossary_mixed"
  if bash "$script_path" "$data_glossary_mixed" >/dev/null 2>"$mixed_stderr"; then
    echo "  [FAIL] ケースl: 新旧混在glossaryが誤ってPASS" >&2
    rc=1
  elif grep -q '新旧混在' "$mixed_stderr"; then
    echo "  [PASS] ケースl: 新旧混在glossaryをerrorで拒否"
  else
    echo "  [FAIL] ケースl: 新旧混在glossaryの診断が不明確" >&2
    rc=1
  fi

  # --- ケースm: semantic term配下の候補専用keyはネスト位置にかかわらずerror ---
  local data_glossary_nested_candidate="$tmp/page-data-glossary-nested-candidate.json"
  local nested_candidate_stderr="$tmp/glossary-nested-candidate.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"候補混入拒否確認",
    projectionVersion:"0.1", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"1.0.0",
    categories:[{key:"business",label:"業務"}],
    terms:[{key:"customer",label:"顧客",definition:"商品を購入する主体",kind:"entity",category:"business",representations:[],status:"active",sourceRefs:[],relations:[{type:"related_to",targetKey:"order",analysis:{approval:{status:"detected"},confidence:{score:0.7},detected_by:{skill:"reverse"},reviewers:[{role:"business"}]}}]}]
  }' > "$data_glossary_nested_candidate"
  if bash "$script_path" "$data_glossary_nested_candidate" >/dev/null 2>"$nested_candidate_stderr"; then
    echo "  [FAIL] ケースm: semantic term内の候補専用key混入が誤ってPASS" >&2
    rc=1
  elif grep -q '候補専用key' "$nested_candidate_stderr"; then
    echo "  [PASS] ケースm: semantic term内のnested候補専用keyをerrorで拒否"
  else
    echo "  [FAIL] ケースm: nested候補専用keyの診断が不明確" >&2
    rc=1
  fi

  # --- ケースn: semantic term rootのprojection v0.1 allowlist外keyはerror ---
  local data_glossary_unknown_root="$tmp/page-data-glossary-unknown-root.json"
  local unknown_root_stderr="$tmp/glossary-unknown-root.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"root allowlist確認",
    projectionVersion:"0.1", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"1.0.0",
    categories:[{key:"business",label:"業務"}],
    terms:[{key:"customer",label:"顧客",definition:"商品を購入する主体",kind:"entity",category:"business",representations:[],status:"active",sourceRefs:[],reviewers:[{role:"business",actor:"domain-reviewer"}]}]
  }' > "$data_glossary_unknown_root"
  if bash "$script_path" "$data_glossary_unknown_root" >/dev/null 2>"$unknown_root_stderr"; then
    echo "  [FAIL] ケースn: semantic term rootのallowlist外keyが誤ってPASS" >&2
    rc=1
  elif grep -q 'semantic root key.*reviewers' "$unknown_root_stderr"; then
    echo "  [PASS] ケースn: semantic term rootのallowlist外reviewersをerrorで拒否"
  else
    echo "  [FAIL] ケースn: semantic term root allowlist違反の診断が不明確" >&2
    rc=1
  fi

  # --- ケースo: semantic page-data rootの候補監査keyと未知keyはerror ---
  local data_glossary_root_attack="$tmp/page-data-glossary-root-attack.json"
  local root_attack_stderr="$tmp/glossary-root-attack.stderr"
  jq -n '{
    pageKind:"glossary", generatedAt:"2026-01-01T00:00:00Z", title:"用語辞書", description:"page root allowlist確認",
    projectionVersion:"0.1", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"1.0.0",
    categories:[{key:"business",label:"業務"}], terms:[],
    proposalAudit:{secret:"must-not-reach-html"}
  }' > "$data_glossary_root_attack"
  if bash "$script_path" "$data_glossary_root_attack" >/dev/null 2>"$root_attack_stderr"; then
    echo "  [FAIL] ケースo: semantic page-data rootのproposalAuditが誤ってPASS" >&2
    rc=1
  elif grep -Eq 'glossary.*root.*key|glossary候補分離' "$root_attack_stderr"; then
    echo "  [PASS] ケースo: semantic page-data rootのproposalAuditをerrorで拒否"
  else
    echo "  [FAIL] ケースo: semantic page-data root allowlist違反の診断が不明確" >&2
    rc=1
  fi

  # --- ケースp: legacy page-data rootの互換allowlist外keyはerror ---
  local data_glossary_legacy_root_attack="$tmp/page-data-glossary-legacy-root-attack.json"
  local legacy_root_attack_stderr="$tmp/glossary-legacy-root-attack.stderr"
  jq '. + {unknownRootKey:"must-be-rejected"}' "$data_glossary_legacy" > "$data_glossary_legacy_root_attack"
  if bash "$script_path" "$data_glossary_legacy_root_attack" >/dev/null 2>"$legacy_root_attack_stderr"; then
    echo "  [FAIL] ケースp: legacy page-data rootの未知keyが誤ってPASS" >&2
    rc=1
  elif grep -q 'glossary page root key.*legacy.*unknownRootKey' "$legacy_root_attack_stderr"; then
    echo "  [PASS] ケースp: legacy互換root allowlist外の未知keyをerrorで拒否"
  else
    echo "  [FAIL] ケースp: legacy page-data root allowlist違反の診断が不明確" >&2
    rc=1
  fi

  # --- ケースq: allowlist済みnested object内でも未知keyはerror ---
  local data_glossary_nested_unknown="$tmp/page-data-glossary-nested-unknown.json"
  local nested_unknown_stderr="$tmp/glossary-nested-unknown.stderr"
  jq '.terms[0].representations = [{channel:"code",value:"Customer",location:"src/customer.ts:1",candidatePayload:{status:"detected"}}]' \
    "$data_glossary_semantic" > "$data_glossary_nested_unknown"
  if bash "$script_path" "$data_glossary_nested_unknown" >/dev/null 2>"$nested_unknown_stderr"; then
    echo "  [FAIL] ケースq: representation内の未知candidatePayloadが誤ってPASS" >&2
    rc=1
  elif grep -q 'semantic nested key.*representations.*candidatePayload' "$nested_unknown_stderr"; then
    echo "  [PASS] ケースq: allowlist済みnested object内の未知candidatePayloadをerrorで拒否"
  else
    echo "  [FAIL] ケースq: nested object allowlist違反の診断が不明確" >&2
    rc=1
  fi

  # --- ケースr: components[].file・icons[].files[]も--target-repo指定時の実在検査対象に含む
  #     (改善課題: 証跡パス-絶対パスの混入) ---
  local fake_repo="$tmp/fake-repo"
  mkdir -p "$fake_repo/src/components"
  printf 'export default function Foo() { return null; }\n' > "$fake_repo/src/components/Foo.tsx"

  local data_component_ok="$tmp/page-data-component-ok.json"
  jq -n '{
    pageKind: "component-inventory",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "コンポーネント棚卸し",
    description: "self-test用フィクスチャ(components[].file実在・正常系)",
    components: [{name: "Foo", file: "src/components/Foo.tsx", category: "component", hasProps: false, importCount: 0}]
  }' > "$data_component_ok"
  if _gt_out10="$(bash "$script_path" "$data_component_ok" --target-repo "$fake_repo" 2>&1)"; then
    echo "  [PASS] ケースr-1: components[].fileが実在する相対パスのフィクスチャでPASS"
  else
    echo "  [FAIL] ケースr-1: components[].fileが実在する相対パスのフィクスチャが誤ってFAILした" >&2
    printf '%s\n' "$_gt_out10" | sed 's/^/    /' >&2
    rc=1
  fi

  local data_icon_abs="$tmp/page-data-icon-abs.json"
  jq -n --arg absfile "${fake_repo}/src/components/Foo.tsx:1" '{
    pageKind: "icon-catalog",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "アイコンカタログ",
    description: "self-test用フィクスチャ(icons[].files[]絶対パス混入)",
    icons: [{name: "swords", sourceType: "material", usageCount: 1, files: [$absfile]}]
  }' > "$data_icon_abs"
  if _gt_out11="$(bash "$script_path" "$data_icon_abs" --target-repo "$fake_repo" 2>&1)"; then
    echo "  [FAIL] ケースr-2: icons[].files[]に絶対パスが混入したフィクスチャが誤ってPASSした" >&2
    printf '%s\n' "$_gt_out11" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケースr-2: icons[].files[]に絶対パスが混入したフィクスチャで正しくFAIL"
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
if ! _gt_out12="$(jq empty "$MANIFEST" 2>&1)"; then
  echo "[FAIL] json構文 — 妥当なJSONではありません" >&2
  printf '%s\n' "$_gt_out12" | sed 's/^/    /' >&2
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
  edges_status="$(jq -r 'if has("edgesStatus") then .edgesStatus else null end' "$MANIFEST")"
  if [ "$edges_status" = "null" ]; then
    echo "[PASS] edgesStatus値 — 未指定(後方互換のため検査対象外)" >&2
  else
    case "$edges_status" in
      未抽出|抽出済み)
        echo "[PASS] edgesStatus値 — '${edges_status}'は許可値" >&2
        ;;
      *)
        overall_fail=1
        ln="$(line_of "\"edgesStatus\"")"
        echo "[FAIL] edgesStatus値 — 不正な値: '${edges_status}'(行番号: ${ln:-不明})。未抽出|抽出済みのいずれかである必要があります" >&2
        ;;
    esac
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

# --- glossaryの形式排他・v0.1 page-data検証 ---
# legacyとsemantic v0.1は受理するが、同じterms[]への混在は意味の捏造を招くため拒否する。
# proposal/candidate/changeは承認済み用語の表示面へ持ち込まない。
if [ "$PAGE_KIND" = "glossary" ]; then
  forbidden_candidate_slots="$(jq -r '
    . as $root
    | [
        "proposals","proposal","candidates","candidate","changes","change","proposalAudit","proposal_audit",
        "reviewers","approval","confidence","observations","inferences","evidence","extractedFacts","extracted_facts",
        "approvalEvents","approval_events","detectedBy","detected_by","mergeKey","merge_key","mergedRevision","merged_revision"
      ] as $bad
    | [$bad[] | . as $key | select($root | has($key))] | join(",")
  ' "$MANIFEST" 2>/dev/null || true)"
  if [ -n "$forbidden_candidate_slots" ]; then
    overall_fail=1
    echo "[FAIL] glossary候補分離 — 承認済みpage-dataに候補・変更スロットを含められません: ${forbidden_candidate_slots}" >&2
  else
    echo "[PASS] glossary候補分離 — 候補・変更スロットなし" >&2
  fi

  terms_is_array="$(jq -r '(.terms | type) == "array"' "$MANIFEST")"
  if [ "$terms_is_array" != "true" ]; then
    overall_fail=1
    echo "[FAIL] glossary terms型 — termsはarrayである必要があります" >&2
  fi
  term_count="$(jq -r 'if (.terms | type)=="array" then (.terms|length) else 0 end' "$MANIFEST")"
  legacy_count="$(jq -r '[if (.terms | type)=="array" then .terms[] else empty end | select(type=="object" and has("term") and ((has("key") or has("label"))|not))] | length' "$MANIFEST")"
  semantic_count="$(jq -r '[if (.terms | type)=="array" then .terms[] else empty end | select(type=="object" and (has("key") or has("label") or has("term_ja")) and (has("term")|not))] | length' "$MANIFEST")"
  invalid_count=$((term_count - legacy_count - semantic_count))
  if [ "$invalid_count" -gt 0 ]; then
    overall_fail=1
    echo "[FAIL] glossary未分類term — legacy/semanticのどちらにも一意分類できないtermsが${invalid_count}件あります" >&2
  else
    echo "[PASS] glossary term分類 — 全${term_count}件をlegacyまたはsemanticへ一意分類" >&2
  fi
  if [ "$legacy_count" -gt 0 ] && [ "$semantic_count" -gt 0 ]; then
    overall_fail=1
    echo "[FAIL] glossary形式 — terms[]のlegacy形式とsemantic v0.1形式の新旧混在は禁止です" >&2
  else
    echo "[PASS] glossary形式 — terms[]は単一形式（legacyまたはsemantic projection）" >&2
  fi

  semantic_root_present="$(jq -r 'has("projectionVersion") or has("glossarySchemaVersion") or has("glossaryContentVersion")' "$MANIFEST")"
  semantic_mode=0
  if [ "$semantic_count" -gt 0 ] && [ "$legacy_count" -eq 0 ] && [ "$invalid_count" -eq 0 ]; then
    semantic_mode=1
  elif [ "$term_count" -eq 0 ] && [ "$semantic_root_present" = "true" ]; then
    semantic_mode=1
  fi
  if [ "$semantic_mode" -eq 1 ]; then
    semantic_unknown_page_root_keys="$(jq -r '
      [
        "pageKind","generatedAt","title","description","projectName","projectionVersion","glossarySchemaVersion",
        "glossaryContentVersion","categories","terms","unresolved","diagnostics"
      ] as $allowed
      | [keys[] | . as $key | select($allowed | index($key) | not)] | unique | join(",")
    ' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$semantic_unknown_page_root_keys" ]; then
      overall_fail=1
      echo "[FAIL] glossary page root key — semantic v0.1 allowlist外のkeyです: ${semantic_unknown_page_root_keys}" >&2
    else
      echo "[PASS] glossary page root key — semantic v0.1 rootはallowlist内" >&2
    fi
  elif [ "$legacy_count" -gt 0 ] && [ "$semantic_count" -eq 0 ] && [ "$invalid_count" -eq 0 ]; then
    legacy_unknown_page_root_keys="$(jq -r '
      ["pageKind","generatedAt","title","description","projectName","categories","terms","unresolved","diagnostics"] as $allowed
      | [keys[] | . as $key | select($allowed | index($key) | not)] | unique | join(",")
    ' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$legacy_unknown_page_root_keys" ]; then
      overall_fail=1
      echo "[FAIL] glossary page root key — legacy allowlist外のkeyです: ${legacy_unknown_page_root_keys}" >&2
    else
      echo "[PASS] glossary page root key — legacy rootはallowlist内" >&2
    fi
  fi
  if [ "$semantic_mode" -eq 1 ]; then
    semantic_unknown_root_keys="$(jq -r '
      [
        "key","term_ja","term_en","definition","scope","category","code_name","type_name","db_name","api_name","ui_label","allowed_values","status","notes",
        "label","kind","representations","aliases","forbiddenTerms","relations",
        "examples","counterExamples","constraints","tags","securityClassification","notes","status","introducedIn",
        "deprecatedIn","retiredIn","migrationDeadline","replacementKey","replacedBy","lifecycleReason","approvers",
        "sourceRefs","decisionRef","changeRef"
      ] as $allowed
      | [(.terms // [])[]? | keys[] | . as $key | select($allowed | index($key) | not)]
      | unique | join(",")
    ' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$semantic_unknown_root_keys" ]; then
      overall_fail=1
      echo "[FAIL] glossary semantic root key — projection v0.1 allowlist外のterm root keyです: ${semantic_unknown_root_keys}" >&2
    else
      echo "[PASS] glossary semantic root key — term rootはprojection v0.1 allowlist内" >&2
    fi

    semantic_unknown_nested_keys="$(jq -r '
      [
        (.categories[]? | objects | keys[] as $key
          | select(["key","label"] | index($key) | not)
          | "categories[].\($key)"),
        (.terms[]? | .scope? | objects | keys[] as $key
          | select(["level","includes","excludes"] | index($key) | not)
          | "terms[].scope.\($key)"),
        (.terms[]? | .representations[]? | objects | keys[] as $key
          | select(["channel","value","location","symbolKind"] | index($key) | not)
          | "terms[].representations[].\($key)"),
        (.terms[]? | .forbiddenTerms[]? | objects | keys[] as $key
          | select(["term","reason","replacementKey"] | index($key) | not)
          | "terms[].forbiddenTerms[].\($key)"),
        (.terms[]? | .relations[]? | objects | keys[] as $key
          | select(["type","targetKey"] | index($key) | not)
          | "terms[].relations[].\($key)"),
        (.unresolved[]? | objects | keys[] as $key
          | select(["label","reason","sourceRef"] | index($key) | not)
          | "unresolved[].\($key)"),
        (.diagnostics? | objects | keys[] as $key
          | select(["missingSource","unimplementedLayer"] | index($key) | not)
          | "diagnostics.\($key)"),
        (.diagnostics? | objects | to_entries[] | .key as $metric | .value | objects | keys[] as $key
          | select(["count","total","ratio","threshold","warning"] | index($key) | not)
          | "diagnostics.\($metric).\($key)")
      ] | unique | join(",")
    ' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$semantic_unknown_nested_keys" ]; then
      overall_fail=1
      echo "[FAIL] glossary semantic nested key — projection v0.1 allowlist外のnested keyです: ${semantic_unknown_nested_keys}" >&2
    else
      echo "[PASS] glossary semantic nested key — 全nested objectはprojection v0.1 allowlist内" >&2
    fi

    semantic_candidate_keys="$(jq -r '
      [
        "proposal","proposalKey","proposal_key","proposalSchemaVersion","proposal_schema_version","proposedTerm","proposed_term",
        "targetGlossaryKey","target_glossary_key","baseContentVersion","base_content_version","targetContentVersion","target_content_version",
        "approval","confidence","observations","inferences","evidence","extractedFacts","extracted_facts","reviewers",
        "reviewedAt","reviewed_at","decisionReason","decision_reason","approvalEvents","approval_events","detectedBy","detected_by",
        "mergeKey","merge_key","mergedRevision","merged_revision","proposalAudit","proposal_audit","requestedBy","requested_by",
        "approvedBy","approved_by","affectedTermKeys","affected_term_keys","changeKey","change_key","changeType","change_type",
        "beforeHash","before_hash","afterHash","after_hash","appliedAt","applied_at","appliedRevision","applied_revision"
      ] as $forbidden
      | [(.terms // [])[]? | .. | objects | keys[] | . as $key | select($forbidden | index($key))]
      | unique | join(",")
    ' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$semantic_candidate_keys" ]; then
      overall_fail=1
      echo "[FAIL] glossary候補専用key — semantic terms配下へ候補情報を混入できません: ${semantic_candidate_keys}" >&2
    else
      echo "[PASS] glossary候補専用key — semantic terms配下に候補情報なし" >&2
    fi
  fi
  if [ "$legacy_count" -gt 0 ] && [ "$semantic_count" -eq 0 ] && [ "$invalid_count" -eq 0 ]; then
    legacy_invalid="$(jq -r '[(.terms // [])[] | select(
      (["term","definition","codeRefs","category","sourceRef"] - keys | length) > 0
      or (.term|type)!="string" or (.definition|type)!="string"
      or (.codeRefs|type)!="array" or ([.codeRefs[]|select(type!="string")]|length)>0
      or (.category|type)!="string" or (.sourceRef|type)!="string"
    )] | length' "$MANIFEST" 2>/dev/null || echo 1)"
    if [ "$legacy_invalid" -gt 0 ]; then
      overall_fail=1
      echo "[FAIL] glossary legacy型 — 必須キーまたは型が不正なtermsが${legacy_invalid}件あります" >&2
    else
      echo "[PASS] glossary legacy型 — 旧5項目形式は妥当（表示時keyは未移行）" >&2
      echo "[WARN] glossary legacy互換 — meaningful keyを生成せず未移行として受理しました。reverse adapter完了後の次majorで廃止候補です" >&2
    fi
  elif [ "$semantic_mode" -eq 1 ]; then
    semantic_root_invalid="$(jq -r '
      . as $root
      | ((["0.1","0.2"] | index($root.projectionVersion)) == null)
      or (.glossarySchemaVersion != "1.0.0")
      or ((.glossaryContentVersion | type) != "string")
      or ((.categories | type) != "array")
      or ([.categories[] | . as $category | select(((["key","label"] - keys | length)>0) or (.key|type)!="string" or (.label|type)!="string" or (["business","technical","ai","cross_cutting","entity","attribute","value","process","event","role","rule","metric"]|index($category.key))==null)] | length)>0
    ' "$MANIFEST" 2>/dev/null || echo true)"
    if [ "$semantic_root_invalid" = "true" ]; then
      overall_fail=1
      echo "[FAIL] glossary semantic root — projection/schema/content versionまたはcategoriesが不正です" >&2
    else
      echo "[PASS] glossary semantic root — versionとcategoriesは妥当" >&2
    fi
    semantic_invalid="$(jq -r '
      if .projectionVersion == "0.2" then
        [(.terms // [])[] | . as $term | select(
          (["key","term_ja","term_en","definition","scope","category","code_name","type_name","db_name","api_name","ui_label","allowed_values","status","notes"] - keys | length) > 0
          or ([.key,.term_ja,.term_en,.definition,.scope,.category,.code_name,.db_name,.api_name,.status,.notes] | any(type!="string"))
          or ((.type_name|type)!="string" and (.type_name|type)!="null")
          or ((.ui_label|type)!="string" and (.ui_label|type)!="null")
          or (.allowed_values|type)!="array" or ([.allowed_values[]|select(type!="string")]|length)>0
          or (.representations|type)!="array" or (.sourceRefs|type)!="array"
          or ([.representations[] | select(((["channel","value","location"] - keys | length)>0) or (.channel|type)!="string" or (.value|type)!="string" or (.location|type)!="string")]|length)>0
          or ([.sourceRefs[]|select(type!="string")]|length)>0
          or (has("aliases") and ((.aliases|type)!="array" or ([.aliases[]|select(type!="string")]|length)>0))
          or (has("forbiddenTerms") and ((.forbiddenTerms|type)!="array" or ([.forbiddenTerms[] | select(
            (type!="string") and (type!="object" or (has("term")|not) or (.term|type)!="string" or (has("reason") and (.reason|type)!="string") or (has("replacementKey") and (.replacementKey|type)!="string"))
          )]|length)>0))
          or (has("relations") and ((.relations|type)!="array" or ([.relations[] | select(type!="string" and type!="object")]|length)>0))
          or (has("examples") and ((.examples|type)!="array" or ([.examples[]|select(type!="string")]|length)>0))
          or (has("counterExamples") and ((.counterExamples|type)!="array" or ([.counterExamples[]|select(type!="string")]|length)>0))
          or (has("constraints") and ((.constraints|type)!="array" or ([.constraints[]|select(type!="string")]|length)>0))
          or (has("securityClassification") and (.securityClassification|type)!="string")
          or (has("replacementKey") and (.replacementKey|type)!="string")
          or (["active","deprecated","retired"]|index($term.status))==null
          or (["entity","attribute","value","process","event","role","rule","metric"]|index($term.category))==null
        )] | length
      else
        [(.terms // [])[] | . as $term | select(
      (["key","label","definition","kind","category","representations","status","sourceRefs"] - keys | length) > 0
      or (.key|type)!="string" or (.label|type)!="string" or (.definition|type)!="string"
      or (.kind|type)!="string" or (.category|type)!="string"
      or (.representations|type)!="array" or (.sourceRefs|type)!="array"
      or ([.representations[] | select(((["channel","value","location"] - keys | length)>0) or (.channel|type)!="string" or (.value|type)!="string" or (.location|type)!="string")]|length)>0
      or ([.sourceRefs[]|select(type!="string")]|length)>0
      or (has("aliases") and ((.aliases|type)!="array" or ([.aliases[]|select(type!="string")]|length)>0))
      or (has("forbiddenTerms") and ((.forbiddenTerms|type)!="array" or ([.forbiddenTerms[] | select(
        (type!="string") and (type!="object" or (has("term")|not) or (.term|type)!="string" or (has("reason") and (.reason|type)!="string") or (has("replacementKey") and (.replacementKey|type)!="string"))
      )]|length)>0))
      or (has("relations") and ((.relations|type)!="array" or ([.relations[] | select(type!="string" and type!="object")]|length)>0))
      or (has("scope") and ((.scope|type)!="object" or (.scope.level|type)!="string" or (.scope.includes|type)!="array" or (.scope.excludes|type)!="array" or ([.scope.includes[],.scope.excludes[]|select(type!="string")]|length)>0))
      or (has("examples") and ((.examples|type)!="array" or ([.examples[]|select(type!="string")]|length)>0))
      or (has("counterExamples") and ((.counterExamples|type)!="array" or ([.counterExamples[]|select(type!="string")]|length)>0))
      or (has("constraints") and ((.constraints|type)!="array" or ([.constraints[]|select(type!="string")]|length)>0))
      or (has("notes") and ((.notes|type)!="array" or ([.notes[]|select(type!="string")]|length)>0))
      or (has("securityClassification") and (.securityClassification|type)!="string")
      or (has("replacementKey") and (.replacementKey|type)!="string")
      or (["active","deprecated","retired"]|index($term.status))==null
      or (["business","technical","ai","cross_cutting"]|index($term.category))==null
        )] | length
      end' "$MANIFEST" 2>/dev/null || echo 1)"
    if [ "$semantic_invalid" -gt 0 ]; then
      overall_fail=1
      echo "[FAIL] glossary semantic型 — 必須キー・型・状態・分類が不正なtermsが${semantic_invalid}件あります" >&2
    else
      echo "[PASS] glossary semantic型 — semantic projection termsは妥当" >&2
    fi
  fi
fi

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
    # sourceRefに加え、component-inventoryのcomponents[].file・icon-catalogのicons[].files[]
    # (page-data-schema.mdの型別スロット節が正。改善課題: 証跡パス-絶対パスの混入)。
    source_refs="$(jq -r '[
      (.rows // [])[]?.sourceRef?,
      (.terms // [])[]?.sourceRef?,
      (.terms // [])[]?.sourceRefs[]?,
      (.edges // [])[]?.sourceRef?,
      (.relations // [])[]?.sourceRef?,
      (.allocations // [])[]?.sourceRef?,
      (.unresolved // [])[]?.sourceRef?,
      (.components // [])[]?.file?,
      (.icons // [])[]?.files[]?
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
