#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

# build-portal.sh — 設計ポータルを生成する
#
# Usage:
#   bash generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
#     [--catalog <portal-catalog.json>] [--generated-at <ISO-8601>]
#     [--portal-only] [--standalone] [--screen-manifest <screen-manifest.ext.json>]
#     [--sites <file>] [--site-key <key>]
#     [--pre-build <command>] [--post-build <command>]
#   bash generation-engine/scripts/build-portal.sh --self-test [--case 36]
#
# <output_dir>（第2引数）が指す階層（改善課題1-202）:
#   <output_dir> には docs ディレクトリ自体ではなく、docs と project-portal を子に
#   持つプロジェクトルート（docs の親ディレクトリ）を渡す。output-layout.json の各ルート
#   （docsRoot="docs"・apiUnitRoot="docs/design/apis"・commonRoot="docs/design/common" 等）
#   は、この <output_dir> からの相対パスとして解決される。<output_dir> に docs 自体を
#   渡すと、解決先が二重の "docs/docs/..." となり実在しないため、該当する設計書が
#   1件も見つからず変換が黙って0件のまま終了する事故につながる。この誤りは起動直後に
#   検知して異常終了する（check_docs_root_misconfiguration）。変換した設計書の件数は
#   標準出力へ「変換した設計書の件数: N 件」として報告し、0件の場合は標準エラーへ警告する。
#
# --pre-build / --post-build:
#   生成の前後に任意のコマンドを差し込む受け口。--pre-build は引数解決後・生成開始直前に、
#   --post-build は index.html 書き出し直後に、それぞれ sh -c で実行する。
#   差し込んだコマンドへは REVERSE_DOCS_TARGET_REPO・REVERSE_DOCS_DOCS_DIR・
#   REVERSE_DOCS_PORTAL_DIR を環境変数として渡す。コマンドが非 0 で終了した場合、
#   build-portal.sh もその終了コードで異常終了する（失敗を握りつぶさない）。
#
# --build-manifests-from-docs:
#   指定時は、生成開始前（--pre-build よりも前）に
#   generation-engine/scripts/portal-input/build-manifests-from-docs.sh を実行し、設計文書の
#   frontmatter から非画面6種別（API/テーブル/バッチ/帳票/外部連携/機能）の一覧マニフェスト
#   を組み立てる。出力先は output-layout.json の manifestsRoot（既定 docs/manifests）配下で、
#   既存の一覧生成（generating-<種別>-list-for-reverse-docs）が読む場所と同じ。
#   メッセージ一覧・CRUD対応表・状態遷移図・ER図・画面遷移図も同じ本番経路で生成する。
#   入力資料が存在しない種別は SKIP を記録し、抽出または描画が失敗した場合は非 0 で終了する。
#
# --standalone:
#   通常の生成とシェル値のバックフィルが完了した後、非画面6種別の各設計単位を単独配布用に
#   整形・検査する。ポータルへの戻り導線は単位フォルダに含めないため、--portal-only とは
#   同時に指定できない。
#
# 処理:
#   1. 対象リポジトリのコード行数・ファイル数を計測（FE/BE分離）
#   2. 各種別の一覧HTMLから件数を抽出（規模側の kinds と一覧カードで共用）
#   3. 共通文書リスト・将来ページ受け口（FUTURE_PAGES）を収集
#   4. METRICS_JSON（構造化: scale/tests/freshness/previous）/ CATEGORIES_JSON を組み立て
#   5. テンプレートのプレースホルダを置換して出力

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../../delivery-payload/templates/portal-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../delivery-payload/templates/tokens.css"
DEFAULT_CATALOG="$SCRIPT_DIR/../../delivery-payload/references/portal-catalog.json"
CATALOG_ENGINE="$SCRIPT_DIR/portal-catalog.mjs"

source "$SCRIPT_DIR/render-template.sh"
source "$SCRIPT_DIR/output-layout.sh"

# 課題1-209: project-portal 配下に、現在の定義（output-layout.json の layout の値が
# portalRoot 配下を指すもののうち直下セグメントの集合）に対応しない置き場が残っている
# 場合を検出し、警告する。削除はしない。
#
# 削除しない理由: --self-test の複数のケース（ケース3・7・8・9・12・13・25・48等）が、
# project-portal/一覧・対応表・画面 のような旧名の直下に、このケース自身が読み取る
# 前提のフィクスチャを事前配置している。旧名リストとの単純な文字列一致で削除する設計を
# 一度実装したところ、--self-test ケース13の既存フィクスチャ（project-portal/一覧/用語辞書）
# を実際に削除してしまう事故を実測で確認した（1-209の実装時に検出、パッチは反映前に
# 差し戻し済み）。旧名かどうかを名前だけで判定すると、「rename後に残った孤立した旧構成」と
# 「このセッション内で入力として使われている旧名の置き場」を区別できない。安全側に倒し、
# 完了条件が定める「検出と、削除または警告まで」のうち警告のみを実装する。
detect_stale_portal_placeholders() {
  local layout_json="$1"
  local portal_dir="$2"
  [ -d "$portal_dir" ] || return 0

  local portal_root
  portal_root="$(output_layout_get "$layout_json" portalRoot)" || return 0

  local expected
  expected="$(printf '%s' "$layout_json" | jq -r --arg root "$portal_root" '
    .layout | to_entries[] | select(.value | type == "string") | select(.value | startswith($root + "/")) | .value
  ')"
  local expected_dirs=" "
  local v rest seg
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    rest="${v#*/}"
    seg="${rest%%/*}"
    [ -z "$seg" ] && continue
    case "$expected_dirs" in
      *" $seg "*) ;;
      *) expected_dirs="$expected_dirs$seg " ;;
    esac
  done <<PLACEHOLDER_EOF
$expected
PLACEHOLDER_EOF

  local d name
  for d in "$portal_dir"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case "$expected_dirs" in
      *" $name "*) continue ;;
    esac
    echo "WARN: $portal_root/$name は現在の定義（output-layout.json）に対応しない置き場です（自動削除の対象外。旧構成の残存、または定義に無い作業用の置き場である可能性があります）" >&2
  done
  return 0
}

