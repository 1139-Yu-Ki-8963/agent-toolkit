#!/usr/bin/env bash
# スキルガイド HTML（.claude/skills/*/references/*-guide.html）の <style> 中身を
# shared/templates/skill-guide/guide-style.css へ統一するための注入スクリプト。
#
# 使い方:
#   apply-guide-style.sh              対象ガイドの一覧表示のみ（書き込みなし）
#   apply-guide-style.sh --apply      全ガイドの <style>〜</style> の中身を置き換える
#   apply-guide-style.sh --self-test  統一適用の妥当性を検査する（1件でも外れたら exit 1）
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
style_css="$repo_root/shared/templates/skill-guide/guide-style.css"

mode="${1:-list}"
case "$mode" in
  --apply) mode="apply" ;;
  --self-test) mode="self-test" ;;
  *) mode="list" ;;
esac

if [ ! -f "$style_css" ]; then
  echo "エラー: 統一定義が見つからない: $style_css" >&2
  exit 1
fi

guides=()
while IFS= read -r f; do
  guides+=("$f")
done < <(find "$repo_root/.claude/skills" -type f -name '*-guide.html' -path '*/references/*' | sort)

if [ "${#guides[@]}" -eq 0 ]; then
  echo "エラー: 対象ガイドが見つからない（$repo_root/.claude/skills 配下）" >&2
  exit 1
fi

# <style>〜</style> の中身が統一定義と一致しているかを判定する。
# 空白・改行を除去して比較する（インデント差を無視するため）。
style_normalized="$(tr -d ' \t\n' < "$style_css")"

is_synced() {
  local f="$1"
  local body
  body="$(awk '/^<style>$/{s=1;next} /^<\/style>$/{s=0} s' "$f" | tr -d ' \t\n')"
  [ "$body" = "$style_normalized" ]
}

# <style>〜</style> の中身を統一定義へ差し替える。awk で行単位に組み立てる
# （sed 置換は CSS 中の / や () でエスケープ事故を起こしやすいため使わない）。
apply_one() {
  local f="$1"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/apply-guide-style.XXXXXX")"
  awk -v cssfile="$style_css" '
    BEGIN { while ((getline line < cssfile) > 0) css = css line "\n" }
    /^<style>$/ { print; printf "%s", css; instyle=1; next }
    /^<\/style>$/ { instyle=0; print; next }
    instyle { next }
    { print }
  ' "$f" > "$tmp"
  mv "$tmp" "$f"
}

