#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 1 画面境界検出
#
# Usage: detect-screens.sh <source-dir> <manifest-out-path> \
#          [--screen-id-regex <ERE>] [--view-switch-pattern <ERE>] \
#          [--exclude <ERE>] [--strategy-json <file>]
#        detect-screens.sh --profile <manifest> <source-dir> <profile-out> \
#          --recount-script <path> --repo-root <path>
#        detect-screens.sh --self-test
#
# --screen-id-regex <ERE>:
#   entryFile の basename(拡張子なし) から grep -oE で画面IDを抽出するパターン
#   (例: 'T-[A-Z]+-[0-9]+(-[0-9]+)*')。未指定なら screenId は null。
# --view-switch-pattern <ERE>:
#   埋め込みビュー検出用の grep パターン(例: 'setEditView|setModalView')。
#   未指定なら埋め込みビュー検出をスキップする。
# --exclude <ERE>:
#   デフォルト除外(node_modules/tests/__tests__/test/stories/__mocks__ ディレクトリ、
#   *.test.*/*.spec.*/*.stories.* ファイル)に追加する除外パターン(grep -Ev に合成)。
# --strategy-json <file>:
#   指定した JSON ファイルの中身をマニフェストの "strategy" フィールドにそのまま埋め込む。
#   未指定時は screenIdRegex/viewSwitchPattern/extractionMethod/approvedByUser を自動合成する。
#
# --resolve-files <manifest-in> <source-dir> <manifest-out>:
#   既存マニフェストの kind=route/embedded-view で entryFile が非空の画面それぞれについて、
#   import 文を BFS(幅優先探索)で再帰的に追跡し、画面専有ファイル集合(files/fileCount)を
#   再解決する後処理サブコマンド(strategy を差し替えて再解決したい場合等に使う)。
#   strategy の以下のフィールドを読む:
#     - sharedDirPatterns: 共有資産として除外する ERE の配列(ソースルート相対パスに対して照合)
#     - pathAliases: エイリアス前方一致テーブル({"@/": "src/"} 形式。値はソースルート相対)
#     - importTraversalMaxDepth: BFS の深さ上限(未指定なら既定 6)
#   entryFile がディレクトリの場合(慣習ディレクトリ検出)は従来のディレクトリ収集を維持する。
#
# --self-test:
#   resolve_screen_files(import 再帰追跡)と --resolve-files サブコマンドの自己診断テストを
#   実行する。全PASSでexit 0、FAILがあればexit 1。
#
# 検出優先順位:
#   1. Next.js App Router (app/**/page.{tsx,jsx,js})
#   2. Next.js Pages Router (pages/**/*.{tsx,jsx,js}, _app/_document/api 除外)
#   3. React Router (createBrowserRouter/createHashRouter/useRoutes/<Route> のフラット path 抽出。
#      useRoutes(識別子)/createBrowserRouter(識別子) 形式は1段の import 追跡で定義ファイルを解決する)
#   4. フォールバック: pages/screens/views 慣習ディレクトリ直下を1画面として扱う
#   5. 1-4すべて0件ならハード停止 (exit 3)。画面を捏造しない
#
# デフォルト除外: tests/__tests__/test/stories/__mocks__ ディレクトリ配下と
#   *.test.*/*.spec.*/*.stories.* ファイルは全検出方式の find/grep 結果から除外する。
#
# 画面キー生成アルゴリズム(意味キー規約準拠・連番サフィックス禁止):
#   1. ルートの静的セグメントのみ抽出(動的パラメータ・ワイルドカード除外)
#   2. 末尾1セグメントを仮キーとする
#   3. 衝突時は末尾からのセグメント数を1つずつ増やして再判定
#   4. 全セグメントを使っても衝突する場合、エントリディレクトリのパスで具体化する
#   5. それでも衝突する場合、entry_file の basename(拡張子なし・小文字化)で具体化する
#   6. ルートが `/` または静的セグメント無しの場合は `top`
#
# ファイル収集: entryFile がファイルの場合は import 文を BFS(幅優先探索)で再帰的に
# 追跡し(resolve_screen_files)、strategy の sharedDirPatterns/pathAliases/
# importTraversalMaxDepth/screenIdRegex に従って画面専有ファイル集合を解決する。
# entryFile がディレクトリの場合(慣習ディレクトリ検出)は、エントリと同一ディレクトリ
# 直下 + 直下の components/(_components/) 1階層のみを収集する(フォールバック互換)。
#
# 重複マージ: 同一 (route, entryFile) の行は 1 行にマージし、出現回数を routeDupCount として保持する。
# 共有クラスタ: 異なる screenKey が同一 entryFile を共有する場合、sharedWith / clusterId を付与する。
# 埋め込みビュー: --view-switch-pattern 指定時、条件分岐で切り替えられる子ビューを kind: "embedded-view" として
#   独立行で出力する(1階層 import grep による best-effort 解決)。

set -euo pipefail

# ============================================================================
# 8-4: import 再帰追跡(resolve_screen_files)と --resolve-files サブコマンド
# ============================================================================
#
# resolve_screen_files は、エントリファイルから import グラフを BFS で辿り、
# 画面専有ファイル集合を算出する。BFS 本体・ファイル存在プローブは単一 awk
# プロセス内で完結させ(getline の可否判定によるプローブ)、ファイルごとの
# 外部コマンド fork は発生させない。
#
# 既知の限界: 拡張子解決の候補パス(base+.tsx 等)がディレクトリと偶然同名の
# 場合、one-true-awk は「getline で読めたがclose時にI/Oエラー」を検知すると
# プロセスを異常終了させる(close()がエラーで即abortする実装挙動を確認済み)。
# JS/TS の実運用でディレクトリ名が .tsx/.ts/.jsx/.js で終わることは事実上
# 無いため許容する。この既知の限界を避けるため、拡張子なしの仕様(bare spec)
# を裸のまま getline することはしない(必ず拡張子または/indexを付けてから
# プローブする)。

RESOLVE_COMMON_AWK_FILE="$(mktemp)"
RESOLVE_AWK_FILE="$(mktemp)"
RESOLVE_BATCH_AWK_FILE="$(mktemp)"
trap 'rm -f "$RESOLVE_COMMON_AWK_FILE" "$RESOLVE_AWK_FILE" "$RESOLVE_BATCH_AWK_FILE"' EXIT

# RESOLVE_COMMON_AWK_FILE: resolve_screen_files(単一画面)と
# resolve_files_subcommand の一括BFS(9-3)が共有するヘルパー関数群。
# 単一/一括いずれの awk 呼び出しも `-f COMMON -f 本体` の順で読み込む。
cat > "$RESOLVE_COMMON_AWK_FILE" <<'AWKEOF'
function try_exists(f,    line, rc) {
  rc = (getline line < f)
  close(f)
  return (rc >= 0) ? 1 : 0
}

function has_any_ext(p) {
  return (p ~ /\.[A-Za-z0-9]+$/)
}

function has_code_ext(p) {
  return (p ~ /\.(tsx|ts|jsx|js)$/)
}

function dirname_of(p,    d) {
  d = p
  sub(/\/[^\/]*$/, "", d)
  if (d == "") d = "/"
  return d
}

# 相対パスの正規化(./ の除去・../ の巻き戻し)。split後の空要素(先頭/連続/)は
# ループ内でスキップされるため、多重スラッシュ・絶対パスの前提を壊さない。
function normalize_path(p,    n, i, parts, top, out, seg, stack) {
  n = split(p, parts, "/")
  top = 0
  for (i = 1; i <= n; i++) {
    seg = parts[i]
    if (seg == "" || seg == ".") continue
    if (seg == "..") {
      if (top > 0) top--
    } else {
      top++
      stack[top] = seg
    }
  }
  out = ""
  for (i = 1; i <= top; i++) out = out "/" stack[i]
  if (out == "") out = "/"
  return out
}

