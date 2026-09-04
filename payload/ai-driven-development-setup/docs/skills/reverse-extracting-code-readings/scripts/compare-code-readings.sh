#!/usr/bin/env bash
set -u

# compare-code-readings.sh — 2つの code-readings の親を、単位ごと項目ごとに比べる
#
# 目的:
#   同じコードから2回取り出した読み取り結果が一致することを確かめる（工程2-4の
#   完了条件）。extract-code-readings.sh の --verify から呼ばれるほか、単独でも
#   2つの取り出し結果を比べるのに使える。
#
# 使い方:
#   compare-code-readings.sh <code-readings の親A> <code-readings の親B> [--kind <種別>]
#   compare-code-readings.sh --self-test
#
# <code-readings の親> は <種別>/<単位のフォルダ名>.json を持つフォルダ（通常は
#   extract-code-readings.sh の --out）。--kind を省略すると両方の親に実在する
#   種別フォルダをすべて比べる。集計.json は比較の対象外。
#
# 比較の観点:
#   単位ごとに「読み取り結果」の各項目の「値」の集合（順不同）が一致するか。
#   片方にしか無い単位・項目があれば不一致として列挙する。
#
# 終了コード:
#   0 = 差分0件（一致）
#   1 = 差分1件以上（不一致）
#
# 保守責任者: 人手（ユーザー）。読み取り結果ファイルの形（読み取り結果.<項目>.値）を変える
#   ときは、extract-code-readings.sh と本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 読み取り結果の一致確認を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: compare-code-readings.sh <code-readings の親A> <code-readings の親B> [--kind <種別>]" >&2
  echo "        compare-code-readings.sh --self-test" >&2
  exit 2
}