# 課題1-210: 非画面6種別（API・テーブル・バッチ・帳票・外部連携・機能）の単位ディレクトリ
# （<kindUnitRoot>/<kind>-<unit_id>）の直下に、現在の定義（unitPhaseDirNames.basic・
# unitPhaseDirNames.detail・unitTestDesignDir）に対応しないサブディレクトリが残っている
# 場合を検出し、警告する。削除はしない。理由は1-209と同じで、名前だけでは「定義が
# 変わって孤立した旧階層」と「このセッション内で入力として使われている置き場」を安全に
# 区別できないため。screenUnitRoot配下の画面単位は対象外とする（scaffold-screen.shが
# 現在も基本設計・詳細設計・テスト設計という別方式のハードコードを持ち、本項目はこの
# ハードコードの置換を範囲外としたため、画面単位を対象にすると常に警告が出る）。
detect_undefined_unit_phase_dirs() {
  local layout_json="$1"
  local docs_root="$2"
  local basic_name detail_name test_name expected_dirs
  basic_name="$(printf '%s' "$layout_json" | jq -r '.unitPhaseDirNames.basic // empty')"
  detail_name="$(printf '%s' "$layout_json" | jq -r '.unitPhaseDirNames.detail // empty')"
  test_name="$(output_layout_get "$layout_json" unitTestDesignDir 2>/dev/null)" || test_name=""
  expected_dirs=" "
  [ -n "$basic_name" ] && expected_dirs="$expected_dirs$basic_name "
  [ -n "$detail_name" ] && expected_dirs="$expected_dirs$detail_name "
  [ -n "$test_name" ] && expected_dirs="$expected_dirs$test_name "

  local kind key root_rel root_abs u name
  for kind in api table batch report external feature; do
    key="${kind}UnitRoot"
    root_rel="$(output_layout_get "$layout_json" "$key" 2>/dev/null)" || continue
    [ -z "$root_rel" ] && continue
    root_abs="$docs_root/$root_rel"
    [ -d "$root_abs" ] || continue
    for u in "$root_abs"/*/; do
      [ -d "$u" ] || continue
      for d in "$u"*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        case "$expected_dirs" in
          *" $name "*) continue ;;
        esac
        echo "WARN: $root_rel/$(basename "$u")/$name は現在の定義（unitPhaseDirNames・unitTestDesignDir）に対応しない階層です（自動削除の対象外）" >&2
      done
    done
  done
  return 0
}

# 書込先自身と、そこへ至る既存path componentをlstatで検査する。
# symlinkを1つでも含む場合は、リンク先のrepo外treeへ書かないようfail closedにする。
assert_no_symlink_output_paths() {
  node - "$@" <<'NODE'
const fs = require("fs");
const path = require("path");
function lexicalAbsolute(raw) {
  return path.isAbsolute(raw) ? raw : `${process.cwd()}${path.sep}${raw}`;
}
function assertNoLexicalSymlink(raw) {
  const absolute = lexicalAbsolute(raw);
  const parsed = path.parse(absolute);
  let current = parsed.root;
  for (const segment of absolute.slice(parsed.root.length).split(path.sep)) {
    if (!segment || segment === ".") continue;
    if (segment === "..") {
      current = path.dirname(current);
      continue;
    }
    current = path.join(current, segment);
    try {
      if (fs.lstatSync(current).isSymbolicLink()) {
        throw new Error(`write path must not contain a symbolic link: ${current}`);
      }
    } catch (error) {
      if (error && error.code === "ENOENT") continue;
      throw error;
    }
  }
}
const outputRootRaw = process.argv[2];
const outputRoot = path.resolve(outputRootRaw);
for (const rawTarget of process.argv.slice(3)) {
  assertNoLexicalSymlink(outputRootRaw);
  assertNoLexicalSymlink(rawTarget);
  const target = path.resolve(rawTarget);
  const relative = path.relative(outputRoot, target);
  if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`write path must stay under output_dir: ${target}`);
  }
  const parsed = path.parse(target);
  let current = parsed.root;
  for (const segment of target.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    let stat;
    try {
      stat = fs.lstatSync(current);
    } catch (error) {
      if (error && error.code === "ENOENT") break;
      throw error;
    }
    if (stat.isSymbolicLink()) {
      throw new Error(`write path must not contain a symbolic link: ${current}`);
    }
  }
}
NODE
}

# 改善課題1-202: 第2引数（output_dir）に docs ディレクトリそのものを渡す誤りを検知する。
# output-layout.json の各ルート（例: apiUnitRoot="docs/design/apis"）は docsRoot（既定
# "docs"）を先頭に含んだ、output_dir（第2引数。docs と project-portal を子に持つ
# プロジェクトルート）からの相対パスとして解決される。第2引数へ誤って docs ディレクトリ
# 自体を渡すと、解決先が二重の "docs/docs/..." となり実在しないため、該当するmdファイルが
# 1件も見つからず変換ループが黙って0件のまま終了コード0を返す（実測: 改善課題1-202本文）。
#
# 検知方法: 各ルートについて、本来の解決先（<output_dir>/<root>）が存在せず、かつ
# docsRoot接頭辞を1段取り除いた解決先（<output_dir>/<rootからdocsRoot/を除いた残り>）が
# 実在する場合、第2引数に docs ディレクトリ自体が渡されたことを示す強い証拠として扱う。
# 両方とも不在（例: まだ設計書を1件も生成していない新規プロジェクト）の場合は誤りと
# 判定しない。正しい引数でも起こりうる正当な状態を誤検知しないため。
check_docs_root_misconfiguration() {
  local layout_json="$1"
  local output_dir="$2"
  local docs_root_prefix
  docs_root_prefix="$(output_layout_get "$layout_json" docsRoot 2>/dev/null)" || return 0
  [ -n "$docs_root_prefix" ] || return 0

  local key value stripped evidence=""
  for key in commonRoot crossCuttingDesignRoot screenUnitRoot apiUnitRoot tableUnitRoot \
             batchUnitRoot reportUnitRoot externalUnitRoot featureUnitRoot rulesRoot manifestsRoot; do
    value="$(output_layout_get "$layout_json" "$key" 2>/dev/null)" || continue
    case "$value" in
      "$docs_root_prefix"/*) stripped="${value#"$docs_root_prefix"/}" ;;
      *) continue ;;
    esac
    [ -n "$stripped" ] || continue
    [ -d "$output_dir/$value" ] && continue
    if [ -d "$output_dir/$stripped" ]; then
      evidence="${evidence}  - ${key}: 本来の解決先 ${output_dir}/${value} は存在しませんが、${docs_root_prefix}/ を1段取り除いた ${output_dir}/${stripped} が実在します"$'\n'
    fi
  done

  if [ -n "$evidence" ]; then
    echo "ERROR: <output_dir>（第2引数: ${output_dir}）の指定が誤っています。output-layout.json の解決先が二重の「${docs_root_prefix}/」を含んだまま実在せず、その接頭辞を1段取り除いた場所に実体があります。" >&2
    printf '%s' "$evidence" >&2
    echo "ERROR: <output_dir> には ${docs_root_prefix} ディレクトリ自体ではなく、${docs_root_prefix} と project-portal を子に持つプロジェクトルート（${docs_root_prefix} の親ディレクトリ）を渡してください。" >&2
    return 1
  fi
  return 0
}

if [ -f "$SCRIPT_DIR/shell-injection.sh" ]; then
  . "$SCRIPT_DIR/shell-injection.sh"
fi

# Markdown先頭のYAML frontmatter内だけから単一キーを読む。
# 本文中の同名行は設計根拠ではないため、表示コミットへ混入させない。
frontmatter_value() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    { sub(/\r$/, "", $0) }
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && $0 ~ ("^[[:space:]]*" key "[[:space:]]*:") {
      value = $0
      sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "", value)
      sub("[[:space:]]*$", "", value)
      print value
      exit
    }
  ' "$file"
}

# source_ref は設計書の原本コミットを示すSHAだけを受け入れる。
# 表示値としてHTMLへ渡すため、形式外の値は出力せずfail closedにする。
is_commit_sha() {
  [[ "$1" =~ ^([[:xdigit:]]{7}|[[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]]
}

# run_pipeline_hook — --pre-build / --post-build で差し込まれたコマンドを実行する。
# 差し込んだコマンドへ対象リポジトリ・docs・ポータル出力先のパスを環境変数で渡し、
# 実行したコマンドを標準エラーへ記録する。コマンドが非 0 で終了した場合は
# build-portal.sh 自体もその終了コードで異常終了する（失敗を握りつぶさない）。
#
# 引数:
#   $1 hook_name — ログ表示用のラベル（例: --pre-build）
#   $2 hook_cmd  — sh -c で実行するコマンド文字列。空なら何もしない
run_pipeline_hook() {
  local hook_name="$1"
  local hook_cmd="$2"
  [ -n "$hook_cmd" ] || return 0
  echo "INFO: running $hook_name: $hook_cmd" >&2
  local hook_status=0
  REVERSE_DOCS_TARGET_REPO="$TARGET_REPO" \
    REVERSE_DOCS_DOCS_DIR="$DOCS_ROOT" \
    REVERSE_DOCS_PORTAL_DIR="$PORTAL_DIR" \
    sh -c "$hook_cmd" || hook_status=$?
  if [ "$hook_status" -ne 0 ]; then
    echo "ERROR: $hook_name failed (exit $hook_status): $hook_cmd" >&2
    exit "$hook_status"
  fi
}

# backfill_shell_shared_state — discovery 結果（カテゴリ別実カード数・総資料数・更新日）を
# 生成済み HTML 群へ一括反映する。6 経路（build-portal.sh 本体・unit-list 3 種・
# matrix・detail-pages）がそれぞれ別プロセスで焼いたシェル（サイドバー・フッター）の値を、
# discovery を持つ build-portal.sh の実行末尾で単一の情報源に揃え直すためのバックフィル。
# 対象外（pt-nav-data マーカーを持たない HTML）は無変更のまま skip する。
#
# 引数:
#   $1 shell_counts_json — `[{"key":"<カテゴリキー>","count":<実カード数>},...]`
#   $2 generated_date    — YYYY-MM-DD 形式の更新日
# 標準入力: バックフィル対象の HTML ファイルパス（1 行 1 パス）
backfill_shell_shared_state() {
  local counts_json="$1"
  local generated_date="$2"
  # `node -` はスクリプト自体を標準入力から読むため、ファイル一覧の標準入力は
  # 先に fd 3 へ退避してから node に渡す（link_related_material_paths と同じ作法）。
  node - "$counts_json" "$generated_date" 3<&0 <<'NODE'
const fs = require('node:fs');

const countsJson = process.argv[2];
const generatedDate = process.argv[3];

let counts;
try {
  counts = JSON.parse(countsJson);
} catch (e) {
  process.stderr.write('ERROR: backfill_shell_shared_state: invalid shell_counts_json\n');
  process.exit(1);
}

const countByKey = new Map(counts.map((c) => [c.key, c.count]));
const total = counts.reduce((sum, c) => sum + (Number(c.count) || 0), 0);

// nav_json を script 要素から抜け出させない無害化（shell-injection.sh と同じ規則）
function escapeForScript(json) {
  return json.replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
}

function processFile(filePath) {
  let html;
  try {
    html = fs.readFileSync(filePath, 'utf8');
  } catch (e) {
    return;
  }
  let changed = false;

  const navPattern = /(<script type="application\/json" id="pt-nav-data">)([\s\S]*?)(<\/script>)/;
  const navMatch = html.match(navPattern);
  if (navMatch) {
    let navArray = null;
    try {
      navArray = JSON.parse(navMatch[2]);
    } catch (e) {
      navArray = null;
    }
    if (Array.isArray(navArray)) {
      const updated = navArray.map((entry) => {
        if (entry && typeof entry === 'object' && countByKey.has(entry.key)) {
          return Object.assign({}, entry, { count: countByKey.get(entry.key) });
        }
        return entry;
      });
      const newNavJson = escapeForScript(JSON.stringify(updated));
      if (newNavJson !== navMatch[2]) {
        html = html.slice(0, navMatch.index) + navMatch[1] + newNavJson + navMatch[3]
          + html.slice(navMatch.index + navMatch[0].length);
        changed = true;
      }
    }
  }

  const totalPattern = /(設計台帳\s*·\s*全)(\d+)(資料)/;
  const totalMatch = html.match(totalPattern);
  if (totalMatch && totalMatch[2] !== String(total)) {
    html = html.replace(totalPattern, `$1${total}$3`);
    changed = true;
  }

  // unit-list/matrix/detail-pages の各経路は manifest.generatedAt をそのまま
  // {{GENERATED_DATE}} へ渡すため、ISO-8601 の日時表現（末尾 T00:00:00Z 等）が
  // そのまま焼き込まれることがある。バックフィルは日付のみの形式に限定せず、
  // タグ間の内容を無条件に GENERATED_DATE（YYYY-MM-DD）へ揃える。
  const sidebarDatePattern = /(id="pt-sidebar-date">)([^<]*)(<\/span>)/;
  const sidebarDateMatch = html.match(sidebarDatePattern);
  if (sidebarDateMatch && sidebarDateMatch[2] !== generatedDate) {
    html = html.replace(sidebarDatePattern, `$1${generatedDate}$3`);
    changed = true;
  }

  const footerDatePattern = /(id="pt-footer-date">)([^<]*)(<\/span>)/;
  const footerDateMatch = html.match(footerDatePattern);
  if (footerDateMatch && footerDateMatch[2] !== generatedDate) {
    html = html.replace(footerDatePattern, `$1${generatedDate}$3`);
    changed = true;
  }

  if (changed) {
    fs.writeFileSync(filePath, html);
  }
}

const fileList = fs.readFileSync(3, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
fileList.forEach(processFile);
NODE
}

# remove_orphaned_common_html — 対応する Markdown を失った生成 HTML を限定して削除する。
# common_roots と rules_root は .md と .html を同居させ、foundation_out_dir と
# screen_view_root は分離出力する。どちらも同じ保護判定を通し、対応表・解決済みcatalog
# exact output・build-portal.sh 固有のフッター要素で生成物だと判別できる範囲だけを扱う。
#
# 引数:
#   $1 md_map_file — 1 行「md絶対パス<TAB>html絶対パス」の対応表
#   $2 catalog     — portal-catalog.json
#   $3 output_layout_file — portal-catalog と同じprefix解決に使う合成済みoutput-layout
#   $4 docs_root   — 納品物ルート
#   $5 foundation_out_dir — .md と .html が分離される基盤文書の出力先
#   $6 rules_root — .md と .html を同じ場所へ置く規約文書の入力・出力先
#   $7 screen_view_root — .md と .html が分離される画面文書の出力先
#   $8... common_roots — .md と .html を同じ場所へ置く共通文書の入力・出力先
remove_orphaned_common_html() {
  local md_map_file="$1"
  local catalog="$2"
  local output_layout_file="$3"
  local docs_root="$4"
  local foundation_out_dir="$5"
  local rules_root="$6"
  local screen_view_root="$7"
  shift 7
  node - "$md_map_file" "$catalog" "$output_layout_file" "$docs_root" "$foundation_out_dir" "$rules_root" "$screen_view_root" "$@" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const [mapFile, catalogFile, outputLayoutFile, docsRootRaw, foundationOutDirRaw, rulesRootRaw, screenViewRootRaw, ...commonRootsRaw] = process.argv.slice(2);
const docsRoot = path.resolve(docsRootRaw);
const expected = new Set();
for (const line of fs.readFileSync(mapFile, 'utf8').split('\n')) {
  if (!line) continue;
  const [, htmlFile] = line.split('\t');
  if (htmlFile) expected.add(path.resolve(htmlFile));
}

const scanRoots = new Set();
for (const root of commonRootsRaw) {
  scanRoots.add(path.resolve(root));
}
scanRoots.add(path.resolve(rulesRootRaw));
scanRoots.add(path.resolve(foundationOutDirRaw));
scanRoots.add(path.resolve(screenViewRootRaw));

// portal-catalog.mjs の resolveDefaultRootPrefix と同じ置換を行ってからexact outputを
// 絶対パス化する。カスタムoutput-layoutでもcatalog renderと削除保護の解決先を揃える。
const catalog = JSON.parse(fs.readFileSync(catalogFile, 'utf8'));
const outputLayoutJson = JSON.parse(fs.readFileSync(outputLayoutFile, 'utf8'));
const outputLayout = outputLayoutJson.layout;
const catalogCommonOutputs = new Set();
const catalogOtherOutputs = new Set();
function resolveDefaultRootPrefix(value) {
  for (const [key, prefix] of Object.entries(catalog.defaultRoots || {})) {
    if (value === prefix || value.startsWith(`${prefix}/`)) {
      const override = outputLayout && outputLayout[key];
      if (typeof override === 'string' && override.length > 0) {
        return override + value.slice(prefix.length);
      }
      return value;
    }
  }
  return value;
}
for (const category of catalog.categories || []) {
  for (const blueprint of category.blueprints || []) {
    const rawGlob = blueprint.discovery && blueprint.discovery.glob;
    const glob = typeof rawGlob === 'string' ? resolveDefaultRootPrefix(rawGlob) : rawGlob;
    if (typeof glob !== 'string' || /[*?[\]{}]/.test(glob)) continue;
    const output = path.resolve(docsRoot, glob);
    if (['generating-reverse-common-docs', 'surveying-architecture-for-reverse-docs'].includes(blueprint.generator)) {
      catalogCommonOutputs.add(output);
    } else {
      catalogOtherOutputs.add(output);
    }
  }
}

function underDocsRoot(candidate) {
  const relative = path.relative(docsRoot, candidate);
  return relative === '' || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

const visited = new Set();
function walk(root) {
  if (!underDocsRoot(root) || !fs.existsSync(root) || !fs.lstatSync(root).isDirectory()) return;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const absolute = path.join(root, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      walk(absolute);
      continue;
    }
    if (!entry.isFile() || !entry.name.endsWith('.html') || visited.has(absolute)) continue;
    visited.add(absolute);
    if (expected.has(absolute) || catalogOtherOutputs.has(absolute)) continue;
    const html = fs.readFileSync(absolute, 'utf8');
    // コメントやコード例に生成フッターの文字列が現れても証拠にしない。
    // 実際のHTML要素として残る専用フッターだけを旧生成物の識別子にする。
    const generatedEvidenceHtml = html
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(pre|code|script|style|textarea|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '');
    function hasGeneratedFooter(source) {
      const footerBlocks = source.match(/<footer\b[^>]*>[\s\S]*?<\/footer\s*>/gi) || [];
      for (const block of footerBlocks) {
        if (!block.startsWith('<footer class="pt-footer">')) continue;
        const lines = new Set(block.split(/\r?\n/).map((line) => line.trim()));
        const hasStamp = lines.has('<span class="pt-footer-stamp">REVERSE-DOCS REGISTER</span>');
        const hasGenerator = lines.has('<span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span>');
        if (hasStamp && hasGenerator) return true;
      }
      return false;
    }
    if (!catalogCommonOutputs.has(absolute)
      && !hasGeneratedFooter(generatedEvidenceHtml)) {
      process.stderr.write(`WARN: retained unknown HTML outside expected generated set: ${path.relative(docsRoot, absolute).split(path.sep).join('/')}\n`);
      continue;
    }
    fs.unlinkSync(absolute);
    process.stderr.write(`WARN: removed orphaned generated HTML: ${path.relative(docsRoot, absolute).split(path.sep).join('/')}\n`);
  }
}

for (const root of scanRoots) walk(root);
NODE
}

script_safe_json() {
  node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => { input += chunk; });
    process.stdin.on("end", () => {
      process.stdout.write(
        input
          .replaceAll("<", "\\u003c")
          .replaceAll(">", "\\u003e")
          .replaceAll("&", "\\u0026")
          .replaceAll("\u2028", "\\u2028")
          .replaceAll("\u2029", "\\u2029")
      );
    });
  '
}

RELATED_MATERIAL_CLOSE_BRACKET_MARKER='__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__'

link_related_material_paths() {
  local markdown_dir="$1"
  local html_dir="$2"
  FOUNDATION_MATERIAL_BASENAMES="${FOUNDATION_KNOWN_BASENAMES:-}" \
  FOUNDATION_MATERIAL_OUT_DIR="${FOUNDATION_OUT_DIR:-}" \
  PORTAL_MD_TO_HTML_MAP_FILE="${PORTAL_MD_MAP_FILE:-}" \
  PORTAL_IMPL_TO_HTML_MAP_FILE="${PORTAL_IMPL_MAP_FILE:-}" \
  node - "$markdown_dir" "$html_dir" 3<&0 <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const markdownDir = path.resolve(process.argv[2]);
const htmlDir = path.resolve(process.argv[3]);
const lines = fs.readFileSync(3, 'utf8').split('\n');
let inRelatedMaterials = false;

// 位置と拡張子の解決（実在参照に限る）: commonRoot 配下のうち foundationDir へ物理
// 分離される基盤文書（FOUNDATION_MATERIAL_BASENAMES に列挙済みの basename）だけは、
// 参照時点の相対パス（.md・ソースツリー上の位置）ではなく、実際の生成先
// （FOUNDATION_MATERIAL_OUT_DIR 配下の同名 .html）へ解決する。新しい対応表ファイルは
// 作らず、呼び出し元（build-portal.sh 本体）が既に持つ FOUNDATION_KNOWN_BASENAMES /
// FOUNDATION_OUT_DIR をそのまま使う。判定は既存の実在チェック（statSync）を通過した
// 参照にのみ適用する。このリストに無い名前（対応が取れない参照）は解決せず、
// 既存の実在判定のみで扱う（非実在なら書き換えない）。
const foundationBasenames = new Set(
  (process.env.FOUNDATION_MATERIAL_BASENAMES || '')
    .split('\n')
    .map((entry) => entry.trim())
    .filter(Boolean)
);
const foundationOutDir = process.env.FOUNDATION_MATERIAL_OUT_DIR
  ? path.resolve(process.env.FOUNDATION_MATERIAL_OUT_DIR)
  : '';

// 改善課題1-41: 参照元と参照先の処理順序に左右されず名前を対応づけるため、呼び出し元
// （build-portal.sh 本体）がこれから変換する全.mdの変換先(.html)を先読みして作った
// 対応表を読む。新しい正本ファイルは増やさず、ビルド実行中だけの一時ファイルを読むだけ
// （中身は呼び出し元が実際の変換ループと同じ判定で機械的に導いたもの）。未設定・空なら
// 従来の逐次変換の実在チェック（改善課題1-40のstatSyncフォールバック）のみで動く。
const mdToHtmlMap = new Map();
if (process.env.PORTAL_MD_TO_HTML_MAP_FILE) {
  try {
    const mapContent = fs.readFileSync(process.env.PORTAL_MD_TO_HTML_MAP_FILE, 'utf8');
    for (const line of mapContent.split('\n')) {
      if (!line) continue;
      const [src, dst] = line.split('\t');
      if (!src || !dst) continue;
      mdToHtmlMap.set(path.resolve(src), path.resolve(dst));
    }
  } catch (_) {
    // 対応表が読めない場合はfail-safeで従来のstatSyncフォールバックのみに委ねる。
  }
}

// 改善課題1-41(7回目): ソースツリー上の実装ファイル名（画面の一覧データのentryFile。例:
// pages/HomePage.tsx）から生成後のページのパスへ解決するための対応表。実装ファイル名は
// docsツリー配下に実ファイルとして存在しない（対象リポジトリのソースツリー上の名前であり、
// 名前の体系がmd→html対応表とは異なる）ため、上記mdToHtmlMapとは別の対応表として持つ。
// 呼び出し元（build-portal.sh本体）が画面の一覧データ（screen-manifest.json）から
// 機械的に導いた対応をそのまま読むだけで、新しい正本ファイルは作らない。
const implMap = new Map();
if (process.env.PORTAL_IMPL_TO_HTML_MAP_FILE) {
  try {
    const implMapContent = fs.readFileSync(process.env.PORTAL_IMPL_TO_HTML_MAP_FILE, 'utf8');
    for (const line of implMapContent.split('\n')) {
      if (!line) continue;
      const [key, target] = line.split('\t');
      if (!key || !target) continue;
      implMap.set(key.split(path.sep).join('/'), target);
    }
  } catch (_) {
    // 対応表が読めない場合は解決せず、既存のstatSyncフォールバックのみに委ねる。
  }
}

// 表記のゆれ（文書中の参照は `src/pages/OrderList.tsx` のように前に階層が付くことがあり、
// 一覧データの実装ファイル名 `pages/OrderList.tsx` とは先頭からの完全一致にならない）を
// 吸収するため、対応表の鍵を末尾から見て区切りの境界で一致するものを選ぶ。複数当たる場合は
// 一致した階層（区切りの数）が深いものを優先する。
function resolveImplReference(relativePath) {
  const normalized = relativePath.split(path.sep).join('/');
  let best = null;
  let bestDepth = -1;
  for (const [key, target] of implMap) {
    if (normalized !== key && !normalized.endsWith('/' + key)) continue;
    const depth = key.split('/').length;
    if (depth > bestDepth) {
      bestDepth = depth;
      best = target;
    }
  }
  return best;
}

function toRelativeHref(targetFile) {
  return path.relative(htmlDir, targetFile)
    .split(path.sep)
    .join('/')
    .split('/')
    .map((segment) => segment === '.' || segment === '..'
      ? segment
      : encodeURIComponent(segment).replace(/\(/g, '%28').replace(/\)/g, '%29'))
    .join('/');
}

function existingFileHref(relativePath) {
  // 実装ファイル名の対応（画面のみ）は docs ツリー配下の実ファイル存在を前提にしない
  // （参照先はソースツリー上の名前であり、markdownDir配下には実在しないため）。
  const implTarget = resolveImplReference(relativePath);
  if (implTarget) return toRelativeHref(implTarget);

  const sourceFile = path.join(markdownDir, relativePath);
  try {
    if (!fs.statSync(sourceFile).isFile()) return null;
  } catch (_) {
    return null;
  }

  let targetFile = sourceFile;
  const baseName = path.basename(sourceFile);
  if (foundationOutDir && foundationBasenames.has(baseName)) {
    // 基盤文書は commonRoot 配下に実在すれば必ずこのビルドで foundationDir 配下へ
    // 変換される（宣言済みの既知集合のため、生成物の実在確認は不要）。
    targetFile = path.join(foundationOutDir, baseName.replace(/\.md$/i, '.html'));
  } else {
    const mapped = mdToHtmlMap.get(path.resolve(sourceFile));
    if (mapped) {
      // 対応表に載っている（＝このビルドの変換対象である）参照は、実際にまだ変換済み
      // かどうかによらず、必ず生成される先へ解決する（改善課題1-41）。
      targetFile = mapped;
    } else {
      // 対応表に載っていない参照（rules・screen等、対応表の対象外のループから呼ばれた
      // 場合）は、参照先の .md に対応する生成物（.html）が実際に出力されている場合
      // だけそちらへ解決する（改善課題1-40）。無ければ元の .md 参照のまま残す
      // （実在しないページへの死んだリンクを作らない）。
      const candidateHtmlFile = sourceFile.replace(/\.md$/i, '.html');
      try {
        if (fs.statSync(candidateHtmlFile).isFile()) {
          targetFile = candidateHtmlFile;
        }
      } catch (_) {
        // 生成物なし: targetFile は sourceFile（.md）のまま
      }
    }
  }

  return toRelativeHref(targetFile);
}

function markdownLinkLabel(relativePath) {
  return relativePath.replace(/\]/g, '__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__');
}

// 本文中の Markdown リンク（[label](path.md)）の拡張子解決（改善課題1-40）。
// スキーム付き・`//` 始まりの絶対参照・アンカーのみ・.md 以外の拡張子は対象外。
// 「## 関連資料」表の宣言（バッククォート表記）はこの時点ではまだリンク構文になっていない
// ため対象に含まれず、後続のブロックが別途変換する。両者とも existingFileHref を共用する。
const PROSE_MD_LINK_RE = /\[([^\]]+)\]\(([^()\s]+)\)/g;

function resolveProseMdLink(url) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(url) || /^\/\//.test(url)) return null;
  const match = url.match(/^([^#?]*)\.md([#?].*)?$/i);
  if (!match) return null;
  const href = existingFileHref(match[1] + '.md');
  return href ? href + (match[2] || '') : null;
}

for (let index = 0; index < lines.length; index += 1) {
  let line = lines[index];
  if (/^##\s+/.test(line)) {
    inRelatedMaterials = /^## 関連資料（正の宣言(?:・付録A)?）$/.test(line.trim());
  }

  line = line.replace(PROSE_MD_LINK_RE, (match, label, url) => {
    const resolved = resolveProseMdLink(url);
    return resolved ? `[${label}](${resolved})` : match;
  });

  if (inRelatedMaterials && line.startsWith('|')) {
    line = line.replace(/`([^`]+)`/g, (match, relativePath) => {
      const href = existingFileHref(relativePath);
      return href ? `[${markdownLinkLabel(relativePath)}](${href})` : match;
    });
  }

  lines[index] = line;
}

process.stdout.write(lines.join('\n'));
NODE
}

prepare_screen_doc_link_renderer() {
  node - 3<&0 <<'NODE'
const fs = require('node:fs');
const source = fs.readFileSync(3, 'utf8');
const original = `return sanitizedUrl ? '<a href="' + sanitizedUrl + '">' + label + '</a>' : label;`;
const replacement = `var displayLabel = label.split('__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__').join('&#93;');
    return sanitizedUrl ? '<a href="' + sanitizedUrl + '">' + displayLabel + '</a>' : label;`;

if (!source.includes(original)) {
  throw new Error('screen document link renderer return expression was not found');
}
process.stdout.write(source.replace(original, replacement));
NODE
}

run_related_material_links_self_test() {
  local test_dir test_repo test_docs test_portal test_detail test_edge test_html test_edge_html test_log
  local test_common_dir test_common_html test_foundation_html

  echo "--- 関連資料リンク self-test: 主fixture リンク4/code4・混在セル、補助edge検査 ---"
  test_dir="$(create_physical_tmpdir)"
  test_repo="$test_dir/repo"
  test_docs="$test_dir/docs"
  test_portal="$test_dir/portal"
  test_detail="$test_docs/画面/screen-related-links/詳細設計"
  test_edge="$test_docs/画面/screen-related-links-edge/詳細設計"
  test_common_dir="$test_docs/共通"
  mkdir -p "$test_repo" "$test_detail" "$test_detail/../テスト項目書" "$test_edge" "$test_portal" "$test_common_dir"
  cat > "$test_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面", "commonRoot": "共通", "commonDesignDoc": "共通/共通設計書.md", "foundationDir": "project-portal/基盤" } }
JSON
  touch "$test_detail/画面 (旧).md" "$test_detail/absolute-entry.md" "$test_detail/実在]D.md" "$test_detail/../テスト項目書/実在C.md" "$test_edge/実在&#93;E.md" "$test_edge/false-prefix.md"
  # 改善課題1-41: check-design-doc-section-consistency.sh（改善課題1-74）が
  # screen/画面詳細設計書.md へ必須節16件（§1〜§19の一部）を要求するようになったため、
  # このfixtureも必須節を満たさないと fixture 生成自体（"$0" の呼び出し）が
  # 非0で終了し、本self-testが検証したい関連資料リンク解決へ到達できない
  # （必須節の欠落と本テストの関心事は無関係だが、fixtureは build-portal.sh の
  # 生成経路全体を通すため、この前提条件も満たす必要がある）。
  # 追加した各節の本文は検証に関与しない最小の埋め草で、既存の関連資料テーブル・
  # リンク・コード表記（本テストが検証する対象）は一切変更しない。
  cat > "$test_detail/画面詳細設計書.md" <<'TEST_MD'
# 関連資料リンク検証

## §1 画面概要

検証用の最小記述。

## §2 機能一覧

検証用の最小記述。

## §3 画面構造

検証用の最小記述。

## §5 状態管理

検証用の最小記述。

## §6 データフロー

検証用の最小記述。

## §7 ロジック

検証用の最小記述。

## §8 疑似コード

検証用の最小記述。

## §10 データ定義

検証用の最小記述。

## §11 イベント処理

検証用の最小記述。

## §12 領域別仕様

検証用の最小記述。

## §14 エラーハンドリング

検証用の最小記述。

## §15 画面遷移仕様

検証用の最小記述。

## §16 非機能要件

検証用の最小記述。

## §17 共通仕様への準拠

検証用の最小記述。

## §18 実装契約

検証用の最小記述。

## §19 関連資料

検証用の最小記述（本文は下記「関連資料（正の宣言・付録A）」節を参照）。

## 関連資料（正の宣言・付録A）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| 混在 | `./画面 (旧).md` / `./不存在A.md` | 同一セル内で個別判定する |
| 実在 | `/absolute-entry.md` | markdownDir連結の絶対形式入力 |
| 実在 | `../テスト項目書/実在C.md` | 出力HTML基準の相対リンク |
| 実在 | `./実在]D.md` | renderer互換のラベルエスケープ |
| 非実在 | `./不存在B.md` | 非実在はコード表記 |
| 非実在 | `./不存在C.md` | 非実在はコード表記 |
| 非実在 | `./不存在D.md` | 非実在はコード表記 |
TEST_MD
  cat > "$test_edge/画面詳細設計書.md" <<'TEST_EDGE_MD'
# 関連資料リンク edge検証

## §1 画面概要

検証用の最小記述。

## §2 機能一覧

検証用の最小記述。

## §3 画面構造

検証用の最小記述。

## §5 状態管理

検証用の最小記述。

## §6 データフロー

検証用の最小記述。

## §7 ロジック

検証用の最小記述。

## §8 疑似コード

検証用の最小記述。

## §10 データ定義

検証用の最小記述。

## §11 イベント処理

検証用の最小記述。

## §12 領域別仕様

検証用の最小記述。

## §14 エラーハンドリング

検証用の最小記述。

## §15 画面遷移仕様

検証用の最小記述。

## §16 非機能要件

検証用の最小記述。

## §17 共通仕様への準拠

検証用の最小記述。

## §18 実装契約

検証用の最小記述。

## §19 関連資料

検証用の最小記述（本文は下記「関連資料（正の宣言）」節を参照）。

## 関連資料（正の宣言）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| literal entity | `./実在&#93;E.md` | 入力のentity文字列を維持する |

## 関連資料（正の宣言ではない）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| 対象外 | `./false-prefix.md` | 実在してもコード表記を維持する |
TEST_EDGE_MD

  printf '# 共通設計書\n\n共通設計の本文。\n' > "$test_common_dir/共通設計書.md"
  printf '# 補足資料\n\n補足資料の本文。\n' > "$test_common_dir/補足資料.md"
  cat > "$test_common_dir/本体文書.md" <<'COMMON_MD'
# 共通文書関連資料検証

## 関連資料（正の宣言）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| 実在（基盤文書） | `./共通設計書.md` | 生成先が基盤フォルダへ物理分離される参照。位置と拡張子の解決検証 |
| 実在（非基盤） | `./補足資料.md` | 物理分離されない参照。呼び出し配線のみの検証 |
| 非実在 | `./不存在共通.md` | 対応が取れない参照はコード表記のまま残す |
COMMON_MD

  test_log="$test_dir/build-portal.log"
  if ! "$0" "$test_repo" "$test_docs" "$test_portal" >"$test_log" 2>&1; then
    echo "FAIL: 関連資料リンク self-test（fixture生成が失敗）" >&2
    cat "$test_log" >&2
    rm -rf "$test_dir"
    return 1
  fi
  test_html="$test_detail/画面詳細設計書.html"
  test_edge_html="$test_edge/画面詳細設計書.html"
  test_common_html="$test_common_dir/本体文書.html"
  test_foundation_html="$test_docs/project-portal/基盤/共通設計書.html"
  if [ ! -f "$test_foundation_html" ]; then
    echo "FAIL: 関連資料リンク self-test（共通文書の基盤分離出力が生成されていない: ${test_foundation_html}）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  if ! node - "$test_html" "$test_edge_html" "$test_common_html" <<'NODE'
const fs = require('node:fs');
const vm = require('node:vm');

function rendered(htmlFile) {
  const source = fs.readFileSync(htmlFile, 'utf8');
  const match = source.match(/<script type="application\/json" id="doc-md">([\s\S]*?)<\/script>\s*<script>([\s\S]*?)<\/script>/i);
  if (!match) throw new Error('doc-md or renderer script not found');
  const content = {
    _innerHTML: '', _h1: null,
    set innerHTML(value) {
      this._innerHTML = value;
      const h1Match = value.match(/<h1>([\s\S]*?)<\/h1>/i);
      if (h1Match) this._h1 = { nodeType: 1, tagName: 'H1', textContent: h1Match[1].replace(/<[^>]*>/g, ''), parentNode: { removeChild() { content._h1 = null; } } };
    },
    get innerHTML() { return this._innerHTML; },
    querySelector(selector) { return selector === 'h1' ? this._h1 : null; },
    querySelectorAll() { return []; },
  };
  const document = {
    getElementById(id) { return ({ 'doc-md': { textContent: match[1] }, 'doc-content': content, 'dp-hero-title': { textContent: '' }, 'toc-list': { appendChild() {}, querySelector() { return null; } }, 'screen-nav-title': { textContent: '' } })[id] || null; },
    createElement() { return { classList: { add() {} }, appendChild() {} }; }, querySelectorAll() { return []; },
  };
  vm.runInNewContext(match[2], { document, window: { addEventListener() {} }, requestAnimationFrame(callback) { callback(); } });
  return { markdown: JSON.parse(match[1]), html: content.innerHTML };
}

const main = rendered(process.argv[2]);
const edge = rendered(process.argv[3]);
const common = rendered(process.argv[4]);
const links = [
  '[./画面 (旧).md](%E7%94%BB%E9%9D%A2%20%28%E6%97%A7%29.md)',
  '[/absolute-entry.md](absolute-entry.md)',
  '[../テスト項目書/実在C.md](../%E3%83%86%E3%82%B9%E3%83%88%E9%A0%85%E7%9B%AE%E6%9B%B8/%E5%AE%9F%E5%9C%A8C.md)',
  '[./実在__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__D.md](%E5%AE%9F%E5%9C%A8%5DD.md)',
];
const codes = ['`./不存在A.md`', '`./不存在B.md`', '`./不存在C.md`', '`./不存在D.md`'];
// DOM側のhref拡張子: 生成側（build-portal.sh の existingFileHref）が、参照先の .md に
// 対応する生成物（.html）が実際に出力される場合だけ .html へ解決し、markdown 本文へ
// 直接書き込む。テンプレート側はこの解決済みの URL をそのまま safeUrl で無害化するだけ
// であり、拡張子の書き換えは行わない（改善課題1-40）。
// 注意: 主fixture・補助edgeの参照先（画面 (旧).md・absolute-entry.md・実在C.md・
// 実在]D.md・実在&#93;E.md）は touch で作った空の placeholder であり、build-portal.sh の
// どの変換ループも通らない（対応する .html は生成されない）。したがって以下の期待値は
// 「参照先の生成物が実在しないため .md のまま残る」ことを正としてロックしている。
const expectedDomLinks = [
  '<a href="%E7%94%BB%E9%9D%A2%20%28%E6%97%A7%29.md">./画面 (旧).md</a>',
  '<a href="absolute-entry.md">/absolute-entry.md</a>',
  '<a href="../%E3%83%86%E3%82%B9%E3%83%88%E9%A0%85%E7%9B%AE%E6%9B%B8/%E5%AE%9F%E5%9C%A8C.md">../テスト項目書/実在C.md</a>',
  '<a href="%E5%AE%9F%E5%9C%A8%5DD.md">./実在&#93;D.md</a>',
];
const expectedDomCodes = codes.map((entry) => `<code>${entry.slice(1, -1)}</code>`);
const complete = (main.markdown.match(/\[[^\]]+\]\([^\)]+\)/g) || []).length === 4
  && (main.markdown.match(/`[^`]+`/g) || []).length === 4
  && (main.html.match(/<a href="[^"]+">/g) || []).length === 4
  && (main.html.match(/<code>[^<]+<\/code>/g) || []).length === 4
  && [...links, ...codes].every((entry) => main.markdown.includes(entry))
  && [...expectedDomLinks, ...expectedDomCodes].every((entry) => main.html.includes(entry))
  && edge.markdown.includes('[./実在&#93;E.md](%E5%AE%9F%E5%9C%A8%26%2393%3BE.md)')
  && edge.markdown.includes('`./false-prefix.md`')
  && edge.html.includes('<a href="%E5%AE%9F%E5%9C%A8%26%2393%3BE.md">./実在&amp;#93;E.md</a>')
  && edge.html.includes('<code>./false-prefix.md</code>')
  && common.markdown.includes('[./共通設計書.md](../project-portal/%E5%9F%BA%E7%9B%A4/%E5%85%B1%E9%80%9A%E8%A8%AD%E8%A8%88%E6%9B%B8.html)')
  && common.markdown.includes('[./補足資料.md](%E8%A3%9C%E8%B6%B3%E8%B3%87%E6%96%99.html)')
  && common.markdown.includes('`./不存在共通.md`')
  && common.html.includes('<a href="../project-portal/%E5%9F%BA%E7%9B%A4/%E5%85%B1%E9%80%9A%E8%A8%AD%E8%A8%88%E6%9B%B8.html">./共通設計書.md</a>')
  && common.html.includes('<a href="%E8%A3%9C%E8%B6%B3%E8%B3%87%E6%96%99.html">./補足資料.md</a>')
  && common.html.includes('<code>./不存在共通.md</code>');
if (!complete) process.exit(1);
NODE
  then
    echo "FAIL: 関連資料リンク self-test（主fixture Markdown/portable DOMのリンク4件・コード4件、補助edge検査、共通文書の位置と拡張子の解決検査）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: 関連資料リンク self-test（主fixture 正本見出し・実在4/非実在4・混在セル、Markdown/portable DOMのリンク4件・コード4件；補助fixture false-prefix/literal &#93;；共通文書の基盤文書は位置と拡張子を解決・非基盤は配線のみ・非実在はコード表記のまま）"
  rm -rf "$test_dir"
}

# mktemp -d の戻り値を物理パスへ解決して返す。
# macOS では /var が /private/var へのシンボリックリンクのため、
# assertNoLexicalSymlink が書き込み先を拒否する。
# 素直な形（mktemp -d の戻り値をそのまま使う）をあえて避けている。実測値なし。
# 環境（macOSのディレクトリ構成）に依存する。手元がLinux等でこの問題が起きない
# 環境であっても、この物理パス解決を外すな（self-test群がmacOSで動かなくなる）。
# 過去に消えて再発した経緯: 記録なし。
create_physical_tmpdir() {
  local d
  d="$(mktemp -d "$@")" || return 1
  (cd "$d" && pwd -P)
}

run_project_name_self_test() {
  local test36_dir test36_repo test36_docs test36_explicit_log test36_index
  local test36_docs2 test36_fallback_log test36_index2

  # --- ケース36: --project-name明示指定時は指定名がタイトル・ブランド名・見出し・フッターへ
  # 反映され、未指定時はディレクトリ名(basename)へのフォールバック警告が残ること(1-172) ---
  test36_dir="$(create_physical_tmpdir "${TMPDIR:-/tmp}/build-portal-test36.XXXXXX")"
  test36_repo="$test36_dir/一時作業ディレクトリ名"
  mkdir -p "$test36_repo"

  test36_docs="$test36_dir/docs"
  test36_explicit_log="$test36_dir/explicit.log"
  mkdir -p "$test36_docs"
  "$SCRIPT_DIR/build-portal.sh" "$test36_repo" "$test36_docs" "$test36_docs" \
    --catalog "$DEFAULT_CATALOG" --project-name "実際のプロジェクト名" >/dev/null 2>"$test36_explicit_log"
  test36_index="$test36_docs/index.html"
  if [ -f "$test36_index" ] \
    && grep -q '<title>実際のプロジェクト名 — 設計ポータル</title>' "$test36_index" \
    && grep -q '<h1>実際のプロジェクト名</h1>' "$test36_index" \
    && grep -q 'pt-brand-name">実際のプロジェクト名<' "$test36_index" \
    && grep -q 'pt-footer-meta">実際のプロジェクト名 ' "$test36_index" \
    && ! grep -q 'WARN: --project-name was not specified; using target repo directory name:' "$test36_explicit_log"; then
    echo "PASS: --self-test ケース36a（--project-name明示指定がタイトル・見出し・ブランド名・フッターへ反映され、フォールバック警告は出ない）"
  else
    echo "FAIL: --self-test ケース36a（--project-name明示指定が反映されない、またはフォールバック警告が出た）" >&2
    rm -rf "$test36_dir"
    return 1
  fi

  test36_docs2="$test36_dir/docs2"
  test36_fallback_log="$test36_dir/fallback.log"
  mkdir -p "$test36_docs2"
  "$SCRIPT_DIR/build-portal.sh" "$test36_repo" "$test36_docs2" "$test36_docs2" \
    --catalog "$DEFAULT_CATALOG" >/dev/null 2>"$test36_fallback_log"
  test36_index2="$test36_docs2/index.html"
  if [ -f "$test36_index2" ] \
    && grep -q "<h1>一時作業ディレクトリ名</h1>" "$test36_index2" \
    && grep -q 'WARN: --project-name was not specified; using target repo directory name: 一時作業ディレクトリ名' "$test36_fallback_log"; then
    echo "PASS: --self-test ケース36b（--project-name未指定時はディレクトリ名basenameへフォールバックし、警告が標準エラーに残る）"
  else
    echo "FAIL: --self-test ケース36b（未指定時のフォールバック、またはフォールバック警告の出力に失敗）" >&2
    rm -rf "$test36_dir"
    return 1
  fi
  rm -f "$test36_explicit_log" "$test36_fallback_log"
  rm -rf "$test36_dir"
}

run_prepared_detail_pages_self_test() {
  local test_dir test_repo test_docs test_portal input_dir first_log second_log second_status
  local third_log third_status
  test_dir="$(create_physical_tmpdir "${TMPDIR:-/tmp}/build-portal-test48.XXXXXX")"
  test_repo="$test_dir/repo"
  test_docs="$test_dir/output"
  test_portal="$test_docs/project-portal"
  input_dir="$test_docs/custom/manifests/detail-pages"
  first_log="$test_dir/first.log"
  second_log="$test_dir/second.log"
  third_log="$test_dir/third.log"

  mkdir -p "$test_repo/.claude/rules/always/sample" "$input_dir" "$test_portal"
  jq -n '{specVersion: 1, layout: {manifestsRoot: "custom/manifests"}}' \
    > "$test_docs/output-layout.json"
  cat > "$test_repo/.claude/rules/always/sample/rule.md" <<'EOF'
# 合成規約（SAMPLE）

合成フィクスチャ用の規約。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `sample.sh` | `[SAMPLE]` | 違反を止める |
EOF
  jq -n '{
    pageKind: "techstack", generatedAt: "2026-08-20T00:00:00Z",
    title: "技術スタック", description: "合成フィクスチャ",
    tiles: [{label: "言語", value: "JavaScript", note: "実測"}],
    columns: {item: "項目", value: "値", sourceRef: "出所"},
    rows: [{item: "言語", value: "JavaScript", sourceRef: "package.json"}],
    absentRows: []
  }' > "$input_dir/techstack-page-data.json"
  jq -n '{
    pageKind: "env", generatedAt: "2026-08-20T00:00:00Z",
    title: "環境構築手順", description: "合成フィクスチャ",
    prerequisites: [{name: "Node.js", note: "v18以上"}], environment: [],
    steps: [{order: 1, command: "npm ci", note: "依存関係を導入"}],
    allocations: [], unresolved: []
  }' > "$input_dir/env-page-data.json"
  jq '.generatedAt = "2026-08-20T00:00:00Z"' \
    "$SCRIPT_DIR/detail-pages/fixtures/semantic-glossary-sample-page-data.json" \
    > "$input_dir/glossary-page-data.json"

  if ! "$SCRIPT_DIR/build-portal.sh" "$test_repo" "$test_docs" "$test_portal" \
    --generated-at 2026-08-20T00:00:00Z >"$first_log" 2>&1; then
    echo "FAIL: --self-test ケース48a（準備済み入力からポータルを生成できない）" >&2
    cat "$first_log" >&2
    rm -rf "$test_dir"
    return 1
  fi
  if [ ! -f "$test_portal/基盤/技術スタック.html" ] \
    || [ ! -f "$test_portal/基盤/環境構築手順.html" ] \
    || [ ! -f "$test_portal/一覧/用語辞書/用語辞書.html" ] \
    || [ ! -f "$test_portal/基盤/AI設定資産.html" ] \
    || [ ! -f "$test_docs/custom/manifests/ai-assets.json" ]; then
    echo "FAIL: --self-test ケース48a（3種の詳細ページまたはAI設定資産が生成されない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  if ! grep -q '<div class="pt-brand-name">repo</div>' "$test_portal/基盤/技術スタック.html" \
    || ! grep -q '<div class="pt-brand-name">repo</div>' "$test_portal/基盤/環境構築手順.html" \
    || ! grep -q '<div class="pt-brand-name">repo</div>' "$test_portal/一覧/用語辞書/用語辞書.html" \
    || ! grep -q '<div class="pt-brand-name">repo</div>' "$test_portal/基盤/AI設定資産.html" \
    || ! grep -q '2026-08-20T00:00:00Z' "$test_portal/基盤/AI設定資産.html"; then
    echo "FAIL: --self-test ケース48a（解決したプロジェクト名または生成時刻が全ページへ渡らない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース48a（準備済み3入力と実在するAI設定資産から4ページを生成）"

  rm -f "$input_dir/techstack-page-data.json"
  second_status=0
  "$SCRIPT_DIR/build-portal.sh" "$test_repo" "$test_docs" "$test_portal" \
    --generated-at 2026-08-20T00:00:00Z >"$second_log" 2>&1 || second_status=$?
  if [ "$second_status" -eq 0 ] \
    || ! grep -q 'SKIP: detail page techstack' "$second_log" \
    || ! grep -q 'ERROR: stale detail page detected' "$second_log"; then
    echo "FAIL: --self-test ケース48b（入力欠落の記録と古いページの不合格化が行われない）" >&2
    cat "$second_log" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース48b（入力欠落を記録し、既存ページを古い版として非0終了）"

  jq -n '{
    pageKind: "techstack", generatedAt: "2026-08-20T00:00:00Z",
    title: "技術スタック", description: "合成フィクスチャ",
    tiles: [{label: "言語", value: "JavaScript", note: "実測"}],
    columns: {item: "項目", value: "値", sourceRef: "出所"},
    rows: [{item: "言語", value: "JavaScript", sourceRef: "package.json"}],
    absentRows: []
  }' > "$input_dir/techstack-page-data.json"
  rm -f "$test_repo/.claude/rules/always/sample/rule.md"
  third_status=0
  "$SCRIPT_DIR/build-portal.sh" "$test_repo" "$test_docs" "$test_portal" \
    --generated-at 2026-08-20T00:00:00Z >"$third_log" 2>&1 || third_status=$?
  if [ "$third_status" -eq 0 ] \
    || ! grep -q 'SKIP: AI configuration assets (extracted asset set is empty)' "$third_log" \
    || ! grep -q 'ERROR: stale AI configuration asset page detected' "$third_log"; then
    echo "FAIL: --self-test ケース48c（空のAI設定資産で古いページを不合格化しない）" >&2
    cat "$third_log" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース48c（空のAI設定資産を記録し、既存ページを古い版として非0終了）"

  ensure_playwright_installed
  if [ -z "$PLAYWRIGHT_AVAILABLE" ]; then
    echo "SKIP: --self-test ケース48d実描画（playwrightパッケージが利用できないため。導入後は3種の生成ページでpageerror=0を検査する）"
  elif ! node "$SCRIPT_DIR/tests/assert-generated-detail-pages-runtime.cjs" \
      "$test_portal/基盤/技術スタック.html" \
      "$test_portal/基盤/環境構築手順.html" \
      "$test_portal/一覧/用語辞書/用語辞書.html"; then
      echo "FAIL: --self-test ケース48d（生成した3種の詳細ページで実描画例外が発生）" >&2
      rm -rf "$test_dir"
      return 1
  fi
  rm -rf "$test_dir"
}

run_orphaned_html_self_test() {
  local test_dir test_repo test_root test_portal common_dir rules_dir screen_dir first_log second_log
  local old_html new_html orphan_html late_orphan_html separated_html old_rule_html
  local old_screen_html release_notes_html manual_note_html footer_example_html
  if ! test_dir="$(create_physical_tmpdir "${TMPDIR:-/tmp}/build-portal-test49.XXXXXX")" \
    || [ -z "$test_dir" ]; then
    echo "[UNKNOWN] ケース49の一時ディレクトリを作成できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  test_repo="$test_dir/repo"
  test_root="$test_dir/output"
  test_portal="$test_root/project-portal"
  common_dir="$test_root/docs/design/common"
  rules_dir="$test_root/docs/rules/テスト規約"
  screen_dir="$test_root/docs/design/screens/screen-orphan"
  first_log="$test_dir/first.log"
  second_log="$test_dir/second.log"
  old_html="$common_dir/旧名.html"
  new_html="$common_dir/新名.html"
  orphan_html="$common_dir/孤立.html"
  late_orphan_html="$common_dir/後置孤立.html"
  separated_html="$test_portal/基盤/共通設計書.html"
  old_rule_html="$rules_dir/rule.html"
  old_screen_html="$test_portal/画面/screen-orphan/基本設計/画面基本設計書.html"
  release_notes_html="$test_portal/基盤/リリースノート.html"
  manual_note_html="$common_dir/手動運用メモ.html"
  footer_example_html="$common_dir/フッター記法例.html"

  mkdir -p "$test_repo" "$common_dir" "$rules_dir" \
    "$screen_dir/基本設計" "$screen_dir/詳細設計" "$test_portal"
  printf '# 旧名\n\n改名前の本文。\n' > "$common_dir/旧名.md"
  printf '# 共通設計書\n\n分離配置の本文。\n' > "$common_dir/共通設計書.md"
  printf '# テスト規約\n\n旧規約の本文。\n' > "$rules_dir/rule.md"
  printf '# 合成画面基本設計書\n\n画面の基本設計。\n' > "$screen_dir/基本設計/画面基本設計書.md"
  printf '%s\n' \
    '# 合成画面詳細設計書' \
    '## §1 画面概要' '## §2 機能一覧' '## §3 画面構造' '## §5 状態管理' \
    '## §6 データフロー' '## §7 ロジック' '## §8 疑似コード' '## §10 データ定義' \
    '## §11 イベント処理' '## §12 領域別仕様' '## §14 エラーハンドリング' \
    '## §15 画面遷移仕様' '## §16 非機能要件' '## §17 共通仕様への準拠' \
    '## §18 実装契約' '## §19 関連資料' \
    > "$screen_dir/詳細設計/画面詳細設計書.md"
  if ! "$SCRIPT_DIR/build-portal.sh" "$test_repo" "$test_root" "$test_portal" \
    --generated-at 2026-08-19T00:00:00Z >"$first_log" 2>&1; then
    echo "FAIL: --self-test ケース49（初回の合成フィクスチャを生成できない）" >&2
    cat "$first_log" >&2
    rm -rf "$test_dir"
    return 1
  fi

  mv "$common_dir/旧名.md" "$common_dir/新名.md"
  rm -f "$rules_dir/rule.md"
  rm -f "$screen_dir/基本設計/画面基本設計書.md"
  printf '<html>\n<footer class="pt-footer">\n<span class="pt-footer-stamp">REVERSE-DOCS REGISTER</span>\n<span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span>\n</footer>\n</html>\n' > "$orphan_html"
  printf '<html>実行方法は generation-engine/scripts/build-portal.sh を参照する。</html>\n' > "$manual_note_html"
  printf '<html><!-- <span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span> --><pre><span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span></pre><textarea><footer class="pt-footer"><span class="pt-footer-stamp">REVERSE-DOCS REGISTER</span><span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span></footer></textarea><main><span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span></main>\n<footer class="pt-footer">\n<span class="pt-footer-stamp">REVERSE-DOCS REGISTER</span>\n</footer><footer class="pt-footer">\n<span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span>\n</footer>\n</html>\n' > "$footer_example_html"
  mkdir -p "$(dirname "$release_notes_html")"
  printf '<html>別生成器が作ったリリースノート</html>\n' > "$release_notes_html"
  # 後置孤立HTMLを読み取り専用にし、post-build後の再走査で警告・削除されることを確認する。
  if ! "$SCRIPT_DIR/build-portal.sh" "$test_repo" "$test_root" "$test_portal" \
    --generated-at 2026-08-20T00:00:00Z \
    --post-build 'late_orphan="$REVERSE_DOCS_DOCS_DIR/docs/design/common/後置孤立.html"; printf '\''<span id="pt-sidebar-date">2000-01-01</span>\n<footer class="pt-footer">\n<span class="pt-footer-stamp">REVERSE-DOCS REGISTER</span>\n<span id="pt-footer-date">2000-01-01</span>\n<span class="pt-footer-gen">生成: generation-engine/scripts/build-portal.sh</span>\n</footer>\n'\'' > "$late_orphan"; chmod 444 "$late_orphan"' \
    >"$second_log" 2>&1; then
    echo "FAIL: --self-test ケース49（改名・孤立HTMLを含む合成フィクスチャを再生成できない）" >&2
    cat "$second_log" >&2
    rm -rf "$test_dir"
    return 1
  fi

  if [ -e "$old_html" ] || [ ! -f "$new_html" ]; then
    echo "FAIL: --self-test ケース49a（md改名後に旧名HTMLが残る、または新名HTMLが生成されない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49a（md改名後に旧名HTMLを削除し、新名HTMLを生成）"

  if [ -e "$orphan_html" ] \
    || ! grep -q 'WARN: removed orphaned generated HTML: docs/design/common/孤立.html' "$second_log"; then
    echo "FAIL: --self-test ケース49b（孤立HTMLを削除して警告しない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49b（孤立HTMLを検出し、警告して削除）"

  if [ -e "$late_orphan_html" ] \
    || ! grep -q 'WARN: removed orphaned generated HTML: docs/design/common/後置孤立.html' "$second_log"; then
    echo "FAIL: --self-test ケース49c（post-build後の孤立HTMLを削除して警告しない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49c（読み取り専用の後置孤立HTMLをバックフィル対象にせず、警告して削除）"

  if [ ! -f "$separated_html" ] || ! grep -q '分離配置の本文' "$separated_html"; then
    echo "FAIL: --self-test ケース49d（mdとhtmlの置き場が異なる共通文書を誤って削除した）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49d（portal-catalog対応の分離配置文書を保持）"

  if [ -e "$old_rule_html" ] \
    || ! grep -q 'WARN: removed orphaned generated HTML: docs/rules/テスト規約/rule.html' "$second_log"; then
    echo "FAIL: --self-test ケース49e（削除済み規約の旧HTMLを削除して警告しない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49e（削除済み規約の旧HTMLを検出し、警告して削除）"

  if [ -e "$old_screen_html" ] \
    || ! grep -q 'WARN: removed orphaned generated HTML: project-portal/画面/screen-orphan/基本設計/画面基本設計書.html' "$second_log"; then
    echo "FAIL: --self-test ケース49f（削除済み画面基本設計書の旧HTMLを削除して警告しない）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49f（削除済み画面基本設計書の旧HTMLを検出し、警告して削除）"

  if [ ! -f "$release_notes_html" ] \
    || ! grep -q '別生成器が作ったリリースノート' "$release_notes_html"; then
    echo "FAIL: --self-test ケース49g（catalog上の他生成器exact outputを誤って削除した）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49g（catalog上の他生成器exact outputを負の対照として保持）"

  if [ ! -f "$manual_note_html" ] \
    || ! grep -q '実行方法は generation-engine/scripts/build-portal.sh を参照する。' "$manual_note_html"; then
    echo "FAIL: --self-test ケース49h（生成器のパスを説明する未知HTMLを誤って削除した）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49h（生成器のパスを説明する未知HTMLを負の対照として保持）"

  if [ ! -f "$footer_example_html" ]; then
    echo "FAIL: --self-test ケース49i（コメント・コード例に専用フッター文字列を持つ未知HTMLを誤って削除した）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: --self-test ケース49i（コメント・コード例・フッター外の生成元要素を生成物判定から除外）"
  rm -rf "$test_dir"
}

# 改善課題1-29 検収方法: ケース41（用語辞書ページ）は node_modules の playwright パッケージを
# 直接 require する。node_modules は .gitignore 対象で正本に含まれないため、フレッシュな
# チェックアウトでは require が必ず失敗する。従来は「未導入なら案内してSKIP」するだけで
# 止まっており、検収方法が定める「当該ケースが実行されること」を満たせなかった。
# ここで self-test 自身が `npm ci` を1回だけ試み、成功すればケースを実際に実行する。
# 導入試行は本関数の初回呼び出し時にだけ行い（PLAYWRIGHT_INSTALL_ATTEMPTED で判定）、
# 複数ケースから呼ばれても npm ci を二重実行しない。導入に失敗した場合（オフライン等）
# だけ、従来通りSKIPして案内する。
# npm の既定値（fetch-retries=2・fetch-timeout=300000ms）のままだと、レジストリへ到達
# できない環境では1回の npm ci が数分〜十数分単位で無応答になりうる。呼び出し元（自己
# テストの実行環境）のタイムアウトがそれより短いと、案内メッセージを出す前に呼び出し
# 側ごと打ち切られ「停止し、案内も無い」状態になる。fetch-retries/fetch-timeout を明示
# して1回の到達不能判定を数十秒以内に収め、案内メッセージへ確実に到達させる。
# 2026-08-18 是正（指示書§2.2）: 対象の設定ファイル(package.json)がリポジトリルートに
# 無い場合、以前は下の早期returnで何も試さず(npm ciを1回も呼ばず)戻っていた。それにも
# かかわらず呼び出し元のSKIP文言は「self-test自身によるnpm ciの導入試行にも失敗した」と
# 一律に案内しており、npm ci自体を試みていないケースまで「試行して失敗した」と誤って
# 案内していた。PLAYWRIGHT_NO_PACKAGE_JSONで「設定ファイルが無く試みていない」ことを
# 分けて記録し、呼び出し元がこのケースとnpm ci失敗ケースを文言で区別できるようにする。
PLAYWRIGHT_INSTALL_ATTEMPTED=""
PLAYWRIGHT_AVAILABLE=""
PLAYWRIGHT_NO_PACKAGE_JSON=""
ensure_playwright_installed() {
  if [ -n "$PLAYWRIGHT_INSTALL_ATTEMPTED" ]; then
    return 0
  fi
  PLAYWRIGHT_INSTALL_ATTEMPTED=1

  if node -e "require.resolve('playwright')" >/dev/null 2>&1; then
    PLAYWRIGHT_AVAILABLE=1
    return 0
  fi

  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
  if [ ! -f "$repo_root/package.json" ]; then
    PLAYWRIGHT_NO_PACKAGE_JSON=1
    return 0
  fi

  echo "INFO: playwright パッケージが未導入のため、self-test 自身がリポジトリルートで \`npm ci\` の導入を試みる（レジストリへ到達できる場合は数十秒、到達できない場合は30秒程度で打ち切られる）..." >&2
  if ( cd "$repo_root" && npm ci --prefer-offline --no-audit --no-fund --fetch-retries=0 --fetch-timeout=30000 ) >/dev/null 2>&1; then
    if node -e "require.resolve('playwright')" >/dev/null 2>&1; then
      PLAYWRIGHT_AVAILABLE=1
      echo "INFO: playwright パッケージの導入に成功した。実ブラウザ検証を実行する。" >&2
    else
      echo "INFO: npm ci は完了したが playwright パッケージを解決できなかった。実ブラウザ検証を省略する。" >&2
    fi
  else
    echo "INFO: npm ci の導入試行に失敗した（オフライン環境等）。実ブラウザ検証を省略する。" >&2
  fi
}

# --- self-test ---
if [ "${1:-}" = "--self-test-related-material-links" ]; then
  run_related_material_links_self_test
  exit $?
fi

if [ "${1:-}" = "--self-test" ] && [ "${2:-}" = "--case" ]; then
  if [ "$#" -ne 3 ] || { [ "${3:-}" != "36" ] && [ "${3:-}" != "48" ] && [ "${3:-}" != "49" ]; }; then
    echo "ERROR: usage: build-portal.sh --self-test --case 36|48|49" >&2
    exit 2
  fi
  if [ -d "${TMPDIR:-/tmp}" ]; then
    TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
    export TMPDIR
  fi
  if [ "${3:-}" = "36" ]; then
    run_project_name_self_test
  elif [ "${3:-}" = "48" ]; then
    run_prepared_detail_pages_self_test
  else
    run_orphaned_html_self_test
  fi
  exit $?
fi

# 既知の事実（宣言済み長時間）: 本 self-test は実測815秒かかる
# （generation-engine/scripts/verification/run-layer-machine-checks.sh の
# declared_long_running_known() に登録済み）。機能は delivery-payload/templates
# 由来の決定的生成であり、短縮も改変も本ファイルの担当範囲外。第1層の集約実行では
# TIMEOUT や途中停止の疑いとして数えず、DECLARED-LONG として区別だけ付けて扱う。
if [ "${1:-}" = "--self-test" ]; then
  # 改善課題1-243: 1件のケース不合格で self-test 全体が exit 1 し、以降の
  # ケースが一度も実行されない問題への対応。ケースの FAIL は
  # record_self_test_case_failure で件数だけ記録し、exit で打ち切らない。
  # 走り切ったうえで末尾の SELF-TEST SUMMARY 行に集計し、1件でも不合格なら
  # 最後に非0で終了する（1-183 の check-phase-step-structure.test.sh と同型）。
  #
  # set -e を無効化する理由: 明示的な `exit 1` は上記の対応で件数記録に
  # 置き換えたが、各ケースは `"$SCRIPT_DIR/build-portal.sh" ... 2>/dev/null`
  # のような素の（if/whileで保護されていない）自己再帰呼び出しも多数持つ。
  # 実測（改善課題1-243）: ケース1修正後に実行してみたところ、ケース4の
  # 素の再帰呼び出しが実際の入力不備（必須節欠落）でexit 1を返し、
  # set -e によりケース4の後続チェック（grep によるPASS/FAIL判定）にすら
  # 到達せずself-test全体が打ち切られることを確認した。各ケースは元々
  # 素の再帰呼び出しの終了コード自体ではなく、生成結果（HTML等）を
  # grep 等で検査してPASS/FAILを判定する設計であり、この検査そのものは
  # set -e に依存していない。self-test駆動部分のみ set -e を外し、各ケースが
  # 明示チェックで判定を行う設計へ揃える（再帰呼び出し先の子プロセスは
  # 別プロセスであり本体側の set -euo pipefail は子プロセス内で独立に有効）。
  set +e
  SELF_TEST_CASE_FAIL_COUNT=0
  record_self_test_case_failure() {
    SELF_TEST_CASE_FAIL_COUNT=$((SELF_TEST_CASE_FAIL_COUNT + 1))
    return 0
  }

  if [ -d "${TMPDIR:-/tmp}" ]; then
    TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
    export TMPDIR
  fi
  tmpdir="$(create_physical_tmpdir)"
  tmpdir2="$(create_physical_tmpdir)"
  trap 'rm -rf "$tmpdir" "$tmpdir2"' EXIT

  # ケース1: 旧スキーマ互換（既存フィクスチャそのまま。tests/commit/previous なし）
  mkdir -p "$tmpdir/repo/misc"
  echo "const x = 1;" > "$tmpdir/repo/misc/util.ts"

  mkdir -p "$tmpdir/portal" "$tmpdir/docs"
  cat > "$tmpdir/docs/code-metrics.json" <<'FIXTURE'
{"total":1,"fe":0,"be":0,"file_count":1,"fe_files":0,"be_files":0,"method":"wc","measured_at":"2026-01-01T00:00:00Z"}
FIXTURE

  case1_pass=0
  if bash "$0" "$tmpdir/repo" "$tmpdir/docs" "$tmpdir/portal" 2>/dev/null; then
    if [ -f "$tmpdir/portal/index.html" ]; then
      echo "PASS: --self-test ケース1（旧スキーマ互換, exit 0, index.html generated）" >&2
      case1_pass=1
    fi
  fi
  if [ "$case1_pass" -ne 1 ]; then
    echo "FAIL: --self-test ケース1（旧スキーマ互換）" >&2
    record_self_test_case_failure
  fi

  # ケース2: 新スキーマ + git 管理フィクスチャ（tests/commit/previous あり）
  mkdir -p "$tmpdir2/repo"
  git -C "$tmpdir2/repo" init -q
  git -C "$tmpdir2/repo" config user.email "test@example.com"
  git -C "$tmpdir2/repo" config user.name "Test"
  echo "const x = 1;" > "$tmpdir2/repo/util.ts"
  git -C "$tmpdir2/repo" add -A
  git -C "$tmpdir2/repo" commit -q -m "initial"
  commit_hash="$(git -C "$tmpdir2/repo" rev-parse HEAD)"

  mkdir -p "$tmpdir2/portal" "$tmpdir2/docs"
  cat > "$tmpdir2/docs/code-metrics.json" <<FIXTURE2
{"total":1000,"fe":600,"be":400,"file_count":10,"fe_files":6,"be_files":4,"method":"wc","measured_at":"2026-07-16T00:00:00Z","commit":"$commit_hash","tests":{"count":20,"fe":12,"be":8,"files":5},"previous":{"total":900,"tests_count":15,"measured_at":"2026-07-01T00:00:00Z"}}
FIXTURE2

  mkdir -p "$tmpdir2/docs"

  case2_pass=0
  if bash "$0" "$tmpdir2/repo" "$tmpdir2/docs" "$tmpdir2/portal" 2>/dev/null; then
    out="$tmpdir2/portal/index.html"
    if [ -f "$out" ] && [ "$(grep -c '{{' "$out" || true)" -eq 0 ] && grep -q '"scale"' "$out"; then
      echo "PASS: --self-test ケース2（新スキーマ + git 管理, exit 0, 未解決プレースホルダなし, scale 含む）" >&2
      case2_pass=1
    fi
  fi
  if [ "$case2_pass" -ne 1 ]; then
    echo "FAIL: --self-test ケース2（新スキーマ + git 管理）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース3: 承認済み意味用語のportal discovery ---"
  test3_dir="$(create_physical_tmpdir)"
  test3_docs="$test3_dir/docs"
  test3_portal="$test3_dir/portal"
  mkdir -p "$test3_docs" "$test3_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test3_docs/code-metrics.json"
  mkdir -p "$test3_docs/project-portal/一覧/用語辞書"
  echo '<html><body>test glossary</body></html>' > "$test3_docs/project-portal/一覧/用語辞書/用語辞書.html"
  "$SCRIPT_DIR/build-portal.sh" "$test3_dir" "$test3_docs" "$test3_portal" 2>/dev/null
  if grep -q 'href":"[^"]*用語辞書.html"' "$test3_portal/index.html" \
    && grep -q '"kind":"semantic-glossary"' "$DEFAULT_CATALOG" \
    && grep -q '"generator":"managing-semantic-glossary"' "$DEFAULT_CATALOG" \
    && ! grep -q '"generator":"generating-glossary-for-reverse-docs"' "$DEFAULT_CATALOG"; then
    echo "PASS: --self-test ケース3（旧reverse generatorなし・承認済みsemantic-glossaryカードから用語辞書へ到達）"
  else
    echo "FAIL: --self-test ケース3" >&2; rm -rf "$test3_dir"; record_self_test_case_failure
  fi
  rm -rf "$test3_dir"

  echo "--- ケース4: BOM付き・frontmatter付きmdファイルからのタイトル抽出 ---"
  test4_dir="$(create_physical_tmpdir)"
  test4_repo="$test4_dir/repo"
  test4_docs="$test4_dir/docs"
  test4_portal="$test4_dir/portal"
  mkdir -p "$test4_repo" "$test4_docs/プロジェクト共通" "$test4_docs/画面/screen-title/詳細設計" "$test4_portal"
  cat > "$test4_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通", "screenUnitRoot": "画面" } }
JSON
  printf '\xEF\xBB\xBF# BOM付き見出し\n本文' > "$test4_docs/プロジェクト共通/bom-test.md"
  printf -- '---\ntitle: frontmatter\n---\n# FM後の見出し\n本文' > "$test4_docs/プロジェクト共通/fm-test.md"
  printf -- '---\n# 執筆者向け内部指示: この見出しを文書名に使わない\n---\n# 共通本文タイトル\n本文' > "$test4_docs/プロジェクト共通/title-frontmatter.md"
  printf -- '---\n# 執筆者向け内部指示: この見出しを文書名に使わない\n---\n# 画面本文タイトル\n本文' > "$test4_docs/画面/screen-title/詳細設計/画面詳細設計書.md"
  printf '見出しのない本文' > "$test4_docs/プロジェクト共通/fallback-title.md"
  "$SCRIPT_DIR/build-portal.sh" "$test4_repo" "$test4_docs" "$test4_portal" 2>/dev/null
  bom_ok=0
  fm_ok=0
  grep -q 'BOM付き見出し' "$test4_docs/プロジェクト共通/bom-test.html" 2>/dev/null && bom_ok=1
  grep -q 'FM後の見出し' "$test4_docs/プロジェクト共通/fm-test.html" 2>/dev/null && fm_ok=1
  if [ "$bom_ok" = "1" ] && [ "$fm_ok" = "1" ]; then
    echo "PASS: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出）"
  else
    echo "FAIL: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出, bom=${bom_ok} fm=${fm_ok}）" >&2
    rm -rf "$test4_dir"
    record_self_test_case_failure
  fi

  test4_common_html="$test4_docs/プロジェクト共通/title-frontmatter.html"
  test4_screen_html="$test4_docs/project-portal/画面/screen-title/詳細設計/画面詳細設計書.html"
  test4_fallback_html="$test4_docs/プロジェクト共通/fallback-title.html"
  if ! node -e '
    const fs = require("node:fs");
    const vm = require("node:vm");
    const pages = process.argv.slice(1);
    let failed = false;
    const text = (value) => (value || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").trim();
    for (let i = 0; i < pages.length; i += 2) {
      const [file, expected] = pages.slice(i, i + 2);
      const source = fs.readFileSync(file, "utf8");
      const title = text((source.match(/<title>([\s\S]*?)<\/title>/i) || [])[1]);
      const crumb = text((source.match(/<span class="pt-crumb-current">([\s\S]*?)<\/span>/i) || [])[1]);
      const initialH1 = text((source.match(/<h1[^>]*id="dp-hero-title"[^>]*>([\s\S]*?)<\/h1>/i) || [])[1]);
      const scriptMatch = source.match(/<script\s+type="application\/json"\s+id="doc-md">([\s\S]*?)<\/script>\s*<script>([\s\S]*?)<\/script>/i);
      let runtimeH1 = "(script extraction failed)";
      if (!scriptMatch) {
        console.error(`FAIL: --self-test ケース4（意味語名のNode DOM検査） file=${file} expected=${expected} title=${title} crumb=${crumb} initialH1=${initialH1} runtimeH1=${runtimeH1}`);
        failed = true;
        continue;
      }
      const hero = { textContent: initialH1 };
      const content = {
        _innerHTML: "",
        _h1: null,
        set innerHTML(value) {
          this._innerHTML = value;
          const h1Match = value.match(/<h1>([\s\S]*?)<\/h1>/i);
          if (!h1Match) return;
          const h1 = {
            nodeType: 1,
            tagName: "H1",
            textContent: text(h1Match[1]),
            parentNode: { removeChild(node) { if (node === h1) content._h1 = null; } },
          };
          this._h1 = h1;
        },
        get innerHTML() { return this._innerHTML; },
        querySelector(selector) { return selector === "h1" ? this._h1 : null; },
        querySelectorAll() { return []; },
      };
      const tocList = { querySelector() { return null; }, appendChild() {} };
      const screenNavTitle = { textContent: "" };
      const document = {
        getElementById(id) {
          return ({ "doc-md": { textContent: scriptMatch[1] }, "doc-content": content, "dp-hero-title": hero, "toc-list": tocList, "screen-nav-title": screenNavTitle })[id] || null;
        },
        createElement() { return { appendChild() {}, classList: { add() {} } }; },
        querySelectorAll() { return []; },
      };
      const window = { addEventListener() {} };
      try {
        vm.runInNewContext(scriptMatch[2], { document, window, requestAnimationFrame(callback) { callback(); } });
        runtimeH1 = hero.textContent;
      } catch (error) {
        runtimeH1 = `(vm error: ${error.message})`;
      }
      if (title !== expected || crumb !== expected || initialH1 !== expected || runtimeH1 !== expected) {
        console.error(`FAIL: --self-test ケース4（意味語名のNode DOM検査） file=${file} expected=${expected} title=${title} crumb=${crumb} initialH1=${initialH1} runtimeH1=${runtimeH1}`);
        failed = true;
      }
    }
    process.exit(failed ? 1 : 0);
  ' "$test4_common_html" '共通本文タイトル' "$test4_screen_html" '画面本文タイトル' "$test4_fallback_html" 'fallback-title'; then
    rm -rf "$test4_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース4（frontmatter内の内部指示を意味語名に採用しない）"
  rm -rf "$test4_dir"

  echo "--- ケース5: 共通文書 .md → .html 変換 ---"
  test5_dir="$(create_physical_tmpdir)"
  test5_repo="$test5_dir/repo"
  test5_docs="$test5_dir/docs"
  test5_portal="$test5_dir/portal"
  mkdir -p "$test5_repo" "$test5_docs/プロジェクト共通" "$test5_portal"
  cat > "$test5_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# テスト文書\n\n本文テスト。\n\n| 列1 | 列2 |\n|---|---|\n| A | B |\n' > "$test5_docs/プロジェクト共通/test-doc.md"
  "$SCRIPT_DIR/build-portal.sh" "$test5_repo" "$test5_docs" "$test5_portal" 2>/dev/null
  if [ ! -f "$test5_docs/プロジェクト共通/test-doc.html" ]; then
    echo "FAIL: ケース5 — test-doc.html が生成されていない" >&2; rm -rf "$test5_dir"; record_self_test_case_failure
  fi
  if ! grep -q 'テスト文書' "$test5_docs/プロジェクト共通/test-doc.html"; then
    echo "FAIL: ケース5 — test-doc.html にタイトルが含まれていない" >&2; rm -rf "$test5_dir"; record_self_test_case_failure
  fi
  if grep -q 'test-doc\.md"' "$test5_portal/index.html"; then
    echo "FAIL: ケース5 — ポータルにまだ .md リンクが残っている" >&2; rm -rf "$test5_dir"; record_self_test_case_failure
  fi
  panel_width_decl="$(grep -oE 'width: 100%; min-width: 0; max-width: [^;]+;' "$test5_docs/プロジェクト共通/test-doc.html" | head -1)"
  if [ -z "$panel_width_decl" ] \
     || ! printf '%s' "$panel_width_decl" | grep -qE 'max-width: [^;]*vw' \
     || grep -qF 'grid-template-columns: 200px' "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF "className = 'table-scroll-shell'" "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF 'can-scroll-right' "$test5_docs/プロジェクト共通/test-doc.html"; then
    echo "FAIL: ケース5 — 詳細文書の可変幅パネル（width:100%・min-width:0・vw基準のmax-width）または横スクロール合図が欠落" >&2
    rm -rf "$test5_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース5（共通文書 .md → .html 変換）"

  echo "--- ケース5d: 共通文書がサイドバー統合済みで dp-toc を持たない ---"
  pt_sidebar_count="$(grep -o 'class="pt-sidebar"' "$test5_docs/プロジェクト共通/test-doc.html" | wc -l | tr -d ' ')" || pt_sidebar_count=0
  dp_toc_count="$(grep -o 'class="dp-toc"' "$test5_docs/プロジェクト共通/test-doc.html" | wc -l | tr -d ' ')" || dp_toc_count=0
  pt_doc_nav_count="$(grep -o 'class="pt-doc-nav"' "$test5_docs/プロジェクト共通/test-doc.html" | wc -l | tr -d ' ')" || pt_doc_nav_count=0
  toc_list_count="$(grep -o 'id="toc-list"' "$test5_docs/プロジェクト共通/test-doc.html" | wc -l | tr -d ' ')" || toc_list_count=0
  if [ "$pt_sidebar_count" != "1" ] || [ "$dp_toc_count" != "0" ] || [ "$pt_doc_nav_count" -lt 1 ] || [ "$toc_list_count" != "1" ]; then
    echo "FAIL: ケース5d — サイドバー統合が崩れている pt-sidebar=$pt_sidebar_count dp-toc=$dp_toc_count pt-doc-nav=$pt_doc_nav_count toc-list=$toc_list_count" >&2
    rm -rf "$test5_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース5d（共通文書のサイドバー統合）"

  echo "--- ケース5e: 共通文書に狭幅対応 CSS が含まれる ---"
  if ! grep -qF '@media (max-width: 900px)' "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF 'pt-sidebar-toggle' "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF 'pt-sidebar-scrim' "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -A2 -F '@media (max-width: 900px)' "$test5_docs/プロジェクト共通/test-doc.html" | grep -qF -- '--page-gutter: 16px;'; then
    echo "FAIL: ケース5e — 狭幅対応 CSS（メディアクエリ・トグル・スクリム・page-gutter上書き）が欠落" >&2
    rm -rf "$test5_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース5e（共通文書の狭幅対応CSS）"
  rm -rf "$test5_dir"

  echo "--- ケース5b: サブディレクトリ配下の共通文書リンクがパスを保持する ---"
  test5b_dir="$(create_physical_tmpdir)"
  test5b_repo="$test5b_dir/repo"
  test5b_docs="$test5b_dir/docs"
  test5b_portal="$test5b_dir/portal"
  mkdir -p "$test5b_repo" "$test5b_docs/プロジェクト共通/規約" "$test5b_portal"
  cat > "$test5b_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# サブ規約\n\n本文。\n' > "$test5b_docs/プロジェクト共通/規約/sub-rule.md"
  "$SCRIPT_DIR/build-portal.sh" "$test5b_repo" "$test5b_docs" "$test5b_portal" 2>/dev/null
  if [ ! -f "$test5b_docs/プロジェクト共通/規約/sub-rule.html" ]; then
    echo "FAIL: ケース5b — サブディレクトリ内に sub-rule.html が生成されていない" >&2; rm -rf "$test5b_dir"; record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース5b（サブディレクトリ配下の共通文書変換）"
  rm -rf "$test5b_dir"

  echo "--- ケース5c: 共通文書の戻るリンクが出力先の深さに応じた相対パスになる ---"
  test5c_dir="$(create_physical_tmpdir)"
  test5c_repo="$test5c_dir/repo"
  test5c_docs="$test5c_dir/docs"
  mkdir -p "$test5c_repo" "$test5c_docs/プロジェクト共通/規約"
  cat > "$test5c_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 深さ1文書\n\n本文。\n' > "$test5c_docs/プロジェクト共通/depth1-doc.md"
  printf '# 深さ2規約\n\n本文。\n' > "$test5c_docs/プロジェクト共通/規約/depth2-rule.md"
  # 正本レイアウト: ポータル = docs ルートの index.html
  "$SCRIPT_DIR/build-portal.sh" "$test5c_repo" "$test5c_docs" "$test5c_docs" 2>/dev/null
  if ! grep -q 'href="\.\./index\.html"' "$test5c_docs/プロジェクト共通/depth1-doc.html"; then
    echo "FAIL: ケース5c — 深さ1の戻るリンクが ../index.html でない" >&2; rm -rf "$test5c_dir"; record_self_test_case_failure
  fi
  if ! grep -q 'href="\.\./\.\./index\.html"' "$test5c_docs/プロジェクト共通/規約/depth2-rule.html"; then
    echo "FAIL: ケース5c — 深さ2の戻るリンクが ../../index.html でない" >&2; rm -rf "$test5c_dir"; record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース5c（戻るリンクの深さ別相対パス計算）"
  rm -rf "$test5c_dir"

  echo "--- ケース6: frontmatter 付き md → html で frontmatter が本文に表示されない ---"
  test6_dir="$(create_physical_tmpdir)"
  test6_repo="$test6_dir/repo"
  test6_docs="$test6_dir/docs"
  test6_portal="$test6_dir/portal"
  mkdir -p "$test6_repo" "$test6_docs/プロジェクト共通" "$test6_portal"
  cat > "$test6_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf -- '---\ndoc_id: test-doc\ntype: design\nstatus: traced\n---\n# テスト見出し\n\n本文テスト。' > "$test6_docs/プロジェクト共通/fm-body-test.md"
  "$0" "$test6_repo" "$test6_docs" "$test6_portal" 2>/dev/null
  if grep -q 'doc_id:' "$test6_docs/プロジェクト共通/fm-body-test.html" 2>/dev/null; then
    echo "FAIL: ケース6 — frontmatter が HTML 本文に残留" >&2
    rm -rf "$test6_dir"
    record_self_test_case_failure
  fi
  if ! grep -q 'テスト見出し' "$test6_docs/プロジェクト共通/fm-body-test.html" 2>/dev/null; then
    echo "FAIL: ケース6 — 見出しが消失" >&2
    rm -rf "$test6_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6（frontmatter 除去）"
  rm -rf "$test6_dir"

  echo "--- ケース6b: 単一行 HTML コメントの除去 ---"
  test6b_dir="$(create_physical_tmpdir)"
  test6b_repo="$test6b_dir/repo"
  test6b_docs="$test6b_dir/docs"
  test6b_portal="$test6b_dir/portal"
  mkdir -p "$test6b_repo" "$test6b_docs/プロジェクト共通" "$test6b_portal"
  cat > "$test6b_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 見出し\n\n本文前。\n\n<!-- このコメントは除去される -->\n\n本文後。' > "$test6b_docs/プロジェクト共通/comment-single-test.md"
  "$0" "$test6b_repo" "$test6b_docs" "$test6b_portal" 2>/dev/null
  if grep -q 'このコメントは除去される' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null; then
    echo "FAIL: ケース6b — 単一行コメントが HTML に残留" >&2
    rm -rf "$test6b_dir"
    record_self_test_case_failure
  fi
  if ! grep -q '本文前' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null || ! grep -q '本文後' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null; then
    echo "FAIL: ケース6b — コメント以外の本文が消失" >&2
    rm -rf "$test6b_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6b（単一行 HTML コメントの除去）"
  rm -rf "$test6b_dir"

  echo "--- ケース6c: 複数行 HTML コメントブロックの除去 ---"
  test6c_dir="$(create_physical_tmpdir)"
  test6c_repo="$test6c_dir/repo"
  test6c_docs="$test6c_dir/docs"
  test6c_portal="$test6c_dir/portal"
  mkdir -p "$test6c_repo" "$test6c_docs/プロジェクト共通" "$test6c_portal"
  cat > "$test6c_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 見出し\n\n<!--\nブロック内テキスト\n-->\n\n本文。' > "$test6c_docs/プロジェクト共通/comment-block-test.md"
  "$0" "$test6c_repo" "$test6c_docs" "$test6c_portal" 2>/dev/null
  if grep -q 'ブロック内テキスト' "$test6c_docs/プロジェクト共通/comment-block-test.html" 2>/dev/null; then
    echo "FAIL: ケース6c — 複数行コメントブロックが HTML に残留" >&2
    rm -rf "$test6c_dir"
    record_self_test_case_failure
  fi
  if ! grep -q '本文。' "$test6c_docs/プロジェクト共通/comment-block-test.html" 2>/dev/null; then
    echo "FAIL: ケース6c — コメント以外の本文が消失" >&2
    rm -rf "$test6c_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6c（複数行 HTML コメントブロックの除去）"
  rm -rf "$test6c_dir"

  echo "--- ケース6d: 行内コメントは除去しない ---"
  test6d_dir="$(create_physical_tmpdir)"
  test6d_repo="$test6d_dir/repo"
  test6d_docs="$test6d_dir/docs"
  test6d_portal="$test6d_dir/portal"
  mkdir -p "$test6d_repo" "$test6d_docs/プロジェクト共通" "$test6d_portal"
  cat > "$test6d_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 見出し\n\nテキスト <!-- コメント --> テキスト' > "$test6d_docs/プロジェクト共通/comment-inline-test.md"
  "$0" "$test6d_repo" "$test6d_docs" "$test6d_portal" 2>/dev/null
  test6d_json="$(sed -n 's|.*<script type="application/json" id="doc-md">\([^<]*\)</script>.*|\1|p' "$test6d_docs/プロジェクト共通/comment-inline-test.html")"
  if ! printf '%s' "$test6d_json" | jq -r . | grep -Fq 'テキスト <!-- コメント --> テキスト'; then
    echo "FAIL: ケース6d — 行内コメントを含む行が変化した" >&2
    rm -rf "$test6d_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6d（行内コメントは除去しない）"
  rm -rf "$test6d_dir"

  echo "--- ケース6e: コードブロック内の行頭コメント記法は保持される ---"
  test6e_dir="$(create_physical_tmpdir)"
  test6e_repo="$test6e_dir/repo"
  test6e_docs="$test6e_dir/docs"
  test6e_portal="$test6e_dir/portal"
  mkdir -p "$test6e_repo" "$test6e_docs/プロジェクト共通" "$test6e_portal"
  cat > "$test6e_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 見出し\n\n```\n<!-- 保持されるべき行 -->\n```\n\n本文。' > "$test6e_docs/プロジェクト共通/comment-fence-inside-test.md"
  "$0" "$test6e_repo" "$test6e_docs" "$test6e_portal" 2>/dev/null
  if ! grep -q '保持されるべき行' "$test6e_docs/プロジェクト共通/comment-fence-inside-test.html" 2>/dev/null; then
    echo "FAIL: ケース6e — コードブロック内のコメント記法行が消失" >&2
    rm -rf "$test6e_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6e（コードブロック内の行頭コメント記法は保持される）"
  rm -rf "$test6e_dir"

  echo "--- ケース6f: コードブロック外の行頭コメント記法は従来どおり除去される ---"
  test6f_dir="$(create_physical_tmpdir)"
  test6f_repo="$test6f_dir/repo"
  test6f_docs="$test6f_dir/docs"
  test6f_portal="$test6f_dir/portal"
  mkdir -p "$test6f_repo" "$test6f_docs/プロジェクト共通" "$test6f_portal"
  cat > "$test6f_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 見出し\n\n```\n擬似コード本体\n```\n\n<!-- 除去されるべき行 -->\n\n本文。' > "$test6f_docs/プロジェクト共通/comment-fence-outside-test.md"
  "$0" "$test6f_repo" "$test6f_docs" "$test6f_portal" 2>/dev/null
  if grep -q '除去されるべき行' "$test6f_docs/プロジェクト共通/comment-fence-outside-test.html" 2>/dev/null; then
    echo "FAIL: ケース6f — コードブロック外のコメント記法行が HTML に残留" >&2
    rm -rf "$test6f_dir"
    record_self_test_case_failure
  fi
  if ! grep -q '擬似コード本体' "$test6f_docs/プロジェクト共通/comment-fence-outside-test.html" 2>/dev/null; then
    echo "FAIL: ケース6f — コードブロック内の本文が消失" >&2
    rm -rf "$test6f_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース6f（コードブロック外の行頭コメント記法は従来どおり除去される）"
  rm -rf "$test6f_dir"

  echo "--- ケース7: 複数行 unit-manifest JSON からの件数抽出 ---"
  test7_dir="$(create_physical_tmpdir)"
  test7_repo="$test7_dir/repo"
  test7_docs="$test7_dir/docs"
  test7_portal="$test7_dir/portal"
  mkdir -p "$test7_repo" "$test7_docs/project-portal/一覧/API一覧" "$test7_portal"
  cat > "$test7_docs/project-portal/一覧/API一覧/API一覧.html" <<'TEST7HTML'
<!DOCTYPE html><html><head><title>API一覧</title></head><body>
<script type="application/json" id="unit-manifest">
{
  "detectionSummary": {
    "unitCount": 5,
    "analyzedFiles": 10
  },
  "units": [{},{},{},{},{}]
}
</script>
</body></html>
TEST7HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test7_docs/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test7_repo" "$test7_docs" "$test7_portal" 2>/dev/null
  if tr -d ' \n' < "$test7_portal/index.html" | grep -q '"kind":"api".*"count":5'; then
    echo "PASS: --self-test ケース7（複数行 unit-manifest JSON からの件数抽出, count=5）"
  else
    echo "FAIL: --self-test ケース7（複数行 unit-manifest JSON からの件数抽出）" >&2
    rm -rf "$test7_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test7_dir"

  echo "--- ケース8: screen-manifest + screenCount からの件数抽出 ---"
  test8_dir="$(create_physical_tmpdir)"
  test8_repo="$test8_dir/repo"
  test8_docs="$test8_dir/docs"
  test8_portal="$test8_dir/portal"
  mkdir -p "$test8_repo" "$test8_docs/project-portal/一覧/画面一覧" "$test8_portal"
  cat > "$test8_docs/project-portal/一覧/画面一覧/画面一覧.html" <<'TEST8HTML'
<!DOCTYPE html><html><head><title>画面一覧</title></head><body>
<script type="application/json" id="screen-manifest">
{
  "detectionSummary": {
    "screenCount": 12,
    "analyzedFiles": 20
  },
  "screens": [{},{},{},{},{},{},{},{},{},{},{},{}]
}
</script>
</body></html>
TEST8HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test8_docs/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test8_repo" "$test8_docs" "$test8_portal" 2>/dev/null
  if tr -d ' \n' < "$test8_portal/index.html" | grep -q '"kind":"screen".*"count":12'; then
    echo "PASS: --self-test ケース8（screen-manifest + screenCount からの件数抽出, count=12）"
  else
    echo "FAIL: --self-test ケース8（screen-manifest + screenCount からの件数抽出）" >&2
    rm -rf "$test8_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test8_dir"

  echo "--- ケース9: マトリクス・対応表・AI設定資産カード（実在時のみ出現、全不在時は空状態表示） ---"
  test9_dir="$(create_physical_tmpdir)"
  test9_repo="$test9_dir/repo"
  test9_docs="$test9_dir/docs"
  test9_portal="$test9_dir/portal"
  mkdir -p "$test9_repo" "$test9_docs/project-portal/対応表/権限画面マトリクス" "$test9_docs/AI設定資産" "$test9_portal"
  echo '<html><body>perm screen matrix</body></html>' > "$test9_docs/project-portal/対応表/権限画面マトリクス/権限画面マトリクス.html"
  echo '<html><body>ai assets</body></html>' > "$test9_docs/AI設定資産/AI設定資産.html"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9_docs" "$test9_portal" 2>/dev/null
  # 全不在ケース: 全カテゴリを空状態付きで保持し、サイドバーのアンカー先を本文生成契約へ接続する
  test9b_docs="$test9_dir/docs-empty"
  test9b_portal="$test9_dir/portal-empty"
  mkdir -p "$test9b_docs" "$test9b_portal"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9b_docs" "$test9b_portal" 2>/dev/null
  if node - "$test9_portal/index.html" "$test9b_portal/index.html" "$DEFAULT_CATALOG" <<'NODE'
const fs = require('fs');
const assert = require('assert/strict');
const vm = require('vm');
const mixedSource = fs.readFileSync(process.argv[2], 'utf8');
const emptySource = fs.readFileSync(process.argv[3], 'utf8');
const catalog = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
function embeddedJson(source, id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing embedded JSON: ${id}`);
  return JSON.parse(match[1]);
}
class TestNode {
  constructor(tagName, text = '') {
    this.tagName = tagName.toUpperCase();
    this.attributes = {};
    this.childNodes = [];
    this.parentNode = null;
    this._text = text;
    this._listeners = {};
    this.classList = {
      add: (...names) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        this.className = [...classes].join(' ');
      },
      contains: (name) => this.className.split(/\s+/).includes(name),
      toggle: (name, force) => {
        const present = this.classList.contains(name);
        const enabled = force === undefined ? !present : Boolean(force);
        if (enabled && !present) this.classList.add(name);
        if (!enabled && present) {
          this.className = this.className.split(/\s+/).filter((item) => item && item !== name).join(' ');
        }
        return enabled;
      },
    };
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') nodesById.set(String(value), this);
  }
  getAttribute(name) { return this.attributes[name] || null; }
  set className(value) { this.attributes.class = String(value); }
  get className() { return this.attributes.class || ''; }
  set id(value) { this.setAttribute('id', value); }
  get id() { return this.getAttribute('id') || ''; }
  set href(value) { this.setAttribute('href', value); }
  get href() { return this.getAttribute('href') || ''; }
  set textContent(value) {
    this._text = String(value);
    this.childNodes = [];
  }
  get textContent() {
    return this._text + this.childNodes.map((child) => child.textContent).join('');
  }
  set innerHTML(value) { this._innerHTML = String(value); }
  get innerHTML() { return this._innerHTML || ''; }
  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) this.childNodes.splice(index, 1);
    child.parentNode = null;
    return child;
  }
  addEventListener(type, listener) { this._listeners[type] = listener; }
  querySelectorAll(selector) { return descendants(this).filter((node) => matches(node, selector)); }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function descendants(node) {
  return node.childNodes.flatMap((child) => [child, ...descendants(child)]);
}
function matches(node, selector) {
  const parts = selector.split('.');
  const tag = !selector.startsWith('.') ? parts.shift().toUpperCase() : '';
  return (!tag || node.tagName === tag) && parts.filter(Boolean).every((name) => node.classList.contains(name));
}
let nodesById = new Map();
function element(tag, attrs = {}, text = '') {
  const node = new TestNode(tag, text);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
}
function verifyFixture(source, expectedAllEmpty) {
nodesById = new Map();
const categories = embeddedJson(source, 'portal-categories');
const sidebar = embeddedJson(source, 'pt-nav-data');
assert(categories.length > 0, 'fixture must retain catalog categories');
if (expectedAllEmpty) {
  // disabledWhenEmpty: true の種別は実発見が0件でも無効プレースホルダーカードを残す。
  // 「発見が無い」ことの検証は「実カードが無い（無効プレースホルダー以外のtoolが無い）」で行う。
  assert(categories.every((category) => category.tools.every((tool) => tool.disabled === true)),
    'all-zero fixture must have zero real discoveries (disabled placeholders are allowed)');
} else {
  assert(categories.some((category) => category.tools.length > 0), 'mixed fixture must contain discovered tools');
  assert(categories.some((category) => category.tools.length === 0), 'mixed fixture must contain empty categories');
}
assert(categories.every((category) => category.tools.length > 0
  || (category.empty
    && category.empty.title === '生成済み資料はありません'
    && category.empty.desc === `${category.title}の資料はまだ生成されていません。`
    && category.empty.count === '0 件')),
  'every empty category requires canonical display content');
const sidebarKeys = sidebar.map((item) => item.key);
const categoryIds = categories.map((category) => category.id);
assert.equal(new Set(sidebarKeys).size, sidebarKeys.length, 'sidebar category keys must be unique');
assert.equal(new Set(categoryIds).size, categoryIds.length, 'rendered category ids must be unique');
assert.deepEqual(sidebarKeys, categoryIds, 'sidebar keys and rendered category ids must match in order');
const toolCountById = new Map(categories.map((category) => [category.id, category.tools.length]));
assert(sidebar.every((item) => item.count === toolCountById.get(item.key)),
  'sidebar counts must match discovered card counts (写真指摘 1-98: 旧基準はblueprint数固定で不具合そのものを検証していた)');
const catsMountMatch = source.match(/<div\b(?=[^>]*\bid=["']pm-cats["'])(?=[^>]*\bclass=["'][^"']*\bpm-cats\b[^"']*["'])[^>]*>([\s\S]*?)<\/div>/);
assert(catsMountMatch, 'generated HTML must contain the pm-cats container');
function attributesFromStartTag(startTag) {
  return Object.fromEntries(
    [...startTag.matchAll(/\s([:\w-]+)\s*=\s*(["'])(.*?)\2/g)]
      .map((match) => [match[1], match[3]])
  );
}
function categorySections(html) {
  return [...html.matchAll(/(<section\b[^>]*>)/g)]
    .map((match) => attributesFromStartTag(match[1]))
    .filter((attributes) => /^cat-[a-z0-9-]+$/.test(attributes.id || ''));
}
const containerSections = categorySections(catsMountMatch[1]);
const bodySections = categorySections(source);
const containerIdList = containerSections.map((attributes) => attributes.id);
const bodyIdList = bodySections.map((attributes) => attributes.id);
assert.equal(containerSections.length, categories.length, 'pm-cats must contain exactly one section per category');
assert(containerSections.every((attributes) => (attributes.class || '').split(/\s+/).includes('pm-cat')), 'generated category sections must retain the pm-cat class');
assert.equal(new Set(containerIdList).size, containerIdList.length, 'pm-cats category section ids must not be duplicated');
assert.equal(bodySections.length, containerSections.length, 'all category sections in generated HTML must belong to pm-cats');
assert.equal(new Set(bodyIdList).size, bodyIdList.length, 'category section ids in generated HTML must not be duplicated');
assert(sidebar.length === categories.length, 'sidebar and body must retain the same category count');
assert(sidebar.every((item) => containerIdList.includes(`cat-${item.key}`)), 'every sidebar category must have a pm-cats category id');

const documentElement = element('html');
const metricsMount = element('div', { id: 'metrics-mount' });
const catsMount = element('div', { id: 'pm-cats' });
const searchInput = element('input', { id: 'pm-search-input' });
const nav = element('nav', { id: 'pt-nav' });
const sideMatch = source.match(/<aside\b(?=[^>]*\bclass=["'][^"']*\bpt-sidebar\b[^"']*["'])[^>]*>/);
assert(sideMatch, 'generated HTML must contain the portal sidebar');
const side = element('aside', attributesFromStartTag(sideMatch[0]));
const portalHref = side.getAttribute('data-portal-href');
assert(portalHref, 'generated portal sidebar must declare data-portal-href');
containerSections.forEach((attributes) => catsMount.appendChild(element('section', attributes)));
for (const id of ['portal-metrics', 'portal-categories', 'pt-nav-data', 'pt-sites-data']) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing script data: ${id}`);
  element('script', { id }, match[1]);
}
const document = {
  documentElement,
  readyState: 'complete',
  activeElement: null,
  getElementById(id) { return nodesById.get(id) || null; },
  createElement(tag) { return element(tag); },
  createTextNode(text) { return new TestNode('#text', String(text)); },
  querySelector(selector) { return selector === '.pt-sidebar' ? side : null; },
  querySelectorAll() { return []; },
  addEventListener() {},
};
const scripts = [...source.matchAll(/<script(?![^>]*type=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
const sidebarScript = scripts.find((script) => script.includes('var portalHref =') && script.includes('cats.forEach'));
const portalScript = scripts.find((script) => script.includes("var categories = JSON.parse") && script.includes('categories.forEach'));
assert(sidebarScript, 'generated sidebar runtime script must exist');
assert(portalScript, 'generated portal runtime script must exist');
const context = {
  document,
  window: { matchMedia() { return { matches: false }; } },
  localStorage: { getItem() { return null; }, setItem() {} },
};
vm.runInNewContext(sidebarScript, context);
vm.runInNewContext(portalScript, context);

const sections = catsMount.querySelectorAll('section.pm-cat');
assert.equal(sections.length, categories.length, 'runtime DOM must retain exactly one section per category');
assert.equal(new Set(sections.map((section) => section.id)).size, sections.length, 'runtime DOM category section ids must not be duplicated');
categories.forEach((category) => {
  const section = sections.find((candidate) => candidate.id === `cat-${category.id}`);
  assert(section, `missing runtime category section: ${category.id}`);
  const emptyCards = section.querySelectorAll('.card.is-empty');
  const toolCards = section.querySelectorAll('.card.is-tool');
  assert.equal(toolCards.length, category.tools.length, `runtime tool card count mismatch: ${category.id}`);
  assert.equal(emptyCards.length, category.tools.length === 0 ? 1 : 0, `runtime empty-state card count mismatch: ${category.id}`);
  if (category.tools.length > 0) return;
  const card = emptyCards[0];
  assert.equal(card.tagName, 'DIV', `empty-state card must be a non-link div: ${category.id}`);
  assert.equal(card.getAttribute('href'), null, `empty-state card must not have an href: ${category.id}`);
  assert.equal(card.getAttribute('role'), 'status', `empty-state card must expose role=status: ${category.id}`);
  assert.equal(card.querySelector('.card-title')?.textContent, category.empty.title, `empty title mismatch: ${category.id}`);
  assert.equal(card.querySelector('.card-desc')?.textContent, category.empty.desc, `empty description mismatch: ${category.id}`);
  assert.equal(card.querySelector('.card-count')?.textContent, category.empty.count, `empty count mismatch: ${category.id}`);
});
const navCategoryLinks = nav.querySelectorAll('a.pt-nav-item').filter((link) => (link.getAttribute('href') || '').includes('#cat-'));
assert.equal(navCategoryLinks.length, sidebar.length, 'runtime sidebar must render one anchor per category');
const navCategoryHrefs = navCategoryLinks.map((link) => link.getAttribute('href') || '');
assert.equal(new Set(navCategoryHrefs).size, navCategoryHrefs.length, 'runtime sidebar category hrefs must be unique');
sidebar.forEach((item, index) => {
  const expectedHref = `${portalHref}#cat-${item.key}`;
  assert.equal(navCategoryHrefs[index], expectedHref, `runtime sidebar href mismatch: ${item.key}`);
  assert(sections.some((section) => section.id === `cat-${item.key}`), `runtime sidebar target section missing: ${item.key}`);
});
}
verifyFixture(mixedSource, false);
verifyFixture(emptySource, true);
NODE
  then
    echo "PASS: --self-test ケース9a（混在カテゴリの通常カードと空状態カード）"
    echo "PASS: --self-test ケース9b（全不在カテゴリの空状態とサイドバーアンカー先ID）"
  else
    echo "FAIL: --self-test ケース9a/9b（実生成DOMのカテゴリカード契約）" >&2
    rm -rf "$test9_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test9_dir"

  echo "--- ケース10: catalog外の旧レイアウトを暗黙発見しない ---"
  test10_dir="$(create_physical_tmpdir)"
  test10_repo="$test10_dir/repo"
  test10_docs="$test10_dir/docs"
  test10_portal="$test10_dir/portal"
  mkdir -p "$test10_repo" "$test10_docs/API一覧" "$test10_portal"
  cat > "$test10_docs/API一覧/API一覧.html" <<'TEST10HTML'
<!DOCTYPE html><html><head><title>API一覧</title></head><body>
<script type="application/json" id="unit-manifest">
{"detectionSummary":{"unitCount":7,"analyzedFiles":10},"units":[{},{},{},{},{},{},{}]}
</script>
</body></html>
TEST10HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test10_docs/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test10_repo" "$test10_docs" "$test10_portal" 2>/dev/null
  # api は disabledWhenEmpty のため、0件でも無効プレースホルダーカード（title="API一覧"・
  # disabled:true・countは「該当なし」）が常に出る。誤発見の検査は「実発見の痕跡」の不在で行う:
  # 規模インベントリチップ（kind:"api"）・実件数表示（7 エンドポイント）・誤配置ファイルへの
  # href のいずれも出ないことを確認する。
  if ! grep -q '"kind":"api"' "$test10_portal/index.html" \
     && ! grep -q '7 エンドポイント' "$test10_portal/index.html" \
     && ! grep -q 'API一覧/API一覧\.html' "$test10_portal/index.html"; then
    echo "PASS: --self-test ケース10（catalog外artifact typeを暗黙発見しない）"
  else
    echo "FAIL: --self-test ケース10（catalog外artifact typeを発見した）" >&2
    rm -rf "$test10_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test10_dir"

  echo "--- ケース11: .pt-main の縦スクロール指定 ---"
  test11_dir="$(create_physical_tmpdir)"
  test11_repo="$test11_dir/repo"
  test11_docs="$test11_dir/docs"
  test11_portal="$test11_dir/portal"
  mkdir -p "$test11_repo" "$test11_docs" "$test11_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test11_docs/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test11_repo" "$test11_docs" "$test11_portal" 2>/dev/null
  if grep -A3 '\.pt-main {' "$test11_portal/index.html" | grep -q 'overflow-y: auto'; then
    echo "PASS: --self-test ケース11（.pt-main の縦スクロール指定, 共通シェル partials 由来）"
  else
    echo "FAIL: --self-test ケース11（.pt-main の縦スクロール指定）" >&2
    rm -rf "$test11_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test11_dir"

  echo "--- ケース12: テスト観点表は正本ディレクトリから派生一覧カードになる ---"
  test12_dir="$(create_physical_tmpdir)"
  test12_repo="$test12_dir/repo"
  test12_docs="$test12_dir/docs"
  test12_portal="$test12_dir/portal"
  mkdir -p "$test12_repo" "$test12_docs/project-portal/一覧/テスト観点表" "$test12_portal"
  cat > "$test12_docs/project-portal/一覧/テスト観点表/テスト観点表.html" <<'TEST12HTML'
<!DOCTYPE html><html><body><script type="application/json" id="unit-manifest">{"unitKind":"test_viewpoint","detectionSummary":{"unitCount":3,"unresolvedCount":0},"units":[]}</script></body></html>
TEST12HTML
  "$SCRIPT_DIR/build-portal.sh" "$test12_repo" "$test12_docs" "$test12_portal" 2>/dev/null
  if grep -q '"title":"テスト観点表"' "$test12_portal/index.html" \
     && grep -q '一覧/テスト観点表/テスト観点表.html' "$test12_portal/index.html"; then
    echo "PASS: --self-test ケース12（テスト観点表の正本パスを派生一覧カードへ反映）"
  else
    echo "FAIL: --self-test ケース12（テスト観点表の派生一覧カード）" >&2
    rm -rf "$test12_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test12_dir"

  echo "--- ケース13: --portal-only は index.html 以外を変更しない ---"
  test13_dir="$(create_physical_tmpdir)"
  test13_repo="$test13_dir/repo"
  test13_docs="$test13_dir/docs"
  mkdir -p "$test13_repo" "$test13_docs/プロジェクト共通" "$test13_docs/project-portal/一覧/用語辞書"
  printf '# 変換禁止\n\n本文。\n' > "$test13_docs/プロジェクト共通/source.md"
  printf '<html><body>glossary</body></html>\n' > "$test13_docs/project-portal/一覧/用語辞書/用語辞書.html"
  before13="$(find "$test13_docs" -type f ! -name index.html -print0 | sort -z | xargs -0 shasum -a 256)"
  "$SCRIPT_DIR/build-portal.sh" "$test13_repo" "$test13_docs" "$test13_docs" --portal-only --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  after13="$(find "$test13_docs" -type f ! -name index.html -print0 | sort -z | xargs -0 shasum -a 256)"
  if [ "$before13" != "$after13" ] || [ -f "$test13_docs/プロジェクト共通/source.html" ]; then
    echo "FAIL: --portal-only changed or generated a non-index artifact" >&2
    rm -rf "$test13_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --portal-only preserves every non-index artifact"
  rm -rf "$test13_dir"

  echo "--- ケース14: generatedAt と manifestContentHash の受け渡し（ラベルの文言に依存せず、値が埋め込まれていることを確認する） ---"
  test14_dir="$(create_physical_tmpdir)"
  test14_repo="$test14_dir/repo"
  test14_docs="$test14_dir/docs"
  mkdir -p "$test14_repo" "$test14_docs"
  test14_hash="$(printf 'a%.0s' {1..64})"
  printf '{"manifestContentHash":"%s","screens":[]}\n' "$test14_hash" > "$test14_dir/screen-manifest.ext.json"
  "$SCRIPT_DIR/build-portal.sh" "$test14_repo" "$test14_docs" "$test14_docs" \
    --portal-only --generated-at 2026-07-28T00:00:00Z \
    --screen-manifest "$test14_dir/screen-manifest.ext.json" 2>/dev/null
  if ! grep -qF '2026-07-28' "$test14_docs/index.html" \
     || ! grep -qF "$test14_hash" "$test14_docs/index.html"; then
    echo "FAIL: generatedAt or manifestContentHash was not embedded" >&2
    rm -rf "$test14_dir"
    record_self_test_case_failure
  fi
  echo "PASS: generatedAt and manifestContentHash are embedded deterministically"
  rm -rf "$test14_dir"

  echo "--- ケース15: 埋め込みJSONのscript終端文字列を無害化して復号できる ---"
  test15_dir="$(create_physical_tmpdir)"
  test15_repo="$test15_dir/repo"
  test15_docs="$test15_dir/docs"
  mkdir -p "$test15_repo" "$test15_docs/pages"
  printf '<h1>&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;</h1>\n' > "$test15_docs/pages/unsafe.html"
  cat > "$test15_dir/catalog.json" <<'TEST15CATALOG'
{"schemaVersion":1,"categories":[{"key":"unsafe","label":"Unsafe","group":"Test","icon":"warning","sub":"test","blueprints":[{"kind":"unsafe-page","label":"Unsafe page","icon":"warning","desc":"test","dir":"pages","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"unsafe-page","root":"output-dir","glob":"pages/*.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST15CATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test15_repo" "$test15_docs" "$test15_docs" \
    --portal-only --catalog "$test15_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if grep -Fq '</script><img' "$test15_docs/index.html"; then
    echo "FAIL: raw script terminator escaped from embedded JSON" >&2
    rm -rf "$test15_dir"
    record_self_test_case_failure
  fi
  if ! node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const title = JSON.parse(match[1])[0].tools[0].title;
    if (title !== "</script><img src=x onerror=alert(1)>") process.exit(1);
  ' "$test15_docs/index.html"; then
    echo "FAIL: script-safe JSON did not decode to the original title" >&2
    rm -rf "$test15_dir"
    record_self_test_case_failure
  fi
  echo "PASS: embedded JSON is script-safe and JSON.parse restores the original title"
  rm -rf "$test15_dir"

  echo "--- ケース17: 規約・設計いずれのパターンにも一致しない共通文書が『規約』カテゴリに混入しない ---"
  test17_dir="$(create_physical_tmpdir)"
  test17_repo="$test17_dir/repo"
  test17_docs="$test17_dir/docs"
  mkdir -p "$test17_repo" "$test17_docs/プロジェクト共通"
  cat > "$test17_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "プロジェクト共通" } }
JSON
  printf '# 作業記録\n\n本文。\n' > "$test17_docs/プロジェクト共通/作業記録.md"
  "$SCRIPT_DIR/build-portal.sh" "$test17_repo" "$test17_docs" "$test17_docs" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17_docs/index.html"; then
    echo "PASS: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリに入らない）"
  else
    echo "FAIL: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリへ混入した）" >&2
    rm -rf "$test17_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test17_dir"

  echo "--- ケース17b: standardsカテゴリが欠落した合成カタログでは、ケース17の検査ロジックがFAILを返す（検査自体の健全性確認・陰性フィクスチャ） ---"
  test17b_dir="$(create_physical_tmpdir)"
  test17b_repo="$test17b_dir/repo"
  test17b_docs="$test17b_dir/docs"
  mkdir -p "$test17b_repo" "$test17b_docs"
  cat > "$test17b_dir/catalog.json" <<'TEST17BCATALOG'
{"schemaVersion":1,"categories":[{"key":"project","label":"Project","group":"共通","icon":"folder","sub":"test","blueprints":[]}]}
TEST17BCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17b_repo" "$test17b_docs" "$test17b_docs" \
    --portal-only --catalog "$test17b_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17b_docs/index.html"; then
    echo "FAIL: --self-test ケース17b（standardsカテゴリの欠落を検査が見逃した）" >&2
    rm -rf "$test17b_dir"
    record_self_test_case_failure
  else
    echo "PASS: --self-test ケース17b（standardsカテゴリの欠落をケース17ロジックがFAILとして検知した）"
  fi
  rm -rf "$test17b_dir"

  echo "--- ケース17c: 想定外タイトルがstandardsカテゴリへ混入した合成カタログでは、ケース17の検査ロジックがFAILを返す（検査自体の健全性確認・陰性フィクスチャ） ---"
  test17c_dir="$(create_physical_tmpdir)"
  test17c_repo="$test17c_dir/repo"
  test17c_docs="$test17c_dir/docs"
  mkdir -p "$test17c_repo" "$test17c_docs/プロジェクト共通"
  printf '<h1>作業記録</h1>\n' > "$test17c_docs/プロジェクト共通/作業記録.html"
  cat > "$test17c_dir/catalog.json" <<'TEST17CCATALOG'
{"schemaVersion":1,"categories":[{"key":"standards","label":"規約","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"contaminated-standard","label":"Contaminated","icon":"rule","desc":"test","dir":"プロジェクト共通","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"contaminated-standard-page","root":"output-dir","glob":"プロジェクト共通/作業記録.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST17CCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17c_repo" "$test17c_docs" "$test17c_docs" \
    --portal-only --catalog "$test17c_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17c_docs/index.html"; then
    echo "FAIL: --self-test ケース17c（想定外タイトルの混入を検査が見逃した）" >&2
    rm -rf "$test17c_dir"
    record_self_test_case_failure
  else
    echo "PASS: --self-test ケース17c（想定外タイトルの混入をケース17ロジックがFAILとして検知した）"
  fi
  rm -rf "$test17c_dir"

  echo "--- ケース17d: 合成カタログ経由でも汚染が無ければケース17の検査ロジックはPASSする（正常系） ---"
  test17d_dir="$(create_physical_tmpdir)"
  test17d_repo="$test17d_dir/repo"
  test17d_docs="$test17d_dir/docs"
  mkdir -p "$test17d_repo" "$test17d_docs/プロジェクト共通"
  printf '<h1>コーディング規約</h1>\n' > "$test17d_docs/プロジェクト共通/作業記録.html"
  cat > "$test17d_dir/catalog.json" <<'TEST17DCATALOG'
{"schemaVersion":1,"categories":[{"key":"standards","label":"規約","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"clean-standard","label":"Clean","icon":"rule","desc":"test","dir":"プロジェクト共通","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"clean-standard-page","root":"output-dir","glob":"プロジェクト共通/作業記録.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST17DCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17d_repo" "$test17d_docs" "$test17d_docs" \
    --portal-only --catalog "$test17d_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17d_docs/index.html"; then
    echo "PASS: --self-test ケース17d（合成カタログ経由でも汚染が無ければ検査はPASSする）"
  else
    echo "FAIL: --self-test ケース17d（汚染が無いのに検査がFAILした）" >&2
    rm -rf "$test17d_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test17d_dir"

  echo "--- ケース18: docs/rules（規約定義）の正規配置をstandardsカテゴリへ反映する ---"
  test18_dir="$(create_physical_tmpdir)"
  test18_repo="$test18_dir/repo"
  test18_docs="$test18_dir/docs"
  test18_portal="$test18_dir/portal"
  mkdir -p "$test18_repo" "$test18_portal"
  bash "$SCRIPT_DIR/rules/scaffold-rule-definitions.sh" "$test18_dir" --apply >/dev/null 2>&1
  if [ ! -d "$test18_docs/rules" ]; then
    echo "FAIL: --self-test ケース18（scaffold-rule-definitions.shがdocs/rulesを生成しない）" >&2
    rm -rf "$test18_dir"
    record_self_test_case_failure
  fi
  "$SCRIPT_DIR/build-portal.sh" "$test18_repo" "$test18_dir" "$test18_portal" --generated-at 2026-07-29T00:00:00Z 2>/dev/null
  test18_expected_approved="$(jq '[.parents[].children[] | select(.toolDefined == true)] | length' "$SCRIPT_DIR/../../delivery-payload/references/rule-taxonomy.json")"
  test18_total_children="$(jq '[.parents[].children[]] | length' "$SCRIPT_DIR/../../delivery-payload/references/rule-taxonomy.json")"
  test18_expected_draft=$((test18_total_children - test18_expected_approved))
  if ! node - "$test18_docs" "$test18_portal/index.html" "$test18_expected_approved" "$test18_expected_draft" <<'NODE'
const fs = require("fs");
const path = require("path");
const [docsRoot, portalHtml, expectedApprovedArg, expectedDraftArg] = process.argv.slice(2);
const expectedApproved = Number(expectedApprovedArg);
const expectedDraft = Number(expectedDraftArg);
const source = fs.readFileSync(portalHtml, "utf8");
const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
if (!match) process.exit(1);
const categories = JSON.parse(match[1]);
const standards = categories.find((category) => category.id === "standards");
if (!standards || standards.tools.length !== expectedApproved + expectedDraft) process.exit(1);
if (standards.tools.some((tool) => !tool.href.startsWith("../docs/rules/"))) process.exit(1);
// status: draft の子カテゴリはタイトルへ「（下書き）」が付き、approvedの子カテゴリ（ツール定義）には付かない
const draftTools = standards.tools.filter((tool) => tool.title.includes("（下書き）"));
const approvedTools = standards.tools.filter((tool) => !tool.title.includes("（下書き）"));
if (draftTools.length !== expectedDraft) process.exit(1);
if (approvedTools.length !== expectedApproved) process.exit(1);
NODE
  then
    echo "FAIL: --self-test ケース18（docs/rules経由の規約（approved${test18_expected_approved}件・draft${test18_expected_draft}件）がstandardsカテゴリへ反映されない、またはdraft表示が不正）" >&2
    rm -rf "$test18_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース18（docs/rules経由の規約（approved${test18_expected_approved}件・draft${test18_expected_draft}件）・draft表示・standards件数一致）"
  rm -rf "$test18_dir"

  echo "--- ケース16: ポータル規約検査 ---"
  CONVENTIONS_TEST="$SCRIPT_DIR/tests/test-portal-conventions.sh"
  if [ -f "$CONVENTIONS_TEST" ]; then
    test16_dir="$(create_physical_tmpdir)"
    test16_repo="$test16_dir/repo"
    test16_docs="$test16_dir/docs"
    test16_portal="$test16_dir/portal"
    mkdir -p "$test16_repo" "$test16_docs" "$test16_portal"
    echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test16_docs/code-metrics.json"
    "$SCRIPT_DIR/build-portal.sh" "$test16_repo" "$test16_docs" "$test16_portal" 2>/dev/null
    if bash "$CONVENTIONS_TEST" "$test16_portal/index.html"; then
      echo "PASS: --self-test ケース16（ポータル規約検査）"
    else
      echo "FAIL: --self-test ケース16（ポータル規約検査）" >&2
      rm -rf "$test16_dir"
      record_self_test_case_failure
    fi
    rm -rf "$test16_dir"
  else
    echo "SKIP: --self-test ケース16（ポータル規約検査, test-portal-conventions.sh 不在）" >&2
  fi

  echo "--- ケース19: 画面詳細設計書の本文・付録順序 ---"
  # 集約（run-layer-machine-checks.sh）から呼ばれたときは、tests/ 配下の検査を
  # 引数なしで呼ぶケースを飛ばす。集約は同じ検査を独立した対象として直接呼ぶため、
  # ここで走らせると完全な二重実行になる（2026-08-19 実測: 引数なしで呼ぶ 8 本が
  # すべて集約の対象にも含まれていた）。この二重実行が自己テストを 779 秒まで
  # 延ばし、上限 120 秒を超えて「宣言済み長時間」として除外される原因だった。
  # 単体実行（集約を経由しない）では従来どおり全ケースを走らせる。
  skip_when_aggregated() {
    [ "${RUN_LAYER_MACHINE_CHECKS:-}" = "1" ]
  }

  SECTION_ORDER_TEST="$SCRIPT_DIR/tests/test-screen-doc-section-order.cjs"
  if [ ! -f "$SECTION_ORDER_TEST" ]; then
    echo "FAIL: --self-test ケース19（章順序検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$SECTION_ORDER_TEST"; then
    echo "PASS: --self-test ケース19（実テンプレート・正式生成経路のDOM章順序）"
  else
    echo "FAIL: --self-test ケース19（実テンプレート・正式生成経路のDOM章順序）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース20: サイドバーとメインコンテンツの見出し番号が全カテゴリで一致する（DOM比較） ---"
  test20_dir="$(create_physical_tmpdir)"
  test20_repo="$test20_dir/repo"
  test20_docs="$test20_dir/docs"
  mkdir -p "$test20_repo" "$test20_docs/docs"
  printf '<h1>Gamma Doc</h1>\n' > "$test20_docs/docs/gamma.html"
  printf '<h1>Beta Doc</h1>\n' > "$test20_docs/docs/beta.html"
  # alpha カテゴリの glob はどのファイルにも一致させず、空状態カテゴリを意図的に作る
  cat > "$test20_dir/catalog.json" <<'TEST20CATALOG'
{"schemaVersion":1,"categories":[
  {"key":"gamma","label":"Gamma","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"gamma-doc","label":"Gamma Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"gamma-doc-page","root":"output-dir","glob":"docs/gamma.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]},
  {"key":"alpha","label":"Alpha","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"alpha-doc","label":"Alpha Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"alpha-doc-page","root":"output-dir","glob":"docs/nomatch-alpha.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]},
  {"key":"beta","label":"Beta","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"beta-doc","label":"Beta Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"beta-doc-page","root":"output-dir","glob":"docs/beta.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}
]}
TEST20CATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test20_repo" "$test20_docs" "$test20_docs" \
    --portal-only --catalog "$test20_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node - "$test20_docs/index.html" <<'NODE'
const fs = require('fs');
const assert = require('assert/strict');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

function embeddedJson(id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing embedded JSON: ${id}`);
  return JSON.parse(match[1]);
}

let nodesById = new Map();
class TestNode {
  constructor(tagName, text = '') {
    this.tagName = tagName.toUpperCase();
    this.attributes = {};
    this.childNodes = [];
    this.parentNode = null;
    this._text = text;
    this._listeners = {};
    this.classList = {
      add: (...names) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        this.className = [...classes].join(' ');
      },
      contains: (name) => this.className.split(/\s+/).includes(name),
      toggle: (name, force) => {
        const present = this.classList.contains(name);
        const enabled = force === undefined ? !present : Boolean(force);
        if (enabled && !present) this.classList.add(name);
        if (!enabled && present) {
          this.className = this.className.split(/\s+/).filter((item) => item && item !== name).join(' ');
        }
        return enabled;
      },
    };
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') nodesById.set(String(value), this);
  }
  getAttribute(name) { return this.attributes[name] || null; }
  set className(value) { this.attributes.class = String(value); }
  get className() { return this.attributes.class || ''; }
  set id(value) { this.setAttribute('id', value); }
  get id() { return this.getAttribute('id') || ''; }
  set href(value) { this.setAttribute('href', value); }
  get href() { return this.getAttribute('href') || ''; }
  set textContent(value) {
    this._text = String(value);
    this.childNodes = [];
  }
  get textContent() {
    return this._text + this.childNodes.map((child) => child.textContent).join('');
  }
  set innerHTML(value) { this._innerHTML = String(value); }
  get innerHTML() { return this._innerHTML || ''; }
  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) this.childNodes.splice(index, 1);
    child.parentNode = null;
    return child;
  }
  addEventListener(type, listener) { this._listeners[type] = listener; }
  querySelectorAll(selector) { return descendants(this).filter((node) => matches(node, selector)); }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function descendants(node) {
  return node.childNodes.flatMap((child) => [child, ...descendants(child)]);
}
function matches(node, selector) {
  const parts = selector.split('.');
  const tag = !selector.startsWith('.') ? parts.shift().toUpperCase() : '';
  return (!tag || node.tagName === tag) && parts.filter(Boolean).every((name) => node.classList.contains(name));
}
function element(tag, attrs = {}, text = '') {
  const node = new TestNode(tag, text);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
}
function attributesFromStartTag(startTag) {
  return Object.fromEntries(
    [...startTag.matchAll(/\s([:\w-]+)\s*=\s*(["'])(.*?)\2/g)]
      .map((match) => [match[1], match[3]])
  );
}

const categories = embeddedJson('portal-categories');
const sidebar = embeddedJson('pt-nav-data');
assert(categories.length >= 3, 'fixture must retain every synthetic category (including the empty one)');
assert(categories.some((category) => category.tools.length === 0), 'fixture must include an empty category to exercise index continuity');

const metricsMount = element('div', { id: 'metrics-mount' });
const catsMount = element('div', { id: 'pm-cats' });
const searchInput = element('input', { id: 'pm-search-input' });
const nav = element('nav', { id: 'pt-nav' });
const sideMatch = source.match(/<aside\b(?=[^>]*\bclass=["'][^"']*\bpt-sidebar\b[^"']*["'])[^>]*>/);
assert(sideMatch, 'generated HTML must contain the portal sidebar');
const side = element('aside', attributesFromStartTag(sideMatch[0]));
for (const id of ['portal-metrics', 'portal-categories', 'pt-nav-data', 'pt-sites-data']) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing script data: ${id}`);
  element('script', { id }, match[1]);
}
const document = {
  documentElement: element('html'),
  readyState: 'complete',
  activeElement: null,
  getElementById(id) { return nodesById.get(id) || null; },
  createElement(tag) { return element(tag); },
  createTextNode(text) { return new TestNode('#text', String(text)); },
  querySelector(selector) { return selector === '.pt-sidebar' ? side : null; },
  querySelectorAll() { return []; },
  addEventListener() {},
};
const scripts = [...source.matchAll(/<script(?![^>]*type=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
const sidebarScript = scripts.find((script) => script.includes('var portalHref =') && script.includes('cats.forEach'));
const portalScript = scripts.find((script) => script.includes('var categories = JSON.parse') && script.includes('categories.forEach'));
assert(sidebarScript, 'generated sidebar runtime script must exist');
assert(portalScript, 'generated portal runtime script must exist');
const context = {
  document,
  window: { matchMedia() { return { matches: false }; } },
  localStorage: { getItem() { return null; }, setItem() {} },
};
vm.runInNewContext(sidebarScript, context);
vm.runInNewContext(portalScript, context);

const sections = catsMount.querySelectorAll('section.pm-cat');
assert.equal(sections.length, categories.length, 'runtime DOM must retain exactly one section per category');
const navItems = nav.querySelectorAll('a.pt-nav-item');
const navCategoryItems = navItems.filter((item) => (item.getAttribute('href') || '').includes('#cat-'));
assert.equal(navCategoryItems.length, sidebar.length, 'runtime sidebar must render one anchor per category');

categories.forEach((category) => {
  const section = sections.find((candidate) => candidate.id === `cat-${category.id}`);
  assert(section, `missing runtime category section: ${category.id}`);
  const mainNumEl = section.querySelector('.pm-cat-num');
  assert(mainNumEl, `missing main content heading number: ${category.id}`);
  const mainNum = mainNumEl.textContent;

  const navItem = navCategoryItems.find((item) => (item.getAttribute('href') || '').endsWith(`#cat-${category.id}`));
  assert(navItem, `missing sidebar nav item: ${category.id}`);
  const navNumEl = navItem.querySelector('.pt-nav-num');
  assert(navNumEl, `missing sidebar heading number: ${category.id}`);
  const sideNum = navNumEl.textContent;

  assert.equal(mainNum, sideNum, `heading number mismatch for category ${category.id}: main=${mainNum} sidebar=${sideNum}`);
});
NODE
  then
    echo "PASS: --self-test ケース20（サイドバーとメインコンテンツの見出し番号がDOM上で全カテゴリ一致）"
  else
    echo "FAIL: --self-test ケース20（サイドバーとメインコンテンツの見出し番号が不一致）" >&2
    rm -rf "$test20_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test20_dir"

  echo "--- ケース21: 画面詳細/基本設計書テンプレートのコンテンツカラム幅拡張・横スクロール発生率（DOM計測） ---"
  COLUMN_WIDTH_TEST="$SCRIPT_DIR/tests/test-screen-doc-column-width.cjs"
  if [ ! -f "$COLUMN_WIDTH_TEST" ]; then
    echo "FAIL: --self-test ケース21（コンテンツカラム幅検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$COLUMN_WIDTH_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース21（コンテンツカラム幅拡張・横スクロール発生率の検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース22: 画面詳細設計書テンプレートの参照用付録折りたたみ（生コード全文・API全量列挙、DOM計測） ---"
  APPENDIX_COLLAPSE_TEST="$SCRIPT_DIR/tests/test-screen-doc-appendix-collapse.cjs"
  if [ ! -f "$APPENDIX_COLLAPSE_TEST" ]; then
    echo "FAIL: --self-test ケース22（付録折りたたみ検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$APPENDIX_COLLAPSE_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース22（参照用付録折りたたみの検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース23: §16要確認事項一覧の行数自動判定によるpt-calloutコールアウト付与（DOM計測） ---"
  UNRESOLVED_CALLOUT_TEST="$SCRIPT_DIR/tests/test-screen-doc-unresolved-callout.cjs"
  if [ ! -f "$UNRESOLVED_CALLOUT_TEST" ]; then
    echo "FAIL: --self-test ケース23（要確認事項コールアウト検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$UNRESOLVED_CALLOUT_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース23（要確認事項コールアウトの検証に失敗）" >&2
    record_self_test_case_failure
  fi

  # 改善課題1-243: 本関数は内部でFAIL時に `return 1` するため、set -e下で
  # 素の呼び出しのままだと以降のケースへ到達しない。record_self_test_case_failure
  # で件数だけ記録し打ち切らない。
  run_related_material_links_self_test || record_self_test_case_failure

  echo "--- ケース24: nav件数とカード件数の一致（写真指摘1-98の検収方法。blueprint定義があるのに実体が無いカテゴリを含む合成カタログ） ---"
  test24_dir="$(create_physical_tmpdir)"
  test24_repo="$test24_dir/repo"
  test24_docs="$test24_dir/docs"
  mkdir -p "$test24_repo" "$test24_docs/a" "$test24_docs/b"
  printf '<h1>A One Doc</h1>\n' > "$test24_docs/a/one.html"
  printf '<h1>B One Doc</h1>\n' > "$test24_docs/b/one.html"
  # cat-a は blueprint 3件中1件のみ実体あり（a-two・a-three は定義のみで実ファイル無し）。
  # cat-b は blueprint 1件・実体1件で完全一致させ、両パターンを混在させる。
  cat > "$test24_dir/catalog.json" <<'TEST24CATALOG'
{"schemaVersion":1,"categories":[{"key":"cat-a","label":"CatA","group":"Test","icon":"folder","sub":"test","blueprints":[{"kind":"a-one","label":"A One","icon":"desc","desc":"test","dir":"a","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"a-one-page","root":"output-dir","glob":"a/one.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}},{"kind":"a-two","label":"A Two","icon":"desc","desc":"test","dir":"a","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"a-two-page","root":"output-dir","glob":"a/two.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}},{"kind":"a-three","label":"A Three","icon":"desc","desc":"test","dir":"a","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"a-three-page","root":"output-dir","glob":"a/three.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]},{"key":"cat-b","label":"CatB","group":"Test","icon":"folder","sub":"test","blueprints":[{"kind":"b-one","label":"B One","icon":"desc","desc":"test","dir":"b","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"b-one-page","root":"output-dir","glob":"b/one.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST24CATALOG
  # 陰性フィクスチャ健全性確認: cat-a は blueprint数(3)と実体数(1)が意図的に異なる。
  # 一致していたら本ケースの検査は不一致を検知できないため、まずフィクスチャ自体を検証する。
  test24_blueprint_count_a="$(jq -r '.categories[] | select(.key=="cat-a") | .blueprints | length' "$test24_dir/catalog.json")"
  if [ "$test24_blueprint_count_a" -eq 1 ]; then
    echo "FAIL: --self-test ケース24（フィクスチャ不備: cat-aのblueprint数と実体数が一致しており検査として機能しない）" >&2
    rm -rf "$test24_dir"
    record_self_test_case_failure
  fi
  "$SCRIPT_DIR/build-portal.sh" "$test24_repo" "$test24_docs" "$test24_docs" \
    --portal-only --catalog "$test24_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const html = fs.readFileSync(process.argv[1], "utf8");
    const navMatch = html.match(/<script type="application\/json" id="pt-nav-data">([\s\S]*?)<\/script>/);
    const catMatch = html.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!navMatch || !catMatch) process.exit(1);
    const nav = JSON.parse(navMatch[1]);
    const categories = JSON.parse(catMatch[1]);
    const cardCountById = new Map(categories.map((c) => [c.id, c.tools.length]));
    if (nav.length !== categories.length) process.exit(1);
    for (const item of nav) {
      if (item.count !== cardCountById.get(item.key)) {
        console.error(`mismatch: ${item.key} nav=${item.count} cards=${cardCountById.get(item.key)}`);
        process.exit(1);
      }
    }
  ' "$test24_docs/index.html"; then
    echo "PASS: --self-test ケース24（nav件数と実カード件数が全カテゴリで一致。blueprint数固定の不具合は再発していない）"
  else
    echo "FAIL: --self-test ケース24（nav件数と実カード件数が不一致）" >&2
    rm -rf "$test24_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test24_dir"

  echo "--- ケース25: 全ページのシェル表示値の単一性（写真指摘1-99の検収方法。カテゴリ別件数・総資料数・更新日が全ページで一致し、一部ページ再生成後もbuild-portal.sh再実行でPASSする） ---"
  test25_dir="$(create_physical_tmpdir)"
  test25_repo="$test25_dir/repo"
  test25_docs="$test25_dir/docs"
  mkdir -p "$test25_repo/src/routes" "$test25_docs/project-portal/一覧/API一覧"
  echo "export function usersRoute() {}" > "$test25_repo/src/routes/users.ts"

  test25_manifest="$test25_dir/manifest-api.json"
  jq -n --arg sourceDir "$test25_repo/src" --arg sourceFile "$test25_repo/src/routes/users.ts" '
    {
      generatedAt: "2026-07-28T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [{unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", unitNameGuess: "ユーザー一覧", sourceFile: $sourceFile, confidence: "high", fileCount: 1, detectionMethod: "manual"}]
    }' > "$test25_manifest"

  compare_shell_state_across_pages() {
    # 引数: HTMLファイルパス群。全ページで nav件数・総資料数・更新日(サイドバー/フッター)が
    # 一致すれば "MATCH"、1件でも不一致があれば "MISMATCH" を標準出力へ返す。
    node -e '
      const fs = require("fs");
      const files = process.argv.slice(1);
      const states = files.map((f) => {
        const html = fs.readFileSync(f, "utf8");
        const navMatch = html.match(/<script type="application\/json" id="pt-nav-data">([\s\S]*?)<\/script>/);
        const totalMatch = html.match(/設計台帳\s*·\s*全(\d+)資料/);
        const sidebarDateMatch = html.match(/id="pt-sidebar-date">([^<]*)</);
        const footerDateMatch = html.match(/id="pt-footer-date">([^<]*)</);
        if (!navMatch || !totalMatch || !sidebarDateMatch || !footerDateMatch) { process.exit(2); }
        return JSON.stringify({
          nav: JSON.parse(navMatch[1]).map((item) => [item.key, item.count]).sort(),
          total: totalMatch[1],
          sidebarDate: sidebarDateMatch[1],
          footerDate: footerDateMatch[1],
        });
      });
      process.stdout.write(new Set(states).size === 1 ? "MATCH" : "MISMATCH");
    ' "$@"
  }

  # 手順1: unit-listビルダー単独でAPI一覧ページを生成する（shell_counts_json未指定のため
  # blueprint数のまま焼かれる = discoveryを持たない5経路の実際の挙動を再現）
  "$SCRIPT_DIR/unit-list/build-unit-list.sh" "$test25_manifest" "$test25_docs/project-portal/一覧/API一覧/API一覧.html" \
    --unit-kind api --portal-dir "$test25_docs" --project-name test25 >/dev/null 2>&1

  # 手順2: build-portal.sh フル生成（discoveryを持つ唯一の経路。末尾でDOCS_ROOT配下の
  # 全HTMLをバックフィルし、単一の情報源に揃える）
  "$SCRIPT_DIR/build-portal.sh" "$test25_repo" "$test25_docs" "$test25_docs" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1

  # 改善課題1-243: 本ケースは複数の独立したガード（手順1〜4）を経て末尾で
  # 1行のPASSを出す構造を持つ。record_self_test_case_failureは打ち切らずに
  # 件数だけ記録するため、途中のガードが1つでも不合格になった場合、末尾の
  # 無条件PASSを抑止する必要がある（実測: 手順4のガードのみ不合格でも
  # FAILとPASSの両方が印字されていた）。ガード開始前の件数を記録し、
  # 末尾のPASSは「このケースの間に新たな不合格が記録されていない」場合
  # にのみ出す。
  test25_fail_snapshot="$SELF_TEST_CASE_FAIL_COUNT"
  test25_result1="$(compare_shell_state_across_pages "$test25_docs/index.html" "$test25_docs/project-portal/一覧/API一覧/API一覧.html")"
  if [ "$test25_result1" != "MATCH" ]; then
    echo "FAIL: --self-test ケース25（フル生成直後に全ページのシェル表示値が一致しない）" >&2
    rm -rf "$test25_dir"
    record_self_test_case_failure
  fi

  # 手順3（陰性フィクスチャ健全性確認）: build-portal.sh を経由せずAPI一覧ページのみを
  # 再生成する（更新日も変えて stale 状態を作る）。この単独再生成はバックフィルを経ないため、
  # 全ページの表示値は不一致に戻るはずである。不一致にならなければ検査に判別力が無い。
  test25_manifest2="$test25_dir/manifest-api2.json"
  jq '.generatedAt = "2026-07-29T00:00:00Z"' "$test25_manifest" > "$test25_manifest2"
  "$SCRIPT_DIR/unit-list/build-unit-list.sh" "$test25_manifest2" "$test25_docs/project-portal/一覧/API一覧/API一覧.html" \
    --unit-kind api --portal-dir "$test25_docs" --project-name test25 >/dev/null 2>&1
  test25_result2="$(compare_shell_state_across_pages "$test25_docs/index.html" "$test25_docs/project-portal/一覧/API一覧/API一覧.html")"
  if [ "$test25_result2" != "MISMATCH" ]; then
    echo "FAIL: --self-test ケース25（フィクスチャ不備: 一部ページ単独再生成後も不一致を検知できず検査として機能しない）" >&2
    rm -rf "$test25_dir"
    record_self_test_case_failure
  fi

  # 手順4: build-portal.sh を再実行する（一部ページのみ再生成した直後でもPASSすることの
  # 検収方法。バックフィルがDOCS_ROOT配下の全HTMLを再度単一の情報源へ揃え直す）
  "$SCRIPT_DIR/build-portal.sh" "$test25_repo" "$test25_docs" "$test25_docs" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1
  test25_result3="$(compare_shell_state_across_pages "$test25_docs/index.html" "$test25_docs/project-portal/一覧/API一覧/API一覧.html")"
  if [ "$test25_result3" != "MATCH" ]; then
    echo "FAIL: --self-test ケース25（一部ページ再生成後にbuild-portal.shを再実行しても全ページが一致しない）" >&2
    rm -rf "$test25_dir"
    record_self_test_case_failure
  fi
  if [ "$SELF_TEST_CASE_FAIL_COUNT" -eq "$test25_fail_snapshot" ]; then
    echo "PASS: --self-test ケース25（フル生成直後は全ページ一致・一部ページ単独再生成直後は不一致・build-portal.sh再実行で再び全ページ一致）"
  fi
  rm -rf "$test25_dir"

  echo "--- ケース26: クラスタ数0のとき関与件数の注記を出さない（写真指摘1-106の検収方法1） ---"
  test26_dir="$(create_physical_tmpdir)"
  mkdir -p "$test26_dir/src/screens"
  echo "export function A() { return null; }" > "$test26_dir/src/screens/A.tsx"
  echo "export function B() { return null; }" > "$test26_dir/src/screens/B.tsx"

  # 実際の写真指摘の再現データ: 2画面が互いにsharedWithで参照し合う(=画面同士は
  # 現に共有関係にある)のに、clusterId付与だけが実行されておらず全screenでnull。
  # validate-manifest.shはdetectionSummaryを screens 配列から再計算して照合するため、
  # ここではclusterCount=0・sharedScreenCount=2の組合せが「screens配列とは矛盾しない」
  # 状態として検証を通過する(=実際に起こりうるバグの形)。
  test26_manifest_zero="$test26_dir/manifest-cluster-zero.json"
  jq -n --arg sourceDir "$test26_dir/src" --arg entryA "$test26_dir/src/screens/A.tsx" --arg entryB "$test26_dir/src/screens/B.tsx" '
    {
      generatedAt: "2026-07-30T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 2, clusterCount: 0, sharedScreenCount: 2, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {screenKey: "screen-a", screenNameGuess: "画面A", kind: "route", route: "/a", entryFile: $entryA, detectionMethod: "route-static", confidence: "high", screenType: "list", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false, sharedWith: ["screen-b"]},
        {screenKey: "screen-b", screenNameGuess: "画面B", kind: "route", route: "/b", entryFile: $entryB, detectionMethod: "route-static", confidence: "high", screenType: "list", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false, sharedWith: ["screen-a"]}
      ]
    }' > "$test26_manifest_zero"

  test26_out_zero="$test26_dir/out-zero.html"
  "$SCRIPT_DIR/unit-list/build-screen-list.sh" "$test26_manifest_zero" "$test26_out_zero" >/dev/null 2>/dev/null || {
    echo "FAIL: --self-test ケース26（clusterCount=0フィクスチャの生成コマンド自体が失敗した）" >&2
    rm -rf "$test26_dir"
    record_self_test_case_failure
  }
  # タイル本体(class="tile"のdiv)だけを対象にする。テンプレート冒頭のマーカー説明コメントに
  # 「画面が関与」という語自体が含まれるため、文書全体への単純grepは常にヒットしてしまう。
  test26_tile_zero="$(grep -o '<div class="tile"><strong>[0-9]*</strong>共有クラスタ数[^<]*</div>' "$test26_out_zero" || true)"
  if [ -z "$test26_tile_zero" ]; then
    echo "FAIL: --self-test ケース26（共有クラスタ数タイル自体が出力に見つからない）" >&2
    rm -rf "$test26_dir"
    record_self_test_case_failure
  fi
  if printf '%s' "$test26_tile_zero" | grep -q '画面が関与'; then
    echo "FAIL: --self-test ケース26（clusterCount=0なのに関与件数の注記が出力されている: ${test26_tile_zero}）" >&2
    rm -rf "$test26_dir"
    record_self_test_case_failure
  fi

  # 矛盾のない正常系(clusterId付与済み・clusterCount>=1)では注記が出ることも確認する
  # (片側だけだと「常に注記を出さない」実装でも通ってしまうため)
  test26_manifest_nonzero="$test26_dir/manifest-cluster-nonzero.json"
  jq '.detectionSummary.clusterCount = 1 | .screens[0].clusterId = "cluster-1" | .screens[1].clusterId = "cluster-1"' \
    "$test26_manifest_zero" > "$test26_manifest_nonzero"
  test26_out_nonzero="$test26_dir/out-nonzero.html"
  "$SCRIPT_DIR/unit-list/build-screen-list.sh" "$test26_manifest_nonzero" "$test26_out_nonzero" >/dev/null 2>&1 || {
    echo "FAIL: --self-test ケース26（clusterCount>=1フィクスチャの生成コマンド自体が失敗した）" >&2
    rm -rf "$test26_dir"
    record_self_test_case_failure
  }
  test26_tile_nonzero="$(grep -o '<div class="tile"><strong>[0-9]*</strong>共有クラスタ数[^<]*</div>' "$test26_out_nonzero" || true)"
  if ! printf '%s' "$test26_tile_nonzero" | grep -q '2画面が関与'; then
    echo "FAIL: --self-test ケース26（clusterCountが1以上なのに関与件数の注記が出力されない: ${test26_tile_nonzero}）" >&2
    rm -rf "$test26_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース26（クラスタ数0では関与件数の注記を出力せず、1以上では出力する）"
  rm -rf "$test26_dir"

  echo "--- ケース27: 未計測タイルに計測手段の案内が出る（写真指摘1-106の検収方法2） ---"
  test27_dir="$(create_physical_tmpdir)"
  mkdir -p "$test27_dir/repo/misc" "$test27_dir/docs" "$test27_dir/portal"
  echo "const x = 1;" > "$test27_dir/repo/misc/util.ts"
  # code-metrics.json をあえて配置しない(=テスト規模が未計測の状態を再現)

  if ! bash "$0" "$test27_dir/repo" "$test27_dir/docs" "$test27_dir/portal" >/dev/null 2>/dev/null; then
    echo "FAIL: --self-test ケース27（code-metrics.json不在時に生成コマンド自体が失敗した）" >&2
    rm -rf "$test27_dir"
    record_self_test_case_failure
  fi
  test27_out="$test27_dir/portal/index.html"
  node -e '
    const fs = require("fs");
    const html = fs.readFileSync(process.argv[1], "utf8");
    const m = html.match(/<script type="application\/json" id="portal-metrics">([\s\S]*?)<\/script>/);
    if (!m) { console.error("portal-metrics script tag not found"); process.exit(1); }
    const metrics = JSON.parse(m[1]);
    if (metrics.tests !== null) {
      console.error("tests is not null (unmeasured state not reached): " + JSON.stringify(metrics.tests));
      process.exit(1);
    }
    if (!html.includes("未計測") || !html.includes("counting-code-lines")) {
      console.error("unmeasured guidance text not found");
      process.exit(1);
    }
  ' "$test27_out" || {
    echo "FAIL: --self-test ケース27（未計測タイルに計測手段の案内文言が出力されていない、または未計測状態に到達していない）" >&2
    rm -rf "$test27_dir"
    record_self_test_case_failure
  }
  echo "PASS: --self-test ケース27（未計測タイルにcounting-code-linesでの計測案内が出力される）"
  rm -rf "$test27_dir"

  echo "--- ケース28: 必須成分が全て0件の合成データではマトリクスページが生成されない（写真指摘1-101の検収方法1） ---"
  test28_dir="$(create_physical_tmpdir)"
  test28_matrix_script="$SCRIPT_DIR/matrix/build-matrix-pages.sh"
  test28_out="$test28_dir/CRUD図.html"
  jq -n '{generatedAt: "2026-01-01T00:00:00Z", dataSource: "test", tables: [], features: []}' \
    > "$test28_dir/crud-matrix-empty.json"
  if ! bash "$test28_matrix_script" crud "$test28_dir/crud-matrix-empty.json" "$test28_out" >/dev/null 2>"$test28_dir/stderr.log"; then
    echo "FAIL: --self-test ケース28（必須成分0件のcrudデータで生成コマンド自体が非0終了した。仕様はexit 0でのスキップ）" >&2
    rm -rf "$test28_dir"
    record_self_test_case_failure
  fi
  if [ -e "$test28_out" ]; then
    echo "FAIL: --self-test ケース28（tables/features両方0件なのにページファイルが生成された: ${test28_out}）" >&2
    rm -rf "$test28_dir"
    record_self_test_case_failure
  fi
  if ! grep -q 'SKIP' "$test28_dir/stderr.log"; then
    echo "FAIL: --self-test ケース28（スキップ理由がstderrに出力されていない）" >&2
    rm -rf "$test28_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース28（必須成分が全て0件のcrudデータではページが生成されない）"
  rm -rf "$test28_dir"

  echo "--- ケース29: 全成分ありの合成データでは現行同等にマトリクスページが生成される（写真指摘1-101の検収方法2。一部成分欠落時の空状態表示も検査） ---"
  test29_dir="$(create_physical_tmpdir)"
  test29_matrix_script="$SCRIPT_DIR/matrix/build-matrix-pages.sh"
  test29_full_out="$test29_dir/CRUD図-full.html"
  test29_partial_out="$test29_dir/CRUD図-partial.html"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z", dataSource: "test",
    tables: [{physicalName: "users", logicalName: "ユーザー"}],
    features: [{featureId: "user-manage", featureName: "ユーザー管理", cells: {users: "CRUD"}}]
  }' > "$test29_dir/crud-matrix-full.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z", dataSource: "test",
    tables: [], features: [{featureId: "user-manage", featureName: "ユーザー管理", cells: {}}]
  }' > "$test29_dir/crud-matrix-partial.json"
  if ! bash "$test29_matrix_script" crud "$test29_dir/crud-matrix-full.json" "$test29_full_out" >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース29（全成分ありのcrudデータで生成コマンド自体が失敗した）" >&2
    rm -rf "$test29_dir"
    record_self_test_case_failure
  fi
  if ! bash "$test29_matrix_script" crud "$test29_dir/crud-matrix-partial.json" "$test29_partial_out" >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース29（tables欠落のcrudデータで生成コマンド自体が失敗した）" >&2
    rm -rf "$test29_dir"
    record_self_test_case_failure
  fi
  node -e '
    const fs = require("fs");
    const fullHtml = fs.readFileSync(process.argv[1], "utf8");
    const partialHtml = fs.readFileSync(process.argv[2], "utf8");
    const m = fullHtml.match(/<script type="application\/json" id="matrix-manifest">([\s\S]*?)<\/script>/);
    if (!m) { console.error("matrix-manifest script tag not found in full-data page"); process.exit(1); }
    const manifest = JSON.parse(m[1]);
    if (!(manifest.tables.length > 0) || !(manifest.features.length > 0)) {
      console.error("full-data page does not retain non-empty tables/features rows");
      process.exit(1);
    }
    if (!partialHtml.includes("matrix-empty-callout")) {
      console.error("partial-data page does not contain empty-state callout markup");
      process.exit(1);
    }
    if (!partialHtml.includes("テーブル") || !partialHtml.includes("原因区分")) {
      console.error("partial-data page empty-state message does not name the missing component or the cause category");
      process.exit(1);
    }
  ' "$test29_full_out" "$test29_partial_out" || {
    echo "FAIL: --self-test ケース29（全成分ありページのデータ行維持、または一部成分欠落ページの空状態表示に不備がある）" >&2
    rm -rf "$test29_dir"
    record_self_test_case_failure
  }
  echo "PASS: --self-test ケース29（全成分ありでは現行同等のページが生成され、一部成分欠落時は空状態コールアウトが表示される）"
  rm -rf "$test29_dir"

  echo "--- ケース30: 画面遷移図を開いた直後のDOMに空でない規模サマリが存在する（写真指摘1-104の検収方法1、DOM計測） ---"
  TRANSITION_INITIAL_SUMMARY_TEST="$SCRIPT_DIR/tests/test-transition-diagram-initial-summary.cjs"
  if [ ! -f "$TRANSITION_INITIAL_SUMMARY_TEST" ]; then
    echo "FAIL: --self-test ケース30（画面遷移図初期表示検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$TRANSITION_INITIAL_SUMMARY_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース30（画面遷移図の初期DOMに空でない規模サマリが存在することの検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース31: ER図の巨大ハブ(200テーブル)カード内、最小フォントサイズが10px以上（写真指摘1-104の検収方法2、Canvas計測） ---"
  ER_HUB_FONT_SIZE_TEST="$SCRIPT_DIR/tests/test-er-diagram-hub-card-font-size.cjs"
  if [ ! -f "$ER_HUB_FONT_SIZE_TEST" ]; then
    echo "FAIL: --self-test ケース31（ER図巨大ハブ検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$ER_HUB_FONT_SIZE_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース31（ER図の巨大ハブカード内、最小フォントサイズ10px以上であることの検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース41: 用語辞書ページの意味投影とUI契約が実ブラウザ計測を含めて検証される（改善課題1-29 自己テスト配線） ---"
  SEMANTIC_GLOSSARY_PAGE_TEST="$SCRIPT_DIR/tests/test-semantic-glossary-page.cjs"
  if [ ! -f "$SEMANTIC_GLOSSARY_PAGE_TEST" ]; then
    echo "FAIL: --self-test ケース41（用語辞書ページ検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  # このケースは node_modules の playwright パッケージを直接 require する（他のDOM計測
  # ケースが使う find-cached-browser.cjs 経由のブラウザバイナリ探索とは別経路）。未導入の
  # 環境では require が失敗し、node側の未捕捉例外でスタックトレースに埋もれた案内しか
  # 出せず、後続ケース（42以降）ごと自己テスト全体が exit 1 で止まっていた。ここで先に
  # ensure_playwright_installed で導入有無を判定し、未導入なら self-test 自身が npm ci を
  # 1回だけ試みる。導入に成功すれば実際にケースを実行し、導入に失敗した場合（オフライン等）
  # だけスタックトレースを出さずに案内した上でSKIPし、後続ケースへ進める
  # （改善課題1-29 検収方法「当該ケースが実行されること」の充足）。
  ensure_playwright_installed
  if [ -n "$PLAYWRIGHT_NO_PACKAGE_JSON" ]; then
    # 指示書§2.2の是正: package.jsonが無い環境ではnpm ci自体を試みていないため、
    # 「試行にも失敗した」とは案内しない（実際に何も試していない）。
    echo "SKIP: --self-test ケース41（playwright パッケージが未導入で、リポジトリルートに package.json が無いため self-test 自身による \`npm ci\` の導入試行を行わずに実ブラウザ検証を省略した。有効化するには対象リポジトリへ package.json を配置したうえで \`npm ci\` を実行するか、既にセットアップ済みの兄弟ツリー・worktree の node_modules を cp -R でコピーすること）"
  elif [ -z "$PLAYWRIGHT_AVAILABLE" ]; then
    echo "SKIP: --self-test ケース41（playwright パッケージが未導入で、self-test自身による \`npm ci\` の導入試行にも失敗したため実ブラウザ検証を省略した。有効化するにはリポジトリルートで手動で \`npm ci\` を実行すること。npm レジストリへ到達できない環境では、既にセットアップ済みの兄弟ツリー・worktree の node_modules を cp -R でコピーしてもよい）"
  elif skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$SEMANTIC_GLOSSARY_PAGE_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース41（用語辞書ページの意味投影/検証/UI契約の検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース42: disabledWhenEmpty:trueの作成不可カードは遷移せず、活性カードと視覚差があり実際に遷移する（改善課題1-29 自己テスト配線） ---"
  DISABLED_CARD_INTERACTION_TEST="$SCRIPT_DIR/tests/test-portal-disabled-card-interaction.cjs"
  if [ ! -f "$DISABLED_CARD_INTERACTION_TEST" ]; then
    echo "FAIL: --self-test ケース42（作成不可カード検査スクリプトが見つからない）" >&2
    record_self_test_case_failure
  fi
  if skip_when_aggregated; then
    echo "SKIP: 集約から呼ばれたため飛ばす（集約が同じ検査を直接呼ぶ）"
  elif node "$DISABLED_CARD_INTERACTION_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース42（作成不可カードのクリック無反応/視覚差/活性カードの遷移検証に失敗）" >&2
    record_self_test_case_failure
  fi

  echo "--- ケース32: 画面遷移bridgeの再実行で、同一manifestContentHashなら既存edges/edgesStatusが引き継がれる（画面遷移図edges消失バグ修正の検収方法1） ---"
  BRIDGE_SCRIPT="$SCRIPT_DIR/detail-pages/build-detail-pages-from-screen-manifest.sh"
  test32_dir="$(create_physical_tmpdir)"
  mkdir -p "$test32_dir/out"
  jq -n '{screens:[{screenKey:"a",kind:"route",route:"/a",screenNameGuess:"画面A"},{screenKey:"b",kind:"route",route:"/b",screenNameGuess:"画面B"}]}' \
    > "$test32_dir/raw.json"
  test32_hash="$(jq -cjS . "$test32_dir/raw.json" | shasum -a 256 | awk '{print $1}')"
  jq --arg hash "$test32_hash" '.generatedAt = "2026-01-01T00:00:00Z" | .manifestContentHash = $hash' \
    "$test32_dir/raw.json" > "$test32_dir/ext.json"
  if ! bash "$BRIDGE_SCRIPT" "$test32_dir/ext.json" "$test32_dir/out" \
    --raw-manifest "$test32_dir/raw.json" --generated-at 2026-01-01T00:00:00Z \
    >/dev/null 2>"$test32_dir/run1.log"; then
    echo "FAIL: --self-test ケース32（1回目のbridge実行が失敗した）" >&2
    cat "$test32_dir/run1.log" >&2
    rm -rf "$test32_dir"
    record_self_test_case_failure
  fi
  # 遷移抽出スキルがedgesを書き込んだ状態を模擬する
  jq '.edges = [{from:"a",to:"b",trigger:"リンク遷移",sourceRef:"src/router.tsx:1",confidence:"高"}] | .edgesStatus = "抽出済み"' \
    "$test32_dir/out/画面遷移図-data.json" > "$test32_dir/out/画面遷移図-data.json.tmp" \
    && mv "$test32_dir/out/画面遷移図-data.json.tmp" "$test32_dir/out/画面遷移図-data.json"
  # 同一raw/extでbridgeを再実行(一括再生成を模擬)
  if ! bash "$BRIDGE_SCRIPT" "$test32_dir/ext.json" "$test32_dir/out" \
    --raw-manifest "$test32_dir/raw.json" --generated-at 2026-01-01T00:00:00Z \
    >/dev/null 2>"$test32_dir/run2.log"; then
    echo "FAIL: --self-test ケース32（2回目のbridge実行が失敗した）" >&2
    cat "$test32_dir/run2.log" >&2
    rm -rf "$test32_dir"
    record_self_test_case_failure
  fi
  if ! grep -q "既存の edges" "$test32_dir/run2.log"; then
    echo "FAIL: --self-test ケース32（edges引き継ぎのINFOログが出力されていない）" >&2
    cat "$test32_dir/run2.log" >&2
    rm -rf "$test32_dir"
    record_self_test_case_failure
  fi
  test32_edge_count="$(jq '.edges | length' "$test32_dir/out/画面遷移図-data.json")"
  test32_status="$(jq -r '.edgesStatus' "$test32_dir/out/画面遷移図-data.json")"
  if [ "$test32_edge_count" != "1" ] || [ "$test32_status" != "抽出済み" ]; then
    echo "FAIL: --self-test ケース32（同一manifestContentHashで既存edges/edgesStatusが引き継がれていない: edges=${test32_edge_count} edgesStatus=${test32_status}）" >&2
    rm -rf "$test32_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース32（同一manifestContentHashで既存のedges/edgesStatusが引き継がれる）"
  rm -rf "$test32_dir"

  echo "--- ケース33: 画面遷移bridgeの再実行で、manifestContentHashが変わると既存edgesは破棄されedgesStatusが未抽出に戻る（画面遷移図edges消失バグ修正の検収方法2） ---"
  test33_dir="$(create_physical_tmpdir)"
  mkdir -p "$test33_dir/out"
  jq -n '{screens:[{screenKey:"a",kind:"route",route:"/a",screenNameGuess:"画面A"},{screenKey:"b",kind:"route",route:"/b",screenNameGuess:"画面B"}]}' \
    > "$test33_dir/raw.json"
  test33_hash="$(jq -cjS . "$test33_dir/raw.json" | shasum -a 256 | awk '{print $1}')"
  jq --arg hash "$test33_hash" '.generatedAt = "2026-01-01T00:00:00Z" | .manifestContentHash = $hash' \
    "$test33_dir/raw.json" > "$test33_dir/ext.json"
  if ! bash "$BRIDGE_SCRIPT" "$test33_dir/ext.json" "$test33_dir/out" \
    --raw-manifest "$test33_dir/raw.json" --generated-at 2026-01-01T00:00:00Z \
    >/dev/null 2>"$test33_dir/run1.log"; then
    echo "FAIL: --self-test ケース33（1回目のbridge実行が失敗した）" >&2
    cat "$test33_dir/run1.log" >&2
    rm -rf "$test33_dir"
    record_self_test_case_failure
  fi
  jq '.edges = [{from:"a",to:"b",trigger:"リンク遷移",sourceRef:"src/router.tsx:1",confidence:"高"}] | .edgesStatus = "抽出済み"' \
    "$test33_dir/out/画面遷移図-data.json" > "$test33_dir/out/画面遷移図-data.json.tmp" \
    && mv "$test33_dir/out/画面遷移図-data.json.tmp" "$test33_dir/out/画面遷移図-data.json"
  # 画面を追加してrawを変化させ、manifestContentHash不一致を発生させる
  jq '.screens += [{screenKey:"c",kind:"route",route:"/c",screenNameGuess:"画面C"}]' "$test33_dir/raw.json" \
    > "$test33_dir/raw2.json"
  test33_hash2="$(jq -cjS . "$test33_dir/raw2.json" | shasum -a 256 | awk '{print $1}')"
  jq --arg hash "$test33_hash2" '.generatedAt = "2026-01-01T00:00:00Z" | .manifestContentHash = $hash' \
    "$test33_dir/raw2.json" > "$test33_dir/ext2.json"
  if ! bash "$BRIDGE_SCRIPT" "$test33_dir/ext2.json" "$test33_dir/out" \
    --raw-manifest "$test33_dir/raw2.json" --generated-at 2026-01-01T00:00:00Z \
    >/dev/null 2>"$test33_dir/run2.log"; then
    echo "FAIL: --self-test ケース33（manifest変化後のbridge実行が失敗した）" >&2
    cat "$test33_dir/run2.log" >&2
    rm -rf "$test33_dir"
    record_self_test_case_failure
  fi
  if ! grep -q "manifest が変化したため" "$test33_dir/run2.log"; then
    echo "FAIL: --self-test ケース33（manifest変化を示すINFOログが出力されていない）" >&2
    cat "$test33_dir/run2.log" >&2
    rm -rf "$test33_dir"
    record_self_test_case_failure
  fi
  test33_edge_count="$(jq '.edges | length' "$test33_dir/out/画面遷移図-data.json")"
  test33_status="$(jq -r '.edgesStatus' "$test33_dir/out/画面遷移図-data.json")"
  if [ "$test33_edge_count" != "0" ] || [ "$test33_status" != "未抽出" ]; then
    echo "FAIL: --self-test ケース33（manifestContentHash変化時にedgesが空・edgesStatusが未抽出になっていない: edges=${test33_edge_count} edgesStatus=${test33_status}）" >&2
    rm -rf "$test33_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース33（manifestContentHashが変化すると既存edgesは破棄されedgesStatusが未抽出に戻る）"
  rm -rf "$test33_dir"

  echo "--- ケース34: 表示コミットの source_ref 集計（画面詳細設計書 frontmatter からの表示。混在時は「画面ごとに異なる」の注記、同一値なら短縮表示、frontmatter 不在なら空、設計書ページ個別ではその画面自身の値を表示することの検収方法） ---"
  test34_dir="$(create_physical_tmpdir)"
  test34_repo="$test34_dir/repo"
  test34_docs="$test34_dir/docs"
  test34_portal="$test34_dir/portal"
  mkdir -p "$test34_repo" "$test34_portal" "$test34_docs/画面/screen-a/基本設計" \
    "$test34_docs/画面/screen-a/詳細設計" "$test34_docs/画面/screen-b/基本設計" \
    "$test34_docs/画面/screen-b/詳細設計" "$test34_docs/画面/archive/詳細設計"
  cat > "$test34_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面" } }
JSON

  cat > "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.md" <<'TEST34_A_MD'
---
source_repo: sample-repo
source_ref: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
source_encoding: UTF-8
source_line_ending: LF
---
# 画面A詳細設計書
本文
TEST34_A_MD

  cat > "$test34_docs/画面/screen-a/基本設計/画面基本設計書.md" <<'TEST34_A_BASIC_MD'
# 画面A基本設計書
本文
TEST34_A_BASIC_MD

  cat > "$test34_docs/画面/screen-b/詳細設計/画面詳細設計書.md" <<'TEST34_B_MD'
---
source_repo: sample-repo
source_ref: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
source_encoding: UTF-8
source_line_ending: LF
---
# 画面B詳細設計書
本文
TEST34_B_MD

  cat > "$test34_docs/画面/screen-b/基本設計/画面基本設計書.md" <<'TEST34_B_BASIC_MD'
# 画面B基本設計書
本文
TEST34_B_BASIC_MD

  cat > "$test34_docs/画面/archive/詳細設計/画面詳細設計書.md" <<'TEST34_DECOY_MD'
---
source_repo: sample-repo
source_ref: dddddddddddddddddddddddddddddddddddddddd
---
# 集約対象外decoy
TEST34_DECOY_MD

  # 改善課題1-243: 本ケースはパターン1〜4の複数の独立したガードを経て末尾で
  # 1行のPASSを出す構造を持つ。途中のガードが1つでも不合格になった場合、
  # 末尾の無条件PASSを抑止する必要がある（実測: パターン2/3の一部ガードのみ
  # 不合格でもFAILとPASSの両方が印字されていた）。ガード開始前の件数を
  # 記録し、末尾のPASSは新たな不合格が記録されていない場合にのみ出す。
  test34_fail_snapshot="$SELF_TEST_CASE_FAIL_COUNT"

  # パターン1: 2画面のsource_refが異なる → index.htmlに「画面ごとに異なる」の注記が出る
  "$SCRIPT_DIR/build-portal.sh" "$test34_repo" "$test34_docs" "$test34_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1
  if ! grep -q "画面ごとに異なる" "$test34_portal/index.html"; then
    echo "FAIL: --self-test ケース34（値が異なる2画面でindex.htmlに『画面ごとに異なる』の注記が出ない）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi

  # パターン3（混在状態のまま）: 設計書ページ個別ではその画面自身のsource_ref値を表示する
  if ! grep -q "コミット番号: aaaaaaa" "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.html"; then
    echo "FAIL: --self-test ケース34（混在時にscreen-aのページ自身がaaaaaaaを表示しない）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi
  if ! grep -q "コミット番号: bbbbbbb" "$test34_docs/画面/screen-b/詳細設計/画面詳細設計書.html"; then
    echo "FAIL: --self-test ケース34（混在時にscreen-bのページ自身がbbbbbbbを表示しない）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi
  if ! grep -q "コミット番号: aaaaaaa" "$test34_docs/画面/screen-a/基本設計/画面基本設計書.html" \
    || ! grep -q "コミット番号: bbbbbbb" "$test34_docs/画面/screen-b/基本設計/画面基本設計書.html"; then
    echo "FAIL: --self-test ケース34（異なるsource_ref時に画面A/Bの基本設計書が各画面の7桁commitを表示しない）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi

  # パターン2: 2画面のsource_refを同一値へ変更して再生成 → index.htmlにその値の先頭7文字が出る
  cat > "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.md" <<'TEST34_A_SAME_MD'
---
source_repo: sample-repo
source_ref: cccccccccccccccccccccccccccccccccccccccc
source_encoding: UTF-8
source_line_ending: LF
---
# 画面A詳細設計書
本文
source_ref: ffffffffffffffffffffffffffffffffffffffff
TEST34_A_SAME_MD
  cat > "$test34_docs/画面/screen-b/詳細設計/画面詳細設計書.md" <<'TEST34_B_SAME_MD'
---
source_repo: sample-repo
source_ref: cccccccccccccccccccccccccccccccccccccccc
source_encoding: UTF-8
source_line_ending: LF
---
# 画面B詳細設計書
本文
source_ref: ffffffffffffffffffffffffffffffffffffffff
TEST34_B_SAME_MD
  "$SCRIPT_DIR/build-portal.sh" "$test34_repo" "$test34_docs" "$test34_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1
  if ! grep -q "コミット番号: ccccccc" "$test34_portal/index.html" \
    || grep -q "画面ごとに異なる" "$test34_portal/index.html"; then
    echo "FAIL: --self-test ケース34（値が一致する2画面のccccccc表示にdirect-child decoyが混入）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi
  test34_page_footer="$(grep -o '<span id="pt-footer-commit">[^<]*</span>' "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.html")"
  if ! printf '%s' "$test34_page_footer" | grep -q 'コミット番号: ccccccc' \
    || printf '%s' "$test34_page_footer" | grep -q 'fffffff'; then
    echo "FAIL: --self-test ケース34（本文source_refが画面個別footerへ混入: ${test34_page_footer}）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi

  # パターン4: source_refを持たないmdだけにして再生成 → index.htmlのコミット表示が空になる
  cat > "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.md" <<'TEST34_A_NOREF_MD'
# 画面A詳細設計書
本文
TEST34_A_NOREF_MD
  cat > "$test34_docs/画面/screen-b/詳細設計/画面詳細設計書.md" <<'TEST34_B_NOREF_MD'
# 画面B詳細設計書
本文
TEST34_B_NOREF_MD
  "$SCRIPT_DIR/build-portal.sh" "$test34_repo" "$test34_docs" "$test34_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1
  test34_footer="$(grep -o '<span id="pt-footer-commit">[^<]*</span>' "$test34_portal/index.html")"
  if printf '%s' "$test34_footer" | grep -q "番号"; then
    echo "FAIL: --self-test ケース34（source_ref不在後もindex.htmlのコミット表示が空にならない: ${test34_footer}）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi
  test34_no_ref_page_footer="$(grep -o '<span id="pt-footer-commit">[^<]*</span>' "$test34_docs/画面/screen-a/詳細設計/画面詳細設計書.html")"
  if printf '%s' "$test34_no_ref_page_footer" | grep -q "番号"; then
    echo "FAIL: --self-test ケース34（source_ref不在画面が全体コミットへfallbackした: ${test34_no_ref_page_footer}）" >&2
    rm -rf "$test34_dir"
    record_self_test_case_failure
  fi

  if [ "$SELF_TEST_CASE_FAIL_COUNT" -eq "$test34_fail_snapshot" ]; then
    echo "PASS: --self-test ケース34（表示コミットの source_ref 集計: 混在で注記・同一で短縮表示・不在で空・ページ個別値）"
  fi
  rm -rf "$test34_dir"

  echo "--- ケース34b: screenUnitRoot の外部symlinkを拒否する ---"
  test34b_dir="$(create_physical_tmpdir)"
  test34b_repo="$test34b_dir/repo"
  test34b_docs="$test34b_dir/docs"
  test34b_portal="$test34b_dir/portal"
  test34b_external="$test34b_dir/external"
  mkdir -p "$test34b_repo" "$test34b_docs" "$test34b_portal" "$test34b_external/screen-a/詳細設計"
  cat > "$test34b_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面" } }
JSON
  ln -s "$test34b_external" "$test34b_docs/画面"
  if "$SCRIPT_DIR/build-portal.sh" "$test34b_repo" "$test34b_docs" "$test34b_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース34b（screenUnitRootが外部symlinkでもbuildが成功した）" >&2
    rm -rf "$test34b_dir"
    record_self_test_case_failure
  fi
  if find "$test34b_external" -type f -name '*.html' -print -quit | grep -q .; then
    echo "FAIL: --self-test ケース34b（screenUnitRoot外部symlink先にHTMLが生成された）" >&2
    rm -rf "$test34b_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース34b（screenUnitRootの外部symlinkを拒否し外部treeへHTMLを生成しない）"
  rm -rf "$test34b_dir"

  echo "--- ケース34c: screen child の外部symlinkを拒否する ---"
  test34c_dir="$(create_physical_tmpdir)"
  test34c_repo="$test34c_dir/repo"
  test34c_docs="$test34c_dir/docs"
  test34c_portal="$test34c_dir/portal"
  test34c_external="$test34c_dir/external"
  mkdir -p "$test34c_repo" "$test34c_docs/画面/screen-a" "$test34c_portal" "$test34c_external"
  cat > "$test34c_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面" } }
JSON
  ln -s "$test34c_external" "$test34c_docs/画面/screen-a/詳細設計"
  if "$SCRIPT_DIR/build-portal.sh" "$test34c_repo" "$test34c_docs" "$test34c_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース34c（screen childが外部symlinkでもbuildが成功した）" >&2
    rm -rf "$test34c_dir"
    record_self_test_case_failure
  fi
  if find "$test34c_external" -type f -name '*.html' -print -quit | grep -q .; then
    echo "FAIL: --self-test ケース34c（screen child外部symlink先にHTMLが生成された）" >&2
    rm -rf "$test34c_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース34c（screen childの外部symlinkを拒否し外部treeへHTMLを生成しない）"
  rm -rf "$test34c_dir"

  echo "--- ケース34d: 不正source_refを拒否する ---"
  test34d_dir="$(create_physical_tmpdir)"
  test34d_repo="$test34d_dir/repo"
  test34d_docs="$test34d_dir/docs"
  test34d_portal="$test34d_dir/portal"
  mkdir -p "$test34d_repo" "$test34d_docs/画面/screen-a/詳細設計" "$test34d_portal"
  cat > "$test34d_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面" } }
JSON
  cat > "$test34d_docs/画面/screen-a/詳細設計/画面詳細設計書.md" <<'TEST34_D_MD'
---
source_ref: <style>body{display:none}</style>
---
# 悪性source_ref
TEST34_D_MD
  if "$SCRIPT_DIR/build-portal.sh" "$test34d_repo" "$test34d_docs" "$test34d_portal" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース34d（不正source_refでbuildが成功した）" >&2
    rm -rf "$test34d_dir"
    record_self_test_case_failure
  fi
  if find "$test34d_docs" "$test34d_portal" -type f -name '*.html' -print -quit | grep -q .; then
    echo "FAIL: --self-test ケース34d（不正source_refでHTMLが生成された）" >&2
    rm -rf "$test34d_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース34d（不正source_refを拒否しHTMLを生成しない）"
  rm -rf "$test34d_dir"

  echo "--- ケース35: standardsカテゴリのdiscovery.globがdocs/rules/直下から解決される（規約置き場の一本化） ---"
  test35_dir="$(create_physical_tmpdir)"

  test35_count_mismatches() {
    local catalog_file="$1" total=0 mismatch=0 glob
    while IFS= read -r glob; do
      [ -z "$glob" ] && continue
      total=$((total + 1))
      case "$glob" in
        docs/rules/*) ;;
        *) mismatch=$((mismatch + 1)) ;;
      esac
    done < <(jq -r '.categories[] | select(.key=="standards") | .blueprints[].discovery.glob' "$catalog_file")
    printf '%s %s\n' "$total" "$mismatch"
  }

  read -r test35_total test35_mismatch <<< "$(test35_count_mismatches "$DEFAULT_CATALOG")"
  if [ "$test35_total" -ne 27 ]; then
    echo "FAIL: --self-test ケース35（standardsカテゴリのblueprintが27件でない: ${test35_total}件）" >&2
    rm -rf "$test35_dir"
    record_self_test_case_failure
  fi
  if [ "$test35_mismatch" -ne 0 ]; then
    echo "FAIL: --self-test ケース35（standardsカテゴリのdiscovery.globがdocs/rules/直下でないものを${test35_mismatch}/${test35_total}件検出）" >&2
    rm -rf "$test35_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース35a（standardsカテゴリのdiscovery.glob全${test35_total}件がdocs/rules/直下と一致）"

  test35_bad_catalog="$test35_dir/bad-catalog.json"
  jq '(.categories[] | select(.key=="standards") | .blueprints[0].discovery.glob) |= "誤った場所/コーディング規約.html"' "$DEFAULT_CATALOG" > "$test35_bad_catalog"
  read -r test35_bad_total test35_bad_mismatch <<< "$(test35_count_mismatches "$test35_bad_catalog")"
  if [ "$test35_bad_mismatch" -eq 0 ]; then
    echo "FAIL: --self-test ケース35b（意図的に不一致にしたglob 1件を検出できない）" >&2
    rm -rf "$test35_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース35b（意図的な不一致1件を正しく検出する: ${test35_bad_mismatch}/${test35_bad_total}件）"
  rm -rf "$test35_dir"

  # 改善課題1-243: 両関数とも内部でFAIL時に `return 1` する。素の呼び出しの
  # ままだと（set +e下では abort しないが）失敗が件数へ計上されず末尾の
  # 集計が不正確になるため、record_self_test_case_failure で計上する。
  run_project_name_self_test || record_self_test_case_failure
  run_prepared_detail_pages_self_test || record_self_test_case_failure

  # --- ケース37: 信頼境界の宣言がポータルTOP・画面詳細設計書・画面基本設計書へ
  # 機械挿入されること(1-171) ---
  test37_dir="$(create_physical_tmpdir "${TMPDIR:-/tmp}/build-portal-test37.XXXXXX")"
  test37_repo="$test37_dir/repo"
  mkdir -p "$test37_repo"

  test37_docs="$test37_dir/docs"
  mkdir -p "$test37_docs/画面/screen-trust-boundary/基本設計" "$test37_docs/画面/screen-trust-boundary/詳細設計"
  cat > "$test37_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "画面", "screenViewRoot": "画面" } }
JSON
  # 実サンプル（generation-engine/samples配下）と同じく1行目が空行・2行目がタイトルの形にする
  # （NR==1限定のawk実装だと検出できない回帰を防ぐフィクスチャ）
  printf '\n# 信頼境界検証画面 画面基本設計書\n本文' > "$test37_docs/画面/screen-trust-boundary/基本設計/画面基本設計書.md"
  printf '\n# 信頼境界検証画面 画面詳細設計書\n本文' > "$test37_docs/画面/screen-trust-boundary/詳細設計/画面詳細設計書.md"

  "$SCRIPT_DIR/build-portal.sh" "$test37_repo" "$test37_docs" "$test37_docs" --catalog "$DEFAULT_CATALOG" >/dev/null 2>&1

  test37_index="$test37_docs/index.html"
  test37_detail_html="$test37_docs/画面/screen-trust-boundary/詳細設計/画面詳細設計書.html"
  test37_base_html="$test37_docs/画面/screen-trust-boundary/基本設計/画面基本設計書.html"

  test37_ok=1
  grep -q '現行実装をそのまま記録' "$test37_index" 2>/dev/null || test37_ok=0
  grep -q '現行実装をそのまま記録' "$test37_detail_html" 2>/dev/null || test37_ok=0
  grep -q '現行実装をそのまま記録' "$test37_base_html" 2>/dev/null || test37_ok=0

  if [ "$test37_ok" = "1" ]; then
    echo "PASS: --self-test ケース37（信頼境界の宣言がポータルTOP・画面詳細設計書・画面基本設計書へ機械挿入される: 改善課題1-171）"
  else
    echo "FAIL: --self-test ケース37（信頼境界の宣言がポータルTOP・画面詳細設計書・画面基本設計書へ機械挿入される: 改善課題1-171）" >&2
    rm -rf "$test37_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test37_dir"

  echo "--- ケース38: disabledWhenEmptyの種別は0件でも無効カードとして残り、falseの種別は出ない ---"
  test38_dir="$(create_physical_tmpdir)"
  test38_repo="$test38_dir/repo"
  test38_docs="$test38_dir/docs"
  test38_portal="$test38_dir/portal"
  mkdir -p "$test38_repo" "$test38_docs" "$test38_portal"
  cat > "$test38_dir/catalog.json" <<'JSON'
{"schemaVersion":1,"categories":[{"key":"degrade-test","label":"縮退検査","group":"Test","icon":"folder","sub":"test","blueprints":[{"kind":"keep-visible","label":"維持カード","icon":"description","desc":"0件でも残る種別。","dir":"","generator":"test-generator","unit":"件","countFormat":"detail","disabledWhenEmpty":true,"discovery":{"artifactType":"keep-visible-page","root":"output-dir","glob":"keep-visible.html","matchKind":"file","titleSource":"blueprint-label","dirSource":"blueprint","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}},{"kind":"hide-when-empty","label":"消えるカード","icon":"description","desc":"0件なら出ない種別。","dir":"","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"hide-when-empty-page","root":"output-dir","glob":"hide-when-empty.html","matchKind":"file","titleSource":"blueprint-label","dirSource":"blueprint","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
JSON
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test38_docs/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test38_repo" "$test38_docs" "$test38_portal" --catalog "$test38_dir/catalog.json" 2>/dev/null
  if node - "$test38_portal/index.html" <<'NODE'
const fs = require('fs');
const assert = require('assert/strict');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');
function embeddedJson(id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing embedded JSON: ${id}`);
  return JSON.parse(match[1]);
}
const categories = embeddedJson('portal-categories');
const category = categories.find((c) => c.id === 'degrade-test');
assert(category, 'degrade-test category must be present');
assert.equal(category.tools.length, 1, 'only the disabledWhenEmpty=true blueprint keeps a card');
const tool = category.tools[0];
assert.equal(tool.title, '維持カード', 'the disabled placeholder card must retain the blueprint label');
assert.equal(tool.disabled, true, 'the placeholder tool object must be flagged disabled');
assert.equal(tool.count, '該当なし', 'the placeholder count text must read 該当なし');
assert(!category.tools.some((t) => t.title === '消えるカード'), 'the blueprint without disabledWhenEmpty must not render any card when empty');

// --- ランタイムDOM検査: 無効カードが data-disabled を持ち href を持たないことを確認する ---
class TestNode {
  constructor(tagName, text = '') {
    this.tagName = tagName.toUpperCase();
    this.attributes = {};
    this.childNodes = [];
    this._text = text;
    this.classList = {
      add: (...names) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        this.className = [...classes].join(' ');
      },
      contains: (name) => this.className.split(/\s+/).includes(name),
    };
  }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null; }
  set className(value) { this.attributes.class = String(value); }
  get className() { return this.attributes.class || ''; }
  set id(value) { this.setAttribute('id', value); }
  get id() { return this.getAttribute('id') || ''; }
  set textContent(value) { this._text = String(value); this.childNodes = []; }
  get textContent() { return this._text + this.childNodes.map((c) => c.textContent).join(''); }
  appendChild(child) { this.childNodes.push(child); return child; }
  addEventListener() {}
  querySelectorAll(selector) { return descendants(this).filter((node) => matchesSelector(node, selector)); }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function descendants(node) { return node.childNodes.flatMap((child) => [child, ...descendants(child)]); }
function matchesSelector(node, selector) {
  const parts = selector.split('.');
  const tag = !selector.startsWith('.') ? parts.shift().toUpperCase() : '';
  return (!tag || node.tagName === tag) && parts.filter(Boolean).every((name) => node.classList.contains(name));
}
const nodesById = new Map();
function element(tag, attrs = {}) {
  const node = new TestNode(tag);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
}
const metricsMount = element('div', { id: 'metrics-mount' });
const catsMount = element('div', { id: 'pm-cats' });
const searchInput = element('input', { id: 'pm-search-input' });
nodesById.set('metrics-mount', metricsMount);
nodesById.set('pm-cats', catsMount);
nodesById.set('pm-search-input', searchInput);
const metricsScriptText = source.match(/<script[^>]*id=["']portal-metrics["'][^>]*>([\s\S]*?)<\/script>/)[1];
const categoriesScriptText = source.match(/<script[^>]*id=["']portal-categories["'][^>]*>([\s\S]*?)<\/script>/)[1];
const metricsScriptNode = element('script', { id: 'portal-metrics' });
metricsScriptNode.textContent = metricsScriptText;
const categoriesScriptNode = element('script', { id: 'portal-categories' });
categoriesScriptNode.textContent = categoriesScriptText;
nodesById.set('portal-metrics', metricsScriptNode);
nodesById.set('portal-categories', categoriesScriptNode);
const document = {
  getElementById(id) { return nodesById.get(id) || null; },
  createElement(tag) { return element(tag); },
  createTextNode(text) { return new TestNode('#text', String(text)); },
  addEventListener() {},
};
const scripts = [...source.matchAll(/<script(?![^>]*type=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
const portalScript = scripts.find((s) => s.includes('var categories = JSON.parse') && s.includes('categories.forEach'));
assert(portalScript, 'portal top runtime script must exist');
const context = { document, window: { matchMedia() { return { matches: false }; } }, localStorage: { getItem() { return null; }, setItem() {} } };
vm.runInNewContext(portalScript, context);
const section = catsMount.querySelectorAll('section.pm-cat').find((s) => s.id === 'cat-degrade-test');
assert(section, 'runtime DOM must contain the degrade-test category section');
const disabledCards = section.querySelectorAll('.card.is-tool.is-disabled');
assert.equal(disabledCards.length, 1, 'exactly one disabled card must be rendered at runtime');
const disabledCard = disabledCards[0];
assert.equal(disabledCard.getAttribute('data-disabled'), 'true', 'the disabled card must declare data-disabled="true"');
assert.equal(disabledCard.getAttribute('href'), null, 'the disabled card must not declare an href');
assert.equal(disabledCard.getAttribute('aria-disabled'), 'true', 'the disabled card must declare aria-disabled="true"');
assert.equal(disabledCard.querySelector('.card-title')?.textContent, '維持カード', 'the disabled card must show the blueprint label');
assert.equal(disabledCard.querySelector('.card-count')?.textContent, '該当なし', 'the disabled card must show 該当なし as its count');
const allCards = section.querySelectorAll('.card.is-tool');
assert.equal(allCards.length, 1, 'no card must be rendered for the blueprint without disabledWhenEmpty when empty');
NODE
  then
    echo "PASS: --self-test ケース38（disabledWhenEmpty:trueの種別は0件でも無効カードとして残り、falseの種別は出ない）"
  else
    echo "FAIL: --self-test ケース38（disabledWhenEmpty:trueの種別は0件でも無効カードとして残り、falseの種別は出ない）" >&2
    rm -rf "$test38_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test38_dir"

  echo "--- ケース39: --pre-build と --post-build が実行され、環境変数が渡る ---"
  test39_dir="$(create_physical_tmpdir)"
  test39_repo="$test39_dir/repo"
  test39_docs="$test39_dir/docs"
  test39_portal="$test39_dir/portal"
  mkdir -p "$test39_repo" "$test39_docs" "$test39_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test39_docs/code-metrics.json"
  test39_pre_out="$test39_dir/pre.out"
  test39_post_out="$test39_dir/post.out"
  "$SCRIPT_DIR/build-portal.sh" "$test39_repo" "$test39_docs" "$test39_portal" \
    --generated-at 2026-07-28T00:00:00Z \
    --pre-build "printf '%s\n%s\n%s\n' \"\$REVERSE_DOCS_TARGET_REPO\" \"\$REVERSE_DOCS_DOCS_DIR\" \"\$REVERSE_DOCS_PORTAL_DIR\" > '$test39_pre_out'" \
    --post-build "printf '%s\n%s\n%s\n' \"\$REVERSE_DOCS_TARGET_REPO\" \"\$REVERSE_DOCS_DOCS_DIR\" \"\$REVERSE_DOCS_PORTAL_DIR\" > '$test39_post_out'" \
    2>/dev/null
  test39_pre_expected="$test39_repo"$'\n'"$test39_docs"$'\n'"$test39_portal"
  test39_post_expected="$test39_pre_expected"
  if [ ! -f "$test39_pre_out" ] || [ "$(cat "$test39_pre_out")" != "$test39_pre_expected" ]; then
    echo "FAIL: --self-test ケース39（--pre-build が実行されない、または環境変数が渡らない）" >&2
    rm -rf "$test39_dir"
    record_self_test_case_failure
  fi
  if [ ! -f "$test39_post_out" ] || [ "$(cat "$test39_post_out")" != "$test39_post_expected" ]; then
    echo "FAIL: --self-test ケース39（--post-build が実行されない、または環境変数が渡らない）" >&2
    rm -rf "$test39_dir"
    record_self_test_case_failure
  fi
  if [ ! -f "$test39_portal/index.html" ]; then
    echo "FAIL: --self-test ケース39（--pre-build/--post-build 指定時に index.html が生成されない）" >&2
    rm -rf "$test39_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース39（--pre-build と --post-build が実行され、REVERSE_DOCS_TARGET_REPO/REVERSE_DOCS_DOCS_DIR/REVERSE_DOCS_PORTAL_DIR が渡る）"
  rm -rf "$test39_dir"

  echo "--- ケース40: --pre-build/--post-build が失敗すると build-portal.sh が非0で終わる ---"
  test40_dir="$(create_physical_tmpdir)"
  test40_repo="$test40_dir/repo"
  test40_docs="$test40_dir/docs"
  test40_portal="$test40_dir/portal"
  mkdir -p "$test40_repo" "$test40_docs" "$test40_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test40_docs/code-metrics.json"
  test40_pre_status=0
  "$SCRIPT_DIR/build-portal.sh" "$test40_repo" "$test40_docs" "$test40_portal" \
    --generated-at 2026-07-28T00:00:00Z \
    --pre-build "exit 7" \
    2>/dev/null || test40_pre_status=$?
  if [ "$test40_pre_status" -ne 7 ] || [ -f "$test40_portal/index.html" ]; then
    echo "FAIL: --self-test ケース40（--pre-build 失敗時に非0で終わらない、または index.html が生成された）" >&2
    rm -rf "$test40_dir"
    record_self_test_case_failure
  fi
  rm -rf "$test40_portal"
  mkdir -p "$test40_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test40_docs/code-metrics.json"
  test40_post_status=0
  "$SCRIPT_DIR/build-portal.sh" "$test40_repo" "$test40_docs" "$test40_portal" \
    --generated-at 2026-07-28T00:00:00Z \
    --post-build "exit 9" \
    2>/dev/null || test40_post_status=$?
  if [ "$test40_post_status" -ne 9 ]; then
    echo "FAIL: --self-test ケース40（--post-build 失敗時に非0で終わらない）" >&2
    rm -rf "$test40_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース40（--pre-build/--post-build の失敗を握りつぶさず build-portal.sh が非0で終わる）"
  rm -rf "$test40_dir"

  echo "--- ケース43: --build-manifests-from-docs で設計文書からマニフェストを組み立て、一覧ページの生成まで到達する ---"
  test43_dir="$(create_physical_tmpdir)"
  test43_repo="$test43_dir/repo"
  test43_docs="$test43_dir/docs"
  test43_portal="$test43_dir/portal"
  mkdir -p "$test43_repo" "$test43_docs/docs/design/apis/api-get-users/詳細設計" "$test43_portal"
  cat > "$test43_docs/docs/design/apis/api-get-users/詳細設計/API詳細設計書.md" <<'EOF'
---
api_key: get-users
api_id: api-get-users
method: GET
path: /api/users
source_ref: src/api/users.py
unit_kind: api
---

# ユーザー一覧 API詳細設計書
EOF
  mkdir -p "$test43_docs/docs/design/tables/table-users/詳細設計"
  cat > "$test43_docs/docs/design/tables/table-users/詳細設計/テーブル定義書.md" <<'EOF'
---
table_key: users
table_id: table-users
table_name: ユーザー
source_ref: src/models/users.py
unit_kind: table
---

# ユーザー テーブル定義書

### 6.3 外部キー

| カラム | 参照先のテーブル | 参照先のカラム | 削除時の動作 | 関連の種別 | 出典参照 |
|---|---|---|---|---|---|
EOF
  mkdir -p "$test43_docs/docs/design/tables/table-orders/詳細設計"
  cat > "$test43_docs/docs/design/tables/table-orders/詳細設計/テーブル定義書.md" <<'EOF'
---
table_key: orders
table_id: table-orders
table_name: 注文
source_ref: src/models/orders.py
unit_kind: table
---

# 注文 テーブル定義書

### 6.3 外部キー

| カラム | 参照先のテーブル | 参照先のカラム | 削除時の動作 | 関連の種別 | 出典参照 |
|---|---|---|---|---|---|
| `user_id` | `users` | `id` | `CASCADE` | `一対多` | `src/models/orders.py#L12` |
EOF
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test43_portal/code-metrics.json"
  # 改善課題1-66により、method・pathが揃ったAPI文書のkindは"endpoint"へ解決されるため、
  # validate-manifest.shのsourceFile-実在検査(kind!=unresolvedの行のみ検査)がsource_ref
  # (src/api/users.py)の実在を要求するようになった。この検査はmanifest_dir(.git祖先が
  # 見つからないためのフォールバック)を起点にsourceDir+source_refを解決するため、
  # 該当パスへダミーの実体を用意する(既存のvalidate-manifest.shの解決仕様に合わせるだけで、
  # build-portal.sh本体・1-66の挙動は変えない)。
  mkdir -p "$test43_docs/docs/manifests/docs/design/apis/src/api"
  : > "$test43_docs/docs/manifests/docs/design/apis/src/api/users.py"
  mkdir -p "$test43_docs/docs/manifests/docs/design/tables/src/models"
  : > "$test43_docs/docs/manifests/docs/design/tables/src/models/users.py"
  : > "$test43_docs/docs/manifests/docs/design/tables/src/models/orders.py"
  # 改善課題1-243: 本ケースは複数の独立したガードを経て末尾で1行のPASSを
  # 出す構造を持つ。途中のガードが1つでも不合格になった場合、末尾の
  # 無条件PASSを抑止する必要がある（実測: ER図データのガードのみ不合格
  # でもFAILとPASSの両方が印字されていた）。ガード開始前の件数を記録し、
  # 末尾のPASSは新たな不合格が記録されていない場合にのみ出す。
  test43_fail_snapshot="$SELF_TEST_CASE_FAIL_COUNT"
  "$SCRIPT_DIR/build-portal.sh" "$test43_repo" "$test43_docs" "$test43_portal" \
    --generated-at 2026-07-28T00:00:00Z \
    --build-manifests-from-docs \
    2>/dev/null
  test43_manifest="$test43_docs/docs/manifests/api-manifest.json"
  if [ ! -f "$test43_manifest" ] || [ "$(jq -r '.units[0].unitKey' "$test43_manifest" 2>/dev/null)" != "get-users" ]; then
    echo "FAIL: --self-test ケース43（--build-manifests-from-docs でマニフェストが組み立てられない）" >&2
    rm -rf "$test43_dir"
    record_self_test_case_failure
  fi
  test43_list_html="$test43_dir/API一覧.html"
  if ! "$SCRIPT_DIR/unit-list/build-unit-list.sh" "$test43_manifest" "$test43_list_html" --unit-kind api >/dev/null 2>&1; then
    echo "FAIL: --self-test ケース43（抽出したマニフェストから一覧ページの生成に到達しない）" >&2
    rm -rf "$test43_dir"
    record_self_test_case_failure
  fi
  if [ ! -f "$test43_list_html" ]; then
    echo "FAIL: --self-test ケース43（一覧HTMLが生成されない）" >&2
    rm -rf "$test43_dir"
    record_self_test_case_failure
  fi
  test43_er_data="$test43_docs/.er-page-data.json"
  if [ ! -f "$test43_er_data" ] \
    || [ "$(jq -r '.entities | length' "$test43_er_data" 2>/dev/null)" != "2" ] \
    || [ "$(jq -r '.relations | length' "$test43_er_data" 2>/dev/null)" != "1" ] \
    || [ ! -f "$test43_portal/図/ER図.html" ]; then
    echo "FAIL: --self-test ケース43（生成連鎖からER図データ2実体・1関係とER図.htmlが生成されない）" >&2
    rm -rf "$test43_dir"
    record_self_test_case_failure
  fi
  if [ "$SELF_TEST_CASE_FAIL_COUNT" -eq "$test43_fail_snapshot" ]; then
    echo "PASS: --self-test ケース43（--build-manifests-from-docs で一覧ページとER図データ2実体・1関係、ER図.htmlの生成まで到達）"
  fi
  rm -rf "$test43_dir"

  echo "--- ケース46: --build-manifests-from-docs で拡張マニフェスト(<種別>-manifest.ext.json)も6種別すべて生成される（改善課題1-61） ---"
  test46_dir="$(create_physical_tmpdir)"
  test46_repo="$test46_dir/repo"
  test46_docs="$test46_dir/docs"
  test46_portal="$test46_dir/portal"
  mkdir -p "$test46_repo" "$test46_docs/docs/design/apis/api-get-users/詳細設計" "$test46_portal"
  cat > "$test46_docs/docs/design/apis/api-get-users/詳細設計/API詳細設計書.md" <<'EOF'
---
api_key: get-users
api_id: api-get-users
method: GET
path: /api/users
source_ref: src/api/users.py
unit_kind: api
---

# ユーザー一覧 API詳細設計書
EOF
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test46_portal/code-metrics.json"
  # 改善課題1-66の影響でsourceFile-実在検査が効くため、ケース43と同じ理由でダミーの実体を用意する。
  mkdir -p "$test46_docs/docs/manifests/docs/design/apis/src/api"
  : > "$test46_docs/docs/manifests/docs/design/apis/src/api/users.py"
  "$SCRIPT_DIR/build-portal.sh" "$test46_repo" "$test46_docs" "$test46_portal" \
    --generated-at 2026-07-28T00:00:00Z \
    --build-manifests-from-docs \
    2>/dev/null
  case46_pass=1
  for ext46_kind in api table batch report external feature; do
    if [ ! -f "$test46_docs/docs/manifests/${ext46_kind}-manifest.ext.json" ]; then
      echo "FAIL: --self-test ケース46（${ext46_kind}-manifest.ext.jsonが生成されない）" >&2
      case46_pass=0
    fi
  done
  if [ "$case46_pass" -ne 1 ]; then
    rm -rf "$test46_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース46（--build-manifests-from-docs で6種別すべての拡張マニフェストが生成される）"
  rm -rf "$test46_dir"

  echo "--- ケース44: テンプレート先頭の生成情報コメントが除去され、本文中の意味のあるコメントは残る（改善課題1-47） ---"
  case44_pass=1
  if grep -q "プレースホルダ" "$tmpdir2/portal/index.html" 2>/dev/null || grep -q "render_template()" "$tmpdir2/portal/index.html" 2>/dev/null; then
    echo "FAIL: --self-test ケース44a（生成したポータルトップに生成情報コメントが残っている）" >&2
    case44_pass=0
  else
    echo "PASS: --self-test ケース44a（生成したポータルトップから生成情報コメントが除去されている）" >&2
  fi

  case44_fixture='<!DOCTYPE html><html><head><title>{{T}}</title>
<!--
  テンプレート — 設計スキル群
  生成: generation-engine/scripts/dummy-build.sh
  プレースホルダ一覧:
    {{T}} — タイトル
-->
<style>body{}</style>
</head><body>
<!-- 条件分岐: unresolvedが0件のときはこのブロックを隠す -->
<div id="x">{{T}}</div>
</body></html>'
  case44_out="$(render_template "$case44_fixture" "{{T}}" "テスト")"
  if [ "$(printf '%s' "$case44_out" | grep -c "プレースホルダ一覧")" -eq 0 ] \
    && [ "$(printf '%s' "$case44_out" | grep -c "生成: generation-engine/scripts/dummy-build.sh")" -eq 0 ] \
    && printf '%s' "$case44_out" | grep -q "条件分岐: unresolvedが0件のときはこのブロックを隠す"; then
    echo "PASS: --self-test ケース44b（先頭の生成情報コメントを除去しつつ、本文中の意味のあるコメントは保持する）" >&2
  else
    echo "FAIL: --self-test ケース44b（生成情報コメントの除去、または本文コメントの保持に失敗）" >&2
    case44_pass=0
  fi

  if [ "$case44_pass" -ne 1 ]; then
    record_self_test_case_failure
  fi

  echo "--- ケース45: 本文が空の資料に未記入である旨の表示が出る（改善課題1-51） ---"
  case45_pass=1
  if ! node - "$SCRIPT_DIR/../../delivery-payload/templates/common-doc-template.html" "$SCRIPT_DIR/../../delivery-payload/templates/screen-doc-template.html" <<'NODE'
const fs = require('node:fs');
const vm = require('node:vm');

// 見出し以外の本文が無く、かつ表の行が無い資料をテンプレートへ流し込み、
// doc-empty-callout の表示切り替えを検査する（実DOMではなく最小限のスタブで動かす）。
function renderDoc(templatePath, markdown) {
  const raw = fs.readFileSync(templatePath, 'utf8');
  const withDoc = raw.replace('{{DOC_MARKDOWN_JSON}}', JSON.stringify(markdown));
  const match = withDoc.match(/<script type="application\/json" id="doc-md">([\s\S]*?)<\/script>\s*<script>([\s\S]*?)<\/script>/i);
  if (!match) throw new Error('doc-md or renderer script not found: ' + templatePath);
  const content = {
    _innerHTML: '',
    set innerHTML(value) { this._innerHTML = value; },
    get innerHTML() { return this._innerHTML; },
    querySelector() { return null; },
    querySelectorAll() { return []; },
  };
  const emptyCallout = { hidden: true };
  const elements = {
    'doc-md': { textContent: match[1] },
    'doc-content': content,
    'dp-hero-title': { textContent: '' },
    'toc-list': { appendChild() {}, querySelector() { return null; } },
    'screen-nav-title': { textContent: '' },
    'doc-empty-callout': emptyCallout,
  };
  const document = {
    getElementById(id) { return elements[id] || null; },
    createElement() { return { classList: { add() {} }, appendChild() {}, setAttribute() {} }; },
    querySelectorAll() { return []; },
  };
  vm.runInNewContext(match[2], { document, window: { addEventListener() {} }, requestAnimationFrame(cb) { cb(); } });
  return emptyCallout.hidden;
}

const emptyMd = '# 見出しのみ\n\n## 空の表1\n\n| 列A | 列B |\n|---|---|\n\n## 空の表2\n\n| 列C |\n|---|\n\n## 空の表3\n\n| 列D | 列E | 列F |\n|---|---|---|\n';
// 生成側が挿入する「本書の位置づけ」注記を含む、見出し以外の本文が無い資料。
// この注記を判定処理が本文と誤って数えると、未記入表示が出なくなる（改善課題1-51・4回目の指摘）。
const emptyMdWithNotice = '# 見出しのみ\n\n> **本書の位置づけ**: 本書は現行実装をそのまま記録したものであり、業務要件・非機能要件・設計意図・運用実態は対象外です。未確定の事項は「要確認事項一覧」を参照してください。\n\n## 空の表1\n\n| 列A | 列B |\n|---|---|\n\n## 空の表2\n\n| 列C |\n|---|\n\n## 空の表3\n\n| 列D | 列E | 列F |\n|---|---|---|\n';
const filledMd = '# 見出し\n\n本文がある。\n\n| 列A | 列B |\n|---|---|\n| 値1 | 値2 |\n';

let ok = true;
for (const tpl of [process.argv[2], process.argv[3]]) {
  const emptyHidden = renderDoc(tpl, emptyMd);
  const emptyWithNoticeHidden = renderDoc(tpl, emptyMdWithNotice);
  const filledHidden = renderDoc(tpl, filledMd);
  if (emptyHidden !== false) { console.error('FAIL: 見出しのみ・表0件の資料で未記入表示が出ない: ' + tpl); ok = false; }
  if (emptyWithNoticeHidden !== false) { console.error('FAIL: 「本書の位置づけ」注記を含む・表0件の資料で未記入表示が出ない: ' + tpl); ok = false; }
  if (filledHidden !== true) { console.error('FAIL: 本文のある資料で未記入表示が誤って出る: ' + tpl); ok = false; }
}
if (!ok) process.exit(1);
NODE
  then
    echo "FAIL: --self-test ケース45（見出しのみ・表がすべて0件の資料、または「本書の位置づけ」注記を含み表がすべて0件の資料に未記入表示が出ない、あるいは本文のある資料に誤って出る）" >&2
    case45_pass=0
  else
    echo "PASS: --self-test ケース45（見出しのみ・表がすべて0件の資料、および「本書の位置づけ」注記を含む同種の資料には未記入表示が出て、本文のある資料には出ない）"
  fi

  if [ "$case45_pass" -ne 1 ]; then
    record_self_test_case_failure
  fi

  echo "--- ケース47: output_dir に docs ディレクトリ自体を渡すと規約変換の静かなスキップを警告する ---"
  test47_dir="$(create_physical_tmpdir)"
  test47_repo="$test47_dir/repo"
  test47_root="$test47_dir/root"
  mkdir -p "$test47_repo" "$test47_root/docs/rules/親カテゴリ/子カテゴリ" "$test47_root/project-portal"
  cat > "$test47_root/docs/rules/親カテゴリ/子カテゴリ/rule.md" <<'RULE47'
---
title: テスト規約
status: approved
---
# テスト規約

本文。
RULE47
  test47_out="$(bash "$0" "$test47_repo" "$test47_root/docs" "$test47_root/project-portal" 2>&1)"
  if ! printf '%s' "$test47_out" | grep -q 'output_dir に docs ディレクトリ自体が渡されました'; then
    echo "FAIL: --self-test ケース47（誤った output_dir（docsディレクトリ自体）を渡しても警告が出ない）" >&2
    rm -rf "$test47_dir"
    record_self_test_case_failure
  fi
  if [ -f "$test47_root/docs/rules/親カテゴリ/子カテゴリ/rule.html" ]; then
    echo "FAIL: --self-test ケース47（誤った output_dir でも規約変換が実行されてしまった）" >&2
    rm -rf "$test47_dir"
    record_self_test_case_failure
  fi
  echo "PASS: --self-test ケース47（output_dir に docs ディレクトリ自体を渡すと警告が出て、規約変換は行われない）"
  rm -rf "$test47_dir"

  echo "--- ケース48: 画面設計書のテストケースリンクは新配置を優先し、旧配置へfallbackする ---"
  test48_dir="$(create_physical_tmpdir)"
  test48_repo="$test48_dir/repo"
  test48_root="$test48_dir/root"
  test48_portal="$test48_root/project-portal"
  test48_screen="$test48_root/docs/design/screens/screen-orders"
  test48_html="$test48_root/project-portal/画面/screen-orders/基本設計/画面基本設計書.html"
  mkdir -p "$test48_repo" "$test48_portal" "$test48_screen/基本設計" "$test48_screen/詳細設計" \
    "$test48_screen/テスト設計" "$test48_screen/テスト項目書"
  cat > "$test48_screen/基本設計/画面基本設計書.md" <<'TEST48BASE'
# 受注一覧 画面基本設計書
TEST48BASE
  cat > "$test48_screen/詳細設計/画面詳細設計書.md" <<'TEST48DETAIL'
# 受注一覧 画面詳細設計書
TEST48DETAIL
  : > "$test48_screen/テスト設計/画面テスト設計書.md"
  : > "$test48_screen/テスト項目書/単体テスト仕様書.md"
  # 改善課題1-243: 本ケースはパターンa/bの2つの独立したガードを経て末尾で
  # 1行のPASSを出す構造を持つ。片方のガードのみ不合格でもFAILとPASSの
  # 両方が印字されていた（実測）ため、ガード開始前の件数を記録し、末尾の
  # PASSは新たな不合格が記録されていない場合にのみ出す。
  test48_fail_snapshot="$SELF_TEST_CASE_FAIL_COUNT"
  if ! bash "$0" "$test48_repo" "$test48_root" "$test48_portal" >/dev/null 2>&1 \
    || ! grep -q '画面テスト設計書.md' "$test48_html" \
    || grep -q '単体テスト仕様書.md' "$test48_html"; then
    echo "FAIL: --self-test ケース48a（新配置の画面テスト設計書リンクが旧配置より優先されない）" >&2
    rm -rf "$test48_dir"
    record_self_test_case_failure
  fi
  rm -f "$test48_screen/テスト設計/画面テスト設計書.md"
  if ! bash "$0" "$test48_repo" "$test48_root" "$test48_portal" >/dev/null 2>&1 \
    || ! grep -q '単体テスト仕様書.md' "$test48_html"; then
    echo "FAIL: --self-test ケース48b（新配置不在時に旧配置のテストケースリンクへfallbackしない）" >&2
    rm -rf "$test48_dir"
    record_self_test_case_failure
  fi
  if [ "$SELF_TEST_CASE_FAIL_COUNT" -eq "$test48_fail_snapshot" ]; then
    echo "PASS: --self-test ケース48（画面設計書のテストケースリンクは新配置を優先し、旧配置へfallbackする）"
  fi
  rm -rf "$test48_dir"

  echo "--- ケース49: 定義に無い置き場（旧構成・未知のディレクトリ）を検出し、削除せず警告する ---"
  test49_dir="$(create_physical_tmpdir)"
  test49_repo="$test49_dir/repo"
  test49_docs="$test49_dir/docs"
  test49_portal="$test49_dir/portal"
  mkdir -p "$test49_repo" "$test49_docs/docs/design/common" "$test49_docs/docs/design/screens/screen-case49/基本設計"
  printf '# 共通設計書\n\n本文。\n' > "$test49_docs/docs/design/common/共通設計書.md"
  printf '# 画面基本設計書\n\n本文。\n' > "$test49_docs/docs/design/screens/screen-case49/基本設計/画面基本設計書.md"
  mkdir -p "$test49_portal/一覧/ダミー" "$test49_portal/作業中"
  printf 'stale' > "$test49_portal/一覧/ダミー/stale.html"
  printf 'work' > "$test49_portal/作業中/note.txt"
  test49_out="$(bash "$0" "$test49_repo" "$test49_docs" "$test49_portal" 2>&1)"
  test49_status=$?
  if [ "$test49_status" -ne 0 ]; then
    echo "FAIL: --self-test ケース49（生成自体が失敗した）" >&2
    echo "$test49_out" >&2
    rm -rf "$test49_dir"
    record_self_test_case_failure
  elif [ ! -d "$test49_portal/一覧" ] || [ ! -d "$test49_portal/作業中" ]; then
    echo "FAIL: --self-test ケース49（定義に無い置き場が削除されてしまった。警告のみが既定であるべき）" >&2
    rm -rf "$test49_dir"
    record_self_test_case_failure
  elif ! printf '%s' "$test49_out" | grep -qF "WARN: project-portal/一覧"; then
    echo "FAIL: --self-test ケース49（旧構成の置き場への警告が出力されていない）" >&2
    echo "$test49_out" >&2
    rm -rf "$test49_dir"
    record_self_test_case_failure
  elif ! printf '%s' "$test49_out" | grep -qF "WARN: project-portal/作業中"; then
    echo "FAIL: --self-test ケース49（未知のディレクトリへの警告が出力されていない）" >&2
    echo "$test49_out" >&2
    rm -rf "$test49_dir"
    record_self_test_case_failure
  else
    echo "PASS: --self-test ケース49（定義に無い置き場は削除されず、旧構成・未知のディレクトリの両方に警告が出る）"
  fi
  rm -rf "$test49_dir"

  echo "--- ケース50: 単位ディレクトリ配下の定義に無い階層（旧名・未知）を検出し、削除せず警告する ---"
  test50_dir="$(create_physical_tmpdir)"
  test50_repo="$test50_dir/repo"
  test50_docs="$test50_dir/docs"
  test50_portal="$test50_dir/portal"
  mkdir -p "$test50_repo" "$test50_docs/docs/design/common" "$test50_docs/docs/design/screens/screen-x/基本設計"
  printf '# 共通設計書\n\n本文。\n' > "$test50_docs/docs/design/common/共通設計書.md"
  printf '# 画面基本設計書\n\n本文。\n' > "$test50_docs/docs/design/screens/screen-x/基本設計/画面基本設計書.md"
  mkdir -p "$test50_docs/docs/design/tables/table-orders/基本設計" "$test50_docs/docs/design/tables/table-orders/未知階層"
  echo "content" > "$test50_docs/docs/design/tables/table-orders/基本設計/テーブル基本設計書.md"
  echo "content" > "$test50_docs/docs/design/tables/table-orders/未知階層/note.md"
  test50_out="$(bash "$0" "$test50_repo" "$test50_docs" "$test50_portal" 2>&1)"
  test50_status=$?
  if [ "$test50_status" -ne 0 ]; then
    echo "FAIL: --self-test ケース50（生成自体が失敗した）" >&2
    echo "$test50_out" >&2
    rm -rf "$test50_dir"
    record_self_test_case_failure
  elif [ ! -d "$test50_docs/docs/design/tables/table-orders/基本設計" ] || [ ! -d "$test50_docs/docs/design/tables/table-orders/未知階層" ]; then
    echo "FAIL: --self-test ケース50（単位配下の階層が削除されてしまった。警告のみが既定であるべき）" >&2
    rm -rf "$test50_dir"
    record_self_test_case_failure
  elif ! printf '%s' "$test50_out" | grep -qF "WARN: docs/design/tables/table-orders/基本設計"; then
    echo "FAIL: --self-test ケース50（unitPhaseDirNamesに対応しない階層への警告が出力されていない）" >&2
    echo "$test50_out" >&2
    rm -rf "$test50_dir"
    record_self_test_case_failure
  elif ! printf '%s' "$test50_out" | grep -qF "WARN: docs/design/tables/table-orders/未知階層"; then
    echo "FAIL: --self-test ケース50（未知の階層への警告が出力されていない）" >&2
    echo "$test50_out" >&2
    rm -rf "$test50_dir"
    record_self_test_case_failure
  else
    echo "PASS: --self-test ケース50（単位ディレクトリ配下の定義に無い階層は削除されず、警告が出る）"
  fi
  rm -rf "$test50_dir"

  # 改善課題1-243: 集約実行時のPASS:/FAIL:行カウント（run-layer-machine-checks.sh
  # のcount_cases()）と衝突しないよう、この集計行は「PASS:」「FAIL:」で
  # 始めない（SELF-TEST SUMMARY: を接頭辞にする）。1件でも不合格を記録して
  # いれば非0で終了し、走り切ったことと不合格の有無を両立して報告する。
  set -e
  echo "SELF-TEST SUMMARY: 不合格 ${SELF_TEST_CASE_FAIL_COUNT} 件（ケース1件不合格でも以降のケースを打ち切らず走り切る。改善課題1-243）"
  if [ "$SELF_TEST_CASE_FAIL_COUNT" -ne 0 ]; then
    exit 1
  fi
  exit 0
fi

# --- 引数チェック ---
if [ $# -lt 3 ]; then
  echo "Usage: $0 <target_repo_path> <output_dir> <portal_output_dir> [--catalog <file>] [--generated-at <ISO-8601>] [--portal-only] [--standalone] [--screen-manifest <file>] [--sites <file>] [--site-key <key>] [--project-name <name>] [--pre-build <command>] [--post-build <command>] [--build-manifests-from-docs]" >&2
  exit 1
fi

TARGET_REPO="$1"
DOCS_ROOT="$2"
PORTAL_DIR="$3"
shift 3

LAYOUT_JSON="$(resolve_output_layout "$DOCS_ROOT")" || exit 1
# 1-46(4回目): カタログエンジン（portal-catalog.mjs）はカテゴリ内訳の discovery.glob を
# 既定の置き場（defaultRoots）基準で解決するため、置き場を変えたoutput-layout.jsonでは
# カテゴリ件数が0件になる（受け取る側の --output-layout は実装済みだが、呼び出し側が
# 渡していなかった）。他の20箇所と同じ合成済みLAYOUT_JSONを、readOutputLayoutが要求する
# ファイル形式（{specVersion, layout, kindLabels}のJSONファイル）として一時ファイルへ書き出し、
# render呼び出しへ渡す。新しい正本ファイルは作らず、ビルド実行中だけの一時ファイルとして作る。
OUTPUT_LAYOUT_RESOLVED_FILE="$(mktemp "${TMPDIR:-/tmp}/portal-output-layout.XXXXXX")"
OUTPUT_LAYOUT_VALUES_FILE="${OUTPUT_LAYOUT_RESOLVED_FILE}.values"
trap 'rm -f "$OUTPUT_LAYOUT_RESOLVED_FILE" "$OUTPUT_LAYOUT_VALUES_FILE"' EXIT
printf '%s' "$LAYOUT_JSON" > "$OUTPUT_LAYOUT_RESOLVED_FILE"
# 生成のたびに同じJSONへ output_layout_get（存在確認jq + 値取得jq）を繰り返すと、
# self-testの再帰生成50回で短命プロセスが支配的になる。必要な14キーを1プロセスで
# 取り出す。NUL区切りなので、値に空白や改行があっても読み分けられる。
if ! node - "$OUTPUT_LAYOUT_RESOLVED_FILE" \
  commonRoot crossCuttingDesignRoot screenListDir screenUnitRoot rulesRoot foundationDir \
  screenViewRoot manifestsRoot apiUnitRoot tableUnitRoot batchUnitRoot reportUnitRoot \
  externalUnitRoot featureUnitRoot > "$OUTPUT_LAYOUT_VALUES_FILE" <<'NODE'
const fs = require("fs");
const doc = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const layout = doc.layout || {};
for (const key of process.argv.slice(3)) {
  if (!Object.prototype.hasOwnProperty.call(layout, key)) {
    process.stderr.write(`ERROR: output-layout のキーが存在しません: ${key}\n`);
    process.exit(2);
  }
  const value = layout[key];
  const rendered = typeof value === "string"
    ? value
    : value === null
      ? "null"
      : typeof value === "object"
        ? JSON.stringify(value)
        : String(value);
  process.stdout.write(`${rendered}\0`);
}
NODE
then
  exit 1
fi
layout_values=()
while IFS= read -r -d '' layout_value; do
  layout_values+=("$layout_value")
done < "$OUTPUT_LAYOUT_VALUES_FILE"
if [ "${#layout_values[@]}" -ne 14 ]; then
  echo "ERROR: output-layout の一括取得結果が不完全です" >&2
  exit 1
fi
LAYOUT_COMMON_ROOT="${layout_values[0]}"
LAYOUT_CROSS_CUTTING_ROOT="${layout_values[1]}"
LAYOUT_SCREEN_LIST_DIR="${layout_values[2]}"
LAYOUT_SCREEN_UNIT_ROOT="${layout_values[3]}"
LAYOUT_RULES_ROOT="${layout_values[4]}"
LAYOUT_FOUNDATION_DIR="${layout_values[5]}"
LAYOUT_SCREEN_VIEW_ROOT="${layout_values[6]}"
LAYOUT_MANIFESTS_ROOT="${layout_values[7]}"
# 1-36: 非画面6種別（API・テーブル・バッチ・帳票・外部連携・機能）の設計書単位文書を、
# 個別ページへの遷移リンク（一覧マニフェストのdesignDocPath）が指す実体として変換するため、
# 各UnitRootを共通文書ループ（common_roots）へ合流させる。screenUnitRootは既存の専用ループ
# （画面基本設計/詳細設計の別ルート出力・戻るリンク付き）が担うため対象外のまま維持する。
LAYOUT_API_UNIT_ROOT="${layout_values[8]}"
LAYOUT_TABLE_UNIT_ROOT="${layout_values[9]}"
LAYOUT_BATCH_UNIT_ROOT="${layout_values[10]}"
LAYOUT_REPORT_UNIT_ROOT="${layout_values[11]}"
LAYOUT_EXTERNAL_UNIT_ROOT="${layout_values[12]}"
LAYOUT_FEATURE_UNIT_ROOT="${layout_values[13]}"
check_docs_root_misconfiguration "$LAYOUT_JSON" "$DOCS_ROOT" || exit 1
assert_no_symlink_output_paths "$DOCS_ROOT" \
  "$DOCS_ROOT" \
  "$DOCS_ROOT/$LAYOUT_SCREEN_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_CROSS_CUTTING_ROOT" \
  "$DOCS_ROOT/$LAYOUT_API_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_TABLE_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_BATCH_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_REPORT_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_EXTERNAL_UNIT_ROOT" \
  "$DOCS_ROOT/$LAYOUT_FEATURE_UNIT_ROOT" || exit 1

CATALOG="$DEFAULT_CATALOG"
GENERATED_AT=""
PORTAL_ONLY=0
STANDALONE=0
SCREEN_MANIFEST=""
SITES_FILE=""
SITE_KEY=""
PROJECT_NAME_ARG=""
PRE_BUILD=""
POST_BUILD=""
BUILD_MANIFESTS_FROM_DOCS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --catalog)
      [ $# -ge 2 ] || { echo "ERROR: --catalog requires a value" >&2; exit 1; }
      CATALOG="$2"; shift 2 ;;
    --generated-at)
      [ $# -ge 2 ] || { echo "ERROR: --generated-at requires a value" >&2; exit 1; }
      GENERATED_AT="$2"; shift 2 ;;
    --portal-only)
      PORTAL_ONLY=1; shift ;;
    --standalone)
      STANDALONE=1; shift ;;
    --screen-manifest)
      [ $# -ge 2 ] || { echo "ERROR: --screen-manifest requires a value" >&2; exit 1; }
      SCREEN_MANIFEST="$2"; shift 2 ;;
    --sites)
      [ $# -ge 2 ] || { echo "ERROR: --sites requires a value" >&2; exit 1; }
      SITES_FILE="$2"; shift 2 ;;
    --site-key)
      [ $# -ge 2 ] || { echo "ERROR: --site-key requires a value" >&2; exit 1; }
      SITE_KEY="$2"; shift 2 ;;
    --project-name)
      [ $# -ge 2 ] || { echo "ERROR: --project-name requires a value" >&2; exit 1; }
      PROJECT_NAME_ARG="$2"; shift 2 ;;
    --pre-build)
      [ $# -ge 2 ] || { echo "ERROR: --pre-build requires a value" >&2; exit 1; }
      PRE_BUILD="$2"; shift 2 ;;
    --post-build)
      [ $# -ge 2 ] || { echo "ERROR: --post-build requires a value" >&2; exit 1; }
      POST_BUILD="$2"; shift 2 ;;
    --build-manifests-from-docs)
      BUILD_MANIFESTS_FROM_DOCS=1; shift ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

if [ "$PORTAL_ONLY" -eq 1 ] && [ "$STANDALONE" -eq 1 ]; then
  echo "ERROR: --standalone cannot be used with --portal-only" >&2
  exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
  echo "ERROR: target_repo_path does not exist: $TARGET_REPO" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi
if [ ! -f "$CATALOG" ]; then
  echo "ERROR: portal catalog not found: $CATALOG" >&2
  exit 1
fi
if [ ! -f "$CATALOG_ENGINE" ]; then
  echo "ERROR: portal catalog engine not found: $CATALOG_ENGINE" >&2
  exit 1
fi
if [ -n "$SCREEN_MANIFEST" ] && [ ! -f "$SCREEN_MANIFEST" ]; then
  echo "ERROR: screen manifest not found: $SCREEN_MANIFEST" >&2
  exit 1
fi

if [ -n "$PROJECT_NAME_ARG" ]; then
  PROJECT_NAME="$PROJECT_NAME_ARG"
else
  PROJECT_NAME="$(basename "$TARGET_REPO")"
  echo "WARN: --project-name was not specified; using target repo directory name: $PROJECT_NAME" >&2
fi
if [ -n "$GENERATED_AT" ]; then
  GENERATED_DATE="$(node -e 'const d=new Date(process.argv[1]);if(Number.isNaN(d.valueOf()))process.exit(1);process.stdout.write(d.toISOString().slice(0,10))' "$GENERATED_AT")" \
    || { echo "ERROR: --generated-at must be a valid ISO-8601 value" >&2; exit 1; }
else
  GENERATED_DATE="$(date +%Y-%m-%d)"
fi

# 表示コミット: 画面詳細設計書 frontmatter の source_ref を集計する（定義由来）。
# 生成時 HEAD の直接表示は廃止（表示値と設計書の根拠コミットの乖離を防ぐ。AI駆動開発セットアップ構想「コミット値-単一化」）。
SOURCE_REF_VALUES=""
for source_ref_file in "$DOCS_ROOT/$LAYOUT_SCREEN_UNIT_ROOT"/screen-*/詳細設計/画面詳細設計書.md; do
  [ -f "$source_ref_file" ] || continue
  source_ref_value="$(frontmatter_value "$source_ref_file" source_ref)"
  [ -n "$source_ref_value" ] || continue
  [ "$source_ref_value" != "SOURCECOMMIT" ] || continue
  if ! is_commit_sha "$source_ref_value"; then
    echo "ERROR: source_ref must be a short or full commit SHA: $source_ref_file" >&2
    exit 1
  fi
  SOURCE_REF_VALUES="${SOURCE_REF_VALUES}${source_ref_value}"$'\n'
done
SOURCE_REF_VALUES="$(printf '%s' "$SOURCE_REF_VALUES" | sort -u | sed '/^$/d')"
SOURCE_REF_COUNT=0
[ -n "$SOURCE_REF_VALUES" ] && SOURCE_REF_COUNT="$(printf '%s\n' "$SOURCE_REF_VALUES" | wc -l | tr -d ' ')"
if [ "$SOURCE_REF_COUNT" -eq 1 ]; then
  COMMIT_SHORT=" · コミット番号: $(printf '%s' "$SOURCE_REF_VALUES" | cut -c1-7)"
elif [ "$SOURCE_REF_COUNT" -gt 1 ]; then
  COMMIT_SHORT=" · コミット番号: 画面ごとに異なる"
else
  COMMIT_SHORT=""
fi

# 改善課題: 対応表(CRUD対応表)の生成に本当に必要なのは元データ(screen-manifest.json・
# api-manifest.json等)が実在することであり、--build-manifests-from-docsによる元データの
# 組み立て直しではない。組み立て直しを行わない実行(既存の元データをそのまま使う場合)でも
# 対応表を生成できるよう、パス変数は --build-manifests-from-docs の分岐の外で常に解決する。
# --screen-manifest は従来から受け付けている外部入力である。設計書から作る
# API/テーブルのマニフェストと同じ生成連鎖で対応表・遷移図へ渡し、DOCS_ROOT配下に
# 複製させない。未指定時だけ従来どおり既定の配置を読む。
screen_manifest="${SCREEN_MANIFEST:-$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/screen-manifest.json}"
api_manifest="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/api-manifest.json"
table_manifest="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/table-manifest.json"
feature_manifest="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/feature-manifest.json"

# --build-manifests-from-docs 指定時は、一覧・図の材料をここで一括して生成する。
# --portal-only は index.html 以外を変更しない既存契約を守るため、この前段を実行しない。
if [ "$BUILD_MANIFESTS_FROM_DOCS" -eq 1 ] && [ "$PORTAL_ONLY" -eq 0 ]; then
  DOC_EXTRACTION_DECL="$SCRIPT_DIR/../../delivery-payload/references/doc-extraction.json"
  if [ ! -f "$DOC_EXTRACTION_DECL" ]; then
    echo "ERROR: build-portal.sh requires $DOC_EXTRACTION_DECL" >&2
    exit 1
  fi
  echo "INFO: generating design-document manifests" >&2
  bash "$SCRIPT_DIR/portal-input/build-manifests-from-docs.sh" "$DOCS_ROOT" "$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT" \
    || { echo "ERROR: design-document manifest generation failed" >&2; exit 1; }

  # 改善課題1-61: build-manifests-from-docs.shは本体(<kind>-manifest.json)しか作らず、
  # マニフェストの永続化を検査するcheck-manifest-persistence.shが求める拡張版
  # (<kind>-manifest.ext.json)を作る記述がこの経路(--build-manifests-from-docsのみを使う
  # 実行)に無かった。generating-<種別>-list-for-reverse-docsスキル(原本コードを直接解析する
  # 経路)は各Step 4でextract-<種別>-metadata.shを自ら呼ぶが、設計文書のみから組み立てる
  # 本経路はそのスキルを経由しないため、同じ拡張マニフェスト生成をここで肩代わりする。
  # 抽出は原本コードの静的解析に由来するヒューリスティックであり、検出根拠が弱ければ
  # フィールドを付けないfail-safe設計(各extractスクリプトのヘッダ参照)のため、
  # 抽出できる範囲が無くても異常ではない。個々の種別の抽出失敗でビルド全体を止めない
  # (原本コード側の静的解析はベストエフォートであり、設計文書から導けた本体マニフェストの
  # 生成成功をこの失敗で無効化しない)。
  for ext_kind in api table batch report external feature; do
    ext_manifest="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/${ext_kind}-manifest.json"
    [ -f "$ext_manifest" ] || continue
    ext_script="$SCRIPT_DIR/extract/extract-${ext_kind}-metadata.sh"
    [ -f "$ext_script" ] || continue
    ext_out="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/${ext_kind}-manifest.ext.json"
    # このスクリプトはset -euo pipefailで動くため、パイプの右側(sed)が常に0で終わっても
    # pipefailにより左側(抽出スクリプト)の非0終了はパイプ全体の非0終了として伝播し、
    # ガード無しではset -eによりbuild-portal.sh全体が即座に停止する(上のコメントが
    # 述べる「個々の種別の抽出失敗でビルド全体を止めない」を実際に満たすには、この
    # `|| ext_rc=$?`によるガードが必須)。
    ext_rc=0
    if [ "$ext_kind" = "feature" ]; then
      bash "$ext_script" "$ext_manifest" "$ext_out" --source-dir "$TARGET_REPO" 2>&1 \
        | sed "s/^/INFO: extract-${ext_kind}-metadata: /" >&2 || ext_rc=$?
    else
      bash "$ext_script" "$ext_manifest" "$TARGET_REPO" "$ext_out" 2>&1 \
        | sed "s/^/INFO: extract-${ext_kind}-metadata: /" >&2 || ext_rc=$?
    fi
    if [ "$ext_rc" -ne 0 ]; then
      echo "WARN: extract-${ext_kind}-metadata.sh failed (exit ${ext_rc}). ${ext_kind}-manifest.ext.json may be missing or incomplete" >&2
    fi
  done

  message_doc_rel="$(output_layout_get "$LAYOUT_JSON" messageDoc)" || exit 1
  message_manifest="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/message-manifest.json"
  if [ -f "$DOCS_ROOT/$message_doc_rel" ]; then
    echo "INFO: generating message manifest" >&2
    bash "$SCRIPT_DIR/extract/convert-message-doc-to-manifest.sh" "$DOCS_ROOT/$message_doc_rel" "$message_manifest" \
      || { echo "ERROR: message manifest generation failed" >&2; exit 1; }
    echo "INFO: generating message list" >&2
    units_root_rel="$(output_layout_get "$LAYOUT_JSON" unitsRoot)" || exit 1
    bash "$SCRIPT_DIR/unit-list/build-unit-list.sh" "$message_manifest" "$PORTAL_DIR/${units_root_rel#*/}/メッセージ一覧/メッセージ一覧.html" --unit-kind message \
      || { echo "ERROR: message list generation failed" >&2; exit 1; }
  else
    echo "SKIP: message list (message definition document is absent: $DOCS_ROOT/$message_doc_rel)" >&2
  fi

  diagram_dir_rel="$(output_layout_get "$LAYOUT_JSON" diagramDir)" || exit 1
  diagrams_dir="$PORTAL_DIR/${diagram_dir_rel#*/}"
  for diagram_spec in \
    "entity-state|extract-entity-state-page-data.sh|.entity-state-page-data.json" \
    "er|extract-er-page-data.sh|.er-page-data.json"; do
    IFS='|' read -r diagram_page diagram_script diagram_data <<EOF
$diagram_spec
EOF
    echo "INFO: generating ${diagram_page} diagram data" >&2
    bash "$SCRIPT_DIR/portal-input/$diagram_script" "$DOCS_ROOT" "$DOCS_ROOT/$diagram_data" \
      || { echo "ERROR: ${diagram_page} diagram data generation failed" >&2; exit 1; }
    echo "INFO: generating ${diagram_page} diagram page" >&2
    bash "$SCRIPT_DIR/detail-pages/build-detail-page.sh" "$DOCS_ROOT/$diagram_data" "$diagrams_dir" --page "$diagram_page" --portal-dir "$PORTAL_DIR" \
      || { echo "ERROR: ${diagram_page} diagram page generation failed" >&2; exit 1; }
  done

  if [ -f "$screen_manifest" ]; then
    echo "INFO: generating transition diagram data" >&2
    bash "$SCRIPT_DIR/portal-input/extract-transition-page-data.sh" "$DOCS_ROOT" "$DOCS_ROOT/.transition-page-data.json" \
      || { echo "ERROR: transition diagram data generation failed" >&2; exit 1; }
    echo "INFO: generating transition diagram page" >&2
    bash "$SCRIPT_DIR/detail-pages/build-detail-page.sh" "$DOCS_ROOT/.transition-page-data.json" "$diagrams_dir" --page transition --portal-dir "$PORTAL_DIR" \
      || { echo "ERROR: transition diagram page generation failed" >&2; exit 1; }
  else
    echo "SKIP: transition diagram (screen manifest is absent)" >&2
  fi
elif [ "$BUILD_MANIFESTS_FROM_DOCS" -eq 1 ]; then
  echo "INFO: --portal-only skips --build-manifests-from-docs to preserve index-only generation" >&2
fi

# 対応表(CRUD対応表)の生成に本当に必要なのは元データ(screen-manifest.json・
# api-manifest.json)が実在することであり、--build-manifests-from-docsによる
# 組み立て直しではない。上のブロックで組み立て直した場合はその結果を、
# 行わない場合は既存の元データをそのまま使う。いずれの場合も入力の実在だけを条件に
# ここで生成する。--portal-only は index.html 以外を変更しない既存契約を守るため
# 生成しない。
if [ "$PORTAL_ONLY" -eq 0 ]; then
  matrix_dir_rel="$(output_layout_get "$LAYOUT_JSON" matrixDir)" || exit 1
  matrix_dir="$PORTAL_DIR/${matrix_dir_rel#*/}"
  if [ -f "$screen_manifest" ] && [ -f "$api_manifest" ]; then
    matrix_args=("$matrix_dir/data" --screen-manifest "$screen_manifest" --api-manifest "$api_manifest")
    [ -f "$table_manifest" ] && matrix_args+=(--table-manifest "$table_manifest")
    [ -f "$feature_manifest" ] && matrix_args+=(--feature-manifest "$feature_manifest")
    echo "INFO: generating CRUD matrix data" >&2
    bash "$SCRIPT_DIR/extract/build-matrix-data.sh" "${matrix_args[@]}" \
      || { echo "ERROR: CRUD matrix data generation failed" >&2; exit 1; }
    echo "INFO: generating CRUD matrix page" >&2
    bash "$SCRIPT_DIR/matrix/build-matrix-pages.sh" crud "$matrix_dir/data/crud-matrix.json" "$matrix_dir/CRUD図/CRUD図.html" \
      || { echo "ERROR: CRUD matrix page generation failed" >&2; exit 1; }
  else
    echo "SKIP: CRUD matrix (screen or API manifest is absent)" >&2
  fi
fi

run_pipeline_hook "--pre-build" "$PRE_BUILD"

# 1-224: detail-pages のうち対話スキルが page-data を組み立てる3種は、生成済みHTMLを
# 発見するだけでは古い版を更新できない。検証済み入力を manifestsRoot/detail-pages に
# 永続化し、通常のポータル生成から決定的ビルダーへ必ず渡す。入力が無い場合はSKIPを
# 記録し、既存HTMLが残っていれば古い版を成功扱いにしないため全種を確認後に非0終了する。
if [ "$PORTAL_ONLY" -eq 0 ]; then
  detail_page_input_dir="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/detail-pages"
  detail_page_input_failure=0
  foundation_dir_rel="$(output_layout_get "$LAYOUT_JSON" foundationDir)" || exit 1
  detail_units_root_rel="$(output_layout_get "$LAYOUT_JSON" unitsRoot)" || exit 1
  for detail_spec in \
    "techstack|techstack-page-data.json|$PORTAL_DIR/${foundation_dir_rel#*/}|技術スタック.html" \
    "env|env-page-data.json|$PORTAL_DIR/${foundation_dir_rel#*/}|環境構築手順.html" \
    "glossary|glossary-page-data.json|$PORTAL_DIR/${detail_units_root_rel#*/}/用語辞書|用語辞書.html"; do
    IFS='|' read -r detail_page detail_input_name detail_output_dir detail_output_name <<EOF
$detail_spec
EOF
    detail_input="$detail_page_input_dir/$detail_input_name"
    detail_output="$detail_output_dir/$detail_output_name"
    if [ -f "$detail_input" ]; then
      echo "INFO: regenerating detail page ${detail_page} from prepared input: $detail_input" >&2
      detail_args=(
        "$detail_input" "$detail_output_dir"
        --page "$detail_page"
        --portal-dir "$PORTAL_DIR"
        --catalog "$CATALOG"
      )
      [ -n "$GENERATED_AT" ] && detail_args+=(--generated-at "$GENERATED_AT")
      detail_args+=(--project-name "$PROJECT_NAME")
      bash "$SCRIPT_DIR/detail-pages/build-detail-page.sh" "${detail_args[@]}" \
        || { echo "ERROR: detail page generation failed: ${detail_page}" >&2; exit 1; }
    else
      echo "SKIP: detail page ${detail_page} (prepared input is absent: $detail_input)" >&2
      if [ -f "$detail_output" ]; then
        echo "ERROR: stale detail page detected: $detail_output (prepared input is absent)" >&2
        detail_page_input_failure=1
      fi
    fi
  done

  ai_assets_data="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/ai-assets.json"
  ai_foundation_dir_rel="$(output_layout_get "$LAYOUT_JSON" foundationDir)" || exit 1
  ai_assets_output="$PORTAL_DIR/${ai_foundation_dir_rel#*/}/AI設定資産.html"
  if [ -d "$TARGET_REPO/.claude/rules" ] \
    || [ -d "$TARGET_REPO/.claude/skills" ] \
    || [ -d "$TARGET_REPO/.claude/agents" ] \
    || [ -f "$TARGET_REPO/.claude/settings.json" ]; then
    echo "INFO: regenerating AI configuration assets from target repository" >&2
    bash "$SCRIPT_DIR/extract/extract-ai-assets.sh" "$TARGET_REPO" "$ai_assets_data" \
      || { echo "ERROR: AI configuration asset extraction failed" >&2; exit 1; }
    if [ -n "$GENERATED_AT" ]; then
      ai_assets_data_tmp="${ai_assets_data}.tmp"
      jq --arg generatedAt "$GENERATED_AT" '.generatedAt = $generatedAt' \
        "$ai_assets_data" > "$ai_assets_data_tmp" \
        && mv "$ai_assets_data_tmp" "$ai_assets_data" \
        || { rm -f "$ai_assets_data_tmp"; echo "ERROR: AI configuration asset timestamp could not be fixed" >&2; exit 1; }
    fi
    ai_assets_count="$(jq '[.rules, .skills, .subagents, .hooks] | map(length) | add' "$ai_assets_data")" \
      || { echo "ERROR: AI configuration asset count could not be read" >&2; exit 1; }
    if [ "$ai_assets_count" -gt 0 ]; then
      ai_assets_args=(
        ai-assets "$ai_assets_data" "$ai_assets_output"
        --portal-dir "$PORTAL_DIR"
        --project-name "$PROJECT_NAME"
        --catalog "$CATALOG"
      )
      [ -n "$GENERATED_AT" ] && ai_assets_args+=(--generated-at "$GENERATED_AT")
      bash "$SCRIPT_DIR/matrix/build-matrix-pages.sh" "${ai_assets_args[@]}" \
        || { echo "ERROR: AI configuration asset page generation failed" >&2; exit 1; }
    else
      echo "SKIP: AI configuration assets (extracted asset set is empty)" >&2
      if [ -f "$ai_assets_output" ]; then
        echo "ERROR: stale AI configuration asset page detected: $ai_assets_output" >&2
        detail_page_input_failure=1
      fi
    fi
  else
    echo "SKIP: AI configuration assets (no supported .claude assets in target repository)" >&2
    if [ -f "$ai_assets_output" ]; then
      echo "ERROR: stale AI configuration asset page detected: $ai_assets_output" >&2
      detail_page_input_failure=1
    fi
  fi

  if [ "$detail_page_input_failure" -ne 0 ]; then
    echo "ERROR: prepared detail-page input is missing while an older generated page remains" >&2
    exit 1
  fi
fi

# --- 1. コード計測結果の読み取り（counting-code-lines スキルが出力した JSON） ---
# counting-code-lines は納品物ルート（output_dir=DOCS_ROOT）直下へ書く
# （納品物フォルダ体系.md の正本レイアウト）。読み場所を書き場所へ揃える。
CODE_METRICS="$DOCS_ROOT/code-metrics.json"
if [ -f "$CODE_METRICS" ]; then
  total_lines="$(jq -r '.total // 0' "$CODE_METRICS")"
  fe_lines="$(jq -r '.fe // 0' "$CODE_METRICS")"
  be_lines="$(jq -r '.be // 0' "$CODE_METRICS")"
  total_files="$(jq -r '.file_count // 0' "$CODE_METRICS")"
  measured_at="$(jq -r '.measured_at // empty' "$CODE_METRICS")"
  commit_field="$(jq -r '.commit // empty' "$CODE_METRICS")"
  tests_raw="$(jq -c '.tests // null' "$CODE_METRICS")"
  previous_json="$(jq -c '.previous // null' "$CODE_METRICS")"
else
  echo "WARN: code-metrics.json not found at $CODE_METRICS. Using zeros." >&2
  total_lines=0; fe_lines=0; be_lines=0; total_files=0
  measured_at=""
  commit_field=""
  tests_raw="null"
  previous_json="null"
fi

# --- 2. portal catalogが一覧件数とカードを一括導出する ---
kinds_json="[]"

# --- 3. 共通文書リストの収集（design: 設計書系。standards: 規約系は docs/rules/ 専用ループで扱う。category-grouping/rule.md 準拠） ---
# 1-36: 非画面6種別の設計書単位文書（API・テーブル・バッチ・帳票・外部連携・機能）も
# 同じ共通文書ループへ合流させ、md→html変換・関連資料リンク解決・共通シェル注入を
# screenと同じ経路で受けさせる（screenUnitRootは専用ループが担うため含めない）。
common_roots=(
  "$DOCS_ROOT/$LAYOUT_COMMON_ROOT"
  "$DOCS_ROOT/$LAYOUT_CROSS_CUTTING_ROOT"
  "$DOCS_ROOT/$LAYOUT_API_UNIT_ROOT"
  "$DOCS_ROOT/$LAYOUT_TABLE_UNIT_ROOT"
  "$DOCS_ROOT/$LAYOUT_BATCH_UNIT_ROOT"
  "$DOCS_ROOT/$LAYOUT_REPORT_UNIT_ROOT"
  "$DOCS_ROOT/$LAYOUT_EXTERNAL_UNIT_ROOT"
  "$DOCS_ROOT/$LAYOUT_FEATURE_UNIT_ROOT"
)
COMMON_DOC_TEMPLATE_FILE="$SCRIPT_DIR/../../delivery-payload/templates/common-doc-template.html"

# 改善課題1-202: 変換した設計書の件数を数える。commonRootループ・規約定義ループ・
# 画面設計書ループの3経路すべてで対象のmdファイルを読み取るたびに加算する。
CONVERTED_DESIGN_DOC_COUNT=0

if [ "$PORTAL_ONLY" -eq 0 ]; then
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# 信頼境界の宣言文言（改善課題1-171）: 生成される全設計書ページに機械挿入する固定文言。
# 執筆側が手書きで追加する運用は禁止し、本スクリプトが一律に注入する。
TRUST_BOUNDARY_NOTICE_MD='> **本書の位置づけ**: 本書は現行実装をそのまま記録したものであり、業務要件・非機能要件・設計意図・運用実態は対象外です。未確定の事項は「要確認事項一覧」を参照してください。'

# md 本文の前処理（BOM 除去・frontmatter スキップ・HTML コメント除去）
# 共通文書ループ・画面設計書ループの両方から使う共通関数。挙動は従来のインライン処理と同一。
prepare_md_content() {
  local file="$1"
  sed -e '1s/^\xEF\xBB\xBF//' "$file" | awk 'NR==1 && /^---$/ {skip=1; next} skip && /^---$/ {skip=0; next} !skip' | awk '
    in_comment {
      buf[++n] = $0
      if ($0 ~ /-->/) { in_comment = 0; n = 0; next }
      next
    }
    # コードブロックの囲みの内側では、行頭のコメント開始記号も本文として残す。
    # 囲みの中身はそのまま表示すべき内容であり、除去すると擬似コードが欠ける。
    /^```/ { in_fence = !in_fence; print; next }
    in_fence { print; next }
    /^<!--/ {
      if ($0 ~ /-->/) { next }
      in_comment = 1
      n = 1
      buf[1] = $0
      next
    }
    { print }
    END {
      if (in_comment) { for (i = 1; i <= n; i++) print buf[i] }
    }
  '
}

extract_md_title() {
  local content="$1"
  local fallback="$2"
  local title
  title="$(printf '%s\n' "$content" | awk '/^#[[:space:]]+/ { sub(/^#[[:space:]]+/, ""); print; exit }')"
  if [ -z "$title" ]; then
    title="$fallback"
  fi
  printf '%s\n' "$title"
}

# JSON文字列として埋め込み、HTMLパーサーが </script> を終端として解釈しないよう「<」をUnicode escapeする。
markdown_to_script_json() {
  printf '%s' "$1" | jq -Rsr 'tojson | gsub("<"; "\\u003c")'
}

FOUNDATION_OUT_DIR="$DOCS_ROOT/$LAYOUT_FOUNDATION_DIR"
# commonRoot 配下のうち、宣言済みの基盤文書（foundationDoc・commonDesignDoc・dataDesignDoc・
# messageDoc・uiCommonDoc・surveyDoc）だけを foundationDir（project-portal/基盤。人が読む
# 資料の置き場）へ物理分離する。宣言外の文書（プロジェクト固有の補助文書等）は commonRoot
# に .md と .html を co-locate したまま維持する（分離は「人に見せる基盤文書」に限定する）。
FOUNDATION_KNOWN_BASENAMES=""
# 1-35: 基盤文書はすべて foundationDir へ物理分離されるが、ポータルカタログ上の所属カテゴリは
# 文書ごとに異なる（surveyDoc＝アーキテクチャ調査書は「project」＝基盤情報、それ以外の
# foundationDoc・commonDesignDoc・dataDesignDoc・messageDoc・uiCommonDoc は「design」＝設計書。
# 定義は delivery-payload/references/portal-catalog.json の categories[].blueprints[].discovery.glob）。
# パンくずの中カテゴリは物理配置ではなく、この所属カテゴリで判定する。
FOUNDATION_CATEGORY_MAP=""
for foundation_doc_key in foundationDoc commonDesignDoc dataDesignDoc messageDoc uiCommonDoc surveyDoc; do
  foundation_doc_path="$(output_layout_get "$LAYOUT_JSON" "$foundation_doc_key" 2>/dev/null)" || continue
  foundation_doc_basename="$(basename "$foundation_doc_path")"
  FOUNDATION_KNOWN_BASENAMES="${FOUNDATION_KNOWN_BASENAMES}${foundation_doc_basename}
"
  if [ "$foundation_doc_key" = "surveyDoc" ]; then
    foundation_doc_category="project"
  else
    foundation_doc_category="design"
  fi
  FOUNDATION_CATEGORY_MAP="${FOUNDATION_CATEGORY_MAP}${foundation_doc_basename}	${foundation_doc_category}
"
done
# 1-41: 本文中の.md参照が、参照元と参照先の処理順序に左右されず解決できるよう、
# これから変換する全.mdファイルの変換先(.html)を先読みした対応表を先に作る
# （既存の逐次変換だけだと「後で変換される参照はこの時点でまだ解決できない」）。
# 判定はこれから実行する変換ループ自身が使うのと同じ基盤文書振り分けロジックを先取り
# するだけで、新しい正本ファイルは作らない（ビルド実行中だけ使う一時ファイル）。
# 手元にある情報（これから変換するmd→htmlの対応）から機械的に導く。
PORTAL_MD_MAP_FILE="$(mktemp "${TMPDIR:-/tmp}/portal-md-map.XXXXXX")"
: > "$PORTAL_MD_MAP_FILE"
for md_map_dir in "${common_roots[@]}"; do
  [ -d "$md_map_dir" ] || continue
  while IFS= read -r md_map_file; do
    md_map_basename="$(basename "$md_map_file")"
    html_map_basename="$(basename "$md_map_file" .md).html"
    if printf '%s' "$FOUNDATION_KNOWN_BASENAMES" | grep -qxF "$md_map_basename"; then
      html_map_file="$FOUNDATION_OUT_DIR/$html_map_basename"
    else
      html_map_file="$(dirname "$md_map_file")/$html_map_basename"
    fi
    printf '%s\t%s\n' "$md_map_file" "$html_map_file" >> "$PORTAL_MD_MAP_FILE"
  done < <(find "$md_map_dir" -name '*.md' -type f 2>/dev/null | sort)
done
# 規約は rule.md と rule.html を同じディレクトリへ置く。画面設計書は screenUnitRoot の
# 定義ファイルから screenViewRoot の閲覧用HTMLへ分離するため、変換ループと同じ対応を
# 先に対応表へ加える。
rules_map_root="$DOCS_ROOT/$LAYOUT_RULES_ROOT"
if [ -d "$rules_map_root" ]; then
  while IFS= read -r rule_map_file; do
    printf '%s\t%s\n' "$rule_map_file" "$(dirname "$rule_map_file")/rule.html" >> "$PORTAL_MD_MAP_FILE"
  done < <(find "$rules_map_root" -name 'rule.md' -type f 2>/dev/null | sort)
fi
for screen_map_dir in "$DOCS_ROOT/$LAYOUT_SCREEN_UNIT_ROOT"/screen-*/; do
  [ -d "$screen_map_dir" ] || continue
  screen_map_name="$(basename "${screen_map_dir%/}")"
  for screen_map_md in \
    "${screen_map_dir}基本設計/画面基本設計書.md" \
    "${screen_map_dir}詳細設計/画面詳細設計書.md"; do
    [ -f "$screen_map_md" ] || continue
    screen_map_rel="${screen_map_md#"$screen_map_dir"}"
    printf '%s\t%s\n' "$screen_map_md" \
      "$DOCS_ROOT/$LAYOUT_SCREEN_VIEW_ROOT/$screen_map_name/${screen_map_rel%.md}.html" \
      >> "$PORTAL_MD_MAP_FILE"
  done
done
export PORTAL_MD_MAP_FILE

# 1-41(7回目): 本文中の資料参照のうち、対象リポジトリのソースツリー上の実装ファイル名
# （例: pages/HomePage.tsx）は名前の体系が生成後のページ側と異なるため、上記のmd→html
# 対応表では解決できない。画面の一覧データ（screen-manifest.jsonのentryFile）は実装
# ファイル名と生成後のページのパス（designDocPath等）を同じ行に持つため、この対応から
# 「実装ファイル名 → 生成後のページ」の対応表を機械的に作る。画面以外の種別は一覧データが
# 生成後のページのパスを持たないため対象外（1-36が扱う供給経路の範囲）。新しい正本ファイルは
# 作らず、上記のmd→html対応表と同じくビルド実行中だけの一時ファイルとして作る。
PORTAL_IMPL_MAP_FILE="$(mktemp "${TMPDIR:-/tmp}/portal-impl-map.XXXXXX")"
: > "$PORTAL_IMPL_MAP_FILE"
screen_manifest_for_impl_map="$DOCS_ROOT/$LAYOUT_MANIFESTS_ROOT/screen-manifest.json"
if [ -f "$screen_manifest_for_impl_map" ]; then
  screen_list_dir_for_impl_map="$DOCS_ROOT/$LAYOUT_SCREEN_LIST_DIR"
  while IFS=$'\t' read -r impl_entry_file impl_target_rel; do
    [ -z "$impl_entry_file" ] && continue
    [ -z "$impl_target_rel" ] && continue
    # designDocPath等はscreenListDirからの相対パスとして一覧側で組み立てられている
    # （build-screen-list.shの契約）。scheme付き・絶対パスは受け取らない（インジェクション対策。
    # resolveProseMdLinkと同じ判定）。
    case "$impl_target_rel" in
      *://*|/*)
        continue ;;
    esac
    impl_target_abs="$(python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))" \
      "$screen_list_dir_for_impl_map" "$impl_target_rel" 2>/dev/null)" || continue
    printf '%s\t%s\n' "$impl_entry_file" "$impl_target_abs" >> "$PORTAL_IMPL_MAP_FILE"
  done < <(jq -r '
    (.screens // [])[]
    | select(.entryFile != null and .entryFile != "")
    | . as $s
    | ($s.designDocPath // $s.detailDocPath // $s.sequencePath // $s.testCasePath // "") as $target
    | select($target != "" and ($target | endswith(".html")))
    | [$s.entryFile, $target] | @tsv
  ' "$screen_manifest_for_impl_map" 2>/dev/null)
fi
export PORTAL_IMPL_MAP_FILE

for common_dir in "${common_roots[@]}"; do
if [ -d "$common_dir" ]; then
  while IFS= read -r md_file; do
    md_content="$(prepare_md_content "$md_file")"
    title="$(extract_md_title "$md_content" "$(basename "$md_file" .md)")"

    # .md → .html 変換。宣言済みの基盤文書だけ html を commonRoot から物理的に分離し、
    # foundationDir へ出力する。それ以外は従来どおり .md と同じ場所に .html を置く。
    md_basename="$(basename "$md_file")"
    html_basename="$(basename "$md_file" .md).html"
    # 1-35: パンくずの中カテゴリは基盤文書ごとの所属カテゴリ（FOUNDATION_CATEGORY_MAP）から
    # 引く。宣言外の文書（プロジェクト固有の補助文書等）は従来どおり「design」を既定とする。
    # awk の文字列比較は macOS 標準 awk が日本語ファイル名を数値文字列と誤認する既知の
    # 問題があるため使わず、bash のタブ区切り read で比較する。
    common_category="design"
    while IFS=$'\t' read -r map_basename map_category; do
      [ -z "$map_basename" ] && continue
      if [ "$map_basename" = "$md_basename" ]; then
        common_category="$map_category"
        break
      fi
    done <<< "$FOUNDATION_CATEGORY_MAP"
    if printf '%s' "$FOUNDATION_KNOWN_BASENAMES" | grep -qxF "$md_basename"; then
      mkdir -p "$FOUNDATION_OUT_DIR"
      html_file="$FOUNDATION_OUT_DIR/$html_basename"
      html_dir_for_links="$FOUNDATION_OUT_DIR"
    else
      html_file="$(dirname "$md_file")/$html_basename"
      html_dir_for_links="$(dirname "$md_file")"
    fi
    if [ -f "$COMMON_DOC_TEMPLATE_FILE" ]; then
      # 戻るリンク: 出力先の深さに応じてポータル index.html への相対パスを計算する
      # （深さ1: ../index.html、深さ2: ../../index.html。固定文字列だと深さ2で1段足りない）
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$html_dir_for_links" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"
      md_content="$(link_related_material_paths "$(dirname "$md_file")" "$html_dir_for_links" <<< "$md_content")"
      md_content_json="$(markdown_to_script_json "$md_content")"
      local_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
        "{{PORTAL_INDEX_HREF}}" "$portal_index_href"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        local_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      # 共通シェル注入（partials が存在する場合のみ）
      if type shell_injection_args >/dev/null 2>&1; then
        doc_sidebar_html="<nav class=\"pt-doc-nav\" aria-label=\"目次\"><div class=\"pt-doc-nav__group\">目次</div><ul class=\"pt-doc-nav__toc\" id=\"toc-list\"></ul></nav>"
        shell_injection_args "$SCRIPT_DIR/../../delivery-payload/templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "generation-engine/scripts/build-portal.sh" "$common_category" "${SITES_FILE:-}" "${SITE_KEY:-}" "$html_dir_for_links" "$doc_sidebar_html"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          local_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      local_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")
      doc_html="$(render_template "$(cat "$COMMON_DOC_TEMPLATE_FILE")" "${local_render_args[@]}")"
      printf '%s\n' "$doc_html" > "$html_file"
      CONVERTED_DESIGN_DOC_COUNT=$((CONVERTED_DESIGN_DOC_COUNT + 1))
    fi

  done < <(find "$common_dir" -name '*.md' -type f 2>/dev/null | sort)
fi
done

# 改善課題1-205: 変換対象の対応表を正本として、改名・削除後に残った旧HTMLを
# サイドバー状態のバックフィルより前に除去する。分離配置の走査範囲は
# portal-catalog.json の共通文書生成器との対応から導く。
remove_orphaned_common_html \
  "$PORTAL_MD_MAP_FILE" "$CATALOG" "$OUTPUT_LAYOUT_RESOLVED_FILE" "$DOCS_ROOT" "$FOUNDATION_OUT_DIR" \
  "$DOCS_ROOT/$LAYOUT_RULES_ROOT" "$DOCS_ROOT/$LAYOUT_SCREEN_VIEW_ROOT" "${common_roots[@]}"

# --- 3a. 設計文書群の必須節・見出し順検査（改善課題1-74） ---
# 定義ファイルにある必須節の欠落は生成を停止する。必須節をすべて持つ文書の
# 見出し順だけの違いは検査側がWARNとして報告し、生成は継続する。
#
# 改善課題1-243: 対象の設計文書が0件（新規プロジェクト・旧スキーマ等、
# screen/api/table/batch/report/external/feature のいずれの単位ルートも
# 実在しない状態）の場合、check-design-doc-section-consistency.sh は
# 「検査対象の設計文書が0件です」という ERROR を出して終了コード1を返す。
# この検査は本来「project_root の取り違え（1-196）」を検出するための
# ガードだが、build-portal.sh からの呼び出しでは set -e により、必須節の
# 欠落と区別されないままポータル生成そのものが丸ごと停止していた
# （--self-test ケース1が旧スキーマ互換フィクスチャで再現）。
# 「対象が0件」は必須節の欠落ではないため、この呼び出しに限りWARNへ
# 読み替えて生成を継続する。check-design-doc-section-consistency.sh 自身の
# 判定・self-test（1-196回帰含む）は変更しない。
DESIGN_DOC_SECTION_CHECK="$SCRIPT_DIR/tests/check-design-doc-section-consistency.sh"
if [ -f "$DESIGN_DOC_SECTION_CHECK" ]; then
  design_doc_section_check_stderr="$(mktemp "${TMPDIR:-/tmp}/design-doc-section-check.XXXXXX" 2>/dev/null || true)"
  design_doc_section_check_status=0
  if [ -n "$design_doc_section_check_stderr" ]; then
    bash "$DESIGN_DOC_SECTION_CHECK" "$DOCS_ROOT" 2>"$design_doc_section_check_stderr" \
      || design_doc_section_check_status=$?
    cat "$design_doc_section_check_stderr" >&2
    if [ "$design_doc_section_check_status" -ne 0 ] \
      && grep -qF '検査対象の設計文書が0件です' "$design_doc_section_check_stderr"; then
      echo "WARN: 設計文書群の必須節検査は対象の設計文書が0件のため実行されませんでした（改善課題1-243）" >&2
      design_doc_section_check_status=0
    fi
    rm -f "$design_doc_section_check_stderr"
  else
    # 一時ファイルを作成できない場合は従来どおり直接実行する（判定不能規約:
    # このフォールバックは0件時の読み替えを行わないため、環境要因で
    # WARNへ読み替えられないことがある。既存の直接実行と同じ挙動）。
    bash "$DESIGN_DOC_SECTION_CHECK" "$DOCS_ROOT" || design_doc_section_check_status=$?
  fi
  if [ "$design_doc_section_check_status" -ne 0 ]; then
    exit "$design_doc_section_check_status"
  fi
fi

# --- 3b. 規約定義（docs/rules/<親>/<子>/rule.md）の変換 ---
# 規約置き場の一本化（output-layout.jsonの専用ルート廃止）に伴い、規約は docs/rules/ 配下の
# 親子構造から読む。ファイル名が rule.md で全件揃うため、共通文書ループ（*.md 全件探索。
# design-notes.md まで拾ってしまう）とは別に、rule.md だけを対象にする専用ループで処理する。
# 表示名は front matter の title を使い、status: draft の規約はタイトルへ「（下書き）」を
# 付けて未承認であることを示す（新しい色・新しいCSSクラスは導入しない）。
RULES_ROOT="$DOCS_ROOT/$LAYOUT_RULES_ROOT"
if [ -d "$RULES_ROOT" ]; then
  while IFS= read -r rule_md; do
    md_content="$(prepare_md_content "$rule_md")"
    fm_title="$(frontmatter_value "$rule_md" title)"
    fm_status="$(frontmatter_value "$rule_md" status)"
    body_title="$(extract_md_title "$md_content" "$(basename "$(dirname "$rule_md")")")"
    title="${fm_title:-$body_title}"
    if [ "$fm_status" = "draft" ]; then
      title="${title}（下書き）"
    fi

    html_file="$(dirname "$rule_md")/rule.html"
    if [ -f "$COMMON_DOC_TEMPLATE_FILE" ]; then
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$(dirname "$rule_md")" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"
      md_content="$(link_related_material_paths "$(dirname "$rule_md")" "$(dirname "$rule_md")" <<< "$md_content")"
      md_content_json="$(markdown_to_script_json "$md_content")"
      local_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
        "{{PORTAL_INDEX_HREF}}" "$portal_index_href"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        local_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      if type shell_injection_args >/dev/null 2>&1; then
        doc_sidebar_html="<nav class=\"pt-doc-nav\" aria-label=\"目次\"><div class=\"pt-doc-nav__group\">目次</div><ul class=\"pt-doc-nav__toc\" id=\"toc-list\"></ul></nav>"
        shell_injection_args "$SCRIPT_DIR/../../delivery-payload/templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "generation-engine/scripts/build-portal.sh" "standards" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$rule_md")" "$doc_sidebar_html"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          local_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      local_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")
      doc_html="$(render_template "$(cat "$COMMON_DOC_TEMPLATE_FILE")" "${local_render_args[@]}")"
      printf '%s\n' "$doc_html" > "$html_file"
      CONVERTED_DESIGN_DOC_COUNT=$((CONVERTED_DESIGN_DOC_COUNT + 1))
    fi
  done < <(find "$RULES_ROOT" -type f -name 'rule.md' 2>/dev/null | sort)
else
  # ${RULES_ROOT} は波括弧を外すな。set -u下で変数直後に全角括弧「（」が続くと
  # 変数名の続きとして誤読されunbound variableになることを実装時に手動再現で確認した
  # （詳細: docs/design/generation-engine/ルート直下/詳細設計書.md「build-portal.sh」節の実装判断3）。
  echo "WARN: 規約定義ディレクトリが見つかりません: ${RULES_ROOT}（output_dir に docs ディレクトリ自体が渡されました可能性があります。<output_dir> には docs と project-portal を子に持つ納品物ルートを渡してください。docs/rules 自体を持たないプロジェクトではこの警告は無視してかまいません）" >&2
fi

# --- 3.5. 画面設計書の変換 ---
SCREEN_DOC_TEMPLATE_FILE="$SCRIPT_DIR/../../delivery-payload/templates/screen-doc-template.html"
screen_list_dir="$DOCS_ROOT/$LAYOUT_SCREEN_LIST_DIR"

if [ -d "$DOCS_ROOT/$LAYOUT_SCREEN_UNIT_ROOT" ] && [ -f "$SCREEN_DOC_TEMPLATE_FILE" ]; then
  for screen_dir in "$DOCS_ROOT/$LAYOUT_SCREEN_UNIT_ROOT"/screen-*/; do
    [ -d "$screen_dir" ] || continue
    assert_no_symlink_output_paths "$DOCS_ROOT" "$screen_dir" || exit 1

    # html は screenUnitRoot（定義の置き場）と物理的に分離し、screenViewRoot
    # （project-portal/画面。人が読む資料の置き場）の同名 screen-<ID> 配下へ出力する。
    screen_dir_name="$(basename "${screen_dir%/}")"
    screen_view_dir="$DOCS_ROOT/$LAYOUT_SCREEN_VIEW_ROOT/${screen_dir_name}/"
    mkdir -p "$screen_view_dir"

    base_md="${screen_dir}基本設計/画面基本設計書.md"
    detail_md="${screen_dir}詳細設計/画面詳細設計書.md"
    assert_no_symlink_output_paths "$DOCS_ROOT" \
      "$screen_view_dir" \
      "$(dirname "$base_md")" \
      "$(dirname "$detail_md")" || exit 1

    # 表示コミット（画面単位）: 画面詳細設計書 frontmatter の source_ref から算出する。
    # 基本設計書・詳細設計書のどちらをレンダリングする場合も同じ値を使う。
    page_source_ref="$(frontmatter_value "$detail_md" source_ref \
      | grep -v '^SOURCECOMMIT$' | grep -v '^$' | head -n1 || true)"
    if [ -n "$page_source_ref" ] && is_commit_sha "$page_source_ref"; then
      PAGE_COMMIT=" · コミット番号: $(printf '%s' "$page_source_ref" | cut -c1-7)"
    else
      PAGE_COMMIT=""
    fi

    for target_md in "$base_md" "$detail_md"; do
      [ -f "$target_md" ] || continue
      CONVERTED_DESIGN_DOC_COUNT=$((CONVERTED_DESIGN_DOC_COUNT + 1))

      html_basename="$(basename "$target_md" .md).html"
      # screen_dir 配下の相対サブパス（基本設計 / 詳細設計）を screen_view_dir 側へ引き継ぐ。
      target_md_rel="${target_md#"$screen_dir"}"
      html_out_dir="${screen_view_dir}$(dirname "$target_md_rel")"
      mkdir -p "$html_out_dir"
      html_file="$html_out_dir/$html_basename"
      md_content="$(prepare_md_content "$target_md")"
      md_content="$(printf '%s\n' "$md_content" | awk -v notice="$TRUST_BOUNDARY_NOTICE_MD" '
        !inserted && /^#[[:space:]]/ { print; print ""; print notice; inserted=1; next }
        { print }
      ')"
      md_content="$(link_related_material_paths "$(dirname "$target_md")" "$html_out_dir" <<< "$md_content")"
      title="$(extract_md_title "$md_content" "$(basename "$target_md" .md)")"
      md_content_json="$(markdown_to_script_json "$md_content")"

      # 戻るリンク（ブランド）: 出力先の深さに応じてポータル index.html への相対パスを計算する
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$html_out_dir" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"

      # 戻るリンク（doc-nav）: 出力先フォルダ → 画面一覧.html への相対パス
      screen_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$screen_list_dir" "$html_out_dir" 2>/dev/null || echo "../..")"
      screen_index_href="$screen_index_rel/画面一覧.html"

      doc_nav="<a class=\"back-link\" href=\"$screen_index_href\">← 画面一覧へ戻る</a>"
      if [ -f "$base_md" ]; then
        if [ "$target_md" = "$base_md" ]; then
          doc_nav="$doc_nav<span class=\"nav-item active\">基本設計</span>"
        else
          doc_nav="$doc_nav<a class=\"nav-item\" href=\"../基本設計/画面基本設計書.html\">基本設計</a>"
        fi
      fi
      if [ -f "$detail_md" ]; then
        if [ "$target_md" = "$detail_md" ]; then
          doc_nav="$doc_nav<span class=\"nav-item active\">詳細設計</span>"
        else
          doc_nav="$doc_nav<a class=\"nav-item\" href=\"../詳細設計/画面詳細設計書.html\">詳細設計</a>"
        fi
      fi
      if [ -f "${screen_view_dir}シーケンス図.html" ]; then
        doc_nav="$doc_nav<a class=\"nav-item\" href=\"../シーケンス図.html\">シーケンス図</a>"
      fi
      test_case_doc=""
      if [ -f "${screen_dir}テスト設計/画面テスト設計書.md" ]; then
        test_case_doc="${screen_dir}テスト設計/画面テスト設計書.md"
      elif [ -f "${screen_dir}テスト項目書/単体テスト仕様書.md" ]; then
        test_case_doc="${screen_dir}テスト項目書/単体テスト仕様書.md"
      fi
      if [ -n "$test_case_doc" ]; then
        # screenUnitRoot（定義）配下の md への横断リンクのため、screenViewRoot 側の
        # 出力先フォルダから見た相対パスを都度計算する（screenUnitRoot と screenViewRoot は
        # 別ツリーであり、固定 "../" では届かない）。
        test_case_dir="$(dirname "$test_case_doc")"
        test_case_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$test_case_dir" "$html_out_dir" 2>/dev/null || echo "../../テスト設計")"
        doc_nav="$doc_nav<a class=\"nav-item\" href=\"${test_case_rel}/$(basename "$test_case_doc")\">テストケース</a>"
      fi

      screen_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$PAGE_COMMIT"
        "{{PORTAL_INDEX_HREF}}" "$portal_index_href"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        screen_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      # 共通シェル注入（partials が存在する場合のみ）
      if type shell_injection_args >/dev/null 2>&1; then
        doc_sidebar_html="<nav class=\"pt-doc-nav\" aria-label=\"画面設計書\"><div class=\"pt-doc-nav__group\">画面 / 設計書</div>${doc_nav}<div class=\"pt-doc-nav__group\">この設計書内</div><ul class=\"pt-doc-nav__toc\" id=\"toc-list\"></ul></nav>"
        shell_injection_args "$SCRIPT_DIR/../../delivery-payload/templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$PAGE_COMMIT" "generation-engine/scripts/build-portal.sh" "list" "${SITES_FILE:-}" "${SITE_KEY:-}" "$html_out_dir" "$doc_sidebar_html"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          screen_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      screen_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")

      screen_doc_template="$(cat "$SCREEN_DOC_TEMPLATE_FILE")"
      if [[ "$md_content" == *"$RELATED_MATERIAL_CLOSE_BRACKET_MARKER"* ]]; then
        screen_doc_template="$(prepare_screen_doc_link_renderer <<< "$screen_doc_template")"
      fi
      screen_doc_html="$(render_template "$screen_doc_template" "${screen_render_args[@]}")"
      printf '%s\n' "$screen_doc_html" > "$html_file"
    done
  done
fi
rm -f "$PORTAL_IMPL_MAP_FILE"
unset PORTAL_IMPL_MAP_FILE
fi

# 改善課題1-202: 変換した設計書の件数を標準出力へ報告する。0件の場合は出力先の指定
# （第2引数が正しいプロジェクトルートを指しているか）を確認するよう警告する。
# --portal-only は元より変換を行わない既存契約のため対象外とする。
if [ "$PORTAL_ONLY" -eq 0 ]; then
  echo "変換した設計書の件数: ${CONVERTED_DESIGN_DOC_COUNT} 件"
  if [ "$CONVERTED_DESIGN_DOC_COUNT" -eq 0 ]; then
    echo "WARN: 変換した設計書が0件でした。<output_dir>（第2引数）の指定を確認してください（docs ディレクトリ自体ではなく、docs と project-portal を子に持つプロジェクトルートを渡す必要があります）" >&2
  fi
fi

# --- 5. テスト計測・鮮度・前回値の JSON 化 ---
if [ "$tests_raw" != "null" ]; then
  tests_count="$(echo "$tests_raw" | jq -r '.count // 0')"
  if [ "$total_lines" -gt 0 ]; then
    density="$(awk -v c="$tests_count" -v t="$total_lines" 'BEGIN{printf "%.1f", c / (t/1000)}')"
  else
    density="0.0"
  fi
  tests_json="$(echo "$tests_raw" | jq -c --argjson density "$density" '. + {density:$density}')"
else
  tests_json="null"
fi

freshness_behind="null"
freshness_note=""
if [ -n "$commit_field" ] && git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if behind_count="$(git -C "$TARGET_REPO" rev-list --count "${commit_field}..HEAD" 2>/dev/null)"; then
    freshness_behind="$behind_count"
    if [ "$behind_count" -eq 0 ]; then
      freshness_note="最新コミットと一致"
    else
      freshness_note="計測後 ${behind_count} コミット・要再計測"
    fi
  else
    # 計測時コミットが履歴に不在（rebase・squash 等で失われた場合）。
    # 事実の表示のみであり合否の判断はしない（再計測を行うかは人・フロー再実行に委ねる）。
    freshness_note="計測時コミットが履歴に不在・要再計測"
  fi
else
  # git 管理外、または commit フィールド欠落。measured_at のみが手がかり。
  freshness_note=""
fi
freshness_json="$(jq -n --arg measured_at "$measured_at" --argjson behind "$freshness_behind" --arg note "$freshness_note" \
  '{measured_at:$measured_at, behind:$behind, note:$note}')"

# --- 6. JSON 組み立て ---
scale_json="$(jq -n --argjson total "$total_lines" --argjson fe "$fe_lines" --argjson be "$be_lines" --argjson files "$total_files" --argjson kinds "$kinds_json" \
  '{total:$total, fe:$fe, be:$be, files:$files, kinds:$kinds}')"

METRICS_JSON="$(jq -n --argjson scale "$scale_json" --argjson tests "$tests_json" --argjson freshness "$freshness_json" --argjson previous "$previous_json" \
  '{scale:$scale, tests:$tests, freshness:$freshness, previous:$previous}')"

catalog_render="$(node "$CATALOG_ENGINE" render --catalog "$CATALOG" --output-root "$DOCS_ROOT" --portal-dir "$PORTAL_DIR" --output-layout "$OUTPUT_LAYOUT_RESOLVED_FILE")"
CATEGORIES_JSON="$(jq -c '.categories' <<<"$catalog_render")"
CATEGORY_SECTIONS_HTML="$(jq -r '.categories[] | "<section class=\"pm-cat\" id=\"cat-\(.id)\"></section>"' <<<"$catalog_render")"
kinds_json="$(jq -c '.kinds' <<<"$catalog_render")"

# discovery で実在が確認されたカテゴリ別カード数（写真指摘 1-98 の単一情報源）。
# シェル（サイドバー・フッター）のナビ件数・総資料数のバックフィルに使う。
shell_counts_json="$(jq -c '[.categories[] | {key: .id, count: (.tools | length)}]' <<<"$catalog_render")"

# catalogから導出した一覧件数をmetricsにも渡す。カード定義と規模表示の二重管理をしない。
scale_json="$(jq -n --argjson total "$total_lines" --argjson fe "$fe_lines" --argjson be "$be_lines" --argjson files "$total_files" --argjson kinds "$kinds_json" \
  '{total:$total, fe:$fe, be:$be, files:$files, kinds:$kinds}')"
METRICS_JSON="$(jq -n --argjson scale "$scale_json" --argjson tests "$tests_json" --argjson freshness "$freshness_json" --argjson previous "$previous_json" \
  '{scale:$scale, tests:$tests, freshness:$freshness, previous:$previous}')"

SCREEN_MANIFEST_JSON="{}"
if [ -n "$SCREEN_MANIFEST" ]; then
  SCREEN_MANIFEST_JSON="$(jq -c '.' "$SCREEN_MANIFEST")" \
    || { echo "ERROR: invalid screen manifest JSON: $SCREEN_MANIFEST" >&2; exit 1; }
  manifest_content_hash="$(jq -r '.manifestContentHash // empty' "$SCREEN_MANIFEST")"
  [[ "$manifest_content_hash" =~ ^[0-9a-f]{64}$ ]] \
    || { echo "ERROR: screen manifest must contain a 64 lowercase hex manifestContentHash" >&2; exit 1; }
fi

METRICS_JSON_SAFE="$(printf '%s' "$METRICS_JSON" | script_safe_json)"
CATEGORIES_JSON_SAFE="$(printf '%s' "$CATEGORIES_JSON" | script_safe_json)"
SCREEN_MANIFEST_JSON_SAFE="$(printf '%s' "$SCREEN_MANIFEST_JSON" | script_safe_json)"

# --- 7. テンプレート置換・出力 ---
mkdir -p "$PORTAL_DIR"

template_content="$(cat "$TEMPLATE")"
render_args=(
  "{{PROJECT_NAME}}" "$PROJECT_NAME"
  "{{GENERATED_DATE}}" "$GENERATED_DATE"
  "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
  "{{METRICS_JSON}}" "$METRICS_JSON_SAFE"
  "{{CATEGORIES_JSON}}" "$CATEGORIES_JSON_SAFE"
  "{{CATEGORY_SECTIONS_HTML}}" "$CATEGORY_SECTIONS_HTML"
  "{{SCREEN_MANIFEST_JSON}}" "$SCREEN_MANIFEST_JSON_SAFE"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../delivery-payload/templates" "$CATALOG" "index.html" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "generation-engine/scripts/build-portal.sh" "" "${SITES_FILE:-}" "${SITE_KEY:-}" "$PORTAL_DIR" "" "$shell_counts_json"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
output="$(render_template "$template_content" "${render_args[@]}")"

printf '%s' "$output" > "$PORTAL_DIR/index.html"
run_pipeline_hook "--post-build" "$POST_BUILD"
# post-build は生成完了後に任意のHTMLを追加できるため、バックフィル対象を決める前に
# 同じ対応表で再走査し、孤立した生成HTMLを残さない。--portal-only は既存契約どおり
# index.html 以外を変更しないため、対応表の作成・走査とも行わない。
if [ "$PORTAL_ONLY" -eq 0 ]; then
  remove_orphaned_common_html \
    "$PORTAL_MD_MAP_FILE" "$CATALOG" "$OUTPUT_LAYOUT_RESOLVED_FILE" "$DOCS_ROOT" "$FOUNDATION_OUT_DIR" \
    "$DOCS_ROOT/$LAYOUT_RULES_ROOT" "$DOCS_ROOT/$LAYOUT_SCREEN_VIEW_ROOT" "${common_roots[@]}"
fi
echo "OK: wrote $PORTAL_DIR/index.html" >&2
detect_stale_portal_placeholders "$LAYOUT_JSON" "$PORTAL_DIR"
detect_undefined_unit_phase_dirs "$LAYOUT_JSON" "$DOCS_ROOT"

# --- 8. シェル（サイドバー・フッター）の件数・更新日を discovery 結果で一括バックフィル ---
# 写真指摘 1-98（カード数の単一情報源化）・1-99（更新日の単一情報源化）の対応。
# unit-list / matrix / detail-pages の 5 経路は discovery を持たないため、blueprints 数で
# 暫定的にシェルを焼く。ここで DOCS_ROOT 配下の全 HTML を discovery 結果で上書きし、
# 6 経路すべての生成物を単一の情報源に揃える。
if type shell_injection_args >/dev/null 2>&1; then
  if [ "$PORTAL_ONLY" -eq 1 ]; then
    # --portal-only は index.html 以外を変更しない既存挙動（--self-test ケース13）を維持する。
    printf '%s\n' "$PORTAL_DIR/index.html" | backfill_shell_shared_state "$shell_counts_json" "$GENERATED_DATE"
  else
    # バックフィル対象はmd対応表・実在catalogページ・ポータルindexに限定する。
    # catalog未発見の別生成器ページや未知HTMLは、生成元表示の有無にかかわらず含めない。
    while IFS= read -r catalog_href; do
      [ -n "$catalog_href" ] || continue
      catalog_html_path="$(python3 -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))' \
        "$PORTAL_DIR" "$catalog_href")"
      printf 'catalog\t%s\n' "$catalog_html_path" >> "$PORTAL_MD_MAP_FILE"
    done < <(jq -r '.categories[].tools[]?.href // empty' <<< "$catalog_render")
    printf 'portal-index\t%s\n' "$PORTAL_DIR/index.html" >> "$PORTAL_MD_MAP_FILE"
    cut -f2 "$PORTAL_MD_MAP_FILE" | LC_ALL=C sort -u \
      | backfill_shell_shared_state "$shell_counts_json" "$GENERATED_DATE"
  fi
fi
# 単体配布は通常生成とシェル値のバックフィルを終えたHTMLだけを対象にする。
# 既存の生成済み文書を一括是正せず、この実行で変換対象になった単位内HTMLだけを検査・整形する。
if [ "$STANDALONE" -eq 1 ]; then
  node "$SCRIPT_DIR/prepare-standalone-units.mjs" --prepare "$DOCS_ROOT" \
    || { echo "ERROR: standalone unit preparation failed" >&2; exit 1; }
fi

if [ "${PORTAL_ONLY:-0}" -eq 0 ]; then
  rm -f "$PORTAL_MD_MAP_FILE"
  unset PORTAL_MD_MAP_FILE
fi
rm -f "$OUTPUT_LAYOUT_RESOLVED_FILE" "$OUTPUT_LAYOUT_VALUES_FILE"
trap - EXIT