case "$mode" in
  list)
    echo "統一した定義を持たないガイド:"
    count=0
    for f in "${guides[@]}"; do
      if ! is_synced "$f"; then
        echo "  $f"
        count=$((count + 1))
      fi
    done
    echo "対象: ${#guides[@]} 枚 / 未適用: $count 枚"
    ;;

  apply)
    applied=0
    for f in "${guides[@]}"; do
      if ! is_synced "$f"; then
        apply_one "$f"
        applied=$((applied + 1))
      fi
    done
    echo "適用: $applied 枚 / 既に統一済み: $(( ${#guides[@]} - applied )) 枚 / 対象: ${#guides[@]} 枚"
    ;;

  self-test)
    fail=0

    # 1. 51 枚すべてが統一した定義を持つ
    unsynced=0
    for f in "${guides[@]}"; do
      is_synced "$f" || { echo "FAIL(1): 未統一 $f"; unsynced=$((unsynced + 1)); }
    done
    if [ "$unsynced" -eq 0 ]; then
      echo "PASS(1): 全 ${#guides[@]} 枚が統一した定義を持つ"
    else
      fail=1
    fi

    # 2. 各説明書が使うクラス名すべてに、統一した定義の中に対応する規則がある
    #    （<style> ブロックを除いた本文からクラス名を抽出する。除外しないと
    #    CSS 自身のセレクタと自己突合してしまい、検査が無条件に通ってしまう）
    class_check_fail=0
    for f in "${guides[@]}"; do
      body_no_style="$(awk '/^<style>$/{s=1} !s{print} /^<\/style>$/{s=0}' "$f")"
      classes="$(printf '%s' "$body_no_style" | grep -ohE 'class="[^"]*"' | sed 's/class="//;s/"//' | tr ' ' '\n' | sort -u)"
      while IFS= read -r cls; do
        [ -z "$cls" ] && continue
        if ! grep -qE "\.${cls}([^A-Za-z0-9_-]|$)" "$style_css"; then
          echo "FAIL(2): $f のクラス '$cls' に対応する規則が統一定義に無い"
          class_check_fail=$((class_check_fail + 1))
        fi
      done <<< "$classes"
    done
    if [ "$class_check_fail" -eq 0 ]; then
      echo "PASS(2): 全ガイドの使用クラスが統一定義でカバーされている"
    else
      fail=1
    fi

    # 3. 統一した定義および各説明書本体（<style> ブロックを除く）に
    #    border-radius の 0 以外の値がない
    bad_radius="$(grep -oE 'border-radius:[^;]+;' "$style_css" | grep -vE 'border-radius:\s*0\s*;' || true)"
    if [ -n "$bad_radius" ]; then
      echo "FAIL(3): 統一定義の border-radius の 0 以外の値: $bad_radius"
    fi
    radius_body_fail=0
    for f in "${guides[@]}"; do
      body_no_style="$(awk '/^<style>$/{s=1} !s{print} /^<\/style>$/{s=0}' "$f")"
      bad_body_radius="$(printf '%s' "$body_no_style" | grep -oE 'border-radius:[^;"]+' | grep -vE 'border-radius:\s*0\s*$' || true)"
      if [ -n "$bad_body_radius" ]; then
        echo "FAIL(3): $f の本文に border-radius の 0 以外の値: $bad_body_radius"
        radius_body_fail=$((radius_body_fail + 1))
      fi
    done
    if [ -z "$bad_radius" ] && [ "$radius_body_fail" -eq 0 ]; then
      echo "PASS(3): border-radius は 0 のみ（統一定義・全説明書本体とも）"
    else
      fail=1
    fi

    # 4. 各説明書が外部ホストを参照していない
    #    （<link rel= と <script src= だけを見る。文中のリンクは対象外）
    external_ref_fail=0
    for f in "${guides[@]}"; do
      hits="$(grep -oE '<link[^>]*rel="[^"]*"[^>]*>|<script[^>]*src="[^"]*"[^>]*>' "$f" \
        | grep -E 'href="https?://|src="https?://' || true)"
      if [ -n "$hits" ]; then
        echo "FAIL(4): $f が外部ホストを参照している: $hits"
        external_ref_fail=$((external_ref_fail + 1))
      fi
    done
    if [ "$external_ref_fail" -eq 0 ]; then
      echo "PASS(4): 全ガイドが外部ホストを参照していない"
    else
      fail=1
    fi

    # 5. 全説明書が <style> と </style> を行頭単独の行として 1 回ずつ持つ
    #    （行全体一致の判定が空振りしないことを保証する）
    linehead_fail=0
    for f in "${guides[@]}"; do
      open_count="$(grep -c '^<style>$' "$f" || true)"
      close_count="$(grep -c '^</style>$' "$f" || true)"
      if [ "$open_count" -ne 1 ] || [ "$close_count" -ne 1 ]; then
        echo "FAIL(5): $f の <style>/</style> が行頭単独の行として 1 回ずつでない（open=$open_count close=$close_count）"
        linehead_fail=$((linehead_fail + 1))
      fi
    done
    if [ "$linehead_fail" -eq 0 ]; then
      echo "PASS(5): 全 ${#guides[@]} 枚が <style>/</style> を行頭単独の行として 1 回ずつ持つ"
    else
      fail=1
    fi

    if [ "$fail" -eq 0 ]; then
      echo "self-test: 全項目 PASS"
      exit 0
    else
      echo "self-test: FAIL あり"
      exit 1
    fi
    ;;
esac
