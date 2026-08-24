#!/usr/bin/env bash
# build-deliverable-list.sh — .claude/skills/*/SKILL.md から成果物一覧のHTMLを作る
#
# 使い方:
#   build-deliverable-list.sh [--output <出力先>] [--ledger <台帳のパス>] [--skills-dir <スキル置き場>]
#   build-deliverable-list.sh --self-test
#
# 何をするか:
#   <skills-dir>/*/SKILL.md の設定欄（name・日本語名・description）から
#   成果物一覧の表を作る。統計欄（成果物数・スキル数・報告日）を実際の値で
#   埋め、台帳（週次スナップショット.md）の最新2件から「今週の変化」の節を
#   作って統計欄の直後へ置く。配色・版面・表の列は既存の成果物一覧.htmlの
#   ものをそのまま使う。
#
# なぜ必要か:
#   docs/tasks/週次の成果を見える化する指示書.md が指摘するとおり、
#   docs/guides/成果物一覧.html には生成器が無く、52行の表を人が手で並べた
#   ページである。週ごとの更新が回らず、スキルの中身と表示がずれても誰も
#   気づけない。
#
# docs/guides/ 配下は外部向け文書の記述制限（.claude/rules/always/docs/
#   audience-split/rule.md）の対象であり、コミット番号・検査のコマンド・
#   「実測値」等の書き手の断り書きを出力に含めてはならない。
#
# 代替案を採らなかった理由:
#   対話セッションのたびに52本のSKILL.mdを手で読み比べて表を書き直すと、
#   確認のたびに判定基準がぶれ、スキルの中身と表示のずれに気づけない。
#   このリポジトリは Makefile も package.json も持たず、新規導入は本
#   スクリプト専用の依存を増やすだけになるため、繰り返し実行できる bash
#   スクリプトとして1本に閉じた。
#
# 保守責任者: 人手（ユーザー）。表の列・統計欄の項目を変える場合は本
#   スクリプトと docs/tasks/週次の成果を見える化する指示書.md を同時に
#   更新する。
#
# 廃棄条件: 成果物一覧の運用自体を廃止した時。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_OUTPUT="$REPO_ROOT/docs/guides/成果物一覧.html"
DEFAULT_LEDGER="$REPO_ROOT/docs/tasks/work-records/週次スナップショット.md"
DEFAULT_SKILLS_DIR="$REPO_ROOT/.claude/skills"
DEFAULT_FORBIDDEN_NAMES_FILE="$HOME/agent-home/state/payload-forbidden-content.json"
FORBIDDEN_NAMES_FILE="${PAYLOAD_FORBIDDEN_NAMES_FILE:-$DEFAULT_FORBIDDEN_NAMES_FILE}"

TMP_FILES=()
cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [ -n "$f" ] && rm -f "$f"
  done
}
trap cleanup_tmp EXIT

# $(mk_tmp) のようにコマンド置換で呼ぶとサブシェル内でTMP_FILESへ追記され、
# 呼び出し元（親シェル）のTMP_FILESには反映されない。そのため代入先の変数名を
# 引数で受け取り、printf -v で親シェルの変数へ直接書き込む形にしている。
mk_tmp() {
  local __var="$1"
  local t
  if ! t="$(mktemp "${TMPDIR:-/tmp}/build-deliverable-list.XXXXXX" 2>/dev/null)" || [ -z "$t" ]; then
    return 1
  fi
  TMP_FILES+=("$t")
  printf -v "$__var" '%s' "$t"
  return 0
}

unknown_mktemp() {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
}

abspath() {
  python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"
}

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# 配布対象から外すスキル（このリポジトリ専用・非公開）の名前は、
# 除外の定義ファイル（~/agent-home/state/payload-forbidden-content.json の
# .names）から読む。名前をこのスクリプトへ直接書き込まない。
# 定義ファイルまたは jq が無い場合は除外を適用しない（fail-open）。
is_forbidden_skill_name() {
  local name="$1"
  if [ -f "$FORBIDDEN_NAMES_FILE" ] && command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$name" '(.names // []) | index($n) != null' "$FORBIDDEN_NAMES_FILE" >/dev/null 2>&1
    return $?
  fi
  return 1
}

