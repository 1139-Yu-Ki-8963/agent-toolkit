#!/usr/bin/env bash
set -euo pipefail

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
#   normalize: run_id行・行末空白・空行を除去した正規形をstdoutへ出す。
#              Phase 5の再現性検証（2回の独立抽出結果の diff 比較）に用いる。
#
# 正規化の対象外にする理由: run_idは起動ごとに変わりうる値であり、内容の同一性判定
# （封印の改ざん検知・再現性の diff 比較）には含めない。したがってrun_idのみを変更した
# facts.ymlはverifyを通過する（内容が実質同一とみなされるため）。key/value/evidence等の
# 実体データの変更はnormalize後も残るため検知される。
#
# スキーマ（構造・必須フィールド・正規化規則）の正本は shared/references/facts-schema.md。
# 設計判断（ADR）の正本は extracting-unit-facts-from-code の SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。facts.ymlのフィールド構成を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。
#
# ファイル単位モードとの関係（--file-scope は本スクリプトには存在しない）:
#   本スクリプトの seal/verify/normalize はいずれも facts_dir 単位（facts.yml 全体）で
#   ハッシュ計算・照合・正規化を行い、target_file_paths 内の個別ファイルへ限定するオプ
#   ションは持たない。generating-reverse-detailed-design の mode=file（ファイル単位モード）
#   が「当該ファイル由来のキーへ限定した網羅確認」を必要とする場合は、呼び出し元側
#   （scripts/check-fact-coverage.sh 等）が facts.yml 読込後に evidence のパス部分で
#   フィルタする。seal-facts.sh 自体への --file-scope 相当オプションの追加は本改修の
#   対象外（スクリプト本体のロジック変更なし）。

normalize_file() {
  f="$1"
  sed -E '/^run_id:[[:space:]]*.*$/d' "$f" \
    | sed -E 's/[[:space:]]+$//' \
    | sed '/^[[:space:]]*$/d'
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
    echo "SEALED sha256=$hash"
    (cd "$dir" && find . -maxdepth 1 -type f ! -name 'facts.lock' | sed 's|^\./||' | sort)
  } > "$dir/facts.lock"
  echo "封印完了: $dir/facts.lock（sha256=${hash}）"
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
  recorded="$(head -n 1 "$lock" | sed -E 's/^SEALED sha256=//')"
  actual="$(normalize_file "$facts" | sha256_of)"
  if [ "$recorded" != "$actual" ]; then
    echo "封印検証失敗: facts.yml が封印時から改変されています（記録=${recorded} 実際=${actual}）" >&2
    return 1
  fi
  echo "封印検証通過: facts.yml は封印時から改変されていません（sha256=${actual}）"
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