# 指定子抽出: from '...' / import('...') / require('...')。SPECS(グローバル配列)へ
# 書き込み、件数を返す。コメント除去は行わない(この探索の対象は決定的なコード追跡の
# best-effort であり、既存の他検出処理と同水準の割り切り)。
function extract_specs(file,    codeline, s, seg, spec, cnt) {
  cnt = 0
  while ((getline codeline < file) > 0) {
    s = codeline
    while (match(s, /from[ \t]*['"][^'"]+['"]/)) {
      seg = substr(s, RSTART, RLENGTH)
      if (match(seg, /['"][^'"]+['"]/)) {
        spec = substr(seg, RSTART + 1, RLENGTH - 2)
        cnt++; SPECS[cnt] = spec
      }
      s = substr(s, RSTART + RLENGTH)
    }
    s = codeline
    while (match(s, /import\([ \t]*['"][^'"]+['"]/)) {
      seg = substr(s, RSTART, RLENGTH)
      if (match(seg, /['"][^'"]+['"]/)) {
        spec = substr(seg, RSTART + 1, RLENGTH - 2)
        cnt++; SPECS[cnt] = spec
      }
      s = substr(s, RSTART + RLENGTH)
    }
    s = codeline
    while (match(s, /require\([ \t]*['"][^'"]+['"]/)) {
      seg = substr(s, RSTART, RLENGTH)
      if (match(seg, /['"][^'"]+['"]/)) {
        spec = substr(seg, RSTART + 1, RLENGTH - 2)
        cnt++; SPECS[cnt] = spec
      }
      s = substr(s, RSTART + RLENGTH)
    }
  }
  close(file)
  return cnt
}
AWKEOF

# RESOLVE_AWK_FILE: 単一画面のBFS本体(resolve_screen_files が使用)。
# RESOLVE_COMMON_AWK_FILE の関数群を前提とする(呼び出し側で -f を2つ渡す)。
cat > "$RESOLVE_AWK_FILE" <<'AWKEOF'
BEGIN {
  # scalar 値は awk -v の escape 処理(バックスラッシュ解釈)を避けるため
  # ファイル経由で読む(screenidregex 等に \ を含む可能性への安全策)。
  getline entry < paramsfile
  getline srcdir < paramsfile
  getline maxdepth < paramsfile
  getline screenidregex < paramsfile
  getline ownscreenid < paramsfile
  close(paramsfile)
  maxdepth += 0
  if (maxdepth <= 0) maxdepth = 6

  n_shared = 0
  while ((getline line < sharedfile) > 0) {
    if (line != "") { n_shared++; shared[n_shared] = line }
  }
  close(sharedfile)

  while ((getline line < othersfile) > 0) {
    if (line != "") { others[line] = 1 }
  }
  close(othersfile)

  n_alias = 0
  while ((getline line < aliasfile) > 0) {
    if (line == "") continue
    split(line, ap, "\t")
    n_alias++
    alias_prefix[n_alias] = ap[1]
    alias_target[n_alias] = ap[2]
  }
  close(aliasfile)

  codeext[1] = ".tsx"; codeext[2] = ".ts"; codeext[3] = ".jsx"; codeext[4] = ".js"

  # entry は常に含める(境界チェックの対象外)。BFS depth 0。
  qhead = 1; qtail = 1
  queue_file[1] = entry
  queue_depth[1] = 0
  visited[entry] = 1
  result_n = 1
  result[1] = entry

  while (qhead <= qtail) {
    curfile = queue_file[qhead]
    curdepth = queue_depth[qhead]
    qhead++

    # 深さ上限: curdepth == maxdepth のノードは結果に含まれるが、その先の
    # import は追跡しない(自身のimport抽出をスキップする)。
    if (curdepth + 0 >= maxdepth + 0) continue

    n_specs = extract_specs(curfile)
    curdir = dirname_of(curfile)

    for (si = 1; si <= n_specs; si++) {
      spec = SPECS[si]

      base = ""
      matched_ai = 0
      matched_len = -1
      for (ai = 1; ai <= n_alias; ai++) {
        if (index(spec, alias_prefix[ai]) == 1 && length(alias_prefix[ai]) > matched_len) {
          matched_len = length(alias_prefix[ai])
          matched_ai = ai
        }
      }
      if (matched_ai > 0) {
        # エイリアス解決(前方一致・最長一致)。alias_target は呼び出し側で
        # ソースルート相対から絶対パスへ解決済み。"/" を明示挿入することで
        # target/rest 双方の trailing/leading slash 有無に依存しない。
        base = normalize_path(alias_target[matched_ai] "/" substr(spec, length(alias_prefix[matched_ai]) + 1))
      } else if (substr(spec, 1, 1) == ".") {
        base = normalize_path(curdir "/" spec)
      } else {
        # bare import(パッケージ名等の相対/エイリアス解決不能な指定子)は追跡しない。
        continue
      }

      # 拡張子解決順: そのまま(既に拡張子を含む場合のみ)→.tsx→.ts→.jsx→.js→
      # /index.{tsx,ts,jsx,js}。コード拡張子のみ追跡する(非コード拡張子=CSS/JSON/
      # 画像等は resolved を確定させない)。拡張子なしのbare specを裸のまま
      # getlineすることはしない(直上コメント参照の既知の限界回避)。
      # 非コード拡張子(css/scss/json/画像等)は候補付与しても対応ファイルが
      # 存在しないため resolved が空のまま=集合に含まれない(意図的除外)。
      resolved = ""
      if (has_code_ext(base)) {
        if (try_exists(base)) resolved = base
      } else {
        for (ei = 1; ei <= 4; ei++) {
          cand = base codeext[ei]
          if (try_exists(cand)) { resolved = cand; break }
        }
        if (resolved == "") {
          for (ei = 1; ei <= 4; ei++) {
            cand = base "/index" codeext[ei]
            if (try_exists(cand)) { resolved = cand; break }
          }
        }
      }
      if (resolved == "") continue

      if (resolved in visited) continue
      visited[resolved] = 1

      # ソースルート外は追跡しない。
      if (!(resolved == srcdir || index(resolved, srcdir "/") == 1)) continue

      # 境界(a): 共有ディレクトリパターン(ERE)一致は除外し、その先も辿らない。
      # ソースルート相対パスに対して照合する(9-1: `^shared/` 等の ^ アンカー付き
      # パターンが絶対パス照合では常に不一致になっていた不具合の修正)。
      rel = (resolved == srcdir) ? "" : substr(resolved, length(srcdir) + 2)
      is_shared = 0
      for (shi = 1; shi <= n_shared; shi++) {
        if (rel ~ shared[shi]) { is_shared = 1; break }
      }
      if (is_shared) continue

      # 境界(b): 他画面のentryFile集合(自画面のentryは既にvisitedで除外済み)。
      if (resolved in others) continue

      # 境界(c): screenIdRegex設定時、basenameから抽出した画面IDが自画面と異なるもの。
      if (screenidregex != "") {
        bn = resolved
        sub(/.*\//, "", bn)
        sub(/\.[^.]*$/, "", bn)
        if (match(bn, screenidregex)) {
          extracted = substr(bn, RSTART, RLENGTH)
          if (extracted != "" && extracted != ownscreenid) continue
        }
      }

      result_n++
      result[result_n] = resolved
      qtail++
      queue_file[qtail] = resolved
      queue_depth[qtail] = curdepth + 1
    }
  }

  for (i = 1; i <= result_n; i++) print result[i]
}
AWKEOF

# RESOLVE_BATCH_AWK_FILE: 複数画面分のBFSを単一awkプロセス内で連続処理する(9-3)。
# resolve_files_subcommand が --resolve-files の対象画面をまとめて処理する際に使う。
# srcdir/maxdepth/screenidregex/共有パターン/エイリアス表はマニフェスト単位で共通のため
# 一度だけ読み込み、画面ごとの entry/ownscreenid のみを screensfile(TSV)から読む。
# visited/queue/result は画面ごとに delete でリセットする(BFSの状態を画面間で共有しない)。
# 境界(b)の「他画面entryFile集合」は自画面のentryも含めて一括で読み込む: 自画面のentryは
# BFS開始時に既にvisitedへ登録済みのため、visited判定が境界(b)判定より必ず先に効き、
# 自画面entryを誤って除外することはない(単一画面版の自画面除外グレップは冗長だった)。
cat > "$RESOLVE_BATCH_AWK_FILE" <<'AWKEOF'
BEGIN {
  getline srcdir < paramsfile
  getline maxdepth < paramsfile
  getline screenidregex < paramsfile
  close(paramsfile)
  maxdepth += 0
  if (maxdepth <= 0) maxdepth = 6

  n_shared = 0
  while ((getline line < sharedfile) > 0) {
    if (line != "") { n_shared++; shared[n_shared] = line }
  }
  close(sharedfile)

  n_alias = 0
  while ((getline line < aliasfile) > 0) {
    if (line == "") continue
    split(line, ap, "\t")
    n_alias++
    alias_prefix[n_alias] = ap[1]
    alias_target[n_alias] = ap[2]
  }
  close(aliasfile)

  codeext[1] = ".tsx"; codeext[2] = ".ts"; codeext[3] = ".jsx"; codeext[4] = ".js"

  n_screens = 0
  while ((getline line < screensfile) > 0) {
    if (line == "") continue
    split(line, sf, "\t")
    n_screens++
    all_key[n_screens] = sf[1]
    all_entry[n_screens] = sf[2]
    all_ownid[n_screens] = sf[3]
    others[sf[2]] = 1
  }
  close(screensfile)

  for (sidx = 1; sidx <= n_screens; sidx++) {
    key = all_key[sidx]
    entry = all_entry[sidx]
    ownscreenid = all_ownid[sidx]

    delete visited
    delete queue_file
    delete queue_depth
    delete result

    qhead = 1; qtail = 1
    queue_file[1] = entry
    queue_depth[1] = 0
    visited[entry] = 1
    result_n = 1
    result[1] = entry

    while (qhead <= qtail) {
      curfile = queue_file[qhead]
      curdepth = queue_depth[qhead]
      qhead++

      if (curdepth + 0 >= maxdepth + 0) continue

      n_specs = extract_specs(curfile)
      curdir = dirname_of(curfile)

      for (si = 1; si <= n_specs; si++) {
        spec = SPECS[si]

        base = ""
        matched_ai = 0
        matched_len = -1
        for (ai = 1; ai <= n_alias; ai++) {
          if (index(spec, alias_prefix[ai]) == 1 && length(alias_prefix[ai]) > matched_len) {
            matched_len = length(alias_prefix[ai])
            matched_ai = ai
          }
        }
        if (matched_ai > 0) {
          base = normalize_path(alias_target[matched_ai] "/" substr(spec, length(alias_prefix[matched_ai]) + 1))
        } else if (substr(spec, 1, 1) == ".") {
          base = normalize_path(curdir "/" spec)
        } else {
          continue
        }

        resolved = ""
        if (has_code_ext(base)) {
          if (try_exists(base)) resolved = base
        } else {
          for (ei = 1; ei <= 4; ei++) {
            cand = base codeext[ei]
            if (try_exists(cand)) { resolved = cand; break }
          }
          if (resolved == "") {
            for (ei = 1; ei <= 4; ei++) {
              cand = base "/index" codeext[ei]
              if (try_exists(cand)) { resolved = cand; break }
            }
          }
        }
        if (resolved == "") continue

        if (resolved in visited) continue
        visited[resolved] = 1

        if (!(resolved == srcdir || index(resolved, srcdir "/") == 1)) continue

        # 境界(a): 9-1と同一の相対化照合。
        rel = (resolved == srcdir) ? "" : substr(resolved, length(srcdir) + 2)
        is_shared = 0
        for (shi = 1; shi <= n_shared; shi++) {
          if (rel ~ shared[shi]) { is_shared = 1; break }
        }
        if (is_shared) continue

        if (resolved in others) continue

        if (screenidregex != "") {
          bn = resolved
          sub(/.*\//, "", bn)
          sub(/\.[^.]*$/, "", bn)
          if (match(bn, screenidregex)) {
            extracted = substr(bn, RSTART, RLENGTH)
            if (extracted != "" && extracted != ownscreenid) continue
          }
        }

        result_n++
        result[result_n] = resolved
        qtail++
        queue_file[qtail] = resolved
        queue_depth[qtail] = curdepth + 1
      }
    }

    delete outseen
    for (i = 1; i <= result_n; i++) {
      if (!(result[i] in outseen)) {
        outseen[result[i]] = 1
        print key "\t" result[i]
      }
    }
  }
}
AWKEOF

# resolve_screen_files: エントリファイルからBFSで画面専有ファイル集合を算出する。
# 引数:
#   $1 entry           絶対パスのエントリファイル
#   $2 srcdir          絶対パスのソースルート(末尾スラッシュなし)
#   $3 maxdepth         BFS深さ上限(空なら既定6)
#   $4 shared_file      共有ディレクトリERE(改行区切り)を書いたファイル(空文字可)
#   $5 others_file      他画面entryFile(絶対パス・改行区切り、自画面除く)を書いたファイル(空文字可)
#   $6 screenidregex    画面ID抽出ERE(空文字可)
#   $7 ownscreenid      自画面の画面ID(空文字可)
#   $8 alias_file       エイリアスTSV(prefix\t絶対パスtarget、改行区切り)を書いたファイル(空文字可)
# 出力: 解決済み絶対パスを1行1件、重複なしで標準出力へ(entry含む)。
resolve_screen_files() {
  local entry="$1" srcdir="$2" maxdepth="${3:-6}"
  local shared_file="${4:-}" others_file="${5:-}"
  local screenidregex="${6:-}" ownscreenid="${7:-}" alias_file="${8:-}"
  case "$maxdepth" in ''|*[!0-9]*) maxdepth=6 ;; esac

  local params_file empty_file
  params_file="$(mktemp)"
  empty_file="$(mktemp)"
  {
    printf '%s\n' "$entry"
    printf '%s\n' "$srcdir"
    printf '%s\n' "$maxdepth"
    printf '%s\n' "$screenidregex"
    printf '%s\n' "$ownscreenid"
  } > "$params_file"

  local sf="$shared_file" of="$others_file" af="$alias_file"
  [ -n "$sf" ] && [ -f "$sf" ] || sf="$empty_file"
  [ -n "$of" ] && [ -f "$of" ] || of="$empty_file"
  [ -n "$af" ] && [ -f "$af" ] || af="$empty_file"

  awk -v paramsfile="$params_file" -v sharedfile="$sf" -v othersfile="$of" -v aliasfile="$af" \
    -f "$RESOLVE_COMMON_AWK_FILE" -f "$RESOLVE_AWK_FILE" | sort -u

  rm -f "$params_file" "$empty_file"
}

# resolve_files_subcommand: --resolve-files サブコマンド本体。
# 既存マニフェストの kind=route/embedded-view で entryFile 非空の画面に対して
# resolve_screen_files を適用し、files/fileCountのみを更新した新マニフェストを書き出す。
# jqの値受け渡しは一時ファイル+--slurpfileで行う(引数長・エスケープ事故を避ける)。
resolve_files_subcommand() {
  local manifest_in="$1" source_dir="$2" manifest_out="$3"

  if [ ! -f "$manifest_in" ]; then
    echo "ERROR: manifest not found: $manifest_in" >&2
    exit 1
  fi
  if [ ! -d "$source_dir" ]; then
    echo "ERROR: source-dir not found: $source_dir" >&2
    exit 1
  fi
  source_dir="$(cd "$source_dir" && pwd)"

  local max_depth
  max_depth="$(jq -r '.strategy.importTraversalMaxDepth // 6' "$manifest_in" 2>/dev/null || true)"
  case "$max_depth" in ''|*[!0-9]*) max_depth=6 ;; esac

  local screen_id_regex
  screen_id_regex="$(jq -r '.strategy.screenIdRegex // ""' "$manifest_in" 2>/dev/null || true)"
  [ "$screen_id_regex" = "null" ] && screen_id_regex=""

  local rf_shared_file rf_alias_file rf_screens_all_file rf_screens_valid_file
  local rf_params_file rf_batch_result_file rf_updates_file
  rf_shared_file="$(mktemp)"
  rf_alias_file="$(mktemp)"
  rf_screens_all_file="$(mktemp)"
  rf_screens_valid_file="$(mktemp)"
  rf_params_file="$(mktemp)"
  rf_batch_result_file="$(mktemp)"
  rf_updates_file="$(mktemp)"

  jq -r '(.strategy.sharedDirPatterns // [])[]' "$manifest_in" > "$rf_shared_file" 2>/dev/null || true

  : > "$rf_alias_file"
  jq -r '(.strategy.pathAliases // {}) | to_entries[] | "\(.key)\t\(.value)"' "$manifest_in" 2>/dev/null \
    | while IFS=$'\t' read -r prefix target; do
        [ -z "$prefix" ] && continue
        case "$target" in
          /*) abs_target="$target" ;;
          "") abs_target="$source_dir" ;;
          *) abs_target="$source_dir/$target" ;;
        esac
        printf '%s\t%s\n' "$prefix" "$abs_target"
      done > "$rf_alias_file" || true

  # 9-3: 全対象画面の screenKey・entryFile(絶対パス化)・screenId を1回のjq呼び出しで
  # TSVへ一括書き出しする(画面ごとのjq呼び出しをやめ、定数回のjq呼び出しに抑える)。
  jq -r --arg srcdir "$source_dir" '
    [.screens[] | select((.kind=="route" or .kind=="embedded-view") and .entryFile != "" and .entryFile != null)
     | {screenKey, screenId: (.screenId // ""), entryFile}]
    | .[]
    | [.screenKey,
       (if (.entryFile | startswith("/")) then .entryFile else ($srcdir + "/" + .entryFile) end),
       .screenId]
    | @tsv
  ' "$manifest_in" > "$rf_screens_all_file"

  local n_targets=0
  : > "$rf_screens_valid_file"
  while IFS=$'\t' read -r key abs_entry own_id; do
    [ -z "$key" ] && continue
    n_targets=$((n_targets + 1))
    if [ ! -f "$abs_entry" ]; then
      echo "WARN: --resolve-files: entryFile not found, skip: $abs_entry (screenKey=$key)" >&2
      continue
    fi
    printf '%s\t%s\t%s\n' "$key" "$abs_entry" "$own_id" >> "$rf_screens_valid_file"
  done < "$rf_screens_all_file"

  local resolved_count
  resolved_count="$(grep -c . "$rf_screens_valid_file" || true)"
  [ -z "$resolved_count" ] && resolved_count=0

  {
    printf '%s\n' "$source_dir"
    printf '%s\n' "$max_depth"
    printf '%s\n' "$screen_id_regex"
  } > "$rf_params_file"

  # 9-3: 全画面分のBFSを単一awkプロセスで連続処理する(画面ごとのawk起動を廃止)。
  : > "$rf_batch_result_file"
  if [ -s "$rf_screens_valid_file" ]; then
    awk -v paramsfile="$rf_params_file" -v sharedfile="$rf_shared_file" -v aliasfile="$rf_alias_file" \
      -v screensfile="$rf_screens_valid_file" \
      -f "$RESOLVE_COMMON_AWK_FILE" -f "$RESOLVE_BATCH_AWK_FILE" > "$rf_batch_result_file"
  fi

  # 9-3: 結果マージも1回のjq呼び出しで {screenKey: {files, fileCount}} を組み立てる。
  jq -R -s '
    split("\n") | map(select(length > 0) | split("\t") | {key: .[0], file: .[1]})
    | group_by(.key)
    | map({(.[0].key): {files: (map(.file) | sort), fileCount: (map(.file) | length)}})
    | add // {}
  ' "$rf_batch_result_file" > "$rf_updates_file"

  jq --slurpfile updates "$rf_updates_file" '
    .screens |= map(
      . as $s | ($updates[0][$s.screenKey]) as $u |
      if $u then $s + {files: $u.files, fileCount: $u.fileCount} else $s end
    )
  ' "$manifest_in" > "$manifest_out"

  rm -f "$rf_shared_file" "$rf_alias_file" "$rf_screens_all_file" "$rf_screens_valid_file" \
    "$rf_params_file" "$rf_batch_result_file" "$rf_updates_file"
  echo "OK: --resolve-files updated $resolved_count/$n_targets screens -> $manifest_out" >&2
}

# ============================================================================
# 8-6: 画面ごとの複雑度プロファイリング(run_detect_screens_profile / --profile)
# ============================================================================
#
#   detect-screens.sh --profile <manifest> <source-dir> <profile-out> \
#     --recount-script <path> --repo-root <path>
#
# 処理:
#   1. 対象は kind=route/embedded-view の画面のみ。各画面の files[] を
#      repo-root 相対パスへ変換する(files[] が空の画面はスコア対象外として除外し、
#      stderr に警告 + 出力の diagnostics[] に記録する)。
#   2. --recount-script(recount-facts.sh の --recount-only)を画面単位で1回呼び、
#      LOC(loc行)+8軸(import/export_type/const/state/handler/jsx/style/api)を
#      計測する。8軸の値は画面ごとに axisBreakdown{8軸} として保持しつつ、
#      単純合算してaxisSumとする。
#   3. score = locWeight×loc + axisWeight×axisSum(重み既定 1/1、現状は固定値)。
#   4. 四分位境界は nearest-rank-ceil 方式: q_i_rank = ceil(N×{25,50,75}/100)
#      (整数演算: (N*pct+99)/100)をスコア昇順ソート後の1始まり順位として取り、
#      その順位の値を境界値とする。score<=Q1→S / <=Q2→M / <=Q3→L / それ以外→XL。
#      N<4 の場合は全画面 layer=ALL・quartiles=null・stratified=false に縮退する。
#   5. 層内サンプリング: layer(層)ごとに k=ceil(sqrt(層内件数))・下限3・上限10、
#      層内件数<k なら全数を対象とする。screenKey の辞書順先頭k件を採用する。
#      結果は layers.<層名> = {n, sampleK, sampledScreenKeys[]} として出力する。
#   6. 出力JSON(確定仕様)を <profile-out> に書き出す:
#      screens[](axisBreakdown・layerを含む) / layers{S,M,L,XL|ALL}
#      / n / scoreFormula{locWeight,axisWeight,axes[8]} / sourceManifest
#      / quartileMethod:"nearest-rank-ceil" / stratified / diagnostics[]
#
# --profile の自己テストは run_self_tests() 内(8-6-profile-*)に統合済み。

# ceil(sqrt(n)) を計算する(n>=0の整数)。
sqrt_ceil() {
  awk -v n="$1" 'BEGIN { r = sqrt(n); i = int(r); if (i * i < n) i++; print i }'
}

run_detect_screens_profile() {
  local manifest="" source_dir="" profile_out="" recount_script="" repo_root=""
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --recount-script)
        recount_script="${2:-}"
        shift 2
        ;;
      --repo-root)
        repo_root="${2:-}"
        shift 2
        ;;
      -*)
        echo "ERROR: --profile: unknown option: $1" >&2
        return 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#positional[@]}" -lt 3 ]; then
    echo "Usage: detect-screens.sh --profile <manifest> <source-dir> <profile-out> --recount-script <path> --repo-root <path>" >&2
    return 1
  fi
  manifest="${positional[0]}"
  source_dir="${positional[1]}"
  profile_out="${positional[2]}"

  if [ -z "$recount_script" ] || [ ! -f "$recount_script" ]; then
    echo "ERROR: --recount-script が見つかりません: $recount_script" >&2
    return 1
  fi
  if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
    echo "ERROR: --repo-root が見つかりません: $repo_root" >&2
    return 1
  fi
  if [ ! -f "$manifest" ]; then
    echo "ERROR: manifest が見つかりません: $manifest" >&2
    return 1
  fi
  if [ ! -d "$source_dir" ]; then
    echo "ERROR: source-dir が見つかりません: $source_dir" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not found in PATH" >&2
    return 1
  fi

  repo_root="$(cd "$repo_root" && pwd)"

  local loc_weight=1
  local axis_weight=1

  local rows_tmp jsonl_tmp diag_tmp
  rows_tmp="$(mktemp)"
  jsonl_tmp="$(mktemp)"
  diag_tmp="$(mktemp)"
  _cleanup_detect_screens_profile_tmp() { rm -f "$rows_tmp" "$jsonl_tmp" "$diag_tmp"; }
  trap '_cleanup_detect_screens_profile_tmp' RETURN

  : > "$rows_tmp"
  : > "$diag_tmp"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    local screen_key kind file_count
    screen_key="$(jq -r '.screenKey' <<<"$row")"
    kind="$(jq -r '.kind' <<<"$row")"
    file_count="$(jq -r '.files | length' <<<"$row")"
    if [ "$file_count" -eq 0 ]; then
      echo "WARN: --profile: files[]が空のためスコア対象から除外します: $screen_key" >&2
      printf '%s\n' "files[]が空のためスコア対象から除外: ${screen_key}" >> "$diag_tmp"
      continue
    fi
    local rel_files=()
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      rel_files+=("${f#"$repo_root"/}")
    done < <(jq -r '.files[]' <<<"$row")

    local recount_out loc=0 axis_sum=0 sec val
    local import_cnt=0 export_type_cnt=0 const_cnt=0 state_cnt=0 handler_cnt=0 jsx_cnt=0 style_cnt=0 api_cnt=0
    recount_out="$(bash "$recount_script" --recount-only "$repo_root" "${rel_files[@]}")"
    while IFS=' ' read -r sec val; do
      [ -z "$sec" ] && continue
      case "$sec" in
        loc) loc="$val" ;;
        import) import_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        export_type) export_type_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        const) const_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        state) state_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        handler) handler_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        jsx) jsx_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        style) style_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        api) api_cnt="$val"; axis_sum=$((axis_sum + val)) ;;
        *) axis_sum=$((axis_sum + val)) ;;
      esac
    done <<< "$recount_out"

    local score=$((loc_weight * loc + axis_weight * axis_sum))
    jq -n -c \
      --arg key "$screen_key" --arg kind "$kind" \
      --argjson loc "$loc" --argjson axisSum "$axis_sum" --argjson score "$score" \
      --argjson importC "$import_cnt" --argjson exportC "$export_type_cnt" --argjson constC "$const_cnt" \
      --argjson stateC "$state_cnt" --argjson handlerC "$handler_cnt" --argjson jsxC "$jsx_cnt" \
      --argjson styleC "$style_cnt" --argjson apiC "$api_cnt" \
      '{screenKey:$key, kind:$kind, loc:$loc, axisSum:$axisSum, score:$score,
        axisBreakdown:{import:$importC, export_type:$exportC, const:$constC, state:$stateC,
                        handler:$handlerC, jsx:$jsxC, style:$styleC, api:$apiC}}' >> "$rows_tmp"
  done < <(jq -c '.screens[] | select(.kind=="route" or .kind=="embedded-view")' "$manifest")

  local n
  n="$(wc -l < "$rows_tmp" | tr -d ' ')"

  local q1="" q2="" q3="" quartiles_json="null" stratified="false"
  if [ "$n" -ge 4 ]; then
    stratified="true"
    local sorted_scores q1_rank q2_rank q3_rank
    sorted_scores="$(jq -r '.score' "$rows_tmp" | sort -n)"
    q1_rank=$(( (n * 25 + 99) / 100 ))
    q2_rank=$(( (n * 50 + 99) / 100 ))
    q3_rank=$(( (n * 75 + 99) / 100 ))
    q1="$(printf '%s\n' "$sorted_scores" | sed -n "${q1_rank}p")"
    q2="$(printf '%s\n' "$sorted_scores" | sed -n "${q2_rank}p")"
    q3="$(printf '%s\n' "$sorted_scores" | sed -n "${q3_rank}p")"
    quartiles_json="$(jq -n --argjson q1 "$q1" --argjson q2 "$q2" --argjson q3 "$q3" '{q1:$q1,q2:$q2,q3:$q3}')"
  fi

  : > "$jsonl_tmp"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    local score layer
    score="$(jq -r '.score' <<<"$row")"
    if [ "$n" -lt 4 ]; then
      layer="ALL"
    elif [ "$score" -le "$q1" ]; then
      layer="S"
    elif [ "$score" -le "$q2" ]; then
      layer="M"
    elif [ "$score" -le "$q3" ]; then
      layer="L"
    else
      layer="XL"
    fi
    jq -c --arg layer "$layer" '. + {layer:$layer}' <<<"$row" >> "$jsonl_tmp"
  done < "$rows_tmp"

  local layers_json="{}"
  if [ -s "$jsonl_tmp" ]; then
    local layer_names layer_tmp
    layer_names="$(jq -r '.layer' "$jsonl_tmp" | sort -u)"
    layer_tmp="$(mktemp)"
    : > "$layer_tmp"
    while IFS= read -r layer_name; do
      [ -z "$layer_name" ] && continue
      local layer_keys layer_n k sampled sampled_json
      layer_keys="$(jq -r --arg t "$layer_name" 'select(.layer==$t) | .screenKey' "$jsonl_tmp" | sort)"
      layer_n="$(printf '%s\n' "$layer_keys" | grep -c . || true)"
      k="$(sqrt_ceil "$layer_n")"
      [ "$k" -lt 3 ] && k=3
      [ "$k" -gt 10 ] && k=10
      [ "$k" -gt "$layer_n" ] && k="$layer_n"
      sampled="$(printf '%s\n' "$layer_keys" | head -n "$k")"
      sampled_json="$(printf '%s\n' "$sampled" | jq -R -s 'split("\n") | map(select(length>0))')"
      jq -n --arg t "$layer_name" --argjson n "$layer_n" --argjson sampleK "$k" --argjson keys "$sampled_json" \
        '{($t): {n:$n, sampleK:$sampleK, sampledScreenKeys:$keys}}' >> "$layer_tmp"
    done <<< "$layer_names"
    layers_json="$(jq -s 'add // {}' "$layer_tmp")"
    rm -f "$layer_tmp"
  fi

  local manifest_abs
  manifest_abs="$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")"

  local diagnostics_json
  diagnostics_json="$(jq -R -s 'split("\n") | map(select(length>0))' "$diag_tmp")"

  mkdir -p "$(dirname "$profile_out")"
  jq -n \
    --arg generatedAt "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    --arg repoRoot "$repo_root" \
    --arg sourceManifest "$manifest_abs" \
    --argjson locWeight "$loc_weight" \
    --argjson axisWeight "$axis_weight" \
    --argjson n "$n" \
    --argjson quartiles "$quartiles_json" \
    --argjson stratified "$stratified" \
    --slurpfile screens "$jsonl_tmp" \
    --argjson layers "$layers_json" \
    --argjson diagnostics "$diagnostics_json" \
    '{generatedAt:$generatedAt, repoRoot:$repoRoot, sourceManifest:$sourceManifest,
      quartileMethod:"nearest-rank-ceil",
      scoreFormula:{locWeight:$locWeight, axisWeight:$axisWeight,
                    axes:["import","export_type","const","state","handler","jsx","style","api"]},
      n:$n, quartiles:$quartiles, stratified:$stratified,
      screens:$screens, layers:$layers, diagnostics:$diagnostics}' \
    > "$profile_out"

  echo "OK: profiled $n screens -> $profile_out" >&2
  return 0
}

# extract_route_paths() は本来 React Router 検出セクション(後方)に属するが、
# --self-test 分岐は run_self_tests() 呼び出し後に本スクリプトを exit するため、
# 後方定義のままだと自己テスト内(10-3)からの呼び出し時点で未定義になる。
# そのため定義をここ(self-test セクション直前)へ前倒しする。
extract_route_paths() {
  # $1: 対象ファイル。path: "..." / path= "..." 形式を抽出する。
  # 行コメント(行頭//のみ)とブロックコメント(単一行/* */)を除去してから抽出。
  # 行中インライン//はURL等で使われるため除去しない(行頭//のみ対象)。
  local f="$1"
  sed -E 's|^[[:space:]]*//.*||; s|/\*[^*]*\*/||g' "$f" 2>/dev/null \
    | grep -oE 'path[[:space:]]*[:=][[:space:]]*["'"'"'\`][^"'"'"'\`]+["'"'"'\`]' \
    | sed -E 's/^path[[:space:]]*[:=][[:space:]]*["'"'"'\`]//; s/["'"'"'\`]$//' || true
}

# --- --self-test: resolve_screen_files / --resolve-files の自己診断 ---
PASS_COUNT=0
FAIL_COUNT=0

test_report() {
  local name="$1" ok="$2" detail="${3:-}"
  if [ "$ok" -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $name" >&2
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $name -- $detail" >&2
  fi
}

assert_set_equal() {
  local name="$1" expected="$2" actual="$3"
  local exp_sorted act_sorted
  exp_sorted="$(printf '%s\n' "$expected" | grep -v '^$' | sort -u || true)"
  act_sorted="$(printf '%s\n' "$actual" | grep -v '^$' | sort -u || true)"
  if [ "$exp_sorted" = "$act_sorted" ]; then
    test_report "$name" 0
  else
    test_report "$name" 1 "expected=[$exp_sorted] actual=[$act_sorted]"
  fi
}

run_self_tests() {
  local root
  root="$(mktemp -d)"
  PASS_COUNT=0
  FAIL_COUNT=0

  # --- 陽性1: エイリアス解決 ---
  local t1="$root/t1"
  mkdir -p "$t1/src/screens/foo" "$t1/src/shared"
  printf "import { Button } from '@/shared/Button'\n" > "$t1/src/screens/foo/index.tsx"
  printf "export const Button = () => null\n" > "$t1/src/shared/Button.tsx"
  local t1_alias_file
  t1_alias_file="$(mktemp)"
  printf '@/\t%s\n' "$t1/src" > "$t1_alias_file"
  local t1_result
  t1_result="$(resolve_screen_files "$t1/src/screens/foo/index.tsx" "$t1/src" 6 "" "" "" "" "$t1_alias_file")"
  assert_set_equal "8-4-エイリアス解決" \
"$t1/src/screens/foo/index.tsx
$t1/src/shared/Button.tsx" \
    "$t1_result"
  rm -f "$t1_alias_file"

  # --- 陽性2: 共有除外 ---
  local t2="$root/t2"
  mkdir -p "$t2/src/screens/foo" "$t2/src/shared"
  printf "import { Widget } from '../../shared/Widget'\n" > "$t2/src/screens/foo/index.tsx"
  printf "export const Widget = () => null\n" > "$t2/src/shared/Widget.tsx"
  local t2_shared_file
  t2_shared_file="$(mktemp)"
  printf '(^|/)shared/\n' > "$t2_shared_file"
  local t2_result
  t2_result="$(resolve_screen_files "$t2/src/screens/foo/index.tsx" "$t2/src" 6 "$t2_shared_file" "" "" "" "")"
  assert_set_equal "8-4-共有除外" \
"$t2/src/screens/foo/index.tsx" \
    "$t2_result"
  rm -f "$t2_shared_file"

  # --- 陽性2b(9-1): ^アンカー付き共有パターンはソースルート相対パスで照合される ---
  # 絶対パス照合のままだと "^shared/" は tmpdir プレフィックスのせいで常に不一致になる。
  local t2b="$root/t2b"
  mkdir -p "$t2b/src/screens/foo" "$t2b/src/shared"
  printf "import { Widget } from '../../shared/Widget'\n" > "$t2b/src/screens/foo/index.tsx"
  printf "export const Widget = () => null\n" > "$t2b/src/shared/Widget.tsx"
  local t2b_shared_file
  t2b_shared_file="$(mktemp)"
  printf '^shared/\n' > "$t2b_shared_file"
  local t2b_result
  t2b_result="$(resolve_screen_files "$t2b/src/screens/foo/index.tsx" "$t2b/src" 6 "$t2b_shared_file" "" "" "" "")"
  assert_set_equal "9-1-共有除外-アンカー付きパターン相対化" \
"$t2b/src/screens/foo/index.tsx" \
    "$t2b_result"
  rm -f "$t2b_shared_file"

  # --- 陽性3: bare import 不追跡 ---
  local t3="$root/t3"
  mkdir -p "$t3/src/screens/foo"
  printf "import React from 'react'\nimport { Local } from './Local'\n" > "$t3/src/screens/foo/index.tsx"
  printf "export const Local = () => null\n" > "$t3/src/screens/foo/Local.tsx"
  local t3_result
  t3_result="$(resolve_screen_files "$t3/src/screens/foo/index.tsx" "$t3/src" 6 "" "" "" "" "")"
  assert_set_equal "8-4-bare-import不追跡" \
"$t3/src/screens/foo/index.tsx
$t3/src/screens/foo/Local.tsx" \
    "$t3_result"

  # --- 陽性4: 循環収束 ---
  local t4="$root/t4"
  mkdir -p "$t4/src/screens/foo"
  printf "import { A } from './A'\n" > "$t4/src/screens/foo/index.tsx"
  printf "import { B } from './B'\n" > "$t4/src/screens/foo/A.tsx"
  printf "import { A } from './A'\n" > "$t4/src/screens/foo/B.tsx"
  local t4_result
  t4_result="$(resolve_screen_files "$t4/src/screens/foo/index.tsx" "$t4/src" 6 "" "" "" "" "")"
  assert_set_equal "8-4-循環収束" \
"$t4/src/screens/foo/index.tsx
$t4/src/screens/foo/A.tsx
$t4/src/screens/foo/B.tsx" \
    "$t4_result"

  # --- 陽性5: 深さ上限(maxdepth=2ならentry/f1/f2のみ) ---
  local t5="$root/t5"
  mkdir -p "$t5/src/screens/foo"
  printf "import { F1 } from './f1'\n" > "$t5/src/screens/foo/index.tsx"
  printf "import { F2 } from './f2'\n" > "$t5/src/screens/foo/f1.tsx"
  printf "import { F3 } from './f3'\n" > "$t5/src/screens/foo/f2.tsx"
  printf "import { F4 } from './f4'\n" > "$t5/src/screens/foo/f3.tsx"
  printf "export const F4 = 1\n" > "$t5/src/screens/foo/f4.tsx"
  local t5_result
  t5_result="$(resolve_screen_files "$t5/src/screens/foo/index.tsx" "$t5/src" 2 "" "" "" "" "")"
  assert_set_equal "8-4-深さ上限" \
"$t5/src/screens/foo/index.tsx
$t5/src/screens/foo/f1.tsx
$t5/src/screens/foo/f2.tsx" \
    "$t5_result"

  # --- 陽性6: 他画面エントリ境界 ---
  local t6="$root/t6"
  mkdir -p "$t6/src/screens/foo" "$t6/src/screens/bar"
  printf "import Bar from '../bar/index'\n" > "$t6/src/screens/foo/index.tsx"
  printf "import { BarOnly } from './BarOnly'\n" > "$t6/src/screens/bar/index.tsx"
  printf "export const BarOnly = 1\n" > "$t6/src/screens/bar/BarOnly.tsx"
  local t6_others_file
  t6_others_file="$(mktemp)"
  printf '%s\n' "$t6/src/screens/bar/index.tsx" > "$t6_others_file"
  local t6_result
  t6_result="$(resolve_screen_files "$t6/src/screens/foo/index.tsx" "$t6/src" 6 "" "$t6_others_file" "" "" "")"
  assert_set_equal "8-4-他画面エントリ境界" \
"$t6/src/screens/foo/index.tsx" \
    "$t6_result"
  rm -f "$t6_others_file"

  # --- 陽性7: 他画面ID境界 ---
  local t7="$root/t7"
  mkdir -p "$t7/src/screens/foo"
  printf "import { Detail } from './T-001-detail'\nimport { Other } from './T-002-other'\n" > "$t7/src/screens/foo/T-001-index.tsx"
  printf "export const Detail = 1\n" > "$t7/src/screens/foo/T-001-detail.tsx"
  printf "import { Leak } from './T-002-leak'\n" > "$t7/src/screens/foo/T-002-other.tsx"
  printf "export const Leak = 1\n" > "$t7/src/screens/foo/T-002-leak.tsx"
  local t7_result
  t7_result="$(resolve_screen_files "$t7/src/screens/foo/T-001-index.tsx" "$t7/src" 6 "" "" 'T-[0-9]+' "T-001" "")"
  assert_set_equal "8-4-他画面ID境界" \
"$t7/src/screens/foo/T-001-index.tsx
$t7/src/screens/foo/T-001-detail.tsx" \
    "$t7_result"

  # --- 陰性1: entryFile不在で無クラッシュ ---
  local n1_result n1_status
  set +e
  n1_result="$(resolve_screen_files "$root/does-not-exist/index.tsx" "$root/does-not-exist" 6 "" "" "" "" "")"
  n1_status=$?
  set -e
  if [ "$n1_status" -eq 0 ] && [ "$n1_result" = "$root/does-not-exist/index.tsx" ]; then
    test_report "8-4-entryFile不在で無クラッシュ" 0
  else
    test_report "8-4-entryFile不在で無クラッシュ" 1 "status=$n1_status result=[$n1_result]"
  fi

  # --- 陰性2: 共有パターンがentry自身に一致しても含まれる ---
  local t8="$root/t8"
  mkdir -p "$t8/src/screens/foo"
  printf "export const Foo = 1\n" > "$t8/src/screens/foo/index.tsx"
  local t8_shared_file
  t8_shared_file="$(mktemp)"
  printf '(^|/)screens/foo/\n' > "$t8_shared_file"
  local t8_result
  t8_result="$(resolve_screen_files "$t8/src/screens/foo/index.tsx" "$t8/src" 6 "$t8_shared_file" "" "" "" "")"
  assert_set_equal "8-4-共有パターンentry自身包含" \
"$t8/src/screens/foo/index.tsx" \
    "$t8_result"
  rm -f "$t8_shared_file"

  # --- 陽性8(10-1): ドット入り非コード拡張子(.zustand)でも候補付与される ---
  local t12="$root/t12"
  mkdir -p "$t12/src/screens/foo"
  printf "import { store } from './store.zustand'\n" > "$t12/src/screens/foo/index.tsx"
  printf "export const store = {}\n" > "$t12/src/screens/foo/store.zustand.tsx"
  local t12_result
  t12_result="$(resolve_screen_files "$t12/src/screens/foo/index.tsx" "$t12/src" 6 "" "" "" "" "")"
  assert_set_equal "10-1-ドット入り非コード拡張子-候補付与" \
"$t12/src/screens/foo/index.tsx
$t12/src/screens/foo/store.zustand.tsx" \
    "$t12_result"

  # --- 陽性9(10-1): ドット入り .data も候補付与される ---
  local t13="$root/t13"
  mkdir -p "$t13/src/screens/foo"
  printf "import { data } from './foo.data'\n" > "$t13/src/screens/foo/index.tsx"
  printf "export const data = {}\n" > "$t13/src/screens/foo/foo.data.ts"
  local t13_result
  t13_result="$(resolve_screen_files "$t13/src/screens/foo/index.tsx" "$t13/src" 6 "" "" "" "" "")"
  assert_set_equal "10-1-ドット入り.data-候補付与" \
"$t13/src/screens/foo/index.tsx
$t13/src/screens/foo/foo.data.ts" \
    "$t13_result"

  # --- 陰性3(10-1): 非コード拡張子(CSS)は集合に含まれない ---
  local t14="$root/t14"
  mkdir -p "$t14/src/screens/foo"
  printf "import './style.css'\n" > "$t14/src/screens/foo/index.tsx"
  printf "body { color: red }\n" > "$t14/src/screens/foo/style.css"
  local t14_result
  t14_result="$(resolve_screen_files "$t14/src/screens/foo/index.tsx" "$t14/src" 6 "" "" "" "" "")"
  assert_set_equal "10-1-非コード拡張子CSS-集合外" \
"$t14/src/screens/foo/index.tsx" \
    "$t14_result"

  # --- 陰性4(10-3): コメントアウトされたルートは検出されない ---
  local t15="$root/t15"
  mkdir -p "$t15"
  printf '  // { path: "/old-route", element: <OldPage /> },\n  { path: "/active-route", element: <ActivePage /> },\n' > "$t15/routes.tsx"
  local t15_result
  t15_result="$(extract_route_paths "$t15/routes.tsx")"
  if [ "$t15_result" = "/active-route" ]; then
    test_report "10-3-コメントアウトルート除外" 0
  else
    test_report "10-3-コメントアウトルート除外" 1 "got='$t15_result'"
  fi

  # --- 追加: --resolve-files サブコマンドの疎通確認 ---
  local t9="$root/t9"
  mkdir -p "$t9/src/screens/foo" "$t9/src/shared"
  printf "import { Button } from '@/shared/Button'\n" > "$t9/src/screens/foo/index.tsx"
  printf "export const Button = () => null\n" > "$t9/src/shared/Button.tsx"
  local t9_manifest_in t9_manifest_out
  t9_manifest_in="$(mktemp)"
  t9_manifest_out="$(mktemp)"
  cat > "$t9_manifest_in" <<EOF
{
  "generatedAt": null,
  "sourceDir": "$t9/src",
  "strategy": {"pathAliases": {"@/": ""}, "importTraversalMaxDepth": 6},
  "detectionSummary": {"method": "nextjs-app", "screenCount": 1},
  "screens": [
    {"screenKey": "foo", "kind": "route", "route": "/foo", "entryFile": "$t9/src/screens/foo/index.tsx", "files": [], "fileCount": 0}
  ]
}
EOF
  resolve_files_subcommand "$t9_manifest_in" "$t9/src" "$t9_manifest_out"
  local t9_count t9_files t9_expected
  t9_count="$(jq -r '.screens[0].fileCount' "$t9_manifest_out")"
  t9_files="$(jq -r '.screens[0].files | sort | join(",")' "$t9_manifest_out")"
  t9_expected="$(printf '%s\n%s\n' "$t9/src/screens/foo/index.tsx" "$t9/src/shared/Button.tsx" | sort | paste -sd, -)"
  if [ "$t9_count" = "2" ] && [ "$t9_files" = "$t9_expected" ]; then
    test_report "8-4-resolve-filesサブコマンド" 0
  else
    test_report "8-4-resolve-filesサブコマンド" 1 "count=$t9_count files=$t9_files expected=$t9_expected"
  fi
  rm -f "$t9_manifest_in" "$t9_manifest_out"

  # --- 追加(9-3): --resolve-files の複数画面一括処理(バッチBFS)の疎通確認 ---
  # 画面foo が 他画面(bar)のentryFile と ^アンカー付き共有パターン一致のファイルを
  # 同時にimportするフィクスチャで、境界(b)(他画面entryFile)と境界(a)(9-1の相対化
  # 照合)がバッチ処理経路でも機能することを検証する(単一画面版のt2b/t6は
  # resolve_screen_files直接呼び出しのみを検証しており、--resolve-filesのバッチ
  # awk処理経路を通していなかったギャップを埋める)。
  local t10="$root/t10"
  mkdir -p "$t10/src/screens/foo" "$t10/src/screens/bar" "$t10/src/shared"
  printf "import Bar from '../bar/index'\nimport { Widget } from '../../shared/Widget'\n" > "$t10/src/screens/foo/index.tsx"
  printf "export const Bar = 1\n" > "$t10/src/screens/bar/index.tsx"
  printf "export const Widget = () => null\n" > "$t10/src/shared/Widget.tsx"
  local t10_manifest_in t10_manifest_out
  t10_manifest_in="$(mktemp)"
  t10_manifest_out="$(mktemp)"
  cat > "$t10_manifest_in" <<EOF
{
  "generatedAt": null,
  "sourceDir": "$t10/src",
  "strategy": {"sharedDirPatterns": ["^shared/"], "importTraversalMaxDepth": 6},
  "detectionSummary": {"method": "nextjs-app", "screenCount": 2},
  "screens": [
    {"screenKey": "foo", "kind": "route", "route": "/foo", "entryFile": "$t10/src/screens/foo/index.tsx", "files": [], "fileCount": 0},
    {"screenKey": "bar", "kind": "route", "route": "/bar", "entryFile": "$t10/src/screens/bar/index.tsx", "files": [], "fileCount": 0}
  ]
}
EOF
  resolve_files_subcommand "$t10_manifest_in" "$t10/src" "$t10_manifest_out"
  local t10_foo_files t10_bar_files
  t10_foo_files="$(jq -r '.screens[] | select(.screenKey=="foo") | .files | sort | join(",")' "$t10_manifest_out")"
  t10_bar_files="$(jq -r '.screens[] | select(.screenKey=="bar") | .files | sort | join(",")' "$t10_manifest_out")"
  if [ "$t10_foo_files" = "$t10/src/screens/foo/index.tsx" ] && [ "$t10_bar_files" = "$t10/src/screens/bar/index.tsx" ]; then
    test_report "9-3-resolve-files複数画面バッチ境界維持" 0
  else
    test_report "9-3-resolve-files複数画面バッチ境界維持" 1 "foo=$t10_foo_files bar=$t10_bar_files"
  fi
  rm -f "$t10_manifest_in" "$t10_manifest_out"

  # --- 既存検出の最小回帰(Next.js App Routerの最小フィクスチャで従来フローが壊れていないこと) ---
  local reg="$root/reg"
  mkdir -p "$reg/app/dashboard"
  printf "module.exports = {}\n" > "$reg/next.config.js"
  printf "export default function Page() { return null }\n" > "$reg/app/dashboard/page.tsx"
  local reg_manifest reg_status
  reg_manifest="$(mktemp)"
  reg_status=0
  bash "$0" "$reg" "$reg_manifest" >/dev/null 2>&1 || reg_status=$?
  local reg_screen_count reg_route
  reg_screen_count="$(jq -r '.detectionSummary.screenCount' "$reg_manifest" 2>/dev/null || echo -1)"
  reg_route="$(jq -r '.screens[0].route' "$reg_manifest" 2>/dev/null || echo "")"
  if [ "$reg_status" -eq 0 ] && [ "$reg_screen_count" = "1" ] && [ "$reg_route" = "/dashboard" ]; then
    test_report "8-4-既存検出の最小回帰" 0
  else
    test_report "8-4-既存検出の最小回帰" 1 "status=$reg_status count=$reg_screen_count route=$reg_route"
  fi
  rm -f "$reg_manifest"

  # --- 追加: 組み込み検出フロー生成マニフェスト → --resolve-files CLI の疎通確認 ---
  # (t9はハンドクラフトしたマニフェストでresolve_files_subcommand単体を検証するのに対し、
  #  こちらは実際にbuiltin検出器が出力したマニフェストをCLI経由の--resolve-filesに渡し、
  #  スキーマが噛み合うこと・fileCountがディレクトリ収集より増えることを検証する)
  local chain="$root/chain"
  mkdir -p "$chain/app/dashboard" "$chain/app/shared"
  printf "module.exports = {}\n" > "$chain/next.config.js"
  printf "import { Widget } from '../shared/Widget'\nexport default function Page(){return null}\n" > "$chain/app/dashboard/page.tsx"
  printf "export const Widget = () => null\n" > "$chain/app/shared/Widget.tsx"
  local chain_manifest chain_manifest_out chain_status
  chain_manifest="$(mktemp)"
  chain_manifest_out="$(mktemp)"
  chain_status=0
  bash "$0" "$chain" "$chain_manifest" >/dev/null 2>&1 || chain_status=$?
  bash "$0" --resolve-files "$chain_manifest" "$chain" "$chain_manifest_out" >/dev/null 2>&1 || chain_status=$?
  local chain_count chain_files
  chain_count="$(jq -r '.screens[0].fileCount' "$chain_manifest_out" 2>/dev/null || echo -1)"
  chain_files="$(jq -r '.screens[0].files | sort | join(",")' "$chain_manifest_out" 2>/dev/null || echo "")"
  if [ "$chain_status" -eq 0 ] && [ "$chain_count" = "2" ] \
    && printf '%s' "$chain_files" | grep -qF "$chain/app/dashboard/page.tsx" \
    && printf '%s' "$chain_files" | grep -qF "$chain/app/shared/Widget.tsx"; then
    test_report "8-4-builtin検出からresolve-files連結" 0
  else
    test_report "8-4-builtin検出からresolve-files連結" 1 "status=$chain_status count=$chain_count files=$chain_files"
  fi
  rm -f "$chain_manifest" "$chain_manifest_out"

  # --- 追加(9-2): 通常検出フロー(2引数起動、--resolve-files を経由しない)でも
  # BFS(import 再帰追跡)によりファイル集合が解決され、共有ディレクトリが除外されること。
  # --strategy-json で sharedDirPatterns/pathAliases を明示しないと、合成strategyには
  # 両フィールドが存在せず共有除外が機能しないため、必ず --strategy-json 経由で検証する。
  local t11="$root/t11"
  mkdir -p "$t11/app/dashboard" "$t11/shared"
  printf "module.exports = {}\n" > "$t11/next.config.js"
  printf "import { Widget } from '@/shared/Widget'\nexport default function Page(){return null}\n" > "$t11/app/dashboard/page.tsx"
  printf "export const Widget = () => null\n" > "$t11/shared/Widget.tsx"
  local t11_strategy_file t11_manifest t11_status
  t11_strategy_file="$(mktemp)"
  cat > "$t11_strategy_file" <<EOF
{"sharedDirPatterns": ["^shared/"], "pathAliases": {"@/": ""}, "importTraversalMaxDepth": 6}
EOF
  t11_manifest="$(mktemp)"
  t11_status=0
  bash "$0" "$t11" "$t11_manifest" --strategy-json "$t11_strategy_file" >/dev/null 2>&1 || t11_status=$?
  local t11_count t11_files
  t11_count="$(jq -r '.screens[0].fileCount' "$t11_manifest" 2>/dev/null || echo -1)"
  t11_files="$(jq -r '.screens[0].files | sort | join(",")' "$t11_manifest" 2>/dev/null || echo "")"
  if [ "$t11_status" -eq 0 ] && [ "$t11_count" = "1" ] && [ "$t11_files" = "$t11/app/dashboard/page.tsx" ]; then
    test_report "9-2-通常検出フローへのBFS統合-共有除外" 0
  else
    test_report "9-2-通常検出フローへのBFS統合-共有除外" 1 "status=$t11_status count=$t11_count files=$t11_files"
  fi
  rm -f "$t11_strategy_file" "$t11_manifest"

  # --- 追加: --profile サブコマンドの複雑度プロファイリング(8-6) ---
  build_profile_fixture_file() {
    local path="$1" fn="$2" i=0
    mkdir -p "$(dirname "$path")"
    : > "$path"
    while [ "$i" -lt "$fn" ]; do
      echo "import { sym${i} } from './sym${i}';" >> "$path"
      i=$((i + 1))
    done
  }

  local profile_recount_script
  profile_recount_script="$(cd "$(dirname "$0")/../../../.claude/skills/extracting-unit-facts-from-code/scripts" && pwd)/recount-facts.sh"

  local prepo="$root/profile-repo"
  build_profile_fixture_file "$prepo/src/screens/ScreenA/Foo.tsx" 2
  build_profile_fixture_file "$prepo/src/screens/ScreenB/Foo.tsx" 5
  build_profile_fixture_file "$prepo/src/screens/ScreenC/Foo.tsx" 10
  build_profile_fixture_file "$prepo/src/screens/ScreenD/Foo.tsx" 20

  local pmanifest="$root/profile-manifest.json"
  jq -n \
    --arg fa "$prepo/src/screens/ScreenA/Foo.tsx" \
    --arg fb "$prepo/src/screens/ScreenB/Foo.tsx" \
    --arg fc "$prepo/src/screens/ScreenC/Foo.tsx" \
    --arg fd "$prepo/src/screens/ScreenD/Foo.tsx" \
    '{generatedAt:null, sourceDir:"dummy", screens:[
      {screenKey:"screen-a",kind:"route",files:[$fa]},
      {screenKey:"screen-b",kind:"route",files:[$fb]},
      {screenKey:"screen-c",kind:"route",files:[$fc]},
      {screenKey:"screen-d",kind:"route",files:[$fd]}
    ]}' > "$pmanifest"

  local pout="$root/profile-out.json" pstatus=0
  bash "$0" --profile "$pmanifest" "$prepo" "$pout" --recount-script "$profile_recount_script" --repo-root "$prepo" >/dev/null 2>&1 || pstatus=$?
  if [ "$pstatus" -eq 0 ]; then
    local pt_a pt_b pt_c pt_d
    pt_a="$(jq -r '.screens[] | select(.screenKey=="screen-a") | .layer' "$pout")"
    pt_b="$(jq -r '.screens[] | select(.screenKey=="screen-b") | .layer' "$pout")"
    pt_c="$(jq -r '.screens[] | select(.screenKey=="screen-c") | .layer' "$pout")"
    pt_d="$(jq -r '.screens[] | select(.screenKey=="screen-d") | .layer' "$pout")"
    if [ "$pt_a" = "S" ] && [ "$pt_b" = "M" ] && [ "$pt_c" = "L" ] && [ "$pt_d" = "XL" ]; then
      test_report "8-6-profile-S/M/L/XL割当" 0
    else
      test_report "8-6-profile-S/M/L/XL割当" 1 "A=$pt_a B=$pt_b C=$pt_c D=$pt_d"
    fi
  else
    test_report "8-6-profile-S/M/L/XL割当" 1 "status=$pstatus"
  fi

  if [ "$pstatus" -eq 0 ]; then
    local has_screens has_layers has_axis
    has_screens="$(jq -r 'has("screens")' "$pout")"
    has_layers="$(jq -r 'has("layers")' "$pout")"
    has_axis="$(jq -r '.screens[0] | has("axisBreakdown")' "$pout")"
    if [ "$has_screens" = "true" ] && [ "$has_layers" = "true" ] && [ "$has_axis" = "true" ]; then
      test_report "8-6-profile-出力スキーマ確定" 0
    else
      test_report "8-6-profile-出力スキーマ確定" 1 "has_screens=$has_screens has_layers=$has_layers has_axis=$has_axis"
    fi
  else
    test_report "8-6-profile-出力スキーマ確定" 1 "status=$pstatus"
  fi

  if [ "$pstatus" -eq 0 ]; then
    local sk_type sk_match
    sk_type="$(jq -r '.layers | to_entries[0].value.sampleK | type' "$pout")"
    sk_match="$(jq -r '.layers | to_entries[0].value | (.sampleK == (.sampledScreenKeys | length))' "$pout")"
    if [ "$sk_type" = "number" ] && [ "$sk_match" = "true" ]; then
      test_report "10-2-sampleK数値一致" 0
    else
      test_report "10-2-sampleK数値一致" 1 "type=$sk_type match=$sk_match"
    fi
  else
    test_report "10-2-sampleK数値一致" 1 "status=$pstatus"
  fi

  local pmanifest_small="$root/profile-manifest-small.json"
  jq -n \
    --arg fa "$prepo/src/screens/ScreenA/Foo.tsx" \
    --arg fb "$prepo/src/screens/ScreenB/Foo.tsx" \
    '{generatedAt:null, sourceDir:"dummy", screens:[
      {screenKey:"screen-a",kind:"route",files:[$fa]},
      {screenKey:"screen-b",kind:"route",files:[$fb]}
    ]}' > "$pmanifest_small"
  local pout_small="$root/profile-out-small.json" pstatus_small=0
  bash "$0" --profile "$pmanifest_small" "$prepo" "$pout_small" --recount-script "$profile_recount_script" --repo-root "$prepo" >/dev/null 2>&1 || pstatus_small=$?
  if [ "$pstatus_small" -eq 0 ]; then
    local pts_a pts_b pts_q pts_stratified
    pts_a="$(jq -r '.screens[] | select(.screenKey=="screen-a") | .layer' "$pout_small")"
    pts_b="$(jq -r '.screens[] | select(.screenKey=="screen-b") | .layer' "$pout_small")"
    pts_q="$(jq -c '.quartiles' "$pout_small")"
    pts_stratified="$(jq -r '.stratified' "$pout_small")"
    if [ "$pts_a" = "ALL" ] && [ "$pts_b" = "ALL" ] && [ "$pts_q" = "null" ] && [ "$pts_stratified" = "false" ]; then
      test_report "8-6-profile-N4未満ALL縮退" 0
    else
      test_report "8-6-profile-N4未満ALL縮退" 1 "A=$pts_a B=$pts_b quartiles=$pts_q stratified=$pts_stratified"
    fi
  else
    test_report "8-6-profile-N4未満ALL縮退" 1 "status=$pstatus_small"
  fi

  build_profile_fixture_file "$prepo/src/screens/ScreenE1/Foo.tsx" 5
  build_profile_fixture_file "$prepo/src/screens/ScreenE2/Foo.tsx" 5
  build_profile_fixture_file "$prepo/src/screens/ScreenE3/Foo.tsx" 5
  build_profile_fixture_file "$prepo/src/screens/ScreenE4/Foo.tsx" 5
  build_profile_fixture_file "$prepo/src/screens/ScreenE5/Foo.tsx" 5
  local pmanifest_flat="$root/profile-manifest-flat.json"
  jq -n \
    --arg f1 "$prepo/src/screens/ScreenE1/Foo.tsx" \
    --arg f2 "$prepo/src/screens/ScreenE2/Foo.tsx" \
    --arg f3 "$prepo/src/screens/ScreenE3/Foo.tsx" \
    --arg f4 "$prepo/src/screens/ScreenE4/Foo.tsx" \
    --arg f5 "$prepo/src/screens/ScreenE5/Foo.tsx" \
    '{generatedAt:null, sourceDir:"dummy", screens:[
      {screenKey:"screen-e1",kind:"route",files:[$f1]},
      {screenKey:"screen-e2",kind:"route",files:[$f2]},
      {screenKey:"screen-e3",kind:"route",files:[$f3]},
      {screenKey:"screen-e4",kind:"route",files:[$f4]},
      {screenKey:"screen-e5",kind:"route",files:[$f5]}
    ]}' > "$pmanifest_flat"
  local pout_flat="$root/profile-out-flat.json" pstatus_flat=0
  bash "$0" --profile "$pmanifest_flat" "$prepo" "$pout_flat" --recount-script "$profile_recount_script" --repo-root "$prepo" >/dev/null 2>&1 || pstatus_flat=$?
  if [ "$pstatus_flat" -eq 0 ]; then
    local ptf_count ptf_tier ptf_q1 ptf_q2 ptf_q3
    ptf_count="$(jq -r '[.screens[].layer] | unique | length' "$pout_flat")"
    ptf_tier="$(jq -r '.screens[0].layer' "$pout_flat")"
    ptf_q1="$(jq -r '.quartiles.q1' "$pout_flat")"
    ptf_q2="$(jq -r '.quartiles.q2' "$pout_flat")"
    ptf_q3="$(jq -r '.quartiles.q3' "$pout_flat")"
    if [ "$ptf_count" = "1" ] && [ "$ptf_tier" = "S" ] && [ "$ptf_q1" = "$ptf_q2" ] && [ "$ptf_q2" = "$ptf_q3" ]; then
      test_report "8-6-profile-全同値縮退" 0
    else
      test_report "8-6-profile-全同値縮退" 1 "tier種別数=$ptf_count tier=$ptf_tier q1=$ptf_q1 q2=$ptf_q2 q3=$ptf_q3"
    fi
  else
    test_report "8-6-profile-全同値縮退" 1 "status=$pstatus_flat"
  fi

  local pbad_status=0
  bash "$0" --profile "$pmanifest" "$prepo" "$root/profile-out-bad.json" --recount-script "$root/no-such-recount.sh" --repo-root "$prepo" >/dev/null 2>&1 || pbad_status=$?
  if [ "$pbad_status" -ne 0 ]; then
    test_report "8-6-profile-recount-script不在でexit非0" 0
  else
    test_report "8-6-profile-recount-script不在でexit非0" 1 "status=$pbad_status"
  fi

  rm -rf "$root"

  echo "self-test: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL" >&2
  [ "$FAIL_COUNT" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  if run_self_tests; then
    exit 0
  else
    exit 1
  fi
fi

if [ "${1:-}" = "--resolve-files" ]; then
  shift
  if [ "$#" -ne 3 ]; then
    echo "Usage: detect-screens.sh --resolve-files <manifest-in> <source-dir> <manifest-out>" >&2
    exit 1
  fi
  resolve_files_subcommand "$1" "$2" "$3"
  exit 0
fi

if [ "${1:-}" = "--profile" ]; then
  shift
  run_detect_screens_profile "$@"
  exit $?
fi

# ============================================================================
# 既存の画面検出フロー(変更なし)
# ============================================================================

SCREEN_ID_REGEX=""
VIEW_SWITCH_PATTERN=""
EXCLUDE_PATTERN=""
STRATEGY_JSON_FILE=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-id-regex)
      SCREEN_ID_REGEX="${2:-}"
      shift 2
      ;;
    --view-switch-pattern)
      VIEW_SWITCH_PATTERN="${2:-}"
      shift 2
      ;;
    --exclude)
      EXCLUDE_PATTERN="${2:-}"
      shift 2
      ;;
    --strategy-json)
      STRATEGY_JSON_FILE="${2:-}"
      shift 2
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
  echo "Usage: detect-screens.sh <source-dir> <manifest-out-path> [--screen-id-regex <ERE>] [--view-switch-pattern <ERE>] [--exclude <ERE>] [--strategy-json <file>]" >&2
  exit 1