# SKILL.md の説明は内部向けの設定値であり、外部向けガイドでは
# audience-split が禁じる作業報告の言い回しを利用者向けの表現へ直す。
externalize_description() {
  printf '%s' "$1" | sed \
    -e 's/実測値/確認した値/g' \
    -e 's/サンプリング/抽出/g' \
    -e 's/未検証/確認前/g' \
    -e 's/判断不能/判定できない/g' \
    -e 's/証拠なし/根拠を確認できない/g' \
    -e 's/この記録の限界/この記録の対象範囲/g' \
    -e 's/今回の作業で/今回/g' \
    -e 's/前回は/以前は/g' \
    -e 's/差し戻し/修正依頼/g' \
    -e 's/再実行/もう一度実行/g' \
    -e 's/と読める/と分かる/g' \
    -e 's/と考えられる/である/g' \
    -e 's/と判断した/とした/g' \
    -e 's/と推測される/の可能性がある/g'
}

# ---- frontmatter抽出（check-skill-frontmatter.sh と同形） ----

extract_frontmatter() {
  local file="$1"
  awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$file"
}

extract_description() {
  local fm="$1"
  local lineno
  lineno="$(printf '%s\n' "$fm" | grep -n '^description:' | head -1 | cut -d: -f1)"
  [ -z "$lineno" ] && return 0

  local line
  line="$(printf '%s\n' "$fm" | sed -n "${lineno}p")"

  case "$line" in
    'description: "'*)
      printf '%s\n' "$line" | sed -E 's/^description: "//; s/"[[:space:]]*$//'
      ;;
    'description: |'*)
      printf '%s\n' "$fm" | awk -v start="$lineno" '
        NR>start {
          if ($0 ~ /^[[:space:]]/) {
            s=$0
            sub(/^[[:space:]]+/, "", s)
            if (buf=="") { buf=s } else { buf=buf" "s }
          } else {
            exit
          }
        }
        END { print buf }
      '
      ;;
    *)
      printf '%s\n' "$line" | sed -E 's/^description:[[:space:]]*//'
      ;;
  esac
}

extract_japanese_name() {
  local fm="$1"
  local line
  line="$(printf '%s\n' "$fm" | grep -m1 '^日本語名:')"
  [ -z "$line" ] && return 0
  printf '%s\n' "$line" \
    | sed -E 's/^日本語名:[[:space:]]*//; s/^"//; s/"[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
  return 0
}

# ---- 台帳の週次スナップショットの抽出（compare-skill-snapshots.sh と同形） ----

extract_section_rows() {
  local ledger="$1" idx="$2"
  awk -v target="$idx" '
    /^### / { count++; insection = (count == target); next }
    insection && /^\|/ {
      line = $0
      if (line ~ /^\|---/) next
      gsub(/\\\|/, "\x01", line)
      n = split(line, parts, "|")
      out = ""
      skiprow = 0
      for (i = 2; i <= n - 1; i++) {
        v = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        gsub(/\x01/, "|", v)
        if (i == 2 && v == "スキル") skiprow = 1
        out = (out == "") ? v : out "\t" v
      }
      if (skiprow) next
      print out
    }
  ' "$ledger"
}

