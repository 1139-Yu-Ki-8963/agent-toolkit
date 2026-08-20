#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCALAR_CANONICALIZER="$SCRIPT_DIR/canonicalize-facts-scalars.py"

# seal-facts.sh — facts.yml の封印・検証・正規化を担う共有スクリプト（Phase 4 封印 / Phase 5 再現性検証）
#
# 使い方:
#   seal-facts.sh seal <facts_dir>
#   seal-facts.sh verify <facts_dir>
#   seal-facts.sh normalize <facts.yml>
#   seal-facts.sh --self-test
#
# facts_dir は facts.yml が置かれているディレクトリ（例: <screen_dir>/検証記録/facts/<run_id>/）。
#
# サブコマンド:
#   seal     : normalize済みfacts.ymlのsha256を計算し、facts_dir/facts.lockへ
#              「1行目 SEALED sha256=<hash>」「2行目以降 対象ファイル一覧」の形式で書く。
#   verify   : facts.lockの記録ハッシュと、現在のfacts.ymlをnormalizeして再計算したハッシュを照合する。
#              不一致ならexit 1（fail-closed）。
#   normalize: run_id行・行末空白・空行を除去し、key/valueスカラーをYAMLの意味型を
#              保ったタグ付き表現へ変換した正規形をstdoutへ出す。
#              Phase 5の再現性検証（2回の独立抽出結果の diff 比較）に用いる。
#
# 正規化の対象外にする理由: run_idは起動ごとに変わりうる値であり、内容の同一性判定
# （封印の改ざん検知・再現性の diff 比較）には含めない。したがってrun_idのみを変更した
# facts.ymlはverifyを通過する（内容が実質同一とみなされるため）。key/value/evidence等の
# 実体データの変更はnormalize後も残るため検知される。
#
# スキーマ（構造・必須フィールド・正規化規則）の正本は delivery-payload/references/facts-schema.md。
# 設計判断（ADR）の正本は extracting-unit-facts-from-code の SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。facts.ymlのフィールド構成を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。
#
# 封印記録の正規化バージョン管理:
#   facts.lock の1行目は「SEALED sha256=<hash> normalize=<版>」の形式を持つ。
#   normalize= を持たない記録（本仕組み導入前に作られた封印）は版1として扱う。
#   verify は照合前にまず版の一致を確認する。版が現行のNORMALIZE_VERSIONと異なる場合、
#   facts.ymlの改変とは区別し、正規化規則の変更として報告する（要再封印）。
#   正規化規則（normalize_file()の処理内容）を変更する場合は必ずNORMALIZE_VERSIONを
#   上げること。上げ忘れると、規則変更前後の封印を同一版として誤って比較してしまう。
#
# verify の終了コード:
#   0 = 検証通過
#   1 = 改竄検知（facts.ymlが封印時から改変されている）
#   2 = 入力不備（facts.lock/facts.ymlが見つからない）
#   3 = 正規化規則の版が異なる（改竄ではない。要再封印）
#
# ファイル単位モードとの関係（--file-scope は本スクリプトには存在しない）:
#   本スクリプトの seal/verify/normalize はいずれも facts_dir 単位（facts.yml 全体）で
#   ハッシュ計算・照合・正規化を行い、target_file_paths 内の個別ファイルへ限定するオプ
#   ションは持たない。generating-reverse-detailed-design の mode=file（ファイル単位モード）
#   が「当該ファイル由来のキーへ限定した網羅確認」を必要とする場合は、呼び出し元側
#   （scripts/check-fact-coverage.sh 等）が facts.yml 読込後に evidence のパス部分で
#   フィルタする。seal-facts.sh 自体への --file-scope 相当オプションの追加は本改修の
#   対象外（スクリプト本体のロジック変更なし）。

# 正規化規則の版。normalize_file() の処理内容を変えたら必ずこの値を上げる。
# 封印記録に埋め込み、verify は版の一致を先に確認する。版が違う場合は改竄ではなく
# 規則変更として区別して報告し、再封印を促す。
# 版 1: run_id 行・行末空白・空行の除去のみ（sed のみ）
# 版 2: 版 1 に加えて canonicalize-facts-scalars.py によるスカラー正規化
NORMALIZE_VERSION=2

normalize_file() {
  f="$1"
  sed -E '/^run_id:[[:space:]]*.*$/d' "$f" \
    | sed -E 's/[[:space:]]+$//' \
    | sed '/^[[:space:]]*$/d' \
    | python3 "$SCALAR_CANONICALIZER"
}

sha256_of() {
  shasum -a 256 | awk '{print $1}'
}

cmd_normalize() {
  f="${1:?使い方: seal-facts.sh normalize <facts.yml>}"
  if [ ! -f "$f" ]; then
    echo "エラー: ファイルが見つかりません: $f" >&2
    return 2
  fi
  normalize_file "$f"
}