fi
SOURCE_DIR="${POSITIONAL[0]}"
MANIFEST_OUT="${POSITIONAL[1]}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [ -n "$STRATEGY_JSON_FILE" ] && [ ! -f "$STRATEGY_JSON_FILE" ]; then
  echo "ERROR: --strategy-json file not found: $STRATEGY_JSON_FILE" >&2
  exit 1
fi

# --- デフォルト除外(node_modules/tests/stories系ディレクトリ・test/spec/storiesファイル) ---
DEFAULT_EXCLUDE_ERE='(^|/)(node_modules|tests|__tests__|test|__mocks__|stories)(/|$)|\.(test|spec|stories)\.[^/]+$'
EXCLUDE_REGEX="$DEFAULT_EXCLUDE_ERE"
if [ -n "$EXCLUDE_PATTERN" ]; then
  EXCLUDE_REGEX="${EXCLUDE_REGEX}|${EXCLUDE_PATTERN}"
fi

# --- 検出方式の決定(戦略宣言を最優先) ---
# strategy JSON の extractionMethod が builtin-* を指定していれば該当検出器のみを使う。
# 未指定/custom/auto の場合は自動チェーン。ただし自動チェーンの Next.js 判定は
# next.config.* の実在(SOURCE_DIR/その親/祖父)を必須とする。Vite+React Router プロジェクトの
# 慣習的な src/pages/ ディレクトリを Next.js Pages Router と誤判定した実害への対策。
FORCED_METHOD=""
if [ -n "$STRATEGY_JSON_FILE" ]; then
  FORCED_METHOD="$(grep -o '"extractionMethod"[[:space:]]*:[[:space:]]*"[^"]*"' "$STRATEGY_JSON_FILE" 2>/dev/null \
    | head -1 | sed -E 's/.*"extractionMethod"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)"
  case "$FORCED_METHOD" in
    builtin-nextjs-app|builtin-nextjs-pages|builtin-react-router|builtin-fallback) ;;
    *) FORCED_METHOD="" ;;
  esac