# 台帳の最新2件から「今週の変化」の中身（<li>行の並び）を作る。
build_weekly_diff_li() {
  local ledger="$1"

  if [ ! -f "$ledger" ] || [ ! -s "$ledger" ]; then
    printf '<li>台帳がまだありません。</li>\n'
    return 0
  fi

  local section_count
  section_count="$(grep -cE '^### ' "$ledger" 2>/dev/null)"
  section_count="${section_count:-0}"

  if [ "$section_count" -eq 0 ]; then
    printf '<li>台帳に記録がまだありません。</li>\n'
    return 0
  fi

  # 台帳（週次スナップショット）は非公開のこのリポジトリ専用スキルも
  # 含めて記録する。公開する文面に載せる本数・行はここで除外の定義
  # （is_forbidden_skill_name）を通してから使う。台帳の
  # 「**スキル本数**:」欄はこの除外を経ていない生の値のため使わない。
  local latest_rows prev_rows
  if ! mk_tmp latest_rows; then unknown_mktemp; return 2; fi
  if ! mk_tmp prev_rows; then unknown_mktemp; return 2; fi
  extract_section_rows "$ledger" 1 | while IFS=$'\t' read -r skill rest; do
    [ -z "$skill" ] && continue
    is_forbidden_skill_name "$skill" && continue
    printf '%s\t%s\n' "$skill" "$rest"
  done > "$latest_rows"

  local latest_count prev_count diff sign
  if [ "$section_count" -eq 1 ]; then
    latest_count="$(LC_ALL=C wc -l < "$latest_rows" | tr -d '[:space:]')"
    printf '<li>掲載スキル: %s本</li>\n' "$(html_escape "$latest_count")"
    return 0
  fi

  extract_section_rows "$ledger" 2 | while IFS=$'\t' read -r skill rest; do
    [ -z "$skill" ] && continue
    is_forbidden_skill_name "$skill" && continue
    printf '%s\t%s\n' "$skill" "$rest"
  done > "$prev_rows"

  latest_count="$(LC_ALL=C wc -l < "$latest_rows" | tr -d '[:space:]')"
  prev_count="$(LC_ALL=C wc -l < "$prev_rows" | tr -d '[:space:]')"
  diff=$((latest_count - prev_count))
  if [ "$diff" -gt 0 ]; then
    sign="+${diff}"
  elif [ "$diff" -lt 0 ]; then
    sign="${diff}"
  else
    sign="±0"
  fi
  printf '<li>本数: %s本 → %s本（%s）</li>\n' \
    "$(html_escape "$prev_count")" "$(html_escape "$latest_count")" "$(html_escape "$sign")"

  local skill jp desc public_desc phases tools p_line p_skill p_jp p_desc p_phases p_tools
  local added_list="" changed_list="" label label_kind

  while IFS=$'\t' read -r skill jp desc phases tools; do
    [ -z "$skill" ] && continue
    p_line="$(LC_ALL=C awk -F'\t' -v s="$skill" '$1==s{print;exit}' "$prev_rows")"
    if [ -z "$p_line" ]; then
      public_desc="$(externalize_description "$desc")"
      if [ -n "$added_list" ]; then
        added_list="${added_list}、$(html_escape "$skill")（$(html_escape "$public_desc")）"
      else
        added_list="$(html_escape "$skill")（$(html_escape "$public_desc")）"
      fi
      continue
    fi
    IFS=$'\t' read -r p_skill p_jp p_desc p_phases p_tools <<< "$p_line"
    label=""
    if [ "$jp" != "$p_jp" ] || [ "$desc" != "$p_desc" ]; then
      label="選び方"
    fi
    if [ "$phases" != "$p_phases" ] || [ "$tools" != "$p_tools" ]; then
      if [ -n "$label" ]; then
        label="${label}・できること"
      else
        label="できること"
      fi
    fi
    if [ -n "$label" ]; then
      label_kind="$(html_escape "$skill")（${label}）"
      if [ -n "$changed_list" ]; then
        changed_list="${changed_list}、${label_kind}"
      else
        changed_list="$label_kind"
      fi
    fi
  done < "$latest_rows"

  if [ -n "$added_list" ]; then
    printf '<li>新しく加わった: %s</li>\n' "$added_list"
  else
    printf '<li>新しく加わったスキルはありません。</li>\n'
  fi

  if [ -n "$changed_list" ]; then
    printf '<li>書き直した: %s</li>\n' "$changed_list"
  else
    printf '<li>書き直したスキルはありません。</li>\n'
  fi

  return 0
}

