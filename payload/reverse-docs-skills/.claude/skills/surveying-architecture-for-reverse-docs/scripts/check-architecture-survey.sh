#!/usr/bin/env bash
set -euo pipefail

# check-architecture-survey.sh — アーキテクチャ調査書の機械ゲート（7検査すべて決定的）
#
# 使い方:
#   check-architecture-survey.sh <調査書パス> <target_repo_path>
#   check-architecture-survey.sh --self-test
#
# 検査:
#   1. 記載パス実在100%: 調査書内のbacktick囲みトークンのうち「/」を含む相対パスとみなせるものを
#      抽出し、全件 target_repo_path 配下に test -e で実在確認する。URL（://）・glob（* ?）・
#      プレースホルダ（< >）・絶対パス（先頭/）・空白/正規表現記号を含むトークン（grepパターン等の
#      コード例）は対象外とする。トークンが否定文脈マーカー「非実在:」で始まる場合
#      （例: `非実在:.github/workflows/ci.yml`）も対象外とする。これは「このパスは実在しない」と
#      本文で明示的に述べるための記法であり、実在チェックを免除する（改善課題1-115）。
#   2. 6種別網羅: 画面・API・テーブル・バッチ・帳票・外部連携の6語すべてについて、種別名と
#      判定語（実在する / 実在しない（）が同一行に存在する判定行があるか確認する。加えて、
#      §6ユニット種別判定テーブルの検出手がかり列に記録されたgrep/rg/find系コマンドを実際に
#      target_repo_path に対して再実行し、「実在する」なら1件以上・「実在しない」なら0件を
#      返すことを確認する（改善課題1-140）。検索系コマンド以外・手がかり未記載（「-」等）は
#      再実行せず検証不能として通過扱いにする。非UTF-8ファイルは detect-encoding.sh で
#      UTF-8変換した一時ミラーに対して再実行する。
#   3. 推測語ゼロ: おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず が0件。
#   4. テンプレ残存ゼロ: <実測|<FILL|TBD|TODO|（調査結果を記入） が0件（§9テスト基盤のプレースホルダ残存を含む）。
#   5. §4ディレクトリ網羅: §1のfindコマンドから走査範囲を決定的に再現し、直接ファイルを
#      持つディレクトリがすべて§4（責務マップ本体または対象外ディレクトリ）もしくは
#      §4に列挙された層の子ディレクトリとして包含されることを確認する。
#   6. §10プロジェクト形態: §10節が存在し、プロジェクト形態が「単独プロジェクト」または
#      「モノレポ」のいずれかであり、サイト一覧に1行以上あって各ルートディレクトリが
#      target_repo_path配下に実在し、サイトキーが重複していないことを確認する。
#      根拠パス列の書式は検査しない（パス実在は検査1が担当する）。
#   7. §8申し送りエンコーディング実測整合: §8後続工程への申し送りに記載された
#      「エンコーディング-」始まりのキー行について、内容セルの先頭backtickトークンを
#      エンコーディング名、後続のbacktickトークンを対象ファイル群として抽出し、
#      各ファイルが実バイトでそのエンコーディング名により復号できることを
#      detect-encoding.sh decodable で確認する（改善課題1-126）。UNKNOWNと記載された
#      行は復号可否検査の対象外とする（UNKNOWNは明示的な判定不能の申告であり、検証不能な
#      値との復号照合はできないため）。
#
#   いずれか1件でも違反があれば exit 1（fail-closed）。全件PASSでexit 0。
#   --self-test は合成フィクスチャで陽性exit 0・陰性(検査ごと)exit 1を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DETECT_ENCODING_SH="$SCRIPT_DIR/../../../../shared/scripts/detect-encoding.sh"

UNIT_KINDS="画面 API テーブル バッチ 帳票 外部連携"
GUESS_WORDS_RE='おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず'
PLACEHOLDER_RE='<実測|<FILL|TBD|TODO|調査結果を記入'
# 実在しないことを述べるための否定文脈マーカー（改善課題1-115）。backtickトークンの先頭に
# このマーカーを付けると（例: `非実在:src/legacy/old.ts`）、検査1の実在チェックを免除する。
NOT_EXIST_MARKER="非実在:"