fi

has_next_config() {
  local d
  for d in "$SOURCE_DIR" "$SOURCE_DIR/.." "$SOURCE_DIR/../.."; do
    if ls "$d"/next.config.* >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

allow_method() {
  # $1: 検出器名。FORCED_METHOD 指定時はそれのみ許可。
  # 自動チェーン時、Next.js 系は next.config.* の実在を必須とする。
  local m="$1"
  if [ -n "$FORCED_METHOD" ]; then
    [ "$m" = "$FORCED_METHOD" ]
    return
  fi
  case "$m" in
    builtin-nextjs-app|builtin-nextjs-pages) has_next_config ;;
    *) return 0 ;;
  esac
}

TMP_ROWS="$(mktemp)"
SEEN_KEYS_FILE="$(mktemp)"
TMP_MERGED="$(mktemp)"
TMP_KEYED="$(mktemp)"
TMP_EMBEDDED="$(mktemp)"
TMP_ALL="$(mktemp)"
TMP_CLUSTERS="$(mktemp)"
trap 'rm -f "$TMP_ROWS" "$SEEN_KEYS_FILE" "$TMP_MERGED" "$TMP_KEYED" "$TMP_EMBEDDED" "$TMP_ALL" "$TMP_CLUSTERS" "$RESOLVE_COMMON_AWK_FILE" "$RESOLVE_AWK_FILE" "$RESOLVE_BATCH_AWK_FILE" "$STRATEGY_SHARED_FILE" "$STRATEGY_ALIAS_FILE" "$STRATEGY_ALL_ENTRIES_FILE"' EXIT