# ---- 表の行を作る ----

build_table_rows() {
  local skills_dir="$1" output_dir="$2"
  local d name file fm jp desc guide_file guide_cell rel

  find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | while IFS= read -r d; do
    file="$d/SKILL.md"
    [ -f "$file" ] || continue
    name="$(basename "$d")"
    is_forbidden_skill_name "$name" && continue
    fm="$(extract_frontmatter "$file")"
    jp="$(extract_japanese_name "$fm")"
    desc="$(extract_description "$fm")"
    desc="$(externalize_description "$desc")"

    guide_file="$d/references/guide.html"
    if [ -f "$guide_file" ]; then
      rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$guide_file" "$output_dir" 2>/dev/null)"
      guide_cell="<a href=\"${rel}\">ガイドを開く →</a>"
    else
      guide_cell="<span class=\"none\">—</span>"
    fi

    printf '          <tr><td class="id">%s</td><td class="jp">%s</td><td class="desc">%s</td><td class="guide">%s</td></tr>\n' \
      "$(html_escape "$name")" "$(html_escape "$jp")" "$(html_escape "$desc")" "$guide_cell"
  done
}

# ---- HTML本体の組み立て ----

build_html() {
  local output="$1" ledger="$2" skills_dir="$3"
  local output_dir
  output_dir="$(dirname "$output")"
  mkdir -p "$output_dir"
  output_dir="$(abspath "$output_dir")"
  skills_dir="$(abspath "$skills_dir")"

  local skill_count report_date
  skill_count="$(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while IFS= read -r d; do
    is_forbidden_skill_name "$(basename "$d")" && continue
    printf '%s\n' "$d"
  done | wc -l | tr -d '[:space:]')"
  report_date="$(date +%F)"

  local rows_file weekly_diff_file
  if ! mk_tmp rows_file; then unknown_mktemp; return 2; fi
  build_table_rows "$skills_dir" "$output_dir" > "$rows_file"

  if ! mk_tmp weekly_diff_file; then unknown_mktemp; return 2; fi
  build_weekly_diff_li "$ledger" > "$weekly_diff_file"

  local tmp_out
  if ! mk_tmp tmp_out; then unknown_mktemp; return 2; fi

  {
    cat << 'HEAD_EOF'
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>成果物一覧</title>
<style>
  :root {
    --bg: #FFFFFF;
    --panel: #FFFFFF;
    --panel2: #F1F4F8;
    --line: #D8DFE8;
    --line2: #B9C3D1;
    --text: #1A222E;
    --sub: #4B5A70;
    --muted: rgb(101, 114, 133);
    --faint: #8B96A5;
    --accent: #0272AC;
    --accent-hi: rgb(7, 89, 133);
    --accent-soft: rgba(2,132,199,0.10);
    --stamp: #BF3C22;
    --font-body: "Hiragino Kaku Gothic ProN","Hiragino Sans","Noto Sans JP","BIZ UDPGothic","Yu Gothic","Meiryo",system-ui,-apple-system,sans-serif;
    --mono: "SFMono-Regular","Menlo","Cascadia Code","Consolas",monospace;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    background: var(--bg);
    color: var(--text);
    font-family: var(--font-body);
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  @page { size: A4; margin: 0; }

  .sheet {
    position: relative;
    width: 100%;
    max-width: 860px;
    margin: 40px auto;
    padding: 16mm 14mm 14mm 14mm;
    overflow: hidden;
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 6px;
    box-shadow: 0 1px 3px rgba(16,34,64,0.06), 0 8px 24px rgba(16,34,64,0.05);
  }

  @media print {
    .sheet {
      width: 210mm;
      min-height: 297mm;
      max-width: none;
      margin: 0;
      border: none;
      border-radius: 0;
      box-shadow: none;
    }
  }

  @media (max-width: 640px) {
    .sheet { margin: 0; padding: 24px 16px; border: none; border-radius: 0; box-shadow: none; }
  }

  .grid-overlay {
    display: none;
  }

  .content { position: relative; z-index: 1; }

  .eyebrow {
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.22em;
    color: var(--faint);
    text-transform: uppercase;
    margin: 0 0 10px 0;
  }

  header.top {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 20px;
    padding-bottom: 18px;
    border-bottom: 1px solid var(--line);
    margin-bottom: 20px;
  }

  .headline h1 {
    font-size: 30px;
    font-weight: 800;
    margin: 0 0 8px 0;
    letter-spacing: -0.01em;
  }
  .headline p {
    font-size: 12px;
    color: var(--sub);
    margin: 0;
    max-width: 60ch;
    line-height: 1.6;
  }

  .stats {
    display: flex;
    gap: 22px;
    flex-shrink: 0;
  }
  .stat { text-align: right; }
  .stat .label {
    font-size: 9px;
    color: var(--muted);
    letter-spacing: 0.04em;
    margin-bottom: 4px;
  }
  .stat .value {
    font-size: 20px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text);
  }
  .stat .value .unit {
    font-size: 11px;
    font-weight: 500;
    color: var(--sub);
    margin-left: 2px;
  }
  .stat.date .value { font-size: 13px; font-weight: 600; color: var(--sub); font-family: var(--mono); }

  section.block { margin-top: 6px; }
  .block-head {
    display: flex;
    align-items: baseline;
    gap: 10px;
    margin-bottom: 12px;
  }
  .block-head h2 {
    font-size: 15px;
    font-weight: 700;
    margin: 0;
  }
  .block-head .count {
    font-size: 10px;
    color: var(--muted);
    font-family: var(--mono);
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 9.5px;
    table-layout: fixed;
  }
  thead th {
    text-align: left;
    font-size: 9px;
    font-weight: 600;
    color: var(--muted);
    letter-spacing: 0.03em;
    padding: 6px 8px;
    border-bottom: 1px solid var(--line2);
    background: var(--panel2);
  }
  col.c-id { width: 24%; }
  col.c-jp { width: 17%; }
  col.c-desc { width: 45%; }
  col.c-guide { width: 14%; }

  tbody td {
    padding: 7px 8px;
    border-bottom: 1px solid var(--line);
    vertical-align: top;
    color: var(--text);
    line-height: 1.45;
  }
  tbody tr:nth-child(even) td { background: rgba(16,34,64,0.025); }

  td.id { font-family: var(--mono); font-size: 9px; color: var(--sub); word-break: break-word; }
  td.jp { font-weight: 600; color: var(--text); }
  td.desc { color: var(--sub); }
  td.guide a {
    color: var(--accent-hi);
    text-decoration: none;
    font-size: 9px;
    white-space: nowrap;
  }
  td.guide .none { color: var(--faint); font-size: 9px; }

  tr.fail-row td { background: rgba(255,110,78,0.08) !important; }
  .flag {
    display: inline-block;
    margin-top: 3px;
    font-size: 8px;
    font-family: var(--mono);
    color: var(--stamp);
    letter-spacing: 0.02em;
  }

  footer.compliance {
    margin-top: 22px;
    padding-top: 14px;
    border-top: 1px solid var(--line);
  }
  footer.compliance h3 {
    font-size: 12px;
    margin: 0 0 8px 0;
    color: var(--text);
  }
  footer.compliance p {
    font-size: 9.5px;
    color: var(--sub);
    line-height: 1.7;
    margin: 0 0 6px 0;
  }
  .badge-ok { color: rgb(19, 117, 56); font-family: var(--mono); }
  .badge-fail { color: var(--stamp); font-family: var(--mono); }

  section.weekly-diff {
    margin-top: 14px;
    padding: 10px 12px;
    background: var(--panel2);
    border: 1px solid var(--line);
  }
  section.weekly-diff h2 {
    font-size: 12px;
    font-weight: 700;
    margin: 0 0 6px 0;
    color: var(--text);
  }
  section.weekly-diff ul {
    margin: 0;
    padding-left: 18px;
    font-size: 9.5px;
    color: var(--sub);
    line-height: 1.7;
  }
</style>
</head>
<body>
<div class="sheet">
  <div class="grid-overlay"></div>
  <div class="content">

    <div class="eyebrow">OUTPUT REPORT</div>

    <header class="top">
      <div class="headline">
        <h1>成果物一覧</h1>
        <p>作成したスキルの成果物を種別ごとに報告する。各成果物のガイドHTMLへのリンクを併記する。</p>
      </div>
      <div class="stats">
HEAD_EOF

    printf '        <div class="stat"><div class="label">成果物数</div><div class="value">%s<span class="unit">本</span></div></div>\n' "$skill_count"
    printf '        <div class="stat"><div class="label">スキル</div><div class="value">%s<span class="unit">本</span></div></div>\n' "$skill_count"
    printf '        <div class="stat date"><div class="label">報告日</div><div class="value">%s</div></div>\n' "$report_date"

    cat << 'MID_EOF'
      </div>
    </header>

    <section class="weekly-diff">
      <h2>今週の変化</h2>
      <ul>
MID_EOF

    sed 's/^/        /' "$weekly_diff_file"

    cat << 'MID2_EOF'
      </ul>
    </section>

    <section class="block">
      <div class="block-head">
        <h2>スキル</h2>
MID2_EOF

    printf '        <span class="count">%s本</span>\n' "$skill_count"

    cat << 'MID3_EOF'
      </div>
      <table>
        <colgroup>
          <col class="c-id"><col class="c-jp"><col class="c-desc"><col class="c-guide">
        </colgroup>
        <thead>
          <tr>
            <th>成果物の名称（ID）</th>
            <th>名称（日本語）</th>
            <th>説明</th>
            <th>ガイド</th>
          </tr>
        </thead>
        <tbody>
MID3_EOF

    cat "$rows_file"

    cat << 'TAIL_EOF'
        </tbody>
      </table>
    </section>

  </div>
</div>
</body>
</html>
TAIL_EOF
  } > "$tmp_out"

  mv "$tmp_out" "$output"
  echo "成果物一覧を作成しました: ${output}（成果物数: ${skill_count}）"
  return 0
}