compare_readings() {
  local a="$1" b="$2" kind="$3" diff_count=0

  local kinds
  if [ -n "$kind" ]; then
    kinds="$kind"
  else
    kinds="$( { ls "$a" 2>/dev/null; ls "$b" 2>/dev/null; } | sort -u)"
  fi

  local k
  for k in $kinds; do
    local dir_a="${a%/}/${k}" dir_b="${b%/}/${k}"
    local files
    files="$( { ls "$dir_a" 2>/dev/null; ls "$dir_b" 2>/dev/null; } | sort -u)"

    local f
    for f in $files; do
      [ "$f" = "集計.json" ] && continue
      local fa="${dir_a}/${f}" fb="${dir_b}/${f}"

      if [ ! -f "$fa" ]; then
        echo "[FAIL] 単位-不在A: ${k}/${f}"
        diff_count=$((diff_count + 1))
        continue
      fi
      if [ ! -f "$fb" ]; then
        echo "[FAIL] 単位-不在B: ${k}/${f}"
        diff_count=$((diff_count + 1))
        continue
      fi

      local items
      items="$( { jq -r '.["読み取り結果"] | keys[]' "$fa" 2>/dev/null; jq -r '.["読み取り結果"] | keys[]' "$fb" 2>/dev/null; } | sort -u)"

      local item
      for item in $items; do
        local va vb
        va="$(jq -c --arg i "$item" '(.["読み取り結果"][$i]["値"] // []) | sort' "$fa" 2>/dev/null)"
        vb="$(jq -c --arg i "$item" '(.["読み取り結果"][$i]["値"] // []) | sort' "$fb" 2>/dev/null)"
        if [ "$va" != "$vb" ]; then
          echo "[FAIL] 値-不一致: ${k}/${f} ${item}: A=${va} B=${vb}"
          diff_count=$((diff_count + 1))
        fi
      done
    done
  done

  echo "比較 差分 ${diff_count} 件"
  if [ "$diff_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/compare-code-readings-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  check() {
    local name="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${name}"
    else
      echo "FAIL: ${name}"
      fail=$((fail + 1))
    fi
  }

  local a="${tmp}/a" b="${tmp}/b"
  mkdir -p "${a}/screen" "${b}/screen"

  cat > "${a}/screen/OrderList.tsx.json" <<'FIXEOF'
{"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","属するファイル":[],"読み取り結果":{"入力項目":{"値":["orderId","name"],"出所":"機械","根拠":["src/pages/OrderList.tsx"]}},"未":[],"取り出した実行":"run-1"}
FIXEOF
  cp "${a}/screen/OrderList.tsx.json" "${b}/screen/OrderList.tsx.json"

  local rc_match
  bash "$0" "$a" "$b" --kind screen > "${tmp}/match.out" 2>&1
  rc_match=$?
  check "一致: 終了コード0" "$([ "$rc_match" -eq 0 ] && echo 0 || echo 1)"

  # 値の順序が違うだけなら一致扱い
  cat > "${b}/screen/OrderList.tsx.json" <<'FIXEOF'
{"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","属するファイル":[],"読み取り結果":{"入力項目":{"値":["name","orderId"],"出所":"機械","根拠":["src/pages/OrderList.tsx"]}},"未":[],"取り出した実行":"run-2"}
FIXEOF
  local rc_order
  bash "$0" "$a" "$b" --kind screen > "${tmp}/order.out" 2>&1
  rc_order=$?
  check "値の順序違いは一致扱い: 終了コード0" "$([ "$rc_order" -eq 0 ] && echo 0 || echo 1)"

  # 値が違えば不一致
  cat > "${b}/screen/OrderList.tsx.json" <<'FIXEOF'
{"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","属するファイル":[],"読み取り結果":{"入力項目":{"値":["orderId"],"出所":"機械","根拠":["src/pages/OrderList.tsx"]}},"未":[],"取り出した実行":"run-3"}
FIXEOF
  local rc_diff diff_out
  diff_out="$(bash "$0" "$a" "$b" --kind screen 2>&1)"
  rc_diff=$?
  check "値の不一致: 終了コード1" "$([ "$rc_diff" -eq 1 ] && echo 0 || echo 1)"
  case "$diff_out" in
    *"値-不一致"*) check "値の不一致: メッセージに値-不一致" 0 ;;
    *) check "値の不一致: メッセージに値-不一致" 1 ;;
  esac

  # 片方にしか単位が無い
  mkdir -p "${a}/api" "${b}/api"
  cat > "${a}/api/orders.json" <<'FIXEOF'
{"種別":"api","識別子":"/orders","名前":"orders","場所":"src/api/orders.ts","属するファイル":[],"読み取り結果":{},"未":[],"取り出した実行":"run-1"}
FIXEOF
  local rc_missing missing_out
  missing_out="$(bash "$0" "$a" "$b" --kind api 2>&1)"
  rc_missing=$?
  check "片方にしか単位が無い: 終了コード1" "$([ "$rc_missing" -eq 1 ] && echo 0 || echo 1)"
  case "$missing_out" in
    *"単位-不在B"*) check "片方にしか単位が無い: メッセージに単位-不在B" 0 ;;
    *) check "片方にしか単位が無い: メッセージに単位-不在B" 1 ;;
  esac

  # 集計.jsonは比較対象外
  echo '{"単位数":1}' > "${a}/screen/集計.json"
  echo '{"単位数":999}' > "${b}/screen/集計.json"
  cp "${a}/screen/OrderList.tsx.json" "${b}/screen/OrderList.tsx.json"
  local rc_agg
  bash "$0" "$a" "$b" --kind screen > "${tmp}/agg.out" 2>&1
  rc_agg=$?
  check "集計.jsonは比較対象外: 終了コード0" "$([ "$rc_agg" -eq 0 ] && echo 0 || echo 1)"

  # 使い方誤り
  bash "$0" "$a" > /dev/null 2>"${tmp}/usage.err"
  check "使い方誤り: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ $# -lt 2 ]; then
  usage_error
fi

a="$1"; shift
b="$1"; shift
kind=""

while [ $# -gt 0 ]; do
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    *) usage_error ;;
  esac
done

compare_readings "$a" "$b" "$kind"
exit $?