detection_method=""

# --- 1. Next.js App Router ---
if allow_method "builtin-nextjs-app" && [ -d "$SOURCE_DIR/app" ]; then
  pagefiles="$(find "$SOURCE_DIR/app" -type f \( -name "page.tsx" -o -name "page.jsx" -o -name "page.js" \) 2>/dev/null | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" || true)"
  if [ -n "$pagefiles" ]; then
    detection_method="nextjs-app"
    while IFS= read -r pagefile; do
      [ -z "$pagefile" ] && continue
      rel="${pagefile#"$SOURCE_DIR"/app}"
      rel="${rel%/page.*}"
      [ -z "$rel" ] && rel="/"
      route="$(printf '%s' "$rel" | sed -E 's#/\([^)]*\)##g')"
      [ -z "$route" ] && route="/"
      route="$(printf '%s' "$route" | sed -E 's#\[\.\.\.[^]]+\]#*#g; s#\[([^]]+)\]#:\1#g')"
      entry_dir="$(dirname "$pagefile")"
      printf '%s\t%s\t%s\t%s\n' "$route" "$entry_dir" "$pagefile" "high" >> "$TMP_ROWS"
    done <<< "$pagefiles"
  fi
fi

# --- 2. Next.js Pages Router ---
if allow_method "builtin-nextjs-pages" && [ -z "$detection_method" ] && [ -d "$SOURCE_DIR/pages" ]; then
  pagefiles="$(find "$SOURCE_DIR/pages" -type f \( -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) 2>/dev/null \
    | grep -v node_modules \
    | grep -Ev '/_app\.[jt]sx?$' \
    | grep -Ev '/_document\.[jt]sx?$' \
    | grep -Ev '/api/' \
    | grep -Ev "$EXCLUDE_REGEX" || true)"
  if [ -n "$pagefiles" ]; then
    detection_method="nextjs-pages"
    while IFS= read -r pagefile; do
      [ -z "$pagefile" ] && continue
      rel="${pagefile#"$SOURCE_DIR"/pages}"
      rel="${rel%.*}"
      rel="${rel%/index}"
      [ -z "$rel" ] && rel="/"
      route="$(printf '%s' "$rel" | sed -E 's#\[\.\.\.[^]]+\]#*#g; s#\[([^]]+)\]#:\1#g')"
      entry_dir="$(dirname "$pagefile")"
      printf '%s\t%s\t%s\t%s\n' "$route" "$entry_dir" "$pagefile" "high" >> "$TMP_ROWS"
    done <<< "$pagefiles"
  fi