cmd_seal() {
  dir="${1:?使い方: seal-facts.sh seal <facts_dir>}"
  facts="$dir/facts.yml"
  if [ ! -f "$facts" ]; then
    echo "エラー: facts.yml が見つかりません: $facts" >&2
    return 2
  fi
  hash="$(normalize_file "$facts" | sha256_of)"
  {
    echo "SEALED sha256=$hash normalize=$NORMALIZE_VERSION"
    (cd "$dir" && find . -maxdepth 1 -type f ! -name 'facts.lock' | sed 's|^\./||' | sort)
  } > "$dir/facts.lock"
  echo "封印完了: $dir/facts.lock（sha256=${hash} normalize=v${NORMALIZE_VERSION}）"
}

cmd_verify() {
  dir="${1:?使い方: seal-facts.sh verify <facts_dir>}"
  lock="$dir/facts.lock"
  facts="$dir/facts.yml"
  if [ ! -f "$lock" ]; then
    echo "エラー: facts.lock が見つかりません: $lock" >&2
    return 2
  fi
  if [ ! -f "$facts" ]; then
    echo "エラー: facts.yml が見つかりません: $facts" >&2
    return 2
  fi
  lock_head="$(head -n 1 "$lock")"
  recorded="$(printf '%s' "$lock_head" | sed -E 's/^SEALED sha256=([0-9a-f]+).*$/\1/')"
  # normalize= を持たない封印記録は版 1（canonicalize 導入前）として扱う
  recorded_version="$(printf '%s' "$lock_head" | sed -nE 's/.*normalize=([0-9]+).*/\1/p')"
  [ -z "$recorded_version" ] && recorded_version=1

  if [ "$recorded_version" != "$NORMALIZE_VERSION" ]; then
    echo "封印検証保留: 正規化規則が封印時から変わっています（記録=v${recorded_version} 現行=v${NORMALIZE_VERSION}）。" >&2
    echo "  facts.yml の改変ではありません。内容を確認したうえで再封印してください:" >&2
    echo "    seal-facts.sh seal ${dir}" >&2
    return 3
  fi

  actual="$(normalize_file "$facts" | sha256_of)"
  if [ "$recorded" != "$actual" ]; then
    echo "封印検証失敗: facts.yml が封印時から改変されています（記録=${recorded} 実際=${actual}）" >&2
    return 1
  fi
  echo "封印検証通過: facts.yml は封印時から改変されていません（sha256=${actual} normalize=v${NORMALIZE_VERSION}）"
  return 0
}

# ---- 自己テスト ----

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/seal-facts-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  dir="$tmp/facts/extract-1"
  mkdir -p "$dir"
  cat > "$dir/facts.yml" <<'YML'
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
YML

  rc=0

  # 系1: seal → verify 成功
  if cmd_seal "$dir" >/dev/null 2>&1 && cmd_verify "$dir" >/dev/null 2>&1; then
    echo "  [PASS] 系1: seal直後のverifyが成功する"
  else
    echo "  [FAIL] 系1: seal直後のverifyが失敗した" >&2
    rc=1
  fi

  # 系2: 改ざん（実体データを書き換え）→ verify 失敗
  sed -E 's/useState/useReducer/' "$dir/facts.yml" > "$dir/facts.yml.tmp" && mv "$dir/facts.yml.tmp" "$dir/facts.yml"
  if cmd_verify "$dir" >/dev/null 2>&1; then
    echo "  [FAIL] 系2: facts.ymlを改ざんしたのにverifyが成功した" >&2
    rc=1
  else
    echo "  [PASS] 系2: facts.ymlの改ざんをverifyが検知した"
  fi

  # 補助検証: normalize は run_id の差異を吸収する（seal/verifyの意図した挙動の直接確認）
  cat > "$tmp/base.yml" <<'YML'
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
YML
  cat > "$tmp/base2.yml" <<'YML'
run_id: extract-2
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
YML
  n1="$(cmd_normalize "$tmp/base.yml")"
  n2="$(cmd_normalize "$tmp/base2.yml")"
  if [ "$n1" = "$n2" ]; then
    echo "  [PASS] 補助: run_idのみ異なるfacts.ymlはnormalize後に一致する"
  else
    echo "  [FAIL] 補助: run_idのみ異なるfacts.ymlのnormalize結果が一致しなかった" >&2
    rc=1
  fi

  # 1-32: key/valueの外側引用符の有無だけが異なるfactsは同じ正規形になる。
  cat > "$tmp/quoted.yml" <<'YML'
profile: python
sections:
  function:
    reason: ""
    items:
      - key: "function-load"
        value: 'plain-value'
        evidence: "src/load.py:1"
YML
  cat > "$tmp/unquoted.yml" <<'YML'
profile: python
sections:
  function:
    reason: ""
    items:
      - key: function-load
        value: plain-value
        evidence: "src/load.py:1"
YML
  if [ "$(cmd_normalize "$tmp/quoted.yml")" = "$(cmd_normalize "$tmp/unquoted.yml")" ]; then
    echo "  [PASS] 1-32: key/value外側引用符の差をnormalizeが吸収する"
  else
    echo "  [FAIL] 1-32: key/value外側引用符の差がnormalize後も残る" >&2
    rc=1
  fi

  # 引用符の有無でYAML上の意味が変わる値は、同じ正規形へ潰してはならない。
  cat > "$tmp/escaped-string.yml" <<'YML'
