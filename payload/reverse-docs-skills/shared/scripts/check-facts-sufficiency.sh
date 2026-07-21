#!/usr/bin/env bash
set -euo pipefail

# check-facts-sufficiency.sh — 詳細設計の著述「前」に facts.yml 自体の充足を機械検査する fail-closed ゲート
#
# 用途:
#   従来は著述「後」のゲート（fact-coverage 等）しか無く、facts が薄いまま著述に入り
#   何度も差し戻される事故が実測されていた。本スクリプトは著述に入る前段で facts.yml が
#   盲検再構築に足る密度を持つかを機械検査し、薄い facts のまま先へ進むことを止める。
#
# 引数:
#   check-facts-sufficiency.sh <facts.yml>
#   check-facts-sufficiency.sh --self-test
#
# 出力:
#   - stdout: 違反を 1 行 1 件 〈検査記号〉\t〈セクション〉\t〈key または空〉\t〈内容〉）。
#     末尾に違反セクション → 影響する設計書の章の対応を chapter-impact 行で付記する。
#   - stderr: サマリ (violations=<N>) 。
#
# 合格条件（exit code）:
#   0 = 違反 0 件
#   1 = 違反あり (fail-closed)
#   2 = 引数・ファイルエラー
#
# 検査項目（検査記号は意味語・連番禁止）:
#   section-missing      : sections 配下に 12 分類キーがすべて存在するか
#   empty-without-reason : items が空のセクションで reason も空なら違反
#   value-empty          : measurement_pending 以外の items で value が空・欠落なら違反
#   evidence-format      : 全 items の evidence が <相対パス>:<行番号> 形式でなければ違反
#   orphan-evidence      : evidence のパス部が target_file_paths に無ければ違反
#   chapter-impact       : 違反セクション → 影響する設計書の章の付記（違反そのものではなく末尾の案内）
#
# 契約:
#   facts.yml は shared/references/facts-schema.md の固定インデント (sections 配下キー=2スペース、
#   reason/items=4スペース、- key:=6スペース、value:/evidence:=8スペース) に従う。この位置契約を
#   awk が行位置ベースで解析する。
#
# 設計判断 (ADR) の正本は本スクリプトを使う skill の SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手 (ユーザー)。facts-schema.md の 12 分類・必須フィールド・章対応を変更した時に更新する。
# macOS bash 3.2 互換 (mapfile 不使用・cut による空フィールド保持)。

extract_facts() {
    awk '
    function flush_item() {
      if (cur_key != "")
        print "ITEM\t" cur_section "\t" cur_key "\t" cur_value "\t" cur_evidence
      cur_key = ""; cur_value = ""; cur_evidence = ""
    }
    function flush_section() {
      if (cur_section != "")
        print "SECTION\t" cur_section "\t" cur_reason "\t" section_has_items
      cur_section = ""; cur_reason = ""; section_has_items = 0
    }
    BEGIN {
      in_tfp = 0; in_sections = 0
      cur_section = ""; cur_reason = ""; section_has_items = 0
      cur_key = ""; cur_value = ""; cur_evidence = ""
    }
    /^target_file_paths:[ \t]*$/ {
      flush_item(); flush_section()
      in_tfp = 1; in_sections = 0
      next
    }
    /^sections:[ \t]*$/ {
      flush_item(); flush_section()
      in_tfp = 0; in_sections = 1
      next
    }
    /^[A-Za-z_]/ {
      flush_item(); flush_section()
      in_tfp = 0; in_sections = 0
      next
    }
    in_tfp == 1 && /^  - / {
      p = $0
      sub(/^  - /, "", p)
      gsub(/^"/, "", p); gsub(/"$/, "", p)
      gsub(/^[ \t]+/, "", p); gsub(/[ \t]+$/, "", p)
      print "TFP\t" p
      next
    }
    in_sections == 1 && /^  [a-z_]+:[ \t]*$/ {
      flush_item(); flush_section()
      s = $0
      sub(/^  /, "", s)
      sub(/:[ \t]*$/, "", s)
      cur_section = s; cur_reason = ""; section_has_items = 0
      next
    }
    in_sections == 1 && /^    reason:/ {
      r = $0
      sub(/^    reason:[ \t]*/, "", r)
      gsub(/^"/, "", r); gsub(/"$/, "", r)
      gsub(/^[ \t]+/, "", r); gsub(/[ \t]+$/, "", r)
      cur_reason = r
      next
    }
    in_sections == 1 && /^      - key:/ {
      flush_item()
      k = $0
      sub(/^      - key:[ \t]*/, "", k)
      gsub(/^"/, "", k); gsub(/"$/, "", k)
      gsub(/^[ \t]+/, "", k); gsub(/[ \t]+$/, "", k)
      cur_key = k; cur_value = ""; cur_evidence = ""
      section_has_items = 1
      next
    }
    in_sections == 1 && /^        value:/ {
      v = $0
      sub(/^        value:[ \t]*/, "", v)
      gsub(/^"/, "", v); gsub(/"$/, "", v)
      gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
      cur_value = v
      next
    }
    in_sections == 1 && /^        evidence:/ {
      e = $0
      sub(/^        evidence:[ \t]*/, "", e)
      gsub(/^"/, "", e); gsub(/"$/, "", e)
      gsub(/^[ \t]+/, "", e); gsub(/[ \t]+$/, "", e)
      cur_evidence = e
      next
    }
    END { flush_item(); flush_section() }
  ' "$1"
}

