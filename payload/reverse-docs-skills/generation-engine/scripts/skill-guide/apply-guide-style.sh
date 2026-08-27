#!/usr/bin/env bash
# スキルガイド HTML（.claude/skills/*/references/guide.html）の <style> 中身と
# 本文のブロック要素の改行を統一するための整形スクリプト。
#
# 使い方:
#   apply-guide-style.sh              対象ガイドの一覧表示のみ（書き込みなし）
#   apply-guide-style.sh --apply      全ガイドの <style>〜</style> と本文の改行を整形する
#   apply-guide-style.sh --self-test  統一適用の妥当性を検査する（1件でも外れたら exit 1）
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
style_css="$repo_root/delivery-payload/templates/skill-guide/guide-style.css"

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
done < <(find "$repo_root/.claude/skills" -type f -name 'guide.html' -path '*/references/*' | sort)

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
# 続けて本文を整形する。整形と検査は同じsource-preserving tokenizerを使う。
# 開きタグや属性・本文はそのままに、対象ブロックの開きタグを行頭へ移す。
guide_body_processor() {
  python3 - "$@" <<'PY'
import os
import re
import stat
import sys

action = sys.argv[1]
block_tags = {
    "section", "nav", "header", "main", "footer", "table", "thead", "tbody",
    "tr", "td", "th", "ol", "ul", "li", "h1", "h2", "h3", "p", "pre", "div",
}
format_raw_tags = {"style", "pre", "script", "textarea"}
validation_raw_tags = {"style", "script", "textarea"}
name_pattern = re.compile(r"<\s*(/?)\s*([A-Za-z][A-Za-z0-9:-]*)")


def tag_parts(value):
    match = name_pattern.match(value)
    if not match:
        return None
    closing, name = match.groups()
    return bool(closing), name.lower()


def self_closing(value):
    return value.rstrip().endswith("/>")


def tokens(text, raw_tags):
    """Yield (position, is_markup, source) without interpreting quoted attributes."""
    position = 0
    text_start = 0
    while position < len(text):
        if text[position] != "<":
            position += 1
            continue
        if position > text_start:
            yield text_start, False, text[text_start:position]
        if text.startswith("<!--", position):
            end = text.find("-->", position + 4)
            end = len(text) if end == -1 else end + 3
        else:
            end = position + 1
            quote = None
            while end < len(text):
                character = text[end]
                if quote:
                    if character == quote:
                        quote = None
                elif character in "\\\"'":
                    quote = character
                elif character == ">":
                    end += 1
                    break
                end += 1
            else:
                end = len(text)
        markup = text[position:end]
        yield position, True, markup
        position = end
        text_start = position
        parts = tag_parts(markup)
        if not parts:
            continue
        closing, name = parts
        if closing or name not in raw_tags or self_closing(markup):
            continue
        closing_match = re.compile(r"</" + re.escape(name) + r"\s*>", re.IGNORECASE).search(text, position)
        if closing_match:
            if position < closing_match.start():
                yield position, False, text[position:closing_match.start()]
            closing_start = closing_match.start()
            closing_end = closing_match.end()
            yield closing_start, True, text[closing_start:closing_end]
            position = closing_end
            text_start = position
        else:
            if position < len(text):
                yield position, False, text[position:]
            position = len(text)
            text_start = position
    if text_start < len(text):
        yield text_start, False, text[text_start:]


def pop_block(stack, name):
    if stack and stack[-1] == name:
        stack.pop()
    elif name in stack:
        del stack[len(stack) - 1 - stack[::-1].index(name)]


def format_source(source):
    result = []
    block_stack = []

    def begin_block_line(depth):
        while result and result[-1].isspace():
            result.pop()
        if result:
            result.append("\n")
        result.append("  " * depth)

    for _, is_markup, value in tokens(source, format_raw_tags):
        if not is_markup:
            result.append(value)
            continue
        parts = tag_parts(value)
        if not parts:
            result.append(value)
            continue
        closing, name = parts

        if closing:
            result.append(value)
            if name in block_tags:
                pop_block(block_stack, name)
            continue

        if name in block_tags:
            begin_block_line(len(block_stack))
            result.append(value)
            if not self_closing(value):
                block_stack.append(name)
        else:
            result.append(value)

    return "".join(result)


def validate_source(source):
    errors = []
    block_stack = []

    for position, is_markup, value in tokens(source, validation_raw_tags):
        if not is_markup:
            continue
        parts = tag_parts(value)
        if not parts:
            continue
        closing, name = parts

        if closing:
            if name in block_tags:
                pop_block(block_stack, name)
            continue

        if name in block_tags:
            line = source.count("\n", 0, position) + 1
            line_start = source.rfind("\n", 0, position) + 1
            prefix = source[line_start:position]
            if prefix.strip(" \t\r"):
                errors.append((line, f"<{name}> の前に空白以外がある"))
            else:
                indentation = prefix.rstrip("\r")
                expected = "  " * len(block_stack)
                if "\t" in indentation:
                    errors.append((line, f"<{name}> のインデントにタブがある"))
                elif indentation != expected:
                    errors.append((line, f"<{name}> のインデントが深さ {len(block_stack)} の {len(expected)} 個の空白でない"))
            if not self_closing(value):
                block_stack.append(name)

    return errors


def run_regressions():
    invalid_cases = {
        "nested": "<div><p>x</p></div>",
        "joined": "<p>x</p> <p>y</p>",
        "text-before-uppercase": "text <P>x</P>",
        "one-space-indent": "<div>\n <p>x</p>\n</div>",
        "three-space-indent": "<div>\n   <p>x</p>\n</div>",
        "script-raw-followed-by-joined-blocks": "<script>const less = 1 < 2;</script><div><p>x</p></div>",
        "textarea-raw-followed-by-joined-blocks": "<textarea>const less = 1 < 2;</textarea><div><p>x</p></div>",
        "pre-contains-real-markup": "<pre><p>x</p></pre>",
        "tr-contains-td": "<tr><td>x</td></tr>",
        "joined-td": "<tr><td>a</td><td>b</td></tr>",
    }
    valid_case = """<!-- <p>comment</p> -->
<div data-example=\"<p>attribute</p>\">
  <script>const less = 1 < 2; const markup = \"<p>script</p>\";</script>
  <textarea>const less = 1 < 2; <p>textarea</p></textarea>
  <style>.sample { content: \"<p>style</p>\"; }</style>
  <p><span>span</span><code>code</code><strong>strong</strong><a href=\"#\">link</a><br><dt>term</dt><dd>description</dd></p>
</div>"""
    failures = []
    for name, source in invalid_cases.items():
        if not validate_source(source):
            failures.append(f"invalid case was accepted: {name}")
    if validate_source(valid_case):
        failures.append("valid case was rejected")
    return failures


if action == "format":
    input_path, output_path, mode_source = sys.argv[2:]
    source = open(input_path, encoding="utf-8").read()
    with open(output_path, "w", encoding="utf-8", newline="") as output:
        output.write(format_source(source))
    os.chmod(output_path, stat.S_IMODE(os.stat(mode_source).st_mode))
elif action == "check":
    input_path = sys.argv[2]
    source = open(input_path, encoding="utf-8").read()
    for line, reason in validate_source(source):
        print(f"{input_path}:{line}: {reason}")
elif action == "regress":
    failures = run_regressions()
    if failures:
        print("FAIL(8-regression): " + "; ".join(failures))
        sys.exit(1)
    print("PASS(8-regression): 同一行・raw領域・インデントの回帰ケースが合格")
else:
    raise SystemExit(f"unknown action: {action}")
PY
}