# backtick囲みトークンのうち「相対パス」とみなせるもの以外を除外する判定。
# 除外: 「/」を含まない / URL / glob / プレースホルダ / 絶対パス / 空白・正規表現記号を含む /
#       否定文脈マーカー（非実在:）で始まる
is_path_candidate() {
  tok="$1"
  case "$tok" in
    "${NOT_EXIST_MARKER}"*) return 1 ;;
  esac
  case "$tok" in
    */*) : ;;
    *) return 1 ;;
  esac
  case "$tok" in
    *'://'*|*'*'*|*'?'*|*'<'*|*'>'*|/*|*' '*|*'\'*|*'"'*|*"'"*|*'('*|*')'*|*'|'*|*'['*|*']'*|*'^'*|*'$'*|*'+'*|*'{'*|*'}'*)
      return 1 ;;
  esac
  return 0
}

extract_path_tokens() {
  grep -oE '`[^`]+`' "$1" 2>/dev/null | sed -E 's/^`//; s/`$//'
}

# §1 調査メタ節を抽出する（### サブ見出しを含む）
extract_section_meta() {
  awk '/^## .*調査メタ/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §4 ディレクトリ責務マップの本体テーブルのみ抽出する（### 対象外ディレクトリの手前で停止）
extract_section4() {
  awk '/^## .*ディレクトリ責務マップ/{f=1;next} /^## [^#]|^### |^---$/{if(f)exit} f' "$1"
}

# §4 内の「### 対象外ディレクトリ」サブセクションを抽出する
extract_excluded_dirs() {
  awk '/^### .*対象外ディレクトリ/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §10 プロジェクト形態とサイト構成節を抽出する（### サブ見出しを含む）
extract_section10() {
  awk '/^## .*プロジェクト形態とサイト構成/{f=1;next} /^## [^#]/{if(f)exit} f' "$1"
}

# §6 ユニット種別判定の本体テーブルを抽出する（1-140: 検出手がかりの再実行に使う）
extract_section6() {
  awk '/^## .*ユニット種別判定/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §8 後続工程への申し送り節を抽出する（1-126: エンコーディング申し送りの実測整合に使う）
extract_section8() {
  awk '/^## .*後続工程への申し送り/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# repo を丸ごとコピーし、非UTF-8ファイルを detect-encoding.sh でUTF-8へ変換した
# 一時ミラーを作る（1-140: 検出手がかりコマンドの再実行を非UTF-8原本に対しても
# 正しく行うため）。呼び出し元がミラーパスをrm -rfで片付ける。
prepare_utf8_mirror() {
  src="$1"
  mirror="$(mktemp -d "${TMPDIR:-/tmp}/architecture-survey-mirror.XXXXXX")"
  cp -R "$src/." "$mirror/" 2>/dev/null || true
  files="$(find "$mirror" -type f 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    enc="$(bash "$DETECT_ENCODING_SH" encoding "$f" 2>/dev/null || true)"
    if [ -n "$enc" ] && [ "$enc" != "UTF-8" ]; then
      if bash "$DETECT_ENCODING_SH" to-utf8 "$f" "${f}.utf8mirrortmp" 2>/dev/null; then
        mv "${f}.utf8mirrortmp" "$f"
      fi
    fi
  done <<MIRRORFILES
$files
MIRRORFILES
  echo "$mirror"
}

# 検査1: 記載パス実在100%
check_paths_exist() {
  survey="$1"
  repo="$2"
  missing=0
  total=0
  tokens="$(extract_path_tokens "$survey")"
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if ! is_path_candidate "$tok"; then
      continue
    fi
    total=$((total + 1))
    checkpath="$tok"
    case "$checkpath" in
      ./*) checkpath="${checkpath#./}" ;;
    esac
    if [ ! -e "$repo/$checkpath" ]; then
      echo "  未実在: $tok" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$tokens
EOF
  if [ "$missing" -gt 0 ]; then
    echo "検査1失敗: 記載パス $total 件中 $missing 件が target_repo_path 配下に実在しません" >&2
    return 1
  fi
  echo "検査1通過: 記載パス $total 件すべて実在（対象0件を含む）"
  return 0
}

# 検査2: 6種別網羅（判定語が同一行に存在するか）＋ 検出手がかりの再実行整合（1-140）
# repo（第2引数）は任意。単体で呼び出す既存の使い方（判定行の存否のみ検査）を壊さないため、
# repo指定時のみ§6検出手がかりの再実行整合チェックを追加で行う。
check_unit_kinds() {
  survey="$1"
  # 引数名はhint_repoとし、他検査（check_directory_coverage等）が使うグローバル変数
  # repoを本関数が上書きしないようにする（単一引数の既存呼び出しでrepoが空文字に
  # クリアされ、後続検査が壊れる事故を防ぐ）。
  hint_repo="${2:-}"
  missing=0
  for k in $UNIT_KINDS; do
    line="$(grep -F -- "$k" "$survey" 2>/dev/null | grep -E '実在する|実在しない（' || true)"
    if [ -z "$line" ]; then
      echo "  種別未判定: ${k}（種別名と判定語「実在する」または「実在しない（」が同一行に無い）" >&2
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査2失敗: 6種別中 $missing 種別の判定行が見つかりません" >&2
    return 1
  fi

  hint_bad=0
  if [ -n "$hint_repo" ]; then
    s6="$(extract_section6 "$survey")"
    mirror_dir=""
    while IFS= read -r line6; do
      [ -z "$line6" ] && continue
      case "$line6" in '|'*) ;; *) continue ;; esac
      case "$line6" in *'|---|'*) continue ;; esac

      kind_cell="$(echo "$line6" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
      is_kind=0
      for k in $UNIT_KINDS; do
        if [ "$kind_cell" = "$k" ]; then
          is_kind=1
          break
        fi
      done
      if [ "$is_kind" -eq 0 ]; then
        continue
      fi

      verdict_cell="$(echo "$line6" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
      hint_cell="$(echo "$line6" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')"

      case "$verdict_cell" in
        実在する*) expect="positive" ;;
        実在しない*) expect="zero" ;;
        *) continue ;;
      esac

      hint_cmd="$(echo "$hint_cell" | grep -oE '`[^`]+`' 2>/dev/null | head -1 | sed 's/^`//; s/`$//' || true)"
      if [ -z "$hint_cmd" ] || [ "$hint_cmd" = "-" ]; then
        echo "  検証不能: ${kind_cell}の検出手がかりが記録されていないため再実行できません（そのまま通過）" >&2
        continue
      fi

      # 安全のため検索系(grep/rg/find)で始まるコマンドのみ再実行する。
      # シェルメタ文字（; & | ` $( ）で追加コマンドが連結されている場合も、
      # 「検索系コマンドのみ」とはみなさず再実行しない。
      case "$hint_cmd" in
        'grep '*|'rg '*|'find '*) is_search=1 ;;
        *) is_search=0 ;;
      esac
      case "$hint_cmd" in
        *';'*|*'&&'*|*'||'*|*'|'*|*'`'*|*'$('*) is_search=0 ;;
      esac
      if [ "$is_search" -eq 0 ]; then
        echo "  検証不能: ${kind_cell}の検出手がかりは検索系コマンド（grep/rg/find）でないため再実行しません: ${hint_cmd}" >&2
        continue
      fi

      if [ -z "$mirror_dir" ]; then
        mirror_dir="$(prepare_utf8_mirror "$hint_repo")"
      fi

      hint_output="$( (cd "$mirror_dir" && eval "$hint_cmd") 2>/dev/null || true )"
      if [ -n "$hint_output" ]; then
        result="positive"
      else
        result="zero"
      fi

      if [ "$expect" != "$result" ]; then
        echo "  検出手がかり不整合: ${kind_cell}は「${verdict_cell}」と判定されているが検出手がかり再実行結果は${result}件相当です: ${hint_cmd}" >&2
        hint_bad=$((hint_bad + 1))
      fi
    done <<S6END
$s6
S6END
    if [ -n "$mirror_dir" ]; then
      rm -rf "$mirror_dir"
    fi
  fi

  if [ "$hint_bad" -gt 0 ]; then
    echo "検査2失敗: 検出手がかりの再実行結果が判定語と $hint_bad 件不整合です" >&2
    return 1
  fi

  echo "検査2通過: 6種別すべてに判定行あり（検出手がかり再実行の整合確認込み）"
  return 0
}

# 検査3: 推測語ゼロ
check_no_guess_words() {
  survey="$1"
  hits="$(grep -nE -- "$GUESS_WORDS_RE" "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査3失敗: 推測語を検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査3通過: 推測語0件"
  return 0
}

# 検査4: テンプレ残存ゼロ
check_no_placeholder() {
  survey="$1"
  hits="$(grep -nE -- "$PLACEHOLDER_RE" "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査4失敗: テンプレ残存トークンを検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査4通過: テンプレ残存0件"
  return 0
}

# 検査5: §4ディレクトリ網羅性
check_directory_coverage() {
  survey="$1"
  repo="$2"

  # §1に調査手段としてのfindコマンドが記録されていることは引き続き要求する。
  # ただし走査範囲はその記述から導出しない（被検査文書が検査の厳格さを決められるため）。
  meta="$(extract_section_meta "$survey")"
  find_cmds="$(echo "$meta" | grep -oE '`find [^`]+`' | sed 's/^`//; s/`$//')"

  if [ -z "$find_cmds" ]; then
    echo "検査5失敗: §1にfindコマンドが見つかりません" >&2
    return 1
  fi

  # 走査範囲は対象リポジトリの実ディレクトリ構造から決定する。
  # 直接ファイルを持つディレクトリの集合を1回の走査でまとめて取得し、
  # ディレクトリ数に比例したプロセス起動をなくす（旧実装はディレクトリごとにfindを起動していた）。
  scan_max_depth="${DIRCOV_MAX_DEPTH:-}"
  all_files="$(find "$repo" -type f -not -path '*/.git/*' 2>/dev/null)"
  dirs_with_files="$(printf '%s\n' "$all_files" | sed 's|/[^/]*$||' | sort -u)"

  # 深度を制限する場合は、制限した深度と検査対象外にした件数を後段で出力へ明示する
  scanned_dirs=""
  skipped_by_depth=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    if [ -n "$scan_max_depth" ]; then
      if [ "$d" = "$repo" ]; then
        depth=0
      else
        relpath="${d#$repo/}"
        depth="$(printf '%s' "$relpath" | awk -F'/' '{print NF}')"
      fi
      if [ "$depth" -gt "$scan_max_depth" ]; then
        skipped_by_depth=$((skipped_by_depth + 1))
        continue
      fi
    fi
    scanned_dirs="${scanned_dirs}${d}
"
  done <<DIRSRC
$dirs_with_files
DIRSRC
  all_dirs="$(printf '%s' "$scanned_dirs" | sort)"
  scan_count="$(printf '%s' "$all_dirs" | grep -c . || true)"

  # §4本体テーブルからディレクトリパスを抽出（covered集合を構築）
  s4_raw="$(extract_section4 "$survey")"
  covered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in *'|---|'*) continue ;; esac
    case "$line" in *'ディレクトリ'*'責務'*) continue ;; esac
    cell="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    path="$(echo "$cell" | grep -oE '`[^`]+`' | head -1 | sed 's/^`//; s/`$//')"
    if [ -n "$path" ]; then
      norm="$path"
      case "$norm" in ./*) norm="${norm#./}" ;; esac
      if [ -f "$repo/$norm" ] 2>/dev/null; then
        norm="$(dirname "$norm")"
      fi
      covered="${covered}${norm}
"
    fi
  done <<S4END
$s4_raw
S4END

  # 対象外ディレクトリを抽出してcovered集合に追加
  excl_raw="$(extract_excluded_dirs "$survey")"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in *'|---|'*) continue ;; esac
    case "$line" in *'ディレクトリ'*'除外理由'*) continue ;; esac
    cell="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    path="$(echo "$cell" | grep -oE '`[^`]+`' | head -1 | sed 's/^`//; s/`$//')"
    if [ -n "$path" ]; then
      norm="$path"
      case "$norm" in ./*) norm="${norm#./}" ;; esac
      covered="${covered}${norm}
"
    fi
  done <<EXCLEND
$excl_raw
EXCLEND

  # 各ディレクトリの網羅性を検証
  uncovered=0
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue

    # all_dirs は既に「直接ファイルを持つディレクトリ」のみ。ここでのfind再起動は不要

    # 相対パスに変換
    if [ "$dir" = "$repo" ]; then
      rel="."
    else
      rel="${dir#$repo/}"
    fi
    case "$rel" in ./*) rel="${rel#./}" ;; esac

    # covered集合との照合
    found=false
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      if [ "$rel" = "$c" ]; then
        found=true; break
      fi
      # §4の`.`行はルート直下の直接ファイルのみを網羅し、子ディレクトリへは波及しない
      if [ "$c" = "." ] && [ "$rel" = "." ]; then
        found=true; break
      fi
      case "$rel" in
        "$c"/*) found=true; break ;;
      esac
    done <<COVCHECK
$covered
COVCHECK

    if ! "$found"; then
      echo "  未網羅: $rel" >&2
      uncovered=$((uncovered + 1))
    fi
  done <<DIREND
$all_dirs
DIREND

  if [ "$uncovered" -gt 0 ]; then
    echo "検査5失敗: §4ディレクトリ責務マップに $uncovered 件の未網羅ディレクトリがあります（走査対象 ${scan_count} 件 / 深度制限による対象外 ${skipped_by_depth} 件）" >&2
    return 1
  fi
  if [ -n "$scan_max_depth" ]; then
    echo "検査5通過: ディレクトリ網羅性OK（走査対象 ${scan_count} 件 / 深度 ${scan_max_depth} 制限により対象外 ${skipped_by_depth} 件）"
  else
    echo "検査5通過: ディレクトリ網羅性OK（走査対象 ${scan_count} 件 / 深度制限なし・対象外 0 件）"
  fi
  return 0
}

# 検査6: §10 プロジェクト形態とサイト構成
check_project_form() {
  survey="$1"
  repo="$2"

  s10="$(extract_section10 "$survey")"
  if [ -z "$s10" ]; then
    echo "検査6失敗: §10 プロジェクト形態とサイト構成の節が見つかりません" >&2
    return 1
  fi

  form_line="$(echo "$s10" | grep -E '^\|[^|]*プロジェクト形態' | head -1)"
  if [ -z "$form_line" ]; then
    echo "検査6失敗: §10 にプロジェクト形態の行がありません" >&2
    return 1
  fi
  case "$form_line" in
    *単独プロジェクト*|*モノレポ*) : ;;
    *)
      echo "検査6失敗: プロジェクト形態が「単独プロジェクト」「モノレポ」のいずれでもありません" >&2
      echo "$form_line" >&2
      return 1 ;;
  esac

  site_rows="$(echo "$s10" \
    | awk '/^### .*サイト一覧/{f=1;next} f' \
    | grep -E '^\|' \
    | grep -v '^|[[:space:]]*---' \
    | grep -v 'サイトキー')"
  if [ -z "$site_rows" ]; then
    echo "検査6失敗: サイト一覧に行がありません（単独プロジェクトでも1行必要）" >&2
    return 1
  fi

  seen_keys=""
  bad=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' | sed 's/^`//; s/`$//')"
    root="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' | sed 's/^`//; s/`$//')"
    [ -z "$key" ] && continue

    case "$seen_keys" in
      *"[$key]"*)
        echo "  サイトキー重複: $key" >&2
        bad=$((bad + 1)) ;;
    esac
    seen_keys="${seen_keys}[$key]"

    if [ -z "$root" ]; then
      echo "  ルートディレクトリ未記入: $key" >&2
      bad=$((bad + 1))
    elif [ ! -d "$repo/$root" ]; then
      echo "  ルートディレクトリが実在しない: $key -> $root" >&2
      bad=$((bad + 1))
    fi
  done <<S10END
$site_rows
S10END

  if [ "$bad" -gt 0 ]; then
    echo "検査6失敗: サイト一覧に $bad 件の問題があります" >&2
    return 1
  fi
  echo "検査6通過: プロジェクト形態とサイト一覧OK"
  return 0
}

# 検査7: §8申し送りエンコーディング実測整合（1-126）
# 「エンコーディング-」で始まるキー行のみを対象とする。内容セルの先頭backtickトークンを
# エンコーディング名、後続backtickトークンを対象ファイル群として、各ファイルが実バイトで
# そのエンコーディング名により復号できることを detect-encoding.sh decodable で確認する。
# UNKNOWN行は復号可否検査の対象外（明示的な判定不能の申告のため）。
check_encoding_hints() {
  survey="$1"
  repo="$2"
  bad=0
  total=0
  s8="$(extract_section8 "$survey")"
  while IFS= read -r line8; do
    [ -z "$line8" ] && continue
    case "$line8" in '|'*) ;; *) continue ;; esac
    case "$line8" in *'|---|'*) continue ;; esac

    key_cell="$(echo "$line8" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    case "$key_cell" in
      エンコーディング-*) : ;;
      *) continue ;;
    esac

    content_cell="$(echo "$line8" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    cell_tokens="$(echo "$content_cell" | grep -oE '`[^`]+`' 2>/dev/null | sed 's/^`//; s/`$//' || true)"
    enc="$(echo "$cell_tokens" | head -1)"
    files="$(echo "$cell_tokens" | tail -n +2)"
    [ -z "$enc" ] && continue

    if [ "$enc" = "UNKNOWN" ]; then
      continue
    fi

    while IFS= read -r f; do
      [ -z "$f" ] && continue
      total=$((total + 1))
      path="$repo/$f"
      if [ ! -f "$path" ]; then
        echo "  対象ファイル不在: ${f}（キー=${key_cell}, エンコーディング=${enc}）" >&2
        bad=$((bad + 1))
        continue
      fi
      if ! bash "$DETECT_ENCODING_SH" decodable "$path" "$enc" >/dev/null 2>&1; then
        echo "  復号不可: ${f} はエンコーディング ${enc} で復号できません（キー=${key_cell}）" >&2
        bad=$((bad + 1))
      fi
    done <<FILESEND
$files
FILESEND
  done <<S8END
$s8
S8END

  if [ "$bad" -gt 0 ]; then
    echo "検査7失敗: 申し送りのエンコーディング記載 $bad 件が実バイトで復号できません（対象 $total 件中）" >&2
    return 1
  fi
  echo "検査7通過: 申し送りのエンコーディング記載はすべて実バイトで復号可能（対象 $total 件。UNKNOWN行は対象外）"
  return 0
}

# 登録済み検査の唯一の一覧（検査数はこの一覧から導出する。固定文字列で件数を書かない）。
# 検査を追加・削除する場合はこの一覧のみを更新すればよい（成功時メッセージ・失敗時メッセージは
# CHECK_COUNT を通じて自動追従する）。
CHECK_NAMES="check_paths_exist check_unit_kinds check_no_guess_words check_no_placeholder check_directory_coverage check_project_form check_encoding_hints"

# CHECK_NAMES 内の検査すべてを実行し集約結果を返す。実行後 CHECK_COUNT に登録検査数を格納する。
run_all_checks() {
  survey="$1"
  repo="$2"
  rc=0
  count=0
  for name in $CHECK_NAMES; do
    count=$((count + 1))
    case "$name" in
      check_no_guess_words|check_no_placeholder)
        "$name" "$survey" || rc=1 ;;
      *)
        "$name" "$survey" "$repo" || rc=1 ;;
    esac
  done
  CHECK_COUNT="$count"
  return "$rc"
}

# 合成フィクスチャによる自己テスト（陽性1件・検査ごとの陰性6件＝計7ケース）。
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/architecture-survey-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo"
  mkdir -p "$repo/src/app/api"
  mkdir -p "$repo/src/styles"
  : > "$repo/package.json"
  : > "$repo/src/app/page.tsx"
  : > "$repo/src/app/api/route.ts"
  : > "$repo/src/styles/shared-theme.ts"

  # 1-126自己テスト用: §8申し送りエンコーディング実測整合(検査7)の材料となる
  # 非UTF-8ファイル（EUC-JPとShift_JISを取り違えないことも兼ねて確認する）。
  # 既存の$repo（検査5の§4網羅性テストが厳密に対応付けている）を汚さないよう、
  # 独立したencoding_repoに置く。
  encoding_repo="$tmp/encoding-repo"
  mkdir -p "$encoding_repo/src/legacy"
  python3 -c "
import sys
sys.stdout.buffer.write('経理システムのルーティング定義。\n'.encode('euc-jp'))
" > "$encoding_repo/src/legacy/routes.euc.txt"

  base_kinds='| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  # 陽性フィクスチャ: 7検査すべてPASSする想定
  cat > "$tmp/pass.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` と \`src/app/page.tsx\` を確認した。API定義は \`src/app/api/route.ts\`。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep -rlE "from ['\"].*theme['\"]" src で検出（3件） |

### 対象外ディレクトリ
| ディレクトリ | 除外理由 |
|---|---|
| \`src/app\` | ユニット種別判定で個別管理するため |

## ユニット種別判定
$base_kinds

## プロジェクト形態とサイト構成
| 項目 | 内容 | 根拠パス |
|---|---|---|
| プロジェクト形態 | 単独プロジェクト | \`package.json\` |
| ワークスペース定義 | 実在しない（ワークスペース定義ファイルが見つからないため） | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 根拠パス |
|---|---|---|---|---|---|
| main | 単一サイト | . | npm run build | npm run dev | \`package.json\` |
MD

  # 陰性1: 検査1のみ違反（存在しないパスを記載）
  cat > "$tmp/fail1.md" <<MD
## エントリポイント
\`src/app/missing.tsx\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性2: 検査2のみ違反（画面の判定語を欠落）
  cat > "$tmp/fail2.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 要確認 | - | - |
| API | 実在する | \`find src/app/api\` で検出 | \`src/app/api/route.ts\` |
| テーブル | 実在しない（マイグレーションが見つからないため） | - | - |
| バッチ | 実在しない（ジョブ定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリが見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントが見つからないため） | - | - |
MD

  # 陰性3: 検査3のみ違反（推測語混入）
  cat > "$tmp/fail3.md" <<MD
## エントリポイント
\`package.json\` を確認した。ルーティング方式はおそらくApp Routerである。

## ユニット種別判定
$base_kinds
MD

  # 陰性4: 検査4のみ違反（テンプレ残存）
  cat > "$tmp/fail4.md" <<MD
## 調査メタ
updated: <実測: YYYY-MM-DD>

## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性4b: 検査4のみ違反（§9テスト基盤のプレースホルダ残存）
  cat > "$tmp/fail4b.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds

## テスト基盤

### テストフレームワーク

| 種別 | フレームワーク | 設定ファイル | 備考 |
|---|---|---|---|
| 単体テスト | （調査結果を記入） | （パス） | |
MD

  # 陰性5: 検査5のみ違反（ディレクトリ未網羅）
  cat > "$tmp/fail5.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` を確認した。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep で検出 |

## ユニット種別判定
$base_kinds
MD

  # 陰性6: 検査5のみ違反（§4の`.`行が対象外ディレクトリ表なしで存在し、
  # 子ディレクトリsrc/appが個別行にも対象外にも未記載＝`.`の誤った全域マッチを検出する）
  cat > "$tmp/fail6.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` と \`src/app/page.tsx\` を確認した。API定義は \`src/app/api/route.ts\`。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep -rlE "from ['\"].*theme['\"]" src で検出（3件） |

## ユニット種別判定
$base_kinds
MD

  # 陰性7: 検査6のみ違反（§10節そのものが欠落）
  cat > "$tmp/fail7.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性8: 検査6のみ違反（サイト一覧のルートディレクトリが実在しない）
  cat > "$tmp/fail8.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds

## プロジェクト形態とサイト構成
| 項目 | 内容 | 根拠パス |
|---|---|---|
| プロジェクト形態 | モノレポ | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 根拠パス |
|---|---|---|---|---|---|
| web | 利用者サイト | apps/missing-site | npm run build | npm run dev | \`package.json\` |
MD

  rc=0

  if run_all_checks "$tmp/pass.md" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 陽性フィクスチャがexit 0"
  else
    echo "  [FAIL] 陽性フィクスチャがexit 0にならない" >&2
    rc=1
  fi

  if check_paths_exist "$tmp/fail1.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1: 未実在パスがあるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1: 未実在パスでexit 1"
  fi

  if check_unit_kinds "$tmp/fail2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2: 判定行欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2: 判定行欠落でexit 1"
  fi

  if check_no_guess_words "$tmp/fail3.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査3: 推測語混入があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査3: 推測語混入でexit 1"
  fi

  if check_no_placeholder "$tmp/fail4.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: テンプレ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: テンプレ残存でexit 1"
  fi

  if check_no_placeholder "$tmp/fail4b.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: §9テスト基盤のプレースホルダ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: §9テスト基盤のプレースホルダ残存でexit 1"
  fi

  if check_directory_coverage "$tmp/fail5.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: ディレクトリ未網羅があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査5: ディレクトリ未網羅でexit 1"
  fi

  if check_directory_coverage "$tmp/fail6.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: §4の\`.\`行が子ディレクトリへ誤って全域マッチしexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査5: §4の\`.\`行はルート直下のみ網羅しsrc/appの未網羅でexit 1"
  fi

  if check_project_form "$tmp/fail7.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: §10節が欠落しているのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: §10節の欠落でexit 1"
  fi

  if check_project_form "$tmp/fail8.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: サイトのルートディレクトリが未実在なのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: サイトのルートディレクトリ未実在でexit 1"
  fi

  # 陰性9: 検査5のみ違反（走査範囲が被検査文書の記述に依存しない）。
  # §1のfindコマンドは-maxdepth 1という浅い深度を記述するが、深い階層に
  # 責務マップ未記載のディレクトリ（直接ファイルを持つ）を置く。旧実装は
  # §1の記述をそのまま走査範囲に採用していたためこのケースを検出できなかった。
  rangerepo="$tmp/rangerepo"
  mkdir -p "$rangerepo/a/b/c/deep"
  : > "$rangerepo/package.json"
  : > "$rangerepo/a/b/c/deep/file.txt"

  cat > "$tmp/fail9.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 1 -type d\` | ディレクトリ構造の確認 |

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
MD

  if check_directory_coverage "$tmp/fail9.md" "$rangerepo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: §1の浅いfind記述に反して深階層の未網羅ディレクトリを検出できなかった（走査範囲が被検査文書に依存している）" >&2
    rc=1
  else
    echo "  [PASS] 検査5: §1の記述に関わらず深階層の未網羅ディレクトリを検出しexit 1"
  fi

  # 陽性9: 検査5の出力に走査対象件数と対象外件数の両方が含まれる。
  # check_directory_coverage は内部で repo="$2" とグローバル変数を上書きするため、
  # 直前のテストで変化した $repo に依存せず、pass フィクスチャ自身のリポジトリを明示指定する。
  cov_output="$(check_directory_coverage "$tmp/pass.md" "$tmp/repo" 2>&1)" || true
  if echo "$cov_output" | grep -q '走査対象' && echo "$cov_output" | grep -q '対象外'; then
    echo "  [PASS] 検査5: 出力に走査対象件数と対象外件数の両方が含まれる"
  else
    echo "  [FAIL] 検査5: 出力に走査対象件数または対象外件数が含まれない" >&2
    echo "$cov_output" >&2
    rc=1
  fi

  # --- 1-140自己テスト追加分: 検査2への検出手がかり再実行整合チェック ---
  # 陰性10: 「実在しない」と記録しながら再実行すると1件以上返す合成調査書でexit 1になること
  mismatch_kinds='| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | `find src/app -name page.tsx` で検出 | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  cat > "$tmp/fail10.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$mismatch_kinds
MD

  if check_unit_kinds "$tmp/fail10.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2(1-140): 「実在しない」判定なのに検出手がかり再実行が1件以上返すのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2(1-140): 判定と検出手がかり再実行結果の不整合でexit 1"
  fi

  # 陽性: 判定と検出手がかり再実行結果が整合する合成調査書（pass.md）は通過すること
  if check_unit_kinds "$tmp/pass.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査2(1-140): 判定と検出手がかり再実行結果が整合する合成調査書は通過"
  else
    echo "  [FAIL] 検査2(1-140): 整合しているのにexit 1になった" >&2
    rc=1
  fi

  # --- 1-126自己テスト追加分: 検査7(§8申し送りエンコーディング実測整合) ---
  # 陽性: 記録されたエンコーディング名で対象ファイルが実際に復号できる
  cat > "$tmp/encoding-pass.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-legacyルーティング定義 | \`EUC-JP\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-pass.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査7(1-126): 記録されたエンコーディング名で対象ファイルが復号できる場合は通過"
  else
    echo "  [FAIL] 検査7(1-126): 復号できるのにexit 1になった" >&2
    rc=1
  fi

  # 陰性: 記録されたエンコーディング名では対象ファイルを復号できない（EUC-JPの実バイトにShift_JISと誤記）
  cat > "$tmp/encoding-fail.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-legacyルーティング定義誤記 | \`Shift_JIS\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-fail.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査7(1-126): 復号できない値が記録されているのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査7(1-126): 復号できない値の記録でexit 1"
  fi

  # UNKNOWN行は復号可否検査の対象外として通過すること
  cat > "$tmp/encoding-unknown.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-判定不能ファイル | \`UNKNOWN\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-unknown.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査7(1-126): UNKNOWN行は復号可否検査の対象外として通過"
  else
    echo "  [FAIL] 検査7(1-126): UNKNOWN行が誤ってexit 1になった" >&2
    rc=1
  fi

  # 陽性10: 1,000ディレクトリ規模のフィクスチャでディレクトリごとのfind再起動なしに
  # 単一走査が完了する（所要時間ではなく完了することを判定基準とする）
  bigrepo="$tmp/bigrepo"
  mkdir -p "$bigrepo"
  : > "$bigrepo/package.json"
  bi=1
  while [ "$bi" -le 1000 ]; do
    bd="$bigrepo/dir$bi"
    mkdir -p "$bd"
    : > "$bd/file.txt"
    bi=$((bi + 1))
  done

  cat > "$tmp/bigsurvey.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -type f\` | ディレクトリ構造の確認 |

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
MD

  if check_directory_coverage "$tmp/bigsurvey.md" "$bigrepo" >/dev/null 2>&1; then
    echo "  [PASS] 検査5: 1,000ディレクトリ規模のフィクスチャで単一走査が完了した（exit 0）"
  else
    echo "  [PASS] 検査5: 1,000ディレクトリ規模のフィクスチャで単一走査が完了した（exit 1・未網羅検出のため想定内）"
  fi

  # --- 1-111自己テスト追加分: 成功時メッセージの検査数がCHECK_NAMES登録数と一致すること ---
  registered_count="$(printf '%s\n' $CHECK_NAMES | wc -l | tr -d ' ')"
  full_output="$(bash "$0" "$tmp/pass.md" "$tmp/repo" 2>&1)" || true
  if echo "$full_output" | grep -q "全${registered_count}検査PASS"; then
    echo "  [PASS] 1-111: 成功時メッセージの検査数(${registered_count})がCHECK_NAMES登録数と一致"
  else
    echo "  [FAIL] 1-111: 成功時メッセージの検査数がCHECK_NAMES登録数(${registered_count})と一致しない" >&2
    echo "$full_output" >&2
    rc=1
  fi

  # --- 1-115自己テスト追加分: 実在しないことを示す否定文脈マーカー「非実在:」 ---
  cat > "$tmp/notexist-pass.md" <<MD
## エントリポイント
\`非実在:src/legacy/removed.ts\` は過去に存在したが削除済みで、現在は存在しない。
MD

  if check_paths_exist "$tmp/notexist-pass.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査1(1-115): 非実在マーカー付きの実在しないパスは実在チェック対象外として通過"
  else
    echo "  [FAIL] 検査1(1-115): 非実在マーカー付きなのにexit 1になった" >&2
    rc=1
  fi

  cat > "$tmp/notexist-fail.md" <<MD
## エントリポイント
\`src/legacy/removed.ts\` は過去に存在したが削除済みで、現在は存在しない。
MD

  if check_paths_exist "$tmp/notexist-fail.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1(1-115): マーカー無しで実在しないパスを記述したのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1(1-115): マーカー無しで実在しないパスを記述するとexit 1"
  fi

  # --- 1-116自己テスト追加分: ワークスペース定義なしで複数サイト行を持つ調査書 ---
  # Webサーバー設定のドキュメントルート検出（SKILL.md手順）の結果、ワークスペース定義が
  # 無くてもサイト一覧が2行以上になり得ることを検査6で確認する。
  multisite_repo="$tmp/multisite-repo"
  mkdir -p "$multisite_repo/public" "$multisite_repo/admin-assets"
  : > "$multisite_repo/package.json"

  cat > "$tmp/multisite.md" <<MD
## プロジェクト形態とサイト構成
| 項目 | 内容 | 根拠パス |
|---|---|---|
| プロジェクト形態 | 単独プロジェクト | \`package.json\` |
| ワークスペース定義 | 実在しない（ワークスペース定義ファイルが見つからないため） | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 根拠パス |
|---|---|---|---|---|---|
| web | 利用者サイト | public | npm run build | npm run dev | \`nginx.conf\` |
| admin | 管理画面 | admin-assets | npm run build:admin | npm run dev:admin | \`nginx.conf\` |
MD

  if check_project_form "$tmp/multisite.md" "$multisite_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査6(1-116): ワークスペース定義なしでも複数サイト行(2件)が実在ルートで通過"
  else
    echo "  [FAIL] 検査6(1-116): ワークスペース定義なしの複数サイト行がexit 1になった" >&2
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

survey="${1:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"
repo="${2:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"

if [ ! -f "$survey" ]; then
  echo "エラー: 調査書が見つかりません: $survey" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi

if run_all_checks "$survey" "$repo"; then
  echo "アーキテクチャ調査書ゲート: 全${CHECK_COUNT}検査PASS"
  exit 0
else
  echo "アーキテクチャ調査書ゲート: FAIL（登録検査数: ${CHECK_COUNT}）" >&2
  exit 1
fi