profile: python
sections:
  function:
    items:
      - key: function-load
        value: "a\nb"
        evidence: "src/load.py:1"
YML
  cat > "$tmp/plain-backslash.yml" <<'YML'
profile: python
sections:
  function:
    items:
      - key: function-load
        value: a\nb
        evidence: "src/load.py:1"
YML
  if [ "$(cmd_normalize "$tmp/escaped-string.yml")" != "$(cmd_normalize "$tmp/plain-backslash.yml")" ]; then
    echo "  [PASS] 1-32陰性: 引用符内改行escapeとplainバックスラッシュを区別する"
  else
    echo "  [FAIL] 1-32陰性: YAML意味が異なる改行escapeを同一化した" >&2
    rc=1
  fi

  cat > "$tmp/quoted-null.yml" <<'YML'
profile: python
sections:
  function:
    items:
      - key: function-load
        value: "null"
        evidence: "src/load.py:1"
YML
  cat > "$tmp/plain-null.yml" <<'YML'
profile: python
sections:
  function:
    items:
      - key: function-load
        value: null
        evidence: "src/load.py:1"
YML
  if [ "$(cmd_normalize "$tmp/quoted-null.yml")" != "$(cmd_normalize "$tmp/plain-null.yml")" ]; then
    echo "  [PASS] 1-32陰性: 文字列nullとYAML null型を区別する"
  else
    echo "  [FAIL] 1-32陰性: 文字列nullとYAML null型を同一化した" >&2
    rc=1
  fi

  # 1-154/1-167: 正規化バージョン管理
  ver_dir="$tmp/facts/version-1"
  mkdir -p "$ver_dir"
  cat > "$ver_dir/facts.yml" <<'YML'
run_id: extract-ver
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Bar/Bar.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useEffect
        value: "react から useEffect"
        evidence: "src/screens/Bar/Bar.tsx:1"
YML

  # 1-154a: 版が一致する封印は通過する
  cmd_seal "$ver_dir" >/dev/null 2>&1
  ver_verify_rc=0
  ver_verify_out="$(cmd_verify "$ver_dir" 2>&1)" || ver_verify_rc=$?
  if [ "$ver_verify_rc" -eq 0 ] && grep -q 'normalize=2' "$ver_dir/facts.lock"; then
    echo "  [PASS] 1-154a: 版が一致する封印はverifyが通過し、facts.lockにnormalize=2が記録される"
  else
    echo "  [FAIL] 1-154a: 版が一致する封印のverifyが期待通りに通過しなかった（rc=${ver_verify_rc}）" >&2
    rc=1
  fi

  # 1-154b: 版が異なる封印は改竄と区別される（normalize=を持たない=版1相当の記録を模擬）
  sed -E 's/^(SEALED sha256=[0-9a-f]+).*$/\1/' "$ver_dir/facts.lock" > "$ver_dir/facts.lock.tmp" && mv "$ver_dir/facts.lock.tmp" "$ver_dir/facts.lock"
  ver_mismatch_rc=0
  ver_mismatch_out="$(cmd_verify "$ver_dir" 2>&1)" || ver_mismatch_rc=$?
  if [ "$ver_mismatch_rc" -eq 3 ] && printf '%s' "$ver_mismatch_out" | grep -q '改変ではありません' && printf '%s' "$ver_mismatch_out" | grep -q 'seal-facts.sh seal'; then
    echo "  [PASS] 1-154b: 版が異なる封印は改竄ではなく規則変更として exit 3 で報告される"
  else
    echo "  [FAIL] 1-154b: 版が異なる封印の扱いが期待通りでなかった（rc=${ver_mismatch_rc}）" >&2
    rc=1
  fi

  # 1-154c: 版が一致していて内容が改変された場合は従来どおり改竄として検知する
  cmd_seal "$ver_dir" >/dev/null 2>&1
  sed -E 's/useEffect/useLayoutEffect/' "$ver_dir/facts.yml" > "$ver_dir/facts.yml.tmp" && mv "$ver_dir/facts.yml.tmp" "$ver_dir/facts.yml"
  ver_tamper_rc=0
  cmd_verify "$ver_dir" >/dev/null 2>&1 || ver_tamper_rc=$?
  if [ "$ver_tamper_rc" -eq 1 ]; then
    echo "  [PASS] 1-154c: 版が一致していても内容改変は従来どおり改竄としてexit 1で検知される"
  else
    echo "  [FAIL] 1-154c: 版一致下での内容改変が改竄として検知されなかった（rc=${ver_tamper_rc}）" >&2
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

sub="${1:-}"
case "$sub" in
  seal)     shift; cmd_seal "$@"; exit $? ;;
  verify)   shift; cmd_verify "$@"; exit $? ;;
  normalize) shift; cmd_normalize "$@"; exit $? ;;
  *)
    echo "使い方: seal-facts.sh {seal|verify|normalize} <引数> ／ seal-facts.sh --self-test" >&2
    exit 2
    ;;
esac
