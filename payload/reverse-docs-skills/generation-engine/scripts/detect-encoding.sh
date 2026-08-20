#!/usr/bin/env bash

# detect-encoding.sh — 非UTF-8原本の文字コードを候補復号可否の実測で決定的に判定する共通スクリプト
#
# 使い方（単独実行）:
#   detect-encoding.sh encoding <file>              — UTF-8/EUC-JP/Shift_JIS/ISO-2022-JP/UNKNOWNを判定
#   detect-encoding.sh line-ending <file>            — LF/CRLF/CRを判定
#   detect-encoding.sh decodable <file> <encoding>   — 指定エンコーディングで復号できるか（0=可, 1=不可）
#   detect-encoding.sh to-utf8 <file> [出力先]        — UTF-8へ変換（出力先省略時は標準出力）
#   detect-encoding.sh --self-test
#
# 使い方（source される側。改善課題1-131）:
#   他スクリプトから `source ".../detect-encoding.sh"` すると、CLI ディスパッチ（--self-test・
#   サブコマンド分岐）は実行されず、関数 to_utf8_for_scan のみが呼び出し元シェルに追加される。
#   呼び出し元は原本ファイルを grep 等で走査する直前に次のように使う:
#     scan_file="$(to_utf8_for_scan "$src_file" "$SCAN_WORKDIR")"
#     grep ... "$scan_file"
#   $SCAN_WORKDIR は呼び出し元が mktemp -d で用意し、既存の trap ... EXIT に
#   rm -rf "$SCAN_WORKDIR" を畳み込んで使用後に削除すること（bash は EXIT trap を
#   上書きするため、新規に trap を追加すると既存の後始末が失われる）。
#
# 判定は推測ではなく実際の復号可否で行う。候補の順序は UTF-8 → EUC-JP → Shift_JIS → ISO-2022-JP とし、
# 最初に復号できたものを採用する（先勝ち。曖昧な場合の優先順位はこの並びに固定する）。
#
# 設計判断（ADR）:
#   必要性: 改善課題1-126・1-131・1-140が同一の「候補復号による決定的判定」を必要とする。
#   3箇所へ個別実装すると判定基準が分裂し、同じ原本に対して異なるエンコーディング名が記録されうる。
#   代替案を採用しなかった理由: `file --mime-encoding` はEUC-JPとShift_JISを判別できず`unknown-8bit`を
#   返す。Bashツール直叩きは3スキルから繰り返し呼ばれるため再現性を保てない。このリポジトリに
#   Makefile・package.jsonは存在しない。
#   保守責任者: 人手（ユーザー）。候補エンコーディングを追加する場合は本スクリプトの候補一覧のみを更新する。
#   廃棄条件: 対象リポジトリがUTF-8に統一され、非UTF-8原本を扱わなくなった時。
#
# macOS bash 3.2 互換（mapfile 不使用）。
#
# 実行 vs source の判定: BASH_SOURCE[0] と $0 が一致するのは直接実行時のみ。source された
# 場合は一致しないため、この分岐で set -e・python3 必須チェック・CLI ディスパッチを
# 呼び出し元シェルへ波及させない。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH" >&2
  if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    exit 1
  else
    return 1
  fi
fi

# ---------------------------------------------------------------------------
# Python本体。全サブコマンドをここに集約する。stdin/stdoutのencodingは
# 明示的にUTF-8へreconfigureし、実行環境のlocale（LC_ALL=C等）に依存しないようにする。
# ---------------------------------------------------------------------------
_PY_MAIN='
import sys

def _reconfig():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="surrogateescape")
        except Exception:
            pass

CANDIDATES = [
    ("utf-8", "UTF-8"),
    ("euc_jp", "EUC-JP"),
    ("shift_jis", "Shift_JIS"),
    ("iso2022_jp", "ISO-2022-JP"),
]

def _codec_for(name):
    for codec, label in CANDIDATES:
        if label == name:
            return codec
    return None

def _detect(raw):
    for codec, label in CANDIDATES:
        try:
            raw.decode(codec)
            return label
        except UnicodeDecodeError:
            continue
    return None

def cmd_encoding(argv):
    _reconfig()
    with open(argv[0], "rb") as fh:
        raw = fh.read()
    name = _detect(raw)
    if name is None:
        print("UNKNOWN")
        sys.exit(1)
    print(name)
    sys.exit(0)

def cmd_line_ending(argv):
    _reconfig()
    with open(argv[0], "rb") as fh:
        raw = fh.read()
    if b"\r\n" in raw:
        print("CRLF")
    elif b"\r" in raw:
        print("CR")
    else:
        print("LF")
    sys.exit(0)