chapter_for() {
  case "$1" in
    import|export_type|local_type) echo "§15 (実装契約) " ;;
    state)                         echo "§5 (状態管理) " ;;
    handler)                       echo "§8 (イベント処理) " ;;
    jsx|style)                     echo "§3 (画面構造) " ;;
    api)                           echo "§7 (API通信) " ;;
    const)                         echo "§10 (定数設定値) " ;;
    effect_trigger)                echo "§6 (データフロー) " ;;
    error_handling)                echo "§11 (エラーハンドリング) " ;;
    measurement_pending)           echo "§16 (要確認事項) " ;;
    *)                             echo "§不明" ;;
  esac
}

run_check() {
  facts_yml="$1"
  violations=0
  violated_sections=""

  data="$(extract_facts "$facts_yml")"

  tfp="$(printf '%s\n' "$data" | awk -F'\t' '$1=="TFP"{print $2}')"
  present="$(printf '%s\n' "$data" | awk -F'\t' '$1=="SECTION"{print $2}')"

  required="import export_type const state handler jsx style api measurement_pending local_type effect_trigger error_handling"

  for req in $required; do
    found=0
    for p in $present; do
      if [ "$p" = "$req" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      printf '%s\t%s\t%s\t%s\n' "section-missing" "$req" "" "12分類キー '$req' が sections 配下に存在しません"
      violations=$((violations + 1))
      violated_sections="$violated_sections $req"
    fi
  done

  while IFS= read -r row; do
    [ -z "$row" ] && continue
    rtype="$(printf '%s' "$row" | cut -f1)"
    case "$rtype" in
      SECTION)
        sname="$(printf '%s' "$row" | cut -f2)"
        sreason="$(printf '%s' "$row" | cut -f3)"
        shas="$(printf '%s' "$row" | cut -f4)"
        if [ "$shas" = "0" ] && [ -z "$sreason" ]; then
          printf '%s\t%s\t%s\t%s\n' "empty-without-reason" "$sname" "" "items が空 ([]) ですが reason も空です"
          violations=$((violations + 1))
          violated_sections="$violated_sections $sname"
        fi
        ;;
      ITEM)
        isec="$(printf '%s' "$row" | cut -f2)"
        ikey="$(printf '%s' "$row" | cut -f3)"
        ival="$(printf '%s' "$row" | cut -f4)"
        iev="$(printf '%s' "$row" | cut -f5)"

        if [ "$isec" != "measurement_pending" ] && [ -z "$ival" ]; then
          printf '%s\t%s\t%s\t%s\n' "value-empty" "$isec" "$ikey" "value が空または欠落しています"
          violations=$((violations + 1))
          violated_sections="$violated_sections $isec"
        fi

        if printf '%s' "$iev" | grep -qE '^.+:[0-9]+$'; then
          epath="$(printf '%s' "$iev" | sed -E 's/:[0-9]+$//')"
          member=0
          for t in $tfp; do
            if [ "$t" = "$epath" ]; then
              member=1
              break
            fi
          done
          if [ "$member" -eq 0 ]; then
            printf '%s\t%s\t%s\t%s\n' "orphan-evidence" "$isec" "$ikey" "evidence のパス部 '$epath' が target_file_paths にありません"
            violations=$((violations + 1))
            violated_sections="$violated_sections $isec"
          fi
        else
          printf '%s\t%s\t%s\t%s\n' "evidence-format" "$isec" "$ikey" "evidence が 〈相対パス〉:〈行番号〉 形式ではありません: '$iev'"
          violations=$((violations + 1))
          violated_sections="$violated_sections $isec"
        fi
        ;;
      *) : ;;
    esac
  done <<EOF