fi

# --- 3. React Router (フラット抽出 + useRoutes/createBrowserRouter の1段 import 追跡) ---
# extract_route_paths() の定義は --self-test (run_self_tests 内の 10-3 テスト)
# から呼び出すため、self-test 分岐(--self-test 到達時に本箇所より前で exit する)
# より前(--self-test セクション直前)へ移動済み。

if allow_method "builtin-react-router" && [ -z "$detection_method" ]; then
  router_files="$(grep -rlE 'createBrowserRouter|createHashRouter|useRoutes|<Route\b' "$SOURCE_DIR" \
    --include='*.tsx' --include='*.jsx' --include='*.ts' --include='*.js' 2>/dev/null \
    | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" || true)"
  if [ -n "$router_files" ]; then
    detection_method="react-router"
    while IFS= read -r rf; do
      [ -z "$rf" ] && continue
      routes="$(extract_route_paths "$rf")"
      resolved_file="$rf"
      if [ -z "$routes" ]; then
        # 2段階追跡: useRoutes(識別子) / createBrowserRouter(識別子) のように
        # 引数がインライン配列ではなく識別子の場合、import 元を1段だけ辿って定義ファイルを解決する
        ident="$(grep -oE '(useRoutes|createBrowserRouter)\([[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\)' "$rf" 2>/dev/null \
          | head -1 | sed -E 's/^(useRoutes|createBrowserRouter)\([[:space:]]*//; s/[[:space:]]*\)$//' || true)"
        if [ -n "$ident" ]; then
          import_line="$(grep -E "^import[[:space:]].*\\b${ident}\\b.*from" "$rf" 2>/dev/null | head -1 || true)"
          if [ -n "$import_line" ]; then
            import_path="$(printf '%s' "$import_line" | grep -oE "['\"][^'\"]+['\"]" | head -1 | sed "s/^['\"]//; s/['\"]\$//" || true)"
            if [ -n "$import_path" ]; then
              import_base="$(basename "$import_path")"
              import_base="${import_base%.*}"
              target_file="$(find "$SOURCE_DIR" -type f \( -iname "${import_base}.tsx" -o -iname "${import_base}.jsx" -o -iname "${import_base}.ts" -o -iname "${import_base}.js" \) 2>/dev/null \
                | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" | head -1 || true)"
              if [ -z "$target_file" ]; then
                # import 先がディレクトリ(index.{tsx,jsx,ts,js})の場合のフォールバック解決
                target_dir="$(find "$SOURCE_DIR" -type d -iname "$import_base" 2>/dev/null \
                  | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" | head -1 || true)"
                if [ -n "$target_dir" ]; then
                  target_file="$(find "$target_dir" -maxdepth 1 -type f \( -iname "index.tsx" -o -iname "index.jsx" -o -iname "index.ts" -o -iname "index.js" \) 2>/dev/null | head -1 || true)"
                fi
              fi
              if [ -n "$target_file" ]; then
                target_routes="$(extract_route_paths "$target_file")"
                if [ -n "$target_routes" ]; then
                  routes="$target_routes"
                  resolved_file="$target_file"
                fi
              fi
            fi
          fi
        fi
      fi
      [ -z "$routes" ] && continue
      while IFS= read -r route; do
        [ -z "$route" ] && continue
        printf '%s\t%s\t%s\t%s\n' "$route" "$(dirname "$resolved_file")" "$resolved_file" "medium" >> "$TMP_ROWS"
      done <<< "$routes"
    done <<< "$router_files"
  fi