def cmd_decodable(argv):
    codec = _codec_for(argv[1])
    if codec is None:
        sys.exit(1)
    with open(argv[0], "rb") as fh:
        raw = fh.read()
    try:
        raw.decode(codec)
        sys.exit(0)
    except UnicodeDecodeError:
        sys.exit(1)

def cmd_to_utf8(argv):
    _reconfig()
    with open(argv[0], "rb") as fh:
        raw = fh.read()
    name = _detect(raw)
    if name is None:
        sys.exit(1)
    text = raw.decode(_codec_for(name))
    if len(argv) > 1 and argv[1]:
        with open(argv[1], "w", encoding="utf-8", errors="surrogateescape", newline="") as out:
            out.write(text)
    else:
        sys.stdout.write(text)
    sys.exit(0)

_sub = sys.argv[1]
_argv = sys.argv[2:]
if _sub == "encoding":
    cmd_encoding(_argv)
elif _sub == "line-ending":
    cmd_line_ending(_argv)
elif _sub == "decodable":
    cmd_decodable(_argv)
elif _sub == "to-utf8":
    cmd_to_utf8(_argv)
else:
    sys.exit(2)
'

_run_py() {
  python3 -c "$_PY_MAIN" "$@"
}

# ---------------------------------------------------------------------------
# to_utf8_for_scan <file> <workdir>
#   走査スクリプト（extract/*.sh 等）が原本ファイルを grep 等で走査する直前に呼ぶヘルパー。
#   <file> が UTF-8 以外の判定可能なエンコーディング（EUC-JP/Shift_JIS/ISO-2022-JP）なら、
#   UTF-8 へ変換した一時コピーを <workdir> 内に作成し、そのパスを標準出力へ返す。
#   <file> が UTF-8、または候補復号できず判定不能（UNKNOWN）の場合は <file> をそのまま返す
#   （UNKNOWN は変換できないため、原本パスのまま渡してフォールバックさせる。呼び出し元は
#   このケースでも警告が出ないよう grep 呼び出し側で LC_ALL=C 等の対処を検討すること）。
#   常に exit 0（変換失敗時も原本パスを返してフォールバックさせるため、呼び出し元の
#   set -e を止めない）。<workdir> は呼び出し元が用意し、使用後に rm -rf すること。
# ---------------------------------------------------------------------------
to_utf8_for_scan() {
  local file="$1" workdir="$2"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    printf '%s' "$file"
    return 0
  fi
  local enc
  enc="$(_run_py encoding "$file" 2>/dev/null || true)"
  case "$enc" in
    UTF-8|UNKNOWN|"")
      printf '%s' "$file"
      ;;
    *)
      mkdir -p "$workdir" 2>/dev/null || true
      local key dest
      key="$(printf '%s' "$file" | cksum | awk '{print $1}')"
      dest="$workdir/scan-${key}.utf8"
      if _run_py to-utf8 "$file" "$dest" 2>/dev/null; then
        printf '%s' "$dest"
      else
        printf '%s' "$file"
      fi
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/detect-encoding-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  # --- 1. UTF-8/EUC-JP/Shift_JISの判定（EUC-JPとShift_JISを取り違えないこと） ---
  printf 'こんにちは、世界。UTF-8のテストです。\n' > "$tmp/utf8.txt"

  python3 -c "
import sys
sys.stdout.buffer.write('日本語のテストです。全角文字を含みます。\n'.encode('euc-jp'))
" > "$tmp/eucjp.txt"

  python3 -c "