$data
EOF

  if [ -n "$violated_sections" ]; then
    uniq_sections="$(printf '%s\n' $violated_sections | sort -u | sed '/^[[:space:]]*$/d')"
    while IFS= read -r vs; do
      [ -z "$vs" ] && continue
      printf '%s\t%s\t%s\t%s\n' "chapter-impact" "$vs" "" "転記先: $(chapter_for "$vs")"
    done <<IMPACT
$uniq_sections
IMPACT
  fi

  echo "violations=$violations" >&2
  if [ "$violations" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---- 内蔵フィクスチャによる自己テスト ----

fx_hdr() {
  cat <<'YML'
run_id: t
profile: screen
target_repo_path: /abs/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
meta:
    source_repo: /abs/repo
    source_ref: "0000"
    route:
      value: "/foo"
      evidence: "src/screens/Foo/Foo.tsx:1"
sections:
YML
}

fx_sec_empty() {
  printf '  %s:\n    reason: "該当なし（合成フィクスチャ）"\n    items: []\n' "$1"
}

fx_sec_import_ok() {
  cat <<'YML'
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
YML
}

fx_sec_mp_ok() {
  cat <<'YML'
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML
}

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-facts-sufficiency-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  overall=0

  {
    fx_hdr
    fx_sec_import_ok
    for s in export_type const state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/valid.yml"

  {
    fx_hdr
    for s in export_type const state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/neg-missing.yml"

  {
    fx_hdr
    fx_sec_import_ok
    printf '  export_type:\n    reason: ""\n    items: []\n'
    for s in const state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/neg-emptyreason.yml"

  {
    fx_hdr
    fx_sec_import_ok
    fx_sec_empty export_type
    printf '  const:\n    reason: ""\n    items:\n      - key: const-foo\n        value: ""\n        evidence: "src/screens/Foo/Foo.tsx:5"\n'
    for s in state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/neg-valueempty.yml"

  {
    fx_hdr
    fx_sec_import_ok
    fx_sec_empty export_type
    printf '  const:\n    reason: ""\n    items:\n      - key: const-foo\n        value: "MAX=1"\n        evidence: "src/screens/Foo/Foo.tsx"\n'
    for s in state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/neg-evidenceformat.yml"

  {
    fx_hdr
    fx_sec_import_ok
    fx_sec_empty export_type
    printf '  const:\n    reason: ""\n    items:\n      - key: const-foo\n        value: "MAX=1"\n        evidence: "src/screens/Bar/Bar.tsx:5"\n'
    for s in state handler jsx style api local_type effect_trigger error_handling; do
      fx_sec_empty "$s"
    done
    fx_sec_mp_ok
  } > "$tmp/neg-orphan.yml"

  check_case() {
    set +e
    out="$(run_check "$2" 2>/dev/null)"
    rc=$?
    set -e
    ok=1
    [ "$rc" -eq "$3" ] || ok=0
    if [ -n "$4" ]; then
      case "$out" in
        *"$4"*) ;;
        *) ok=0 ;;
      esac
    fi
    if [ "$ok" -eq 1 ]; then
      echo "  [PASS] $1"
    else
      echo "  [FAIL] $1 (rc=$rc 期待=$3 記号=$4)" >&2
      printf '%s\n' "$out" >&2
      overall=1
    fi
  }

  check_case "陽性: 12分類完備・充足で exit 0" "$tmp/valid.yml" 0 ""
  check_case "陰性: section-missing で exit 1" "$tmp/neg-missing.yml" 1 "section-missing"
  check_case "陰性: empty-without-reason で exit 1" "$tmp/neg-emptyreason.yml" 1 "empty-without-reason"
  check_case "陰性: value-empty で exit 1" "$tmp/neg-valueempty.yml" 1 "value-empty"
  check_case "陰性: evidence-format で exit 1" "$tmp/neg-evidenceformat.yml" 1 "evidence-format"
  check_case "陰性: orphan-evidence で exit 1" "$tmp/neg-orphan.yml" 1 "orphan-evidence"

  set +e
  bash "$0" </dev/null >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    echo "  [PASS] 引数なし: exit 2"
  else
    echo "  [FAIL] 引数なし: exit $rc (期待 2) " >&2
    overall=1
  fi

  if [ "$overall" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$overall"
}

# ---- エントリポイント ----

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

facts_yml="${1:-}"
if [ -z "$facts_yml" ]; then
  echo "エラー: facts.yml を指定してください (使い方: check-facts-sufficiency.sh <facts.yml> | --self-test) " >&2
  exit 2
fi
if [ ! -f "$facts_yml" ]; then
  echo "エラー: ファイルが見つかりません: $facts_yml" >&2
  exit 2
fi

if run_check "$facts_yml"; then
  exit 0
else
  exit 1
fi