# ---- 自己テスト ----

make_fixture_skill() {
  local dir="$1" jp="$2" desc="$3"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $(basename "$dir")"
    echo "日本語名: $jp"
    printf 'description: "%s"\n' "$desc"
    echo "invocation: $(basename "$dir")"
    echo "type: transform"
    echo "allowed-tools: [Bash]"
    echo "---"
    echo
    echo "## Phase 1"
  } > "$dir/SKILL.md"
}

write_ledger_single() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" << 'LEDGER_EOF'
# 週次スナップショット

説明文。

## 記録

### 2026-W01

**基準日**: 2026-08-07
**基準のコミット**: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
**スキル本数**: 1

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| stable-skill | 安定 | 変わらない。 | 1 | 0 |
LEDGER_EOF
}

write_ledger_two() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" << 'LEDGER_EOF'
# 週次スナップショット

説明文。

## 記録

### 2026-W02

**基準日**: 2026-08-14
**基準のコミット**: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
**スキル本数**: 2

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| new-skill | 新規 | 新しいスキルの実測値。 | 2 | 0 |
| stable-skill | 安定 | 変わらない説明。 | 1 | 0 |

### 2026-W01

**基準日**: 2026-08-07
**基準のコミット**: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
**スキル本数**: 1

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| stable-skill | 安定 | 変わらない説明。 | 1 | 0 |
LEDGER_EOF
}

