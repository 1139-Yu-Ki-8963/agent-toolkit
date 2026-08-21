#!/usr/bin/env bash
# 抽出エンジン: 画面マニフェスト(screen-manifest.json)へのメタデータ追加抽出。
# 入力マニフェストの既存フィールドは一切変更せず、ヒューリスティックで抽出できた
# フィールドだけを screens[] の各要素に追加した拡張マニフェストを出力する。
# 検出根拠が弱い値は出力しない(誤った値より欠落を優先する fail-safe)。
#
# Usage: extract-screen-metadata.sh <screen-manifest.json> <source-dir> <output.json> \
#          [--api-manifest <api-manifest.json>] [--design-docs-dir <dir>] \
#          [--link-base-dir <dir>] [--doc-view-dir <dir>] [--doc-view-link-base-dir <dir>] \
#          [--generated-at <iso8601>] [--manifest-content-hash <sha256>]
#
# 入力契約:
#   <screen-manifest.json> : validate-manifest.sh --unit-kind screen をPASSする画面マニフェスト
#   <source-dir>           : 原本ソースのルート。screens[].entryFile 等の相対パスの解決基点
#   --api-manifest         : unitKind=api のマニフェスト。relatedApis を unitKey に解決する
#   --design-docs-dir      : 設計書リポジトリ側のディレクトリ（定義の置き場。screenUnitRoot）。
#                            designDocStatus・testCasePath・観点表・シナリオ・confirmedScreenName
#                            の判定元
#   --link-base-dir        : 一覧HTMLを置くディレクトリ。--design-docs-dir 側のリンクを
#                            このディレクトリからの相対パスにする。省略時は従来どおり
#                            --design-docs-dir 配下の相対パスを返す
#   --doc-view-dir         : 人が読むHTMLの置き場（screenViewRoot。project-portal/画面等）。
#                            designDocPath/detailDocPath/sequencePath はこちらを実在判定の基点にする。
#                            未指定なら --design-docs-dir と同一ツリーとして扱う（co-locate互換）
#   --doc-view-link-base-dir : 一覧HTMLを置くディレクトリ。--doc-view-dir 側のリンクをこの
#                            ディレクトリからの相対パスにする。--doc-view-dir 必須
#
# 出力契約(<output.json>):
#   入力マニフェストと同一構造 + screens[] 各要素への追加フィールド。
#   スキーマ正本: delivery-payload/references/manifest-schema-extensions.md「screens(画面)」表。
#   出力は validate-manifest.sh --unit-kind screen で検証可能(全8項目PASS)。
#
# 追加フィールドと検出ヒューリスティック(何を grep するか):
#   category      : route の先頭 prefix 判定。route が "/admin" または "/admin/..." なら「管理」、
#                   それ以外の非空 route なら「一般」。route 不在(unresolved 等)なら付けない
#   permissions   : 構成ファイル(files[] があればそれ、無ければ entryFile/sourceFile/mainFile)内を grep:
#                     - requireRole('x') / requireRole("x")
#                     - hasRole('x') / hasRole("x")
#                     - roles: ['x', 'y'] / roles: ["x"]
#                     - @RolesAllowed("x") / @RolesAllowed({"x","y"})
#                   からロール名を収集。検出なし かつ category=管理 なら ["admin"] を推定値として
#                   付与、category=一般 で検出なしなら [] を付与。category 不明かつ検出なしなら付けない
#   relatedApis   : 構成ファイル内の fetch( / axios. / apiClient. を含む行から
#                   '/api/...' のパス文字列(クォート囲み)を収集(クエリ文字列 ?以降 は除去)。
#                   加えて、パスを変数で受け取る共通のクライアント関数(例: fetch(`${BASE}${path}`)
#                   のように2箇所の変数展開でURLを組み立てる関数)を経由する呼び方も解決する
#                   (改善課題「画面とAPIの対応づけ-担当不在」)。SOURCE_DIR 全体から
#                   build_api_client_map がそのようなラッパー関数と、それを呼ぶ
#                   `<namespace>: { <method>: (...) => wrapper('/path...') }` 形式の
#                   ネストしたオブジェクトリテラルを検出し、`<namespace>.<method>(` を鍵とする
#                   解決済みパスの対応表を作る。ページ側ファイルがこの鍵を含む呼び出し
#                   (`api.teams.list()` 等)を持てば、対応表のパスを relatedApis に採用する。
#                   同名メソッドが唯一の namespace でしか使われていない場合に限り、
#                   `.method(` という namespace 不問の鍵でも解決する(複数 namespace で同名
#                   メソッドが異なるパスを持つ場合はあいまいとして対応表に載せない)。
#                   扱える形: ラッパー関数が `fetch(\`${A}${B}\`` の形で1個のパス引数変数と
#                   1個の定数(文字列リテラルで解決できるもの)を連結している場合。
#                   扱えない形: ラッパー呼び出しが複数行に渡る、BASE 相当の定数が
#                   `import.meta.env.*` 等の実行時解決値である(この場合 prefix なしでパスを
#                   出力する)、3階層以上の namespace 入れ子、非UTF-8原本(この解析経路は
#                   to_utf8_for_scan を通さず直接読む)。
#                   --api-manifest 指定時は units[].identifier のパス部(空白区切りで '/' 始まりの
#                   トークン)と完全一致で突合して unitKey に解決する(解決できないパスは捨てる)。
#                   未指定なら収集パスをそのまま格納。収集 0 件ならフィールド自体を付けない
#   designDocStatus: --design-docs-dir 配下に <screenKey> 名のフォルダ/ファイル
#                   (または <screenKey>.* ファイル)が実在すれば「着手済」、無ければ「未着手」。
#                   オプション未指定ならフィールド自体を付けない
#   designDocPath / detailDocPath / sequencePath / testCasePath / unitTestViewpointPath /
#   integrationTestViewpointPath / integrationTestCasePath / scenarioPath:
#                   --design-docs-dir 配下の画面フォルダ(<screenKey> または screen-<screenKey>)内で
#                   以下のファイル実在を個別に判定し、実在するものだけを画面フォルダからの相対パスで付与する
#                   (1画面あたり読者向け成果物8種類の全量。テスト項目書・観点表はHTML化せずmd参照で統一する):
#                     基本設計/画面基本設計書.html       → designDocPath
#                     詳細設計/画面詳細設計書.html       → detailDocPath
#                     シーケンス図.html                   → sequencePath
#                     テスト設計/画面単体テスト設計書.md   → testCasePath / unitTestViewpointPath
#                     テスト設計/画面テスト設計書.md       → integrationTestViewpointPath / integrationTestCasePath
#                     テスト設計/操作シナリオ仕様書.md     → scenarioPath
#                   新配置がない既存生成物では、旧配置のテスト項目書・詳細設計配下を
#                   上記フィールドの後方互換fallbackとして使う
#                   画面フォルダ自体が不在、またはファイルが不在ならそのフィールドは付けない
#   confirmedScreenName:
#                   画面フォルダの基本設計書または詳細設計書の先頭見出しから確定画面名を
#                   読み取り、推定名 screenNameGuess を上書きせず別フィールドで付与する
#   sourceHash    : 構成ファイル(実在するもの)を列挙順に連結した sha256 の先頭12桁。
#                   実在ファイル 0 件ならフィールド自体を付けない
#
# 全追加フィールドは任意フィールド(manifest-schema-extensions.md の段階的移行方針)。
# 抽出できないフィールドは付けない = 任意フィールドの欠落として扱われる。