import sys
sys.stdout.buffer.write('日本語のテストです。全角文字を含みます。\n'.encode('shift_jis'))
" > "$tmp/sjis.txt"

  got_utf8="$(_run_py encoding "$tmp/utf8.txt" 2>/dev/null || true)"
  if [ "$got_utf8" = "UTF-8" ]; then
    echo "  [PASS] encoding: UTF-8ファイルをUTF-8と判定"
  else
    echo "  [FAIL] encoding: UTF-8ファイルの判定結果が不正 (got=${got_utf8})" >&2
    rc=1
  fi

  got_euc="$(_run_py encoding "$tmp/eucjp.txt" 2>/dev/null || true)"
  if [ "$got_euc" = "EUC-JP" ]; then
    echo "  [PASS] encoding: EUC-JPファイルをEUC-JPと判定"
  else
    echo "  [FAIL] encoding: EUC-JPファイルの判定結果が不正 (got=${got_euc})" >&2
    rc=1
  fi

  got_sjis="$(_run_py encoding "$tmp/sjis.txt" 2>/dev/null || true)"
  if [ "$got_sjis" = "Shift_JIS" ]; then
    echo "  [PASS] encoding: Shift_JISファイルをShift_JISと判定"
  else
    echo "  [FAIL] encoding: Shift_JISファイルの判定結果が不正 (got=${got_sjis})" >&2
    rc=1
  fi

  # EUC-JPとShift_JISを取り違えていないことの直接証拠: Shift_JISのバイト列は
  # EUC-JPとしては復号できないはず（逆方向も同様）。この非対称性が崩れていれば
  # 判定順序（EUC-JPが先勝ち）だけで偶然一致した誤判定を見逃す。
  if _run_py decodable "$tmp/sjis.txt" EUC-JP >/dev/null 2>&1; then
    echo "  [FAIL] EUC-JP/Shift_JIS判別: Shift_JISのバイト列がEUC-JPとしても復号できてしまい取り違えを検出できない" >&2
    rc=1
  else
    echo "  [PASS] EUC-JP/Shift_JIS判別: Shift_JISのバイト列はEUC-JPとして復号不可（取り違え防止を確認）"
  fi
  if _run_py decodable "$tmp/eucjp.txt" Shift_JIS >/dev/null 2>&1; then
    echo "  [FAIL] EUC-JP/Shift_JIS判別: EUC-JPのバイト列がShift_JISとしても復号できてしまい取り違えを検出できない" >&2
    rc=1
  else
    echo "  [PASS] EUC-JP/Shift_JIS判別: EUC-JPのバイト列はShift_JISとして復号不可（取り違え防止を確認）"
  fi

  # --- 2. どの候補でも復号できないバイト列でUNKNOWN・exit 1 ---
  printf '\xff\xfe\x00\x01\xff\xff' > "$tmp/unknown.bin"
  unknown_out="$(_run_py encoding "$tmp/unknown.bin" 2>/dev/null || true)"
  if _run_py encoding "$tmp/unknown.bin" >/dev/null 2>&1; then
    echo "  [FAIL] encoding: 復号不能バイト列がexit 0になった" >&2
    rc=1
  elif [ "$unknown_out" = "UNKNOWN" ]; then
    echo "  [PASS] encoding: 復号不能バイト列でUNKNOWN・exit 1"
  else
    echo "  [FAIL] encoding: 復号不能バイト列の出力が不正 (got=${unknown_out})" >&2
    rc=1
  fi

  # --- 3. line-ending判定 ---
  printf 'line1\nline2\n' > "$tmp/lf.txt"
  printf 'line1\r\nline2\r\n' > "$tmp/crlf.txt"
  printf 'line1\rline2\r' > "$tmp/cr.txt"

  got_lf="$(_run_py line-ending "$tmp/lf.txt")"
  got_crlf="$(_run_py line-ending "$tmp/crlf.txt")"
  got_cr="$(_run_py line-ending "$tmp/cr.txt")"

  if [ "$got_lf" = "LF" ]; then
    echo "  [PASS] line-ending: LF判定"
  else
    echo "  [FAIL] line-ending: LF判定が不正 (got=${got_lf})" >&2
    rc=1
  fi
  if [ "$got_crlf" = "CRLF" ]; then
    echo "  [PASS] line-ending: CRLF判定"
  else
    echo "  [FAIL] line-ending: CRLF判定が不正 (got=${got_crlf})" >&2
    rc=1
  fi
  if [ "$got_cr" = "CR" ]; then
    echo "  [PASS] line-ending: CR判定"
  else
    echo "  [FAIL] line-ending: CR判定が不正 (got=${got_cr})" >&2
    rc=1
  fi

  # --- 4. to-utf8で変換後の内容が元の文字列と一致する ---
  # 比較は文字列読み込みで行う（diff + プロセス置換の組はサンドボックス環境で
  # /dev/fd 経由のfd読み取りがOperation not permittedになる既知の制約があるため避ける）。
  expected_text='日本語のテストです。全角文字を含みます。'

  _run_py to-utf8 "$tmp/eucjp.txt" "$tmp/eucjp.converted.utf8.txt"
  converted_euc="$(cat "$tmp/eucjp.converted.utf8.txt")"
  if [ "$converted_euc" = "$expected_text" ]; then
    echo "  [PASS] to-utf8: EUC-JP→UTF-8変換後の内容が元の文字列と一致"
  else
    echo "  [FAIL] to-utf8: EUC-JP→UTF-8変換後の内容が元の文字列と不一致" >&2
    rc=1
  fi

  _run_py to-utf8 "$tmp/sjis.txt" "$tmp/sjis.converted.utf8.txt"
  converted_sjis="$(cat "$tmp/sjis.converted.utf8.txt")"
  if [ "$converted_sjis" = "$expected_text" ]; then
    echo "  [PASS] to-utf8: Shift_JIS→UTF-8変換後の内容が元の文字列と一致"
  else
    echo "  [FAIL] to-utf8: Shift_JIS→UTF-8変換後の内容が元の文字列と不一致" >&2
    rc=1
  fi

  # to-utf8: 出力先省略時は標準出力へ変換内容を書く
  stdout_converted="$(_run_py to-utf8 "$tmp/eucjp.txt")"
  if [ "$stdout_converted" = "日本語のテストです。全角文字を含みます。" ]; then
    echo "  [PASS] to-utf8: 出力先省略時に標準出力へ変換内容を書く"
  else
    echo "  [FAIL] to-utf8: 標準出力への変換内容が不正" >&2
    rc=1
  fi

  # to-utf8: 元のエンコーディングを判定できない場合はexit 1
  if _run_py to-utf8 "$tmp/unknown.bin" >/dev/null 2>&1; then
    echo "  [FAIL] to-utf8: 判定不能バイト列でexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] to-utf8: 判定不能バイト列でexit 1"
  fi

  # --- decodableの陽性・陰性 ---
  if _run_py decodable "$tmp/utf8.txt" UTF-8 >/dev/null 2>&1; then
    echo "  [PASS] decodable: UTF-8ファイルはUTF-8として復号可"
  else
    echo "  [FAIL] decodable: UTF-8ファイルがUTF-8として復号不可と判定された" >&2
    rc=1
  fi

  # --- to_utf8_for_scan: 走査ヘルパー（改善課題1-131） ---
  scan_workdir="$tmp/scan-workdir"
  scan_path_euc="$(to_utf8_for_scan "$tmp/eucjp.txt" "$scan_workdir")"
  if [ -f "$scan_path_euc" ] && [ "$scan_path_euc" != "$tmp/eucjp.txt" ] \
    && [ "$(cat "$scan_path_euc")" = "$expected_text" ]; then
    echo "  [PASS] to_utf8_for_scan: EUC-JPファイルをUTF-8一時コピーへ変換して返す"
  else
    echo "  [FAIL] to_utf8_for_scan: EUC-JPファイルの変換結果が不正 (got=${scan_path_euc})" >&2
    rc=1
  fi

  scan_path_utf8="$(to_utf8_for_scan "$tmp/utf8.txt" "$scan_workdir")"
  if [ "$scan_path_utf8" = "$tmp/utf8.txt" ]; then
    echo "  [PASS] to_utf8_for_scan: UTF-8ファイルは原本パスをそのまま返す"
  else
    echo "  [FAIL] to_utf8_for_scan: UTF-8ファイルなのに変換コピーへ差し替えられた" >&2
    rc=1
  fi

  scan_path_unknown="$(to_utf8_for_scan "$tmp/unknown.bin" "$scan_workdir")"
  if [ "$scan_path_unknown" = "$tmp/unknown.bin" ]; then
    echo "  [PASS] to_utf8_for_scan: 判定不能バイト列は原本パスをそのまま返す（フォールバック）"
  else
    echo "  [FAIL] to_utf8_for_scan: 判定不能バイト列の戻り値が不正 (got=${scan_path_unknown})" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# CLI ディスパッチ（--self-test・サブコマンド分岐）は直接実行時のみ走らせる。
# source された場合はここで抜け、呼び出し元シェルには関数（_run_py・to_utf8_for_scan等）
# だけが残る。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  sub="${1:-}"
  case "$sub" in
    encoding|to-utf8)
      file="${2:?使い方: detect-encoding.sh $sub <file> [出力先]}"
      if [ ! -f "$file" ]; then
        echo "ERROR: file not found: $file" >&2
        exit 2
      fi
      _run_py "$@"
      ;;
    line-ending)
      file="${2:?使い方: detect-encoding.sh line-ending <file>}"
      if [ ! -f "$file" ]; then
        echo "ERROR: file not found: $file" >&2
        exit 2
      fi
      _run_py "$@"
      ;;
    decodable)
      file="${2:?使い方: detect-encoding.sh decodable <file> <encoding>}"
      enc="${3:?使い方: detect-encoding.sh decodable <file> <encoding>}"
      if [ ! -f "$file" ]; then
        echo "ERROR: file not found: $file" >&2
        exit 2
      fi
      _run_py "$@"
      ;;
    *)
      echo "使い方: detect-encoding.sh {encoding|line-ending|decodable|to-utf8} <file> [args...]" >&2
      echo "        detect-encoding.sh --self-test" >&2
      exit 1
      ;;
  esac
fi