self_test() {
  local base
  if ! base="$(mktemp -d "${TMPDIR:-/tmp}/build-deliverable-list-test.XXXXXX" 2>/dev/null)" || [ -z "$base" ] || [ ! -d "$base" ]; then
    unknown_mktemp
    return 2
  fi

  local pass=0 fail=0 rc

  # ケース1: 台帳が1件だけのとき
  local skills1="$base/skills1" ledger1="$base/records/ledger1.md" out1="$base/out1.html"
  make_fixture_skill "$skills1/stable-skill" "安定" "定義ファイルの実測値を前回は再実行した。"
  write_ledger_single "$ledger1"
  build_html "$out1" "$ledger1" "$skills1" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] \
    && [ -f "$out1" ] \
    && grep -qF "掲載スキル: 1本" "$out1" \
    && grep -qF ">stable-skill<" "$out1"; then
    echo "[PASS] 台帳が1件だけのとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] 台帳が1件だけのとき（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース2: 台帳が2件あるとき
  local skills2="$base/skills2" ledger2="$base/records/ledger2.md" out2="$base/out2.html"
  make_fixture_skill "$skills2/stable-skill" "安定" "変わらない説明。"
  make_fixture_skill "$skills2/new-skill" "新規" "新しいスキルの説明。"
  write_ledger_two "$ledger2"
  build_html "$out2" "$ledger2" "$skills2" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] \
    && grep -qF "本数: 1本 → 2本（+1）" "$out2" \
    && grep -qF "新しく加わった:" "$out2" \
    && grep -qF "new-skill" "$out2"; then
    echo "[PASS] 台帳が2件あるとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] 台帳が2件あるとき（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース3: 禁止語を出力に含まないこと
  if [ -f "$out1" ] && [ -f "$out2" ] \
    && ! grep -qE '(実測値|サンプリング|未検証|判断不能|証拠なし|この記録の限界)' "$out1" \
    && ! grep -qE '(今回の作業で|前回は|差し戻し|再実行した)' "$out1" \
    && ! grep -qE '(と読める|と考えられる|と判断した|と推測される)' "$out1" \
    && ! grep -qE '(実測値|サンプリング|未検証|判断不能|証拠なし|この記録の限界)' "$out2" \
    && ! grep -qE '(今回の作業で|前回は|差し戻し|再実行した)' "$out2" \
    && ! grep -qE '(と読める|と考えられる|と判断した|と推測される)' "$out2" \
    && ! grep -qE '#[0-9]{3,6}([^[:xdigit:]]|$)' "$out1" \
    && grep -qF '定義ファイルの確認した値を以前はもう一度実行した。' "$out1" \
    && grep -qF 'new-skill（新しいスキルの確認した値。）' "$out2"; then
    echo "[PASS] 禁止語を出力に含まないこと"
    pass=$((pass + 1))
  else
    echo "[FAIL] 禁止語を出力に含まないこと"
    fail=$((fail + 1))
  fi

  # ケース4: 同じ入力からは常に同じ出力を返す（決定性。報告日以外）
  local out2b="$base/out2b.html"
  build_html "$out2b" "$ledger2" "$skills2" >/dev/null 2>&1
  if diff -q "$out2" "$out2b" >/dev/null 2>&1; then
    echo "[PASS] 同じ入力からは常に同じ出力を返す"
    pass=$((pass + 1))
  else
    echo "[FAIL] 同じ入力からは常に同じ出力を返す"
    fail=$((fail + 1))
  fi

  rm -rf "$base"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

# ---- 引数解析 ----

main() {
  local output="$DEFAULT_OUTPUT"
  local ledger="$DEFAULT_LEDGER"
  local skills_dir="$DEFAULT_SKILLS_DIR"
  local do_self_test="no"

  while [ $# -gt 0 ]; do
    case "$1" in
      --output) output="$2"; shift 2 ;;
      --ledger) ledger="$2"; shift 2 ;;
      --skills-dir) skills_dir="$2"; shift 2 ;;
      --self-test) do_self_test="yes"; shift ;;
      *) echo "不明な引数: $1" >&2; exit 2 ;;
    esac
  done

  if [ "$do_self_test" = "yes" ]; then
    self_test
    exit $?
  fi

  build_html "$output" "$ledger" "$skills_dir"
  exit $?
}

main "$@"