fi

# --- 4. フォールバック: 慣習ディレクトリ ---
if allow_method "builtin-fallback" && [ -z "$detection_method" ]; then
  for conv in pages screens views; do
    conv_dir="$(find "$SOURCE_DIR" -maxdepth 4 -type d -iname "$conv" 2>/dev/null | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" | head -1 || true)"
    if [ -n "$conv_dir" ]; then
      entries="$(find "$conv_dir" -mindepth 1 -maxdepth 1 2>/dev/null | grep -Ev "$EXCLUDE_REGEX" || true)"
      [ -z "$entries" ] && continue
      detection_method="fallback-directory"
      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if [ -d "$entry" ]; then
          entry_dir="$entry"
        else
          entry_dir="$(dirname "$entry")"
        fi
        printf '不明（フォールバック検出）\t%s\t%s\t%s\n' "$entry_dir" "$entry" "low" >> "$TMP_ROWS"
      done <<< "$entries"
      break
    fi
  done
fi

# --- 5. ハード停止 ---
if [ -z "$detection_method" ] || [ ! -s "$TMP_ROWS" ]; then
  mkdir -p "$(dirname "$MANIFEST_OUT")"
  cat > "$MANIFEST_OUT" <<EOF
{
  "generatedAt": null,
  "sourceDir": "$SOURCE_DIR",
  "detectionSummary": {"method": "none", "screenCount": 0},
  "screens": []
}
EOF
  echo "DETECTION_FAILED: ルーティング定義も慣習ディレクトリも検出できませんでした ($SOURCE_DIR)" >&2
  exit 3
fi

# --- 画面キー生成関数(意味キー規約準拠) ---
# 注意: bash 3.2 (macOS標準/bin/bash) 互換のため declare -A / mapfile は使わない。
# 空配列を printf '%s\n' "${arr[@]}" に渡すとフォーマットが1回だけ評価され
# 空行が1行出力される bash の仕様があるため、要素数ガードを必ず入れる。
static_segments() {
  local route="$1"
  local -a segs
  IFS='/' read -ra segs <<< "$route"
  local out=()
  for s in "${segs[@]}"; do
    [ -z "$s" ] && continue
    case "$s" in
      :*|\**) continue ;;
    esac
    out+=("$s")
  done
  if [ "${#out[@]}" -gt 0 ]; then
    printf '%s\n' "${out[@]}"
  fi
}

read_segments_into() {
  # $1: route, 結果はグローバル配列 SEGS_RESULT に格納(mapfile不使用でbash3.2互換)
  local route="$1"
  SEGS_RESULT=()
  local line
  while IFS= read -r line; do
    SEGS_RESULT+=("$line")
  done < <(static_segments "$route")
}

key_from_tail() {
  local route="$1" n="$2"
  read_segments_into "$route"
  local total="${#SEGS_RESULT[@]}"
  if [ "$total" -eq 0 ]; then
    echo "top"
    return
  fi
  local start=$(( total - n ))
  [ "$start" -lt 0 ] && start=0
  local key=""
  local i
  for ((i=start; i<total; i++)); do
    key="${key}${key:+-}${SEGS_RESULT[$i]}"
  done
  echo "$key"
}

# seen_keys は連想配列(bash4+専用)を使わず、改行区切りファイル($SEEN_KEYS_FILE)で管理する(bash3.2互換)
key_seen() {
  grep -qxF "$1" "$SEEN_KEYS_FILE" 2>/dev/null
}
mark_seen() {
  printf '%s\n' "$1" >> "$SEEN_KEYS_FILE"
}

# キー正規化: 連続ハイフンの縮約・先頭/末尾ハイフンの除去(意味キー品質の担保)
norm_key() {
  local k
  k="$(printf '%s' "$1" | sed -E 's/-+/-/g; s/^-+//; s/-+$//')"
  [ -z "$k" ] && k="top"
  printf '%s' "$k"
}

# --- 完全重複の事前マージ(同一 route + entryFile を1行に集約し、routeDupCount を保持) ---
# dirkey 経路での偶発的なキー重複バグ(問題3)を構造的に解消する: 同一 (route, entryFile) が
# 複数回出現しても、キー生成前に1行へ縮約されるため重複キーが発生しない。
awk -F'\t' '
{
  k = $1 SUBSEP $3
  if (!(k in seen)) {
    order[++n] = k
    r[k] = $1
    ed[k] = $2
    ef[k] = $3
    cf[k] = $4
  }
  seen[k]++
}
END {
  for (i = 1; i <= n; i++) {
    k = order[i]
    printf "%s\t%s\t%s\t%s\t%d\n", r[k], ed[k], ef[k], cf[k], seen[k]
  }
}
' "$TMP_ROWS" > "$TMP_MERGED"

# --- キー採番(保険として dirkey 付与後も再衝突検証を行う) ---
while IFS=$'\t' read -r route entry_dir entry_file confidence dupcount; do
  read_segments_into "$route"
  total="${#SEGS_RESULT[@]}"
  n=1
  key="$(key_from_tail "$route" "$n")"
  while key_seen "$key"; do
    n=$((n+1))
    if [ "$n" -gt "$total" ]; then
      # ソースディレクトリからの相対パスでキーを具体化する(絶対パス・ユーザー名の混入を避ける)
      rel_dir="${entry_dir#"$SOURCE_DIR"}"
      rel_dir="${rel_dir#/}"
      dirkey="$(printf '%s' "$rel_dir" | sed -E 's#[/ ]+#-#g' | tr '[:upper:]' '[:lower:]')"
      # entry_dir が SOURCE_DIR 直下等で dirkey が空になる場合は付与しない(末尾ハイフン防止)
      [ -n "$dirkey" ] && key="${key}-${dirkey}"
      break
    fi
    key="$(key_from_tail "$route" "$n")"
  done
  key="$(norm_key "$key")"
  # 保険: dirkey付与後もなお衝突する場合は entry_file の basename(拡張子なし・小文字化)で具体化する
  if key_seen "$key"; then
    base_noext="$(basename "$entry_file")"
    base_noext="${base_noext%.*}"
    base_noext_lc="$(printf '%s' "$base_noext" | tr '[:upper:]' '[:lower:]')"
    key="$(norm_key "${key}-${base_noext_lc}")"
  fi
  mark_seen "$key"
  kind="route"
  row_confidence="$confidence"
  if [ -z "$entry_file" ]; then
    kind="unresolved"
    row_confidence="low"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$kind" "$route" "$entry_dir" "$entry_file" "$row_confidence" "$dupcount" "" >> "$TMP_KEYED"
done < "$TMP_MERGED"

# --- JSON エスケープ (最小限: バックスラッシュとダブルクォートのみ) ---
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --- screenId 抽出 ---
extract_screen_id() {
  local file="$1"
  [ -z "$SCREEN_ID_REGEX" ] && return 0
  [ -z "$file" ] && return 0
  local base
  base="$(basename "$file")"
  base="${base%.*}"
  printf '%s' "$base" | grep -oE "$SCREEN_ID_REGEX" | head -1 || true
}

# --- 既に route 画面の entryFile として検出済みの basename(拡張子なし)集合 ---
ROUTE_ENTRY_BASENAMES="$(awk -F'\t' '$2=="route"{n=$5; sub(/.*\//,"",n); sub(/\.[^.]*$/,"",n); if (n!="") print n}' "$TMP_KEYED" | sort -u)"

# --- 埋め込みビュー検出(kind: "embedded-view") ---
# --view-switch-pattern 指定時のみ。1階層 import grep による best-effort 解決(完全な import グラフ解析はしない)。
# 同一 entryFile を複数の親画面が共有する場合(共有クラスタ)でも1回だけ処理し、
# embeddedIn には当該 entryFile を持つ全親キーをカンマ結合で記録する(重複行防止)。
if [ -n "$VIEW_SWITCH_PATTERN" ]; then
  awk -F'\t' '$2=="route" && $5!="" {
    if (!($5 in keys)) { order[++n]=$5 }
    keys[$5] = keys[$5] ((keys[$5]=="")?"":",") $1
  } END { for(i=1;i<=n;i++){ f=order[i]; print f "\t" keys[f] } }' "$TMP_KEYED" > "${TMP_EMBEDDED}.parents"
  while IFS=$'\t' read -r entry_file parent_keys; do
    [ -f "$entry_file" ] || continue
    first_parent="${parent_keys%%,*}"
    matching_lines="$(grep -E "$VIEW_SWITCH_PATTERN" "$entry_file" 2>/dev/null || true)"
    [ -z "$matching_lines" ] && continue
    comps="$(printf '%s\n' "$matching_lines" | grep -oE '<[A-Z][A-Za-z0-9]*' | sed 's/^<//' | sort -u || true)"
    [ -z "$comps" ] && continue
    while IFS= read -r comp; do
      [ -z "$comp" ] && continue
      if printf '%s\n' "$ROUTE_ENTRY_BASENAMES" | grep -qxF "$comp"; then
        continue
      fi
      import_line="$(grep -E "^import.*${comp}.*from" "$entry_file" 2>/dev/null | head -1 || true)"
      import_path=""
      if [ -n "$import_line" ]; then
        import_path="$(printf '%s' "$import_line" | grep -oE "['\"][^'\"]+['\"]" | head -1 | sed "s/^['\"]//; s/['\"]\$//" || true)"
      fi
      found_file="$(find "$SOURCE_DIR" -type f \( -iname "${comp}.tsx" -o -iname "${comp}.jsx" -o -iname "${comp}.ts" -o -iname "${comp}.js" \) 2>/dev/null | grep -v node_modules | grep -Ev "$EXCLUDE_REGEX" | head -1 || true)"
      if [ -n "$found_file" ]; then
        resolved="$found_file"
      elif [ -n "$import_path" ]; then
        resolved="$import_path"
      else
        resolved="$comp"
      fi
      ekey="$(printf '%s' "$comp" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g; s/([A-Z]+)([A-Z][a-z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
      ekey="$(norm_key "$ekey")"
      if key_seen "$ekey"; then
        ekey="$(norm_key "${first_parent}-${ekey}")"
      fi
      if key_seen "$ekey"; then
        safeguard="$(basename "$resolved")"
        safeguard="${safeguard%.*}"
        safeguard_lc="$(printf '%s' "$safeguard" | tr '[:upper:]' '[:lower:]')"
        ekey="$(norm_key "${ekey}-${safeguard_lc}")"
      fi
      mark_seen "$ekey"
      edir=""
      if [ -n "$found_file" ]; then
        edir="$(dirname "$found_file")"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ekey" "embedded-view" "なし（埋め込みビュー）" "$edir" "$resolved" "medium" "1" "$parent_keys" >> "$TMP_EMBEDDED"
    done <<< "$comps"
  done < "${TMP_EMBEDDED}.parents"
  rm -f "${TMP_EMBEDDED}.parents"

  # 最終マージ: 異なる親entryFileが同一コンポーネントを参照した場合の (route+entryFile) 重複を1行に統合し、
  # embeddedIn の親キーを結合・重複除去する
  if [ -s "$TMP_EMBEDDED" ]; then
    awk -F'\t' '{
      k=$5
      if (!(k in seen)) { order[++n]=k; k1[k]=$1; k4[k]=$4; parents[k]=$8 }
      else { parents[k]=parents[k] "," $8 }
      seen[k]=1
    } END {
      for(i=1;i<=n;i++){
        k=order[i]
        m=split(parents[k], arr, ",")
        out=""; delete uniq
        for(j=1;j<=m;j++){ if(!(arr[j] in uniq) && arr[j]!=""){ uniq[arr[j]]=1; out=out ((out=="")?"":",") arr[j] } }
        printf "%s\tembedded-view\tなし（埋め込みビュー）\t%s\t%s\tmedium\t1\t%s\n", k1[k], k4[k], k, out
      }
    }' "$TMP_EMBEDDED" > "${TMP_EMBEDDED}.merged" && mv "${TMP_EMBEDDED}.merged" "$TMP_EMBEDDED"
  fi
fi

cat "$TMP_KEYED" "$TMP_EMBEDDED" > "$TMP_ALL"