set -euo pipefail

# ---------------------------------------------------------------------------
# sha256 コマンド解決(macOS: shasum -a 256 / Linux: sha256sum)
# ---------------------------------------------------------------------------
sha256_12() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-12
  else
    sha256sum | cut -c1-12
  fi
}

# ---------------------------------------------------------------------------
# ロール名収集。引数: 実在する構成ファイル群。標準出力: 1行1ロール(重複排除済み)
# ---------------------------------------------------------------------------
extract_roles() {
  [ $# -eq 0 ] && return 0
  {
    grep -hoE "requireRole\([[:space:]]*['\"][A-Za-z0-9_-]+['\"]" "$@" 2>/dev/null || true
    grep -hoE "hasRole\([[:space:]]*['\"][A-Za-z0-9_-]+['\"]" "$@" 2>/dev/null || true
    grep -hoE "roles[[:space:]]*:[[:space:]]*\[[^]]*\]" "$@" 2>/dev/null || true
    grep -hoE "@RolesAllowed\([^)]*\)" "$@" 2>/dev/null || true
  } | { grep -oE "['\"][A-Za-z0-9_-]+['\"]" || true; } \
    | sed "s/^['\"]//; s/['\"]\$//" | sort -u
}

# ---------------------------------------------------------------------------
# API パス収集。引数: 実在する構成ファイル群。標準出力: 1行1パス(重複排除済み)
# ---------------------------------------------------------------------------
extract_api_paths() {
  [ $# -eq 0 ] && return 0
  { grep -hE 'fetch\(|axios\.|apiClient\.' "$@" 2>/dev/null || true; } \
    | { grep -oE "[\"'\`]/api/[^\"'\`]+[\"'\`]" || true; } \
    | sed -e "s/^[\"'\`]//" -e "s/[\"'\`]\$//" -e 's/[?].*$//' \
    | sort -u
}

# ---------------------------------------------------------------------------
# 共通クライアント関数(パスを変数で受け取る fetch ラッパー)経由の API 呼び出し解決。
# build_api_client_map <source-dir> <out.tsv> : source-dir 全体を走査し、
#   "<検索文字列(TAB)解決済みパス>" の行を out.tsv へ書く。検索文字列は
#   "<namespace>.<method>(" または(namespace が一意なら)".<method>(" の形。
# 判定不能(python3 不在・解析失敗)時は空ファイルを返す(fail-safe)。
# ---------------------------------------------------------------------------
build_api_client_map() {
  local src="$1" out="$2"
  python3 - "$src" "$out" <<'PYEOF'
import os
import re
import sys

source_dir, out_path = sys.argv[1], sys.argv[2]
exts = ('.ts', '.tsx', '.js', '.jsx')

files = []
for root, _dirs, fnames in os.walk(source_dir):
    if 'node_modules' in root.split(os.sep):
        continue
    for fn in fnames:
        if fn.endswith(exts):
            files.append(os.path.join(root, fn))

func_re = re.compile(r'^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^>]*>)?\s*\(([^)]*)\)')
arrow_re = re.compile(r'^\s*(?:export\s+)?const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^=]*>)?\s*=\s*(?:async\s*)?\(([^)]*)\)\s*(?::[^=]*)?=>')
fetch_var_re = re.compile(r'fetch\(\s*`\$\{([A-Za-z_$][A-Za-z0-9_$]*)\}\$\{([A-Za-z_$][A-Za-z0-9_$]*)\}')

file_lines = {}
wrappers = {}  # wrapper_name -> base_prefix (str, '' if unresolved)

for f in files:
    try:
        with open(f, 'r', encoding='utf-8', errors='ignore') as fh:
            lines = fh.readlines()
    except OSError:
        continue
    file_lines[f] = lines
    cur_name = None
    cur_params = []
    depth = 0
    in_func = False
    for line in lines:
        if not in_func:
            m = func_re.match(line) or arrow_re.match(line)
            if m:
                cur_name = m.group(1)
                params_raw = m.group(2)
                cur_params = [
                    p.strip().split(':')[0].split('=')[0].strip()
                    for p in params_raw.split(',') if p.strip()
                ]
                depth = line.count('{') - line.count('}')
                in_func = depth > 0
                if not in_func:
                    cur_name = None
            continue
        depth += line.count('{') - line.count('}')
        fm = fetch_var_re.search(line)
        if fm and cur_name:
            a, b = fm.group(1), fm.group(2)
            base_name = b if a in cur_params else (a if b in cur_params else None)
            if base_name is not None:
                base_val = ''
                cre = re.compile(r'^\s*(?:export\s+)?const\s+' + re.escape(base_name) + r'\s*(?::[^=]*)?=\s*[\'"]([^\'"]*)[\'"]')
                for l2 in lines:
                    mm = cre.match(l2)
                    if mm:
                        base_val = mm.group(1)
                        break
                wrappers[cur_name] = base_val
        if depth <= 0:
            in_func = False
            cur_name = None

method_re = re.compile(r'^(\s*)([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*(?:async\s*)?(?:\([^)]*\)\s*(?::[^=]*)?=>|function)')
ns_re = re.compile(r'^(\s*)([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*\{\s*$')

entries = {}  # (ns, method) -> set(path)
bare = {}     # method -> set(path)

for wname, base_val in wrappers.items():
    call_re = re.compile(r'\b' + re.escape(wname) + r'\s*(?:<[^>]*>)?\s*\(\s*(`([^`]*)`|\'([^\']*)\'|"([^"]*)")')
    for _f, lines in file_lines.items():
        for idx, line in enumerate(lines):
            m = call_re.search(line)
            if not m:
                continue
            lit = next((g for g in m.groups()[1:] if g is not None), None)
            if not lit or not lit.startswith('/'):
                continue
            dpos = lit.find('${')
            prefix = lit[:dpos] if dpos != -1 else lit
            prefix = prefix.split('?')[0]
            if not prefix or prefix == '/':
                continue
            full_path = base_val + prefix

            method_name = None
            method_indent = None
            found_j = None
            for j in range(idx, -1, -1):
                mm = method_re.match(lines[j])
                if mm:
                    method_indent = len(mm.group(1))
                    method_name = mm.group(2)
                    found_j = j
                    break
            if method_name is None:
                continue
            bare.setdefault(method_name, set()).add(full_path)

            ns_name = None
            if found_j is not None:
                for j2 in range(found_j - 1, -1, -1):
                    nm = ns_re.match(lines[j2])
                    if nm and len(nm.group(1)) < method_indent:
                        ns_name = nm.group(2)
                        break
            if ns_name:
                entries.setdefault((ns_name, method_name), set()).add(full_path)

out_lines = []
for (ns, method), paths in entries.items():
    if len(paths) == 1:
        out_lines.append('{}.{}(\t{}'.format(ns, method, next(iter(paths))))
for method, paths in bare.items():
    if len(paths) == 1:
        out_lines.append('.{}(\t{}'.format(method, next(iter(paths))))

with open(out_path, 'w', encoding='utf-8') as fh:
    for line in sorted(set(out_lines)):
        fh.write(line + '\n')
PYEOF
}

# ---------------------------------------------------------------------------
# クライアント関数対応表(build_api_client_mapの出力)を使い、対象ファイル群が
# 対応表の検索文字列を含んでいれば解決済みパスを1行1件で返す(重複排除済み)。
# 検索文字列1件ごとにgrepを起動すると画面数×対応表件数の回数だけプロセスを
# fork し、実測(画面35件×対応表159件の対象アプリ)で実行時間が
# 20秒→2分超に劣化した。事前に切り出した検索文字列一覧(patterns_file、
# build_api_client_mapと同時に1回だけ作る)を渡し、grep -f で対象ファイル群を
# 1回だけ走査して一致した検索文字列を求め、map_fileへのパス引き当てはawkで行う。
# ---------------------------------------------------------------------------
resolve_wrapper_api_paths() {
  local map_file="$1" patterns_file="$2"
  shift 2
  [ ! -s "$map_file" ] && return 0
  [ ! -s "$patterns_file" ] && return 0
  [ $# -eq 0 ] && return 0
  local matched_file
  matched_file="$(mktemp "${TMPDIR:-/tmp}/api-client-matched.XXXXXX")"
  grep -Fhof "$patterns_file" "$@" 2>/dev/null | sort -u > "$matched_file"
  if [ ! -s "$matched_file" ]; then
    rm -f "$matched_file"
    return 0
  fi
  # awk への複数行文字列の -v 渡しはBSD awk(macOS標準)で "newline in string" エラーに
  # なるため、一致した検索文字列は一時ファイル経由の2ファイル入力(NR==FNRの照合)で渡す。
  awk -F'\t' '
    NR == FNR { want[$0] = 1; next }
    ($1 in want) { print $2 }
  ' "$matched_file" "$map_file" | sort -u
  rm -f "$matched_file"
}

# ---------------------------------------------------------------------------
# --self-test モード
# mktemp -d にフィクスチャ(React 風 tsx 2画面 + 最小 screen-manifest + api-manifest +
# 設計書ディレクトリ)を生成して本体を実行し、jq で期待フィールド値を検証する。
# ---------------------------------------------------------------------------
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-screen-metadata-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # --- フィクスチャ: React 風 tsx 2画面 ---
  mkdir -p "$tmp/src/screens/admin" "$tmp/src/screens"
  cat > "$tmp/src/screens/admin/UserAdmin.tsx" <<'EOF'
import { requireRole } from "../auth";
export function UserAdmin() {
  requireRole('admin');
  const load = () => fetch('/api/users').then((r) => r.json());
  return null;
}
EOF
  cat > "$tmp/src/screens/Home.tsx" <<'EOF'
export function Home() {
  return null;
}
EOF

  # --- フィクスチャ: 共通クライアント関数(パスを変数で受け取るfetchラッパー)経由の画面
  #     (改善課題「画面とAPIの対応づけ-担当不在」再現。修正前は本パターンでrelatedApisが
  #     0件のままになることを確認済み) ---
  mkdir -p "$tmp/src/api"
  cat > "$tmp/src/api/client.ts" <<'EOF'
const BASE = '/api'
async function req(path) {
  const res = await fetch(`${BASE}${path}`)
  return res.json()
}
export const api = {
  teams: {
    list: () => req('/teams'),
  },
}
EOF
  cat > "$tmp/src/screens/TeamRanking.tsx" <<'EOF'
import { api } from '../api/client'
export function TeamRanking() {
  api.teams.list()
  return null;
}
EOF

  # --- フィクスチャ: 最小 screen-manifest ---
  local manifest="$tmp/screen-manifest.json"
  cat > "$manifest" <<JSON
{
  "generatedAt": "2026-01-01T00:00:00Z",
  "sourceDir": "$tmp/src",
  "strategy": {
    "extractionMethod": "custom",
    "approvedByUser": true,
    "screenIdRegex": null,
    "excludePatterns": []
  },
  "detectionSummary": {
    "screenCount": 4,
    "clusterCount": 0,
    "sharedScreenCount": 0,
    "embeddedCandidateCount": 0,
    "unresolvedCount": 0
  },
  "screens": [
    {
      "screenKey": "user-admin",
      "kind": "route",
      "route": "/admin/users",
      "entryFile": "screens/admin/UserAdmin.tsx",
      "confidence": "high",
      "screenType": "top",
      "accountGroup": "admin",
      "accountSubType": "common",
      "hasTemplate": true,
      "parentScreen": null,
      "childComponents": [],
      "isProcessingEndpoint": false
    },
    {
      "screenKey": "home",
      "kind": "route",
      "route": "/home",
      "entryFile": "screens/Home.tsx",
      "confidence": "high",
      "screenType": "top",
      "accountGroup": "user",
      "accountSubType": "common",
      "hasTemplate": true,
      "parentScreen": null,
      "childComponents": [],
      "isProcessingEndpoint": false
    },
    {
      "screenKey": "partial-screen",
      "kind": "route",
      "route": "/partial",
      "entryFile": "screens/Home.tsx",
      "confidence": "high",
      "screenType": "top",
      "accountGroup": "user",
      "accountSubType": "common",
      "hasTemplate": true,
      "parentScreen": null,
      "childComponents": [],
      "isProcessingEndpoint": false
    },
    {
      "screenKey": "team-ranking",
      "kind": "route",
      "route": "/team-ranking",
      "entryFile": "screens/TeamRanking.tsx",
      "confidence": "high",
      "screenType": "top",
      "accountGroup": "user",
      "accountSubType": "common",
      "hasTemplate": true,
      "parentScreen": null,
      "childComponents": [],
      "isProcessingEndpoint": false
    }
  ]
}
JSON

  # --- フィクスチャ: api-manifest(unitKey 解決用) / 設計書ディレクトリ ---
  local api_manifest="$tmp/api-manifest.json"
  cat > "$api_manifest" <<'JSON'
{
  "unitKind": "api",
  "units": [
    {"unitKey": "users-list", "kind": "endpoint", "identifier": "GET /api/users"},
    {"unitKey": "teams-list", "kind": "endpoint", "identifier": "GET /api/teams"}
  ]
}
JSON
  local docs_root="$tmp/output/画面"
  local list_dir="$tmp/output/一覧/画面一覧"
  mkdir -p \
    "$docs_root/screen-user-admin/基本設計" \
    "$docs_root/screen-user-admin/詳細設計" \
    "$docs_root/screen-user-admin/テスト項目書" \
    "$docs_root/screen-user-admin/テスト設計" \
    "$docs_root/screen-partial-screen/基本設計" \
    "$docs_root/screen-partial-screen/テスト項目書" \
    "$list_dir"
  cat > "$docs_root/screen-user-admin/基本設計/画面基本設計書.md" <<'EOF'
# 確定ユーザー管理 画面基本設計書
EOF
  # --- 新配置優先: 新体系と旧配置の両方があるときは新体系を選ぶ ---
  : > "$docs_root/screen-user-admin/基本設計/画面基本設計書.html"
  : > "$docs_root/screen-user-admin/詳細設計/画面詳細設計書.html"
  : > "$docs_root/screen-user-admin/シーケンス図.html"
  : > "$docs_root/screen-user-admin/テスト設計/画面単体テスト設計書.md"
  : > "$docs_root/screen-user-admin/テスト設計/画面テスト設計書.md"
  : > "$docs_root/screen-user-admin/テスト設計/操作シナリオ仕様書.md"
  : > "$docs_root/screen-user-admin/テスト項目書/単体テスト仕様書.md"
  : > "$docs_root/screen-user-admin/詳細設計/単体テスト観点表.md"
  : > "$docs_root/screen-user-admin/詳細設計/結合テスト観点表.md"
  : > "$docs_root/screen-user-admin/テスト項目書/結合テスト仕様書.md"
  : > "$docs_root/screen-user-admin/テスト項目書/操作シナリオ仕様書.md"
  # --- 旧配置fallback: 新体系がないときは実在する旧ファイルだけを採用 ---
  : > "$docs_root/screen-partial-screen/基本設計/画面基本設計書.html"
  : > "$docs_root/screen-partial-screen/テスト項目書/結合テスト仕様書.md"

  check() {
    local label="$1" expr="$2" file="$3"
    if [ "$(jq -r "$expr" "$file")" = "true" ]; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label — jq: $expr" >&2
      rc=1
    fi
  }

  # --- ケースa: オプションなし(relatedApis は生パス格納) ---
  local out_a="$tmp/out-a.json"
  if _gt_out2="$(bash "$script_path" "$manifest" "$tmp/src" "$out_a" 2>&1)"; then
    check "ケースa: 管理画面 category=管理" '.screens[0].category == "管理"' "$out_a"
    check "ケースa: 管理画面 permissions=[\"admin\"](requireRole検出)" '.screens[0].permissions == ["admin"]' "$out_a"
    check "1-170: requireRole検出 permissions は valueProvenance=measured" '.screens[0].valueProvenance.permissions == "measured"' "$out_a"
    check "ケースa: 管理画面 relatedApis=[\"/api/users\"](生パス)" '.screens[0].relatedApis == ["/api/users"]' "$out_a"
    check "ケースa: 管理画面 sourceHash が12桁hex" '.screens[0].sourceHash | test("^[0-9a-f]{12}$")' "$out_a"
    check "ケースa: 一般画面 category=一般" '.screens[1].category == "一般"' "$out_a"
    check "ケースa: 一般画面 permissions=[](検出なし)" '.screens[1].permissions == []' "$out_a"
    check "1-170: 一般画面の[]推定 permissions は valueProvenance=inferred" '.screens[1].valueProvenance.permissions == "inferred"' "$out_a"
    check "ケースa: 一般画面 relatedApis 欠落(fetchなし)" '.screens[1] | has("relatedApis") | not' "$out_a"
    check "ケースa: designDocStatus 欠落(オプション未指定)" '[.screens[] | has("designDocStatus")] | any | not' "$out_a"
    check "ケースa: 既存フィールド無変更" '(.screens[0].route == "/admin/users") and (.screens[1].entryFile == "screens/Home.tsx") and (.detectionSummary.screenCount == 4)' "$out_a"
    check "画面とAPIの対応づけ-担当不在: 共通クライアント関数経由のrelatedApis=[\"/api/teams\"](生パス、修正前は0件)" '.screens[3].relatedApis == ["/api/teams"]' "$out_a"
  else
    echo "  [FAIL] ケースa: 抽出コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースb: --api-manifest + --design-docs-dir 指定 ---
  local out_b="$tmp/out-b.json"
  if _gt_out3="$(bash "$script_path" "$manifest" "$tmp/src" "$out_b" \
      --api-manifest "$api_manifest" --design-docs-dir "$docs_root" \
      --link-base-dir "$list_dir" 2>&1)"; then
    check "ケースb: relatedApis が unitKey に解決" '.screens[0].relatedApis == ["users-list"]' "$out_b"
    check "画面とAPIの対応づけ-担当不在: 共通クライアント関数経由のrelatedApisもunitKeyに解決" '.screens[3].relatedApis == ["teams-list"]' "$out_b"
    check "ケースb: 管理画面 designDocStatus=着手済" '.screens[0].designDocStatus == "着手済"' "$out_b"
    check "ケースb: 一般画面 designDocStatus=未着手" '.screens[1].designDocStatus == "未着手"' "$out_b"
    check "1-221: 新配置を優先し、旧配置はfallbackとして一覧基準の相対パスで付与" '
      .screens[0].designDocPath == "../../画面/screen-user-admin/基本設計/画面基本設計書.html"
      and .screens[0].detailDocPath == "../../画面/screen-user-admin/詳細設計/画面詳細設計書.html"
      and .screens[0].sequencePath == "../../画面/screen-user-admin/シーケンス図.html"
      and .screens[0].testCasePath == "../../画面/screen-user-admin/テスト設計/画面単体テスト設計書.md"
      and .screens[0].unitTestViewpointPath == "../../画面/screen-user-admin/テスト設計/画面単体テスト設計書.md"
      and .screens[0].integrationTestViewpointPath == "../../画面/screen-user-admin/テスト設計/画面テスト設計書.md"
      and .screens[0].integrationTestCasePath == "../../画面/screen-user-admin/テスト設計/画面テスト設計書.md"
      and .screens[0].scenarioPath == "../../画面/screen-user-admin/テスト設計/操作シナリオ仕様書.md"
      and (.screens[1] | has("designDocPath") | not)
      and (.screens[1] | has("detailDocPath") | not)
      and (.screens[1] | has("sequencePath") | not)
      and (.screens[1] | has("testCasePath") | not)
      and (.screens[1] | has("unitTestViewpointPath") | not)
      and (.screens[1] | has("integrationTestViewpointPath") | not)
      and (.screens[1] | has("integrationTestCasePath") | not)
      and (.screens[1] | has("scenarioPath") | not)
    ' "$out_b"
    check "1-41: 設計書見出しの確定画面名を書き戻し、推定名は保持" '
      .screens[0].confirmedScreenName == "確定ユーザー管理"
      and (.screens[0].screenNameGuess | not)
    ' "$out_b"
    check "1-221: 新体系がない一部欠落フィクスチャは旧配置をfallbackとして維持" '
      .screens[2].designDocPath == "../../画面/screen-partial-screen/基本設計/画面基本設計書.html"
      and .screens[2].integrationTestCasePath == "../../画面/screen-partial-screen/テスト項目書/結合テスト仕様書.md"
      and (.screens[2] | has("detailDocPath") | not)
      and (.screens[2] | has("sequencePath") | not)
      and (.screens[2] | has("testCasePath") | not)
      and (.screens[2] | has("unitTestViewpointPath") | not)
      and (.screens[2] | has("integrationTestViewpointPath") | not)
      and (.screens[2] | has("scenarioPath") | not)
    ' "$out_b"
  else
    echo "  [FAIL] ケースb: 抽出コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 出力が validate-manifest.sh で検証可能であること ---
  local validator="$script_dir/../unit-list/validate-manifest.sh"
  if _gt_out4="$(bash "$validator" "$out_b" --unit-kind screen 2>&1)"; then
    echo "  [PASS] validate-manifest.sh: 拡張マニフェストが全項目PASS"
  else
    echo "  [FAIL] validate-manifest.sh: 拡張マニフェストが検証FAIL" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 1-93: 抽出→一覧生成のフルパイプラインを同一フィクスチャで通し、最終HTMLへ8リンクが反映されること ---
  local builder="$script_dir/../unit-list/build-screen-list.sh"
  local pipeline_html="$tmp/pipeline-screen-list.html"
  if [ -f "$builder" ] && bash "$builder" "$out_b" "$pipeline_html" >/dev/null 2>&1; then
    if grep -Fq '../../画面/screen-user-admin/基本設計/画面基本設計書.html' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/詳細設計/画面詳細設計書.html' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/シーケンス図.html' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/テスト設計/画面単体テスト設計書.md' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/テスト設計/画面単体テスト設計書.md' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/テスト設計/画面テスト設計書.md' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/テスト設計/画面テスト設計書.md' "$pipeline_html" \
      && grep -Fq '../../画面/screen-user-admin/テスト設計/操作シナリオ仕様書.md' "$pipeline_html"; then
      echo "  [PASS] 1-93: 抽出→一覧生成のフルパイプラインで8種類リンクが最終HTMLへ反映"
    else
      echo "  [FAIL] 1-93: フルパイプライン出力に8種類リンクが反映されていない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-93: build-screen-list.sh を通したフルパイプライン実行自体が失敗した" >&2
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

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
USAGE="Usage: extract-screen-metadata.sh <screen-manifest.json> <source-dir> <output.json> [--api-manifest <api-manifest.json>] [--design-docs-dir <dir>] [--link-base-dir <dir>] [--doc-view-dir <dir>] [--doc-view-link-base-dir <dir>] [--generated-at <iso8601>] [--manifest-content-hash <sha256>] [--rules-file <json>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT="${3:?$USAGE}"
shift 3 || true

API_MANIFEST=""
DESIGN_DOCS_DIR=""
LINK_BASE_DIR=""
DOC_VIEW_DIR=""
DOC_VIEW_LINK_BASE_DIR=""
GENERATED_AT=""
MANIFEST_CONTENT_HASH=""
EXTRACTION_RULES_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --api-manifest)
      API_MANIFEST="${2:-}"
      shift 2
      ;;
    --design-docs-dir)
      DESIGN_DOCS_DIR="${2:-}"
      shift 2
      ;;
    --link-base-dir)
      LINK_BASE_DIR="${2:-}"
      shift 2
      ;;
    --doc-view-dir)
      DOC_VIEW_DIR="${2:-}"
      shift 2
      ;;
    --doc-view-link-base-dir)
      DOC_VIEW_LINK_BASE_DIR="${2:-}"
      shift 2
      ;;
    --generated-at)
      GENERATED_AT="${2:-}"
      shift 2
      ;;
    --manifest-content-hash)
      MANIFEST_CONTENT_HASH="${2:-}"
      shift 2
      ;;
    --rules-file)
      EXTRACTION_RULES_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "$USAGE" >&2
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
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
if [ -n "$API_MANIFEST" ] && [ ! -f "$API_MANIFEST" ]; then
  echo "ERROR: api-manifest not found: $API_MANIFEST" >&2
  exit 1