format_body() {
  guide_body_processor format "$1" "$2" "$3"
}

check_body() {
  guide_body_processor check "$1"
}

check_body_regressions() {
  guide_body_processor regress
}

apply_one() (
  local f="$1"
  local relative_path="${f#"$repo_root"/}"
  local tracked_mode
  # 明示テンプレート付きmktemp（"${TMPDIR:-/tmp}/<name>.XXXXXX"）を使う。裸のmktempは
  # ${TMPDIRを無視し書き込み許可の外にある既定領域を使うため}、サンドボックス実行環境では
  # 失敗する（改善課題「一時ディレクトリ-作成先」。手元の環境で動いても裸の形へ戻すな）。
  local css_tmp=""
  local formatted_tmp=""
  trap 'rm -f "$css_tmp" "$formatted_tmp"' EXIT
  # 旧実装が mktemp の 0600 をそのまま mv したガイドは、追跡時の権限へ復元する。
  # 通常はインデックスと同じモードなので、以降のPython処理は元ファイルの権限を保持する。
  tracked_mode="$(git -C "$repo_root" ls-files -s -- "$relative_path" | awk 'NR == 1 { print substr($1, 4) }')"
  if [ -n "$tracked_mode" ]; then
    chmod "$tracked_mode" "$f"
  fi
  if ! css_tmp="$(mktemp "${TMPDIR:-/tmp}/apply-guide-style-css.XXXXXX" 2>/dev/null)" || [ -z "$css_tmp" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  if ! formatted_tmp="$(mktemp "${TMPDIR:-/tmp}/apply-guide-style-body.XXXXXX" 2>/dev/null)" || [ -z "$formatted_tmp" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  awk -v cssfile="$style_css" '
    BEGIN { while ((getline line < cssfile) > 0) css = css line "\n" }
    /^<style>$/ { print; printf "%s", css; instyle=1; next }
    /^<\/style>$/ { instyle=0; print; next }
    instyle { next }
    { print }
  ' "$f" > "$css_tmp"
  format_body "$css_tmp" "$formatted_tmp" "$f"
  mv "$formatted_tmp" "$f"
)

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
      apply_one "$f"
      applied=$((applied + 1))
    done
    echo "整形・適用: $applied 枚 / 対象: ${#guides[@]} 枚"
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
        # ${close_count} は波括弧を外すな。set -u下で変数直後に全角括弧「）」が続くと
        # 変数名の続きとして誤読されunbound variableになる。この行は不合格を報せる
        # 瞬間に実行されるため、検査が失敗を報告しようとした瞬間にクラッシュし、
        # 何が悪いのか読めなくなる。
        echo "FAIL(5): $f の <style>/</style> が行頭単独の行として 1 回ずつでない（open=$open_count close=${close_count}）"
        linehead_fail=$((linehead_fail + 1))
      fi
    done
    if [ "$linehead_fail" -eq 0 ]; then
      echo "PASS(5): 全 ${#guides[@]} 枚が <style>/</style> を行頭単独の行として 1 回ずつ持つ"
    else
      fail=1
    fi

    # 6. references 配下に旧名のガイドが残っていない
    # 7. 旧名を指すパス参照がリポジトリ内に残っていない
    #    検査自身が旧名の文字列を含むと自分を検出してしまうため、接尾辞を組み立てて使う
    old_suffix="-guide"

    stale_files="$(find "$repo_root/.claude/skills" -type f -name "*${old_suffix}.html" -path '*/references/*' | sort || true)"
    if [ -n "$stale_files" ]; then
      echo "FAIL(6): 旧名のガイドが残っている:"
      printf '%s\n' "$stale_files" | sed 's/^/  /'
      fail=1
    else
      echo "PASS(6): references 配下のガイドは guide.html だけ（旧名 0 件 / 対象 ${#guides[@]} 枚）"
    fi

    # references/ 配下を指すパス参照だけを見る。地の文で旧名に言及しただけの記述は拾わない
    # 素直な形（grep -rn での全ディレクトリ走査）ではなく git grep を使う。gitignore対象
    # （生成物・依存ディレクトリ等）を自動的に除外できるため。既知の限界として、
    # 追跡されていない（gitに未addの）ファイルは走査されない
    stale_refs="$(git -C "$repo_root" grep -nE -- "references/[^ \"'<)]*${old_suffix}\.html" || true)"
    if [ -n "$stale_refs" ]; then
      echo "FAIL(7): 旧名を指すパス参照が残っている:"
      printf '%s\n' "$stale_refs" | sed 's/^/  /'
      fail=1
    else
      echo "PASS(7): 旧名を指すパス参照は 0 件（追跡済みファイルのみ走査）"
    fi

    # 8. ブロック要素の開きタグが行ごとに分かれ、深さどおりにインデントされている。
    #    コメント・属性値と style/pre/script/textarea のraw領域はHTML要素として扱わない。
    joined_fail=0
    for f in "${guides[@]}"; do
      hits="$(check_body "$f")"
      if [ -n "$hits" ]; then
        echo "FAIL(8): $f のブロック要素の改行またはインデントが不正:"
        printf '%s\n' "$hits" | head -3 | cut -c1-180 | sed 's/^/  /'
        joined_fail=$((joined_fail + 1))
      fi
    done
    if ! check_body_regressions; then
      fail=1
    fi
    if [ "$joined_fail" -eq 0 ]; then
      echo "PASS(8): 全 ${#guides[@]} 枚がブロック要素を行ごとに分け、正しくインデントしている"
    else
      fail=1
    fi

    # 9. .claude/skills/ 配下の全スキルが references/guide.html を持つ
    missing_guide_fail=0
    skill_count=0
    for d in "$repo_root"/.claude/skills/*/; do
      [ -d "$d" ] || continue
      skill_count=$((skill_count + 1))
      skill_name="$(basename "$d")"
      if [ ! -f "${d}references/guide.html" ]; then
        echo "FAIL(9): $skill_name が references/guide.html を持たない"
        missing_guide_fail=$((missing_guide_fail + 1))
      fi
    done
    if [ "$missing_guide_fail" -eq 0 ]; then
      echo "PASS(9): 全 ${skill_count} スキルが references/guide.html を持つ"
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