# --- 共有クラスタ算出(同一 entryFile を共有する route 画面が2つ以上ある場合) ---
awk -F'\t' '$2=="route" && $5!=""{
  keys[$5] = keys[$5] (($5 in seen) ? "," : "") $1
  seen[$5]=1
}
END {
  for (f in keys) {
    n = split(keys[f], arr, ",")
    if (n >= 2) {
      print f "\t" keys[f]
    }
  }
}' "$TMP_ALL" > "${TMP_CLUSTERS}.raw"

: > "$TMP_CLUSTERS"
while IFS=$'\t' read -r efile keys_csv; do
  sorted="$(printf '%s\n' "$keys_csv" | tr ',' '\n' | sort -u | paste -sd, -)"
  rep="$(printf '%s' "$sorted" | cut -d, -f1)"
  cluster_id="${rep}-shared"
  printf '%s\t%s\t%s\n' "$efile" "$sorted" "$cluster_id" >> "$TMP_CLUSTERS"
done < "${TMP_CLUSTERS}.raw"
rm -f "${TMP_CLUSTERS}.raw"

mkdir -p "$(dirname "$MANIFEST_OUT")"

screen_count="$(wc -l < "$TMP_ALL" | tr -d ' ')"
cluster_count="$(wc -l < "$TMP_CLUSTERS" | tr -d ' ')"
shared_screen_count="$(awk -F'\t' '{n=split($2,a,","); sum+=n} END{print sum+0}' "$TMP_CLUSTERS")"
embedded_candidate_count="$(wc -l < "$TMP_EMBEDDED" | tr -d ' ')"
unresolved_count="$(awk -F'\t' '$5==""{c++} END{print c+0}' "$TMP_ALL")"

# --- entryFile集中の自己診断(route画面が単一ファイルに10件以上かつ80%以上集中している場合) ---
DIAGNOSTICS=()
diag_line="$(awk -F'\t' '
  $2=="route" && $5!="" { cnt[$5]++; total++ }
  END {
    if (total==0) { exit }
    maxfile=""; maxcnt=0
    for (f in cnt) { if (cnt[f]>maxcnt) { maxcnt=cnt[f]; maxfile=f } }
    if (maxcnt>=10 && maxcnt/total>=0.8) {
      printf "%s\t%d\t%d", maxfile, maxcnt, total
    }
  }
' "$TMP_ALL")"
if [ -n "$diag_line" ]; then
  diag_file="$(printf '%s' "$diag_line" | cut -f1)"
  diag_maxcnt="$(printf '%s' "$diag_line" | cut -f2)"
  diag_msg="WARN: ${diag_maxcnt}画面のentryFileが単一ファイル ${diag_file} に集中しています。ルーター定義ファイルがentryFileになっている可能性が高く、element属性等からの実体解決(カスタム抽出パス)を検討してください"
  echo "$diag_msg" >&2
  DIAGNOSTICS+=("$diag_msg")
fi
diagnostics_json="[]"
if [ "${#DIAGNOSTICS[@]}" -gt 0 ]; then
  diag_items=""
  for d in "${DIAGNOSTICS[@]}"; do
    d_esc="$(json_escape "$d")"
    if [ -z "$diag_items" ]; then
      diag_items="\"$d_esc\""
    else
      diag_items="$diag_items,\"$d_esc\""
    fi
  done
  diagnostics_json="[$diag_items]"
fi

screen_id_regex_json="null"
[ -n "$SCREEN_ID_REGEX" ] && screen_id_regex_json="\"$(json_escape "$SCREEN_ID_REGEX")\""
view_switch_pattern_json="null"
[ -n "$VIEW_SWITCH_PATTERN" ] && view_switch_pattern_json="\"$(json_escape "$VIEW_SWITCH_PATTERN")\""

# --- strategy フィールド(--strategy-json 指定時はファイル内容をそのまま埋め込む) ---
if [ -n "$STRATEGY_JSON_FILE" ]; then
  strategy_brace_count="$(grep -c '{' "$STRATEGY_JSON_FILE" || true)"
  if [ -z "$strategy_brace_count" ] || [ "$strategy_brace_count" -eq 0 ]; then
    echo "ERROR: --strategy-json file is empty or invalid: $STRATEGY_JSON_FILE" >&2
    exit 1
  fi
  strategy_json="$(cat "$STRATEGY_JSON_FILE")"
else
  strategy_json="{\"screenIdRegex\": $screen_id_regex_json, \"viewSwitchPattern\": $view_switch_pattern_json, \"extractionMethod\": \"builtin-${detection_method}\", \"approvedByUser\": false}"
fi

# --- 9-2: 通常検出フローでも import 再帰追跡(resolve_screen_files)でファイル集合を
# 解決する。strategy の sharedDirPatterns/pathAliases/importTraversalMaxDepth/
# screenIdRegex を読み込んで BFS に引き渡す(entryFile がディレクトリの場合の
# 従来のディレクトリ収集はフォールバック互換として維持する)。
STRATEGY_SHARED_FILE="$(mktemp)"
STRATEGY_ALIAS_FILE="$(mktemp)"
STRATEGY_ALL_ENTRIES_FILE="$(mktemp)"

STRATEGY_MAX_DEPTH="$(printf '%s' "$strategy_json" | jq -r '.importTraversalMaxDepth // 6' 2>/dev/null || echo 6)"
case "$STRATEGY_MAX_DEPTH" in ''|*[!0-9]*) STRATEGY_MAX_DEPTH=6 ;; esac

# 注意: BFS境界(c)専用のローカル値。extract_screen_id() が使う既存のグローバル
# SCREEN_ID_REGEX は書き換えない(screenId フィールドの算出ロジックへの影響を避ける)。
STRATEGY_SCREEN_ID_REGEX="$(printf '%s' "$strategy_json" | jq -r '.screenIdRegex // ""' 2>/dev/null || echo "")"
[ "$STRATEGY_SCREEN_ID_REGEX" = "null" ] && STRATEGY_SCREEN_ID_REGEX=""

printf '%s' "$strategy_json" | jq -r '(.sharedDirPatterns // [])[]' > "$STRATEGY_SHARED_FILE" 2>/dev/null || true

: > "$STRATEGY_ALIAS_FILE"
printf '%s' "$strategy_json" | jq -r '(.pathAliases // {}) | to_entries[] | "\(.key)\t\(.value)"' 2>/dev/null \
  | while IFS=$'\t' read -r prefix target; do
      [ -z "$prefix" ] && continue
      case "$target" in
        /*) abs_target="$target" ;;
        "") abs_target="$SOURCE_DIR" ;;
        *) abs_target="$SOURCE_DIR/$target" ;;
      esac
      printf '%s\t%s\n' "$prefix" "$abs_target"
    done > "$STRATEGY_ALIAS_FILE" || true

# 境界(b)用: 全画面のentryFile集合(自画面除外は不要。visited判定が先に効くため)。
awk -F'\t' '$5!=""{print $5}' "$TMP_ALL" | sort -u > "$STRATEGY_ALL_ENTRIES_FILE"

{
  printf '{\n'
  printf '  "generatedAt": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
  printf '  "sourceDir": "%s",\n' "$(json_escape "$SOURCE_DIR")"
  printf '  "strategy": %s,\n' "$strategy_json"
  printf '  "diagnostics": %s,\n' "$diagnostics_json"
  printf '  "detectionSummary": {"method": "%s", "screenCount": %d, "clusterCount": %d, "sharedScreenCount": %d, "embeddedCandidateCount": %d, "unresolvedCount": %d},\n' \
    "$detection_method" "$screen_count" "$cluster_count" "$shared_screen_count" "$embedded_candidate_count" "$unresolved_count"
  printf '  "screens": [\n'
  first=1
  while IFS=$'\t' read -r key kind route entry_dir entry_file confidence dupcount embedded_in; do
    if [ -z "$entry_file" ]; then
      kind="unresolved"
      confidence="low"
    fi

    files=""
    file_count=0
    if [ -n "$entry_file" ] && [ -f "$entry_file" ]; then
      # 9-2: import 再帰追跡(BFS)で画面専有ファイル集合を解決する(通常検出フローへの統合)。
      # screenId は extract_screen_id() が使う既存のグローバル SCREEN_ID_REGEX とは
      # 独立に、strategy 由来の STRATEGY_SCREEN_ID_REGEX から算出する(境界(c)専用値)。
      bfs_own_screen_id=""
      if [ -n "$STRATEGY_SCREEN_ID_REGEX" ]; then
        bfs_base="$(basename "$entry_file")"
        bfs_base="${bfs_base%.*}"
        bfs_own_screen_id="$(printf '%s' "$bfs_base" | grep -oE "$STRATEGY_SCREEN_ID_REGEX" | head -1 || true)"
      fi
      screen_others_file="$(mktemp)"
      grep -vxF "$entry_file" "$STRATEGY_ALL_ENTRIES_FILE" > "$screen_others_file" 2>/dev/null || true
      files="$(resolve_screen_files "$entry_file" "$SOURCE_DIR" "$STRATEGY_MAX_DEPTH" "$STRATEGY_SHARED_FILE" "$screen_others_file" "$STRATEGY_SCREEN_ID_REGEX" "$bfs_own_screen_id" "$STRATEGY_ALIAS_FILE")"
      rm -f "$screen_others_file"
      file_count="$(printf '%s\n' "$files" | grep -c . || true)"
    elif [ -n "$entry_dir" ] && [ -d "$entry_dir" ]; then
      # entryFile がディレクトリの場合(慣習ディレクトリ検出): 従来のディレクトリ収集を維持(フォールバック互換)。
      files="$( { find "$entry_dir" -maxdepth 1 -type f 2>/dev/null; find "$entry_dir/components" "$entry_dir/_components" -maxdepth 1 -type f 2>/dev/null; } | grep -v '^$' || true)"
      file_count="$(printf '%s\n' "$files" | grep -c . || true)"
    fi
    files_json="$(printf '%s\n' "$files" | grep -v '^$' | while IFS= read -r f; do printf '      "%s"' "$(json_escape "$f")"; echo; done | paste -sd, - 2>/dev/null || true)"

    screen_id="$(extract_screen_id "$entry_file")"
    screen_id_json="null"
    [ -n "$screen_id" ] && screen_id_json="\"$(json_escape "$screen_id")\""

    if [ "$kind" = "embedded-view" ]; then
      name_guess="$(printf '%s' "$key" | sed 's/-/ /g')"
    elif [ -n "$entry_dir" ]; then
      name_guess="$(basename "$entry_dir" | sed -E 's/[-_]/ /g')"
    else
      name_guess="$(basename "$entry_file" 2>/dev/null | sed -E 's/[-_]/ /g')"
    fi
    name_guess="$(printf '%s' "$name_guess" | sed -E 's/ +/ /g; s/^ //; s/ $//')"

    shared_with_json="[]"
    cluster_id_json="null"
    if [ "$kind" = "route" ] && [ -n "$entry_file" ]; then
      cluster_line="$(awk -F'\t' -v ef="$entry_file" '$1==ef{print; exit}' "$TMP_CLUSTERS" 2>/dev/null || true)"
      if [ -n "$cluster_line" ]; then
        cluster_keys="$(printf '%s' "$cluster_line" | cut -d "$(printf '\t')" -f2)"
        cluster_id_val="$(printf '%s' "$cluster_line" | cut -d "$(printf '\t')" -f3)"
        others="$(printf '%s\n' "$cluster_keys" | tr ',' '\n' | grep -vxF "$key" || true)"
        others_json="$(printf '%s\n' "$others" | grep -v '^$' | while IFS= read -r ok; do printf '"%s"' "$(json_escape "$ok")"; echo; done | paste -sd, - 2>/dev/null || true)"
        if [ -n "$others_json" ]; then
          shared_with_json="[${others_json}]"
        fi
        cluster_id_json="\"$(json_escape "$cluster_id_val")\""
        name_guess="(共有: $(basename "$entry_file"))"
      fi
    fi

    embedded_in_json="null"
    [ -n "$embedded_in" ] && embedded_in_json="\"$(json_escape "$embedded_in")\""

    detection_method_field="$detection_method"
    if [ "$kind" = "embedded-view" ]; then
      detection_method_field="embedded-view-heuristic"
    fi

    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    {\n'
    printf '      "screenKey": "%s",\n' "$(json_escape "$key")"
    printf '      "screenId": %s,\n' "$screen_id_json"
    printf '      "kind": "%s",\n' "$kind"
    printf '      "screenNameGuess": "%s",\n' "$(json_escape "$name_guess")"
    printf '      "route": "%s",\n' "$(json_escape "$route")"
    printf '      "detectionMethod": "%s",\n' "$detection_method_field"
    printf '      "confidence": "%s",\n' "$confidence"
    printf '      "entryFile": "%s",\n' "$(json_escape "$entry_file")"
    printf '      "fileCount": %d,\n' "$file_count"
    if [ -n "$files_json" ]; then
      printf '      "files": [\n%s\n      ],\n' "$files_json"
    else
      printf '      "files": [],\n'
    fi
    printf '      "sharedWith": %s,\n' "$shared_with_json"
    printf '      "clusterId": %s,\n' "$cluster_id_json"
    printf '      "embeddedIn": %s,\n' "$embedded_in_json"
    printf '      "routeDupCount": %d\n' "$dupcount"
    printf '    }'
  done < "$TMP_ALL"
  printf '\n  ]\n'
  printf '}\n'
} > "$MANIFEST_OUT"

echo "OK: detected $screen_count screens ($cluster_count clusters, $embedded_candidate_count embedded, $unresolved_count unresolved) via $detection_method -> $MANIFEST_OUT" >&2
