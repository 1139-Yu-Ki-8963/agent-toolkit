#!/usr/bin/env bash
set -u

# viewpoint-validation.sh — 観点の値の定義と、要確認のキー照合の共有部品
#
# 目的:
#   観点の値は 合・否・要確認 の3つに限る（流れの設計「完了判定の状態」）。
#   record-acceptance.sh（書く側）とcheck-acceptance-record.sh（読む側）の
#   両方が本ファイルをsourceし、同じ定義で値を検査する。書く側が拒む値は
#   読む側も拒む状態を、実装を分けずに保証する。
#
#   「対象外」という値は設けない（項目の対象外は基本設計書の項目の書き方
#   で表す。流れの設計の決定）。
#
# 提供する関数:
#   is_valid_viewpoint_value <値>       値が3値のいずれかなら0を返す
#   trim_str <文字列>                    前後の空白を除いた値を標準出力へ出す
#   check_yakukakunin_key <viewpoints> <reason> <run_dir>
#                                        要確認を含むとき、reasonに確認事項
#                                        一覧のキーが含まれるかを確かめる。
#                                        戻り値は0=整合・1=キー不在・
#                                        2=確認事項の記録を参照できない
#                                        （呼び出し側が「要確認-キー不在」と
#                                        「要確認-判定不能」を区別するために
#                                        分ける）
#
# 要確認のキー照合の対応の取り方（改善指示書の相関強化）:
#   確認事項の記録.mdの行のうち、「事項」または「反映先」の欄に、要確認と
#   なった観点の名前を含む行を、その観点に対応する行とみなす。対応する行
#   が見つかれば、その行の「キー」がreasonに含まれることを条件にする。
#   現状の運用では「事項」「反映先」に観点名をそのまま書く慣行が無いため、
#   対応する行が1件も見つからない記録がほとんどである。その場合は対応の
#   取りようが無いため、reasonにいずれかの行の「キー」が含まれることだけ
#   を最低条件とする。この代替経路は、要確認となった観点と無関係なキーで
#   も通ってしまう（正直な限界。観点名を事項・反映先に書く運用に変えない
#   限り解消しない）。
#
# macOS bash 3.2 互換。
#
# 保守責任者: 人手（ユーザー）。値の集合を変えるときは、書く側・読む側
#   両方の自己テストを同時に見直す。
#
# 廃棄条件: 観点の値の検査を別の仕組みに置き換えた時。

is_valid_viewpoint_value() {
  case "$1" in
    合|否|要確認) return 0 ;;
    *) return 1 ;;
  esac
}

trim_str() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 観点の値に要確認が含まれるとき、理由にその観点の確認事項一覧のキーが
# 含まれているかを確かめる。$1: viewpoints  $2: reason  $3: run_dir
# 戻り値: 0=整合 1=キー不在 2=確認事項の記録を参照できない（run_dirに
# confirmations/確認事項の記録.mdが無い）
check_yakukakunin_key() {
  local viewpoints="$1" reason="$2" run_dir="$3"
  case "$viewpoints" in
    *=要確認*) ;;
    *) return 0 ;;
  esac
  local conf_file="${run_dir%/}/confirmations/確認事項の記録.md"
  [ -f "$conf_file" ] || return 2

  # 要確認となった観点の名前を集める
  local old_ifs="$IFS" item vpk vpv
  IFS=';'
  local vp_arr=($viewpoints)
  IFS="$old_ifs"
  local vp_names=()
  for item in "${vp_arr[@]-}"; do
    [ -n "$item" ] || continue
    vpk="${item%%=*}"
    vpv="${item#*=}"
    [ "$vpv" = "要確認" ] && vp_names+=("$vpk")
  done

  local conf_lines=() line
  while IFS= read -r line || [ -n "$line" ]; do
    conf_lines+=("$line")
  done < "$conf_file"

  # 対応する行（事項または反映先に観点名を含む行）が見つかれば、その行の
  # キーがreasonに含まれることを条件にする（相関を取れる場合の強い判定）
  local key jikou hanei name
  for line in "${conf_lines[@]-}"; do
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in '|'*'---'*) continue ;; esac
    IFS='|' read -r _ key _u _t jikou _kitei hanei _kt _st <<<"$line"
    key="$(trim_str "$key")"
    jikou="$(trim_str "$jikou")"
    hanei="$(trim_str "$hanei")"
    [ -n "$key" ] || continue
    [ "$key" = "キー" ] && continue
    for name in "${vp_names[@]-}"; do
      [ -n "$name" ] || continue
      case "$jikou" in
        *"$name"*) case "$reason" in *"$key"*) return 0 ;; esac ;;
      esac
      case "$hanei" in
        *"$name"*) case "$reason" in *"$key"*) return 0 ;; esac ;;
      esac
    done
  done

  # 対応する行を観点名で特定できない記録の形のときは、reasonにいずれかの
  # 行のキーが含まれることだけを最低条件とする（正直な限界。ファイル冒頭
  # のコメント参照）
  local found=1
  for line in "${conf_lines[@]-}"; do
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in '|'*'---'*) continue ;; esac
    key="${line#|}"
    key="${key%%|*}"
    key="$(trim_str "$key")"
    [ -n "$key" ] || continue
    [ "$key" = "キー" ] && continue
    found=0
    case "$reason" in
      *"$key"*) return 0 ;;
    esac
  done
  if [ "$found" -eq 1 ]; then
    case "$(printf '%s\n' "${conf_lines[@]-}")" in
      *"$reason"*) [ -n "$reason" ] && return 0 ;;
    esac
  fi
  return 1
}