fi
# 標準フローでは一覧を先に作り、設計書ディレクトリを後から展開する。
# そのため両ディレクトリは未作成でも許可し、全画面を未着手として扱う。
if [ -n "$LINK_BASE_DIR" ] && [ -z "$DESIGN_DOCS_DIR" ]; then
  echo "ERROR: --link-base-dir requires --design-docs-dir" >&2
  exit 1
fi
if [ -n "$DOC_VIEW_LINK_BASE_DIR" ] && [ -z "$DOC_VIEW_DIR" ]; then
  echo "ERROR: --doc-view-link-base-dir requires --doc-view-dir" >&2
  exit 1
fi
if { [ -n "$GENERATED_AT" ] && [ -z "$MANIFEST_CONTENT_HASH" ]; } \
  || { [ -z "$GENERATED_AT" ] && [ -n "$MANIFEST_CONTENT_HASH" ]; }; then
  echo "ERROR: --generated-at and --manifest-content-hash must be specified together" >&2
  exit 1
fi
if [ -n "$MANIFEST_CONTENT_HASH" ] \
  && ! printf '%s' "$MANIFEST_CONTENT_HASH" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "ERROR: --manifest-content-hash must be 64 lowercase hex" >&2
  exit 1
fi

DESIGN_DOCS_LINK_PREFIX=""
if [ -n "$DESIGN_DOCS_DIR" ] && [ -n "$LINK_BASE_DIR" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required when --link-base-dir is specified" >&2
    exit 1
  fi
  DESIGN_DOCS_LINK_PREFIX="$(python3 -c '
import os
import sys

relative = os.path.relpath(
    os.path.abspath(sys.argv[2]),
    os.path.abspath(sys.argv[1]),
)
sys.stdout.write(relative.replace(os.sep, "/"))
' "$LINK_BASE_DIR" "$DESIGN_DOCS_DIR")"
fi

# doc-view側(project-portal/画面等、人が読むHTMLの置き場)は design-docs側(定義の置き場)と
# 物理的に別ツリーになりうるため、designDocPath/detailDocPath/sequencePath だけ別ルート・
# 別リンク基点で解決する。未指定時は従来どおり design-docs 側と同一ツリーとして扱う
# (co-locate の後方互換)。
DOC_VIEW_DOCS_DIR="${DOC_VIEW_DIR:-$DESIGN_DOCS_DIR}"
DOC_VIEW_LINK_PREFIX="$DESIGN_DOCS_LINK_PREFIX"
if [ -n "$DOC_VIEW_DIR" ] && [ -n "$DOC_VIEW_LINK_BASE_DIR" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required when --doc-view-link-base-dir is specified" >&2
    exit 1
  fi
  DOC_VIEW_LINK_PREFIX="$(python3 -c '
import os
import sys

relative = os.path.relpath(
    os.path.abspath(sys.argv[2]),
    os.path.abspath(sys.argv[1]),
)
sys.stdout.write(relative.replace(os.sep, "/"))
' "$DOC_VIEW_LINK_BASE_DIR" "$DOC_VIEW_DOCS_DIR")"
elif [ -n "$DOC_VIEW_DIR" ]; then
  DOC_VIEW_LINK_PREFIX=""
fi

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_SCREEN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_SCREEN_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-screen-metadata-scan.XXXXXX")"

TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/extract-screen-metadata.XXXXXX")"
trap 'rm -rf "$TMP_WORK" "$SCAN_WORKDIR"' EXIT
ADDS_FILE="$TMP_WORK/adds.jsonl"
: > "$ADDS_FILE"

# --- 共通クライアント関数(パスを変数で受け取るfetchラッパー)対応表をSOURCE_DIR全体から
#     1回だけ構築する(改善課題「画面とAPIの対応づけ-担当不在」)。python3不在時は空表(fail-safe) ---
API_CLIENT_MAP="$TMP_WORK/api-client-map.tsv"
API_CLIENT_PATTERNS="$TMP_WORK/api-client-patterns.txt"
: > "$API_CLIENT_MAP"
: > "$API_CLIENT_PATTERNS"
if command -v python3 >/dev/null 2>&1; then
  build_api_client_map "$SOURCE_DIR" "$API_CLIENT_MAP" 2>/dev/null || : > "$API_CLIENT_MAP"
fi
cut -f1 "$API_CLIENT_MAP" > "$API_CLIENT_PATTERNS" 2>/dev/null || : > "$API_CLIENT_PATTERNS"

# ---------------------------------------------------------------------------
# 画面ごとの抽出ループ(1行1JSONオブジェクトで受け取り、jqで各フィールドを引く)
# ---------------------------------------------------------------------------
index=0
while IFS= read -r row; do
  [ -z "$row" ] && { index=$((index + 1)); continue; }

  screen_key="$(jq -r '.screenKey // ""' <<<"$row")"
  route="$(jq -r '.route // ""' <<<"$row")"

  # --- 構成ファイルの解決(files[] 優先、無ければ entryFile/sourceFile/mainFile) ---
  existing_files=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "${f#/}" != "$f" ]; then
      resolved="$f"
    else
      resolved="$SOURCE_DIR/$f"
    fi
    [ -f "$resolved" ] && existing_files+=("$resolved")
  done < <(jq -r 'if ((.files // []) | length) > 0 then .files[] else (.entryFile // .sourceFile // .mainFile // empty) end' <<<"$row")

  # scan_files: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。existing_files自体は
  # sourceHash算出(原本バイト列のハッシュ)に使うため変更しない。grep走査には常にscan_filesを使う
  scan_files=()
  for ef in ${existing_files[@]+"${existing_files[@]}"}; do
    scan_files+=("$(to_utf8_for_scan "$ef" "$SCAN_WORKDIR")")
  done

  add='{}'

  # --- 1. category: route の先頭 prefix 判定 ---
  category=""
  if [ -n "$route" ]; then
    case "$route" in
      /admin | /admin/*) category="管理" ;;
      *)                 category="一般" ;;
    esac
    add="$(jq --arg v "$category" '. + {category: $v}' <<<"$add")"
  fi

  # --- 2. permissions: ロール名 grep 収集 + category ベースの推定 ---
  roles="$(extract_roles ${scan_files[@]+"${scan_files[@]}"})"
  if [ -n "$roles" ]; then
    roles_json="$(printf '%s\n' "$roles" | jq -R 'select(length > 0)' | jq -s .)"
    add="$(jq --argjson v "$roles_json" '. + {permissions: $v}' <<<"$add")"
    add="$(jq '. + {valueProvenance: ((.valueProvenance // {}) + {permissions: "measured"})}' <<<"$add")"
  elif [ "$category" = "管理" ]; then
    add="$(jq '. + {permissions: ["admin"]}' <<<"$add")"
    add="$(jq '. + {valueProvenance: ((.valueProvenance // {}) + {permissions: "inferred"})}' <<<"$add")"
  elif [ "$category" = "一般" ]; then
    add="$(jq '. + {permissions: []}' <<<"$add")"
    add="$(jq '. + {valueProvenance: ((.valueProvenance // {}) + {permissions: "inferred"})}' <<<"$add")"
  fi

  # --- 3. relatedApis: '/api/...' パス収集(+ api-manifest 突合で unitKey 解決) ---
  #     直接 fetch/axios/apiClient を呼ぶ形と、共通クライアント関数(パスを変数で受け取る
  #     ラッパー)経由で呼ぶ形の両方を収集して合成する(改善課題「画面とAPIの対応づけ-担当不在」)。
  api_paths_direct="$(extract_api_paths ${scan_files[@]+"${scan_files[@]}"})"
  api_paths_wrapper="$(resolve_wrapper_api_paths "$API_CLIENT_MAP" "$API_CLIENT_PATTERNS" ${scan_files[@]+"${scan_files[@]}"})"
  api_paths="$(printf '%s\n%s\n' "$api_paths_direct" "$api_paths_wrapper" | sed '/^$/d' | sort -u)"
  if [ -n "$api_paths" ]; then
    paths_json="$(printf '%s\n' "$api_paths" | jq -R 'select(length > 0)' | jq -s .)"
    if [ -n "$API_MANIFEST" ]; then
      related_json="$(jq -n --argjson paths "$paths_json" --slurpfile api "$API_MANIFEST" '
        [ $api[0].units[]?
          | {p: (((.identifier // "") | split(" ") | map(select(startswith("/"))) | .[0]) // ""), k: (.unitKey // "")}
          | select((.p | length) > 0 and (.k | length) > 0)
        ] as $map
        | [ $paths[] as $p | $map[] | select(.p == $p) | .k ] | unique
      ')"
    else
      related_json="$paths_json"
    fi
    if [ "$(jq 'length' <<<"$related_json")" -gt 0 ]; then
      add="$(jq --argjson v "$related_json" '. + {relatedApis: $v}' <<<"$add")"
    fi
  fi

  # --- 4. designDocStatus: 設計書ディレクトリ配下の screenKey 実在判定 ---
  if [ -n "$DESIGN_DOCS_DIR" ] && [ -n "$screen_key" ]; then
    doc_status="未着手"
    if [ -e "$DESIGN_DOCS_DIR/$screen_key" ] || [ -e "$DESIGN_DOCS_DIR/screen-$screen_key" ]; then
      doc_status="着手済"
    else
      for cand in "$DESIGN_DOCS_DIR/$screen_key".*; do
        [ -e "$cand" ] && { doc_status="着手済"; break; }
      done
    fi
    add="$(jq --arg v "$doc_status" '. + {designDocStatus: $v}' <<<"$add")"
  fi

  # --- 4b-html. designDocPath / detailDocPath / sequencePath: doc-view側(project-portal/画面等、
  #     人が読むHTMLの置き場)フォルダ内の実在判定。--doc-view-dir 未指定時は design-docs 側と同一 ---
  if [ -n "$DOC_VIEW_DOCS_DIR" ] && [ -n "$screen_key" ]; then
    view_folder=""
    view_folder_rel=""
    if [ -d "$DOC_VIEW_DOCS_DIR/$screen_key" ]; then
      view_folder="$DOC_VIEW_DOCS_DIR/$screen_key"
      view_folder_rel="$screen_key"
    elif [ -d "$DOC_VIEW_DOCS_DIR/screen-$screen_key" ]; then
      view_folder="$DOC_VIEW_DOCS_DIR/screen-$screen_key"
      view_folder_rel="screen-$screen_key"
    fi

    if [ -n "$view_folder" ]; then
      view_link_folder="$view_folder_rel"
      if [ -n "$DOC_VIEW_LINK_PREFIX" ]; then
        view_link_folder="${DOC_VIEW_LINK_PREFIX%/}/$view_folder_rel"
      fi
      if [ -f "$view_folder/基本設計/画面基本設計書.html" ]; then
        add="$(jq --arg v "$view_link_folder/基本設計/画面基本設計書.html" '. + {designDocPath: $v}' <<<"$add")"
      fi
      if [ -f "$view_folder/詳細設計/画面詳細設計書.html" ]; then
        add="$(jq --arg v "$view_link_folder/詳細設計/画面詳細設計書.html" '. + {detailDocPath: $v}' <<<"$add")"
      fi
      if [ -f "$view_folder/シーケンス図.html" ]; then
        add="$(jq --arg v "$view_link_folder/シーケンス図.html" '. + {sequencePath: $v}' <<<"$add")"
      fi
    fi
  fi

  # --- 4b. testCasePath / 観点表 / シナリオ: 設計書ディレクトリ(定義の置き場)配下のmd実在判定 ---
  if [ -n "$DESIGN_DOCS_DIR" ] && [ -n "$screen_key" ]; then
    screen_folder=""
    screen_folder_rel=""
    if [ -d "$DESIGN_DOCS_DIR/$screen_key" ]; then
      screen_folder="$DESIGN_DOCS_DIR/$screen_key"
      screen_folder_rel="$screen_key"
    elif [ -d "$DESIGN_DOCS_DIR/screen-$screen_key" ]; then
      screen_folder="$DESIGN_DOCS_DIR/screen-$screen_key"
      screen_folder_rel="screen-$screen_key"
    fi

    if [ -n "$screen_folder" ]; then
      link_folder="$screen_folder_rel"
      if [ -n "$DESIGN_DOCS_LINK_PREFIX" ]; then
        link_folder="${DESIGN_DOCS_LINK_PREFIX%/}/$screen_folder_rel"
      fi
      if [ -f "$screen_folder/テスト設計/画面単体テスト設計書.md" ]; then
        add="$(jq --arg v "$link_folder/テスト設計/画面単体テスト設計書.md" '. + {testCasePath: $v, unitTestViewpointPath: $v}' <<<"$add")"
      else
        if [ -f "$screen_folder/テスト項目書/単体テスト仕様書.md" ]; then
          add="$(jq --arg v "$link_folder/テスト項目書/単体テスト仕様書.md" '. + {testCasePath: $v}' <<<"$add")"
        fi
        if [ -f "$screen_folder/詳細設計/単体テスト観点表.md" ]; then
          add="$(jq --arg v "$link_folder/詳細設計/単体テスト観点表.md" '. + {unitTestViewpointPath: $v}' <<<"$add")"
        fi
      fi
      if [ -f "$screen_folder/テスト設計/画面テスト設計書.md" ]; then
        add="$(jq --arg v "$link_folder/テスト設計/画面テスト設計書.md" '. + {integrationTestViewpointPath: $v, integrationTestCasePath: $v}' <<<"$add")"
      else
        if [ -f "$screen_folder/詳細設計/結合テスト観点表.md" ]; then
          add="$(jq --arg v "$link_folder/詳細設計/結合テスト観点表.md" '. + {integrationTestViewpointPath: $v}' <<<"$add")"
        fi
        if [ -f "$screen_folder/テスト項目書/結合テスト仕様書.md" ]; then
          add="$(jq --arg v "$link_folder/テスト項目書/結合テスト仕様書.md" '. + {integrationTestCasePath: $v}' <<<"$add")"
        fi
      fi
      if [ -f "$screen_folder/テスト設計/操作シナリオ仕様書.md" ]; then
        add="$(jq --arg v "$link_folder/テスト設計/操作シナリオ仕様書.md" '. + {scenarioPath: $v}' <<<"$add")"
      elif [ -f "$screen_folder/テスト項目書/操作シナリオ仕様書.md" ]; then
        add="$(jq --arg v "$link_folder/テスト項目書/操作シナリオ仕様書.md" '. + {scenarioPath: $v}' <<<"$add")"
      fi

      confirmed_name=""
      if [ -f "$screen_folder/基本設計/画面基本設計書.md" ]; then
        confirmed_name="$(
          sed -n -E 's/^#[[:space:]]+(.+)[[:space:]]+画面基本設計書[[:space:]]*$/\1/p' \
            "$screen_folder/基本設計/画面基本設計書.md" | sed -n '1p'
        )"
      fi
      if [ -z "$confirmed_name" ] && [ -f "$screen_folder/詳細設計/画面詳細設計書.md" ]; then
        confirmed_name="$(
          sed -n -E 's/^#[[:space:]]+(.+)[[:space:]]+画面詳細設計書[[:space:]]*$/\1/p' \
            "$screen_folder/詳細設計/画面詳細設計書.md" | sed -n '1p'
        )"
      fi
      if [ -n "$confirmed_name" ]; then
        add="$(jq --arg v "$confirmed_name" '. + {confirmedScreenName: $v}' <<<"$add")"
      fi
    fi
  fi

  # --- 5. sourceHash: 実在構成ファイル連結の sha256 先頭12桁 ---
  if [ "${#existing_files[@]}" -gt 0 ] && [ "$(jq -r 'has("sourceHash")' <<<"$row")" != "true" ]; then
    source_hash="$(cat "${existing_files[@]}" | sha256_12)"
    add="$(jq --arg v "$source_hash" '. + {sourceHash: $v}' <<<"$add")"
  fi

  jq -n -c --argjson i "$index" --argjson add "$add" '{index: $i, add: $add}' >> "$ADDS_FILE"
  index=$((index + 1))
done < <(jq -c '.screens[]?' "$MANIFEST")

# ---------------------------------------------------------------------------
# マージ出力(既存フィールドは無変更。追加フィールドだけを各要素へ合成)
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTPUT")"
jq --slurpfile adds "$ADDS_FILE" \
  --arg generatedAt "$GENERATED_AT" \
  --arg manifestContentHash "$MANIFEST_CONTENT_HASH" '
  (reduce $adds[] as $a ({}; .[($a.index | tostring)] = $a.add)) as $m
  | .screens = [ .screens // [] | to_entries[] | .value + ($m[(.key | tostring)] // {}) ]
  | if ($generatedAt | length) > 0
    then .generatedAt = $generatedAt | .manifestContentHash = $manifestContentHash
    else . end
' "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
bash "$_EXTRACT_SCREEN_SCRIPT_DIR/finalize-extension-manifest.sh" "$MANIFEST" "$OUTPUT" --unit-array screens --rules-file "$EXTRACTION_RULES_FILE" --rule 'category|route prefix と画面構成ファイル' --rule 'permissions|認可ロール指定' --rule 'relatedApis|fetch または API client のパス' --rule 'designDocStatus|設計書ディレクトリ' --rule 'sourceHash|実在構成ファイル'
