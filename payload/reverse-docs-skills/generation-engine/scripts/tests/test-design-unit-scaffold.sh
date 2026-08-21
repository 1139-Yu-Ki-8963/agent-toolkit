#!/usr/bin/env bash
# scaffold-design-unit.sh の黒箱テスト。
set -euo pipefail

# 第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）は、
# 本文に "--self-test)" を持つ .sh を対象として集める。このスクリプトは引数を取らず、
# 実行そのものが検査になる形のため、引数を見る分岐が無く集約から漏れていた。集約に
# 拾わせるための受け口であり、渡されても渡されなくても動きは変わらない。この分岐を
# 消すと集約から外れ、この検査は二度と走らなくなる。
case "${1:-}" in --self-test) ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCAFFOLD="$REPO_ROOT/generation-engine/scripts/scaffold-design-unit.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-scaffold-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# 1. 5種別×2phaseの展開が成功する
docs1="$tmp/docs1"
mkdir -p "$docs1"
for kind in api table batch report external; do
  for phase in basic detail; do
    bash "$SCAFFOLD" "$kind" "$phase" "$docs1" "case-${kind}" "ケース${kind}" >/dev/null \
      || { echo "FAIL: 展開に失敗しました: $kind $phase" >&2; exit 1; }
  done
done
echo "PASS: 5種別×2phaseの展開が成功"

# テンプレートの未置換の欄を検知できるようにする指示書: scaffold-design-unit.shの
# --verifyへ新設した全大文字トークン検査により、判定材料欄等(scaffold自体が
# 置換しない欄)が未記入のままだと不合格になる。ここでは展開処理自体の正常動作を
# 検証したいだけなので、frontmatter内の未置換欄をダミー値で機械的に埋める。
for kind in api table batch report external; do
  for phase in basic detail; do
    case "$kind" in
      api) kind_dir_fill="apis" ;;
      table) kind_dir_fill="tables" ;;
      batch) kind_dir_fill="batches" ;;
      report) kind_dir_fill="reports" ;;
      external) kind_dir_fill="externals" ;;
    esac
    case "$phase" in
      basic) phase_dir_jp_fill="基本設計" ;;
      detail) phase_dir_jp_fill="詳細設計" ;;
    esac
    unit_dir_fill="$docs1/docs/design/${kind_dir_fill}/${kind}-case-${kind}/${phase_dir_jp_fill}"
    while IFS= read -r fill_file; do
      [ -z "$fill_file" ] && continue
      sed -i.bak -E 's/^([a-z_]+): [A-Z]{2,}$/\1: dummy-value/' "$fill_file"
      rm -f "${fill_file}.bak"
    done < <(find "$unit_dir_fill" -name '*.md' -type f)
  done
done

# 2. --verify が成功する
for kind in api table batch report external; do
  for phase in basic detail; do
    bash "$SCAFFOLD" --verify "$kind" "$phase" "$docs1" "case-${kind}" >/dev/null \
      || { echo "FAIL: verifyに失敗しました: $kind $phase" >&2; exit 1; }
  done
done
echo "PASS: --verify が全件成功"

# 3. --dry-run が何も書かない
docs3="$tmp/docs3"
mkdir -p "$docs3"
before="$(find "$docs3" | sort)"
bash "$SCAFFOLD" --dry-run api basic "$docs3" dryrun-case "ドライラン" >/dev/null \
  || { echo "FAIL: --dry-run 自体が異常終了しました" >&2; exit 1; }
after="$(find "$docs3" | sort)"
if [ "$before" != "$after" ]; then
  echo "FAIL: --dry-run がファイルを書き込みました" >&2
  exit 1
fi
if [ -d "$docs3/docs/design/apis" ]; then
  echo "FAIL: --dry-run が出力ディレクトリを作成しました" >&2
  exit 1
fi
echo "PASS: --dry-run は何も書かない"

# 4. symlink を含む出力先が拒否される
docs4="$tmp/docs4"
external4="$tmp/external4-target"
mkdir -p "$docs4/docs/design" "$external4"
ln -s "$external4" "$docs4/docs/design/apis"
if bash "$SCAFFOLD" api basic "$docs4" symlink-case "シムリンク" >/dev/null 2>&1; then
  echo "FAIL: symlinkを含む出力先を受理しました" >&2
  exit 1
fi
if [ -e "$external4/api-symlink-case" ]; then
  echo "FAIL: symlink経由で外部treeへ書き込みました" >&2
  exit 1
fi
echo "PASS: symlinkを含む出力先を拒否"

# 5. 同じ phase の通常再実行は既存ファイルを上書きしない
docs5="$tmp/docs5"
mkdir -p "$docs5"
# 実装判断: 以前はここで basic フェーズの配下に API単体テスト設計書.md を
#   置いて非上書きを検証していたが、同ファイルは test フェーズの宣言であり
#   basic フェーズの scaffold はそれを触る経路を持たない。テスト自身が
#   作ったファイルが消えないことを見ているだけで、検証になっていなかった。
#   2026-08-21 に実測して判明。basic と test の両フェーズを展開し、
#   それぞれの宣言ファイルを対象にする形へ改めた。
bash "$SCAFFOLD" api basic "$docs5" repeat-case "リピート" >/dev/null
bash "$SCAFFOLD" api test "$docs5" repeat-case "リピート" >/dev/null
target5_basic="$docs5/docs/design/apis/api-repeat-case/基本設計/API基本設計書.md"
target5_test="$docs5/docs/design/apis/api-repeat-case/テスト設計/APIテスト設計書.md"
target5_unit="$docs5/docs/design/apis/api-repeat-case/テスト設計/API単体テスト設計書.md"
printf '\n基本設計を保持するmarker\n' >> "$target5_basic"
printf '\nテスト設計を保持するmarker\n' >> "$target5_test"
printf '\n単体テスト設計を保持するmarker\n' >> "$target5_unit"
checksum5_basic_before="$(cksum "$target5_basic")"
checksum5_test_before="$(cksum "$target5_test")"
checksum5_unit_before="$(cksum "$target5_unit")"
if ! bash "$SCAFFOLD" api basic "$docs5" repeat-case "リピート再実行" >/dev/null 2>&1; then
  echo "FAIL: 同じphaseの通常再実行が異常終了しました" >&2
  exit 1
fi
if ! bash "$SCAFFOLD" api test "$docs5" repeat-case "リピート再実行" >/dev/null 2>&1; then
  echo "FAIL: testフェーズの通常再実行が異常終了しました" >&2
  exit 1
fi
checksum5_basic_after="$(cksum "$target5_basic")"
checksum5_test_after="$(cksum "$target5_test")"
checksum5_unit_after="$(cksum "$target5_unit")"
if [ "$checksum5_basic_before" != "$checksum5_basic_after" ] \
   || [ "$checksum5_test_before" != "$checksum5_test_after" ] \
   || [ "$checksum5_unit_before" != "$checksum5_unit_after" ] \
   || ! grep -q '基本設計を保持するmarker' "$target5_basic" \
   || ! grep -q 'テスト設計を保持するmarker' "$target5_test" \
   || ! grep -q '単体テスト設計を保持するmarker' "$target5_unit"; then
  echo "FAIL: 同じphaseの通常再実行が既存ファイルを上書きしました" >&2
  exit 1
fi
echo "PASS: 同じphaseの通常再実行は全宣言ファイルを保持"

# 6. basic の実行後に detail を実行しても basic が上書きされない
docs6="$tmp/docs6"
mkdir -p "$docs6"
bash "$SCAFFOLD" api basic "$docs6" order-case "オーダー基本" >/dev/null
basic_before="$(cat "$docs6/docs/design/apis/api-order-case/基本設計/API基本設計書.md")"
bash "$SCAFFOLD" api detail "$docs6" order-case "オーダー詳細" >/dev/null
basic_after="$(cat "$docs6/docs/design/apis/api-order-case/基本設計/API基本設計書.md")"
if [ "$basic_before" != "$basic_after" ]; then
  echo "FAIL: detail展開でbasicが上書きされました" >&2
  exit 1
fi
if [ ! -f "$docs6/docs/design/apis/api-order-case/詳細設計/API詳細設計書.md" ]; then
  echo "FAIL: detail展開が行われませんでした" >&2
  exit 1
fi
echo "PASS: basic実行後のdetail実行でbasicが保持される"

# 7. 未置換のトークンが検出される
docs7="$tmp/docs7"
mkdir -p "$docs7"
bash "$SCAFFOLD" api basic "$docs7" token-case "トークン確認" >/dev/null
printf '<API名>\n' >> "$docs7/docs/design/apis/api-token-case/基本設計/API基本設計書.md"
if bash "$SCAFFOLD" --verify api basic "$docs7" token-case >/dev/null 2>&1; then
  echo "FAIL: 未置換トークンが残っているのにverifyが成功しました" >&2
  exit 1
fi
echo "PASS: 未置換トークンをverifyが検出"

# 8. 章の欠落が検出される
docs8="$tmp/docs8"
mkdir -p "$docs8"
bash "$SCAFFOLD" api basic "$docs8" heading-case "見出し確認" >/dev/null
target8="$docs8/docs/design/apis/api-heading-case/基本設計/API基本設計書.md"
grep -v '^## §1 外部仕様$' "$target8" > "$target8.tmp"
mv "$target8.tmp" "$target8"
if bash "$SCAFFOLD" --verify api basic "$docs8" heading-case >/dev/null 2>&1; then
  echo "FAIL: 見出し欠落があるのにverifyが成功しました" >&2
  exit 1
fi
echo "PASS: 見出しの欠落をverifyが検出"

# 9. 未置換の全大文字トークンが1つ残っていると不合格になる
docs9="$tmp/docs9"
mkdir -p "$docs9"
bash "$SCAFFOLD" table detail "$docs9" allcaps-case "全大文字確認" >/dev/null
target9="$docs9/docs/design/tables/table-allcaps-case/詳細設計/テーブル定義書.md"
# table_subkind以外の全大文字トークンをダミー値で埋め、table_subkindだけ未置換のまま残す
sed -i.bak -E 's/^(table_key|table_id|table_name|source_ref): [A-Z]{2,}$/\1: dummy-value/' "$target9"
rm -f "${target9}.bak"
if bash "$SCAFFOLD" --verify table detail "$docs9" allcaps-case >/dev/null 2>&1; then
  echo "FAIL: 未置換-全大文字トークン: table_subkindが未置換のままverifyが成功しました" >&2
  exit 1
fi
echo "PASS: 未置換-全大文字トークン"

# 10. すべて置換した合成データはverifyが合格する
docs10="$tmp/docs10"
mkdir -p "$docs10"
bash "$SCAFFOLD" table detail "$docs10" allcaps-ok-case "全大文字確認済み" >/dev/null
target10="$docs10/docs/design/tables/table-allcaps-ok-case/詳細設計/テーブル定義書.md"
sed -i.bak -E 's/^([a-z_]+): [A-Z]{2,}$/\1: dummy-value/' "$target10"
rm -f "${target10}.bak"
if ! bash "$SCAFFOLD" --verify table detail "$docs10" allcaps-ok-case >/dev/null 2>&1; then
  echo "FAIL: 置換済み-全大文字トークンなし: すべて置換したのにverifyが失敗しました" >&2
  exit 1
fi
echo "PASS: 置換済み-全大文字トークンなし"

# 11. 宣言ファイル自身のsymlinkは通常実行・上書き・dry-run・不足検査で拒否される
docs11="$tmp/docs11"
external11="$tmp/external11-target"
mkdir -p "$docs11" "$external11"
bash "$SCAFFOLD" api basic "$docs11" file-symlink-case "ファイルリンク" >/dev/null
target11="$docs11/docs/design/apis/api-file-symlink-case/基本設計/API基本設計書.md"
rm -f "$target11"
ln -s "$external11" "$target11"
if bash "$SCAFFOLD" api basic "$docs11" file-symlink-case "通常リンク拒否" >/dev/null 2>&1; then
  echo "FAIL: 通常実行が宣言ファイルのsymlinkを受理しました" >&2
  exit 1
fi
if bash "$SCAFFOLD" --overwrite api basic "$docs11" file-symlink-case "上書きリンク拒否" >/dev/null 2>&1; then
  echo "FAIL: --overwriteが宣言ファイルのsymlinkを受理しました" >&2
  exit 1
fi
dryrun11_out="$(bash "$SCAFFOLD" --dry-run api basic "$docs11" file-symlink-case \
  "ドライランリンク拒否" 2>&1)" && dryrun11_rc=0 || dryrun11_rc=$?
if [ "$dryrun11_rc" -eq 0 ] \
   || printf '%s\n' "$dryrun11_out" | grep -q 'コピー元テンプレート: .*API基本設計書.md'; then
  echo "FAIL: --dry-runが宣言ファイルのsymlinkを拒否せずコピー予定を列挙しました" >&2
  exit 1
fi
if find "$external11" -mindepth 1 -print -quit | grep -q .; then
  echo "FAIL: 宣言ファイルのsymlink経由で外部treeへ書き込みました" >&2
  exit 1
fi
missing11_out="$(bash "$SCAFFOLD" --check-missing api basic "$docs11" file-symlink-case 2>&1)" \
  && missing11_rc=0 || missing11_rc=$?
if [ "$missing11_rc" -eq 0 ] || ! printf '%s\n' "$missing11_out" | grep -q 'API基本設計書.md'; then
  echo "FAIL: --check-missingが宣言ファイルのsymlinkを不足として報告しませんでした" >&2
  exit 1
fi
echo "PASS: 宣言ファイル自身のsymlinkを全書込モードで拒否し不足として報告"

# 12. 既存phaseのdry-runは不足宣言ファイルだけを列挙する
docs12="$tmp/docs12"
mkdir -p "$docs12"
bash "$SCAFFOLD" api test "$docs12" dryrun-existing-case "既存ドライラン" >/dev/null
rm -f "$docs12/docs/design/apis/api-dryrun-existing-case/テスト設計/API単体テスト設計書.md"
dryrun12_out="$(bash "$SCAFFOLD" --dry-run api test "$docs12" dryrun-existing-case "既存ドライラン")"
if ! printf '%s\n' "$dryrun12_out" | grep -q 'コピー元テンプレート: .*API単体テスト設計書.md' \
   || printf '%s\n' "$dryrun12_out" | grep -q 'コピー元テンプレート: .*/APIテスト設計書.md'; then
  echo "FAIL: 既存phaseの--dry-runが不足ファイルだけを列挙しませんでした" >&2
  exit 1
fi
echo "PASS: 既存phaseの--dry-runは不足宣言ファイルだけを列挙"

# 13. --check-missingはテンプレート不要・書き込みなしで不足を列挙する
docs13="$tmp/docs13"
mkdir -p "$docs13"
before13="$(find "$docs13" | sort)"
missing13_out="$(bash "$SCAFFOLD" --check-missing api test "$docs13" no-template-case \
  "テンプレート不要" "$tmp/存在しないテンプレート" 2>&1)" && missing13_rc=0 || missing13_rc=$?
after13="$(find "$docs13" | sort)"
missing13_test_count="$(printf '%s\n' "$missing13_out" | grep -c '^不足: .*/APIテスト設計書.md$' || true)"
missing13_unit_count="$(printf '%s\n' "$missing13_out" | grep -c '^不足: .*API単体テスト設計書.md$' || true)"
missing13_line_count="$(printf '%s\n' "$missing13_out" | grep -c '^不足: ' || true)"
if [ "$missing13_rc" -eq 0 ] \
   || [ "$missing13_test_count" -ne 1 ] \
   || [ "$missing13_unit_count" -ne 1 ] \
   || [ "$missing13_line_count" -ne 2 ] \
   || printf '%s\n' "$missing13_out" | grep -q 'テンプレートディレクトリが見つかりません' \
   || [ "$before13" != "$after13" ]; then
  echo "FAIL: --check-missingの複数不足全件列挙・テンプレート不要・書き込みなし契約" >&2
  exit 1
fi
echo "PASS: --check-missingはテンプレート不要・書き込みなしで複数不足を全件列挙"

# 14. --overwriteはphase内の未宣言ファイルを変更しない
docs14="$tmp/docs14"
mkdir -p "$docs14"
bash "$SCAFFOLD" api basic "$docs14" overwrite-scope-case "上書き範囲" >/dev/null
custom14="$docs14/docs/design/apis/api-overwrite-scope-case/基本設計/CUSTOM.md"
printf '未宣言sentinelは保持する\n' > "$custom14"
checksum14_before="$(cksum "$custom14")"
bash "$SCAFFOLD" --overwrite api basic "$docs14" overwrite-scope-case "上書き範囲" >/dev/null
checksum14_after="$(cksum "$custom14")"
if [ "$checksum14_before" != "$checksum14_after" ] \
   || ! grep -q '^未宣言sentinelは保持する$' "$custom14"; then
  echo "FAIL: --overwriteが未宣言ファイルを変更しました" >&2
  exit 1
fi
echo "PASS: --overwriteは未宣言ファイルを保持"

# 15. 宣言ファイルと同名のディレクトリは通常実行・上書きとも拒否する
docs15="$tmp/docs15"
mkdir -p "$docs15"
bash "$SCAFFOLD" api basic "$docs15" directory-boundary-case "同名ディレクトリ" >/dev/null
target15="$docs15/docs/design/apis/api-directory-boundary-case/基本設計/API基本設計書.md"
rm -f "$target15"
mkdir -p "$target15"
if bash "$SCAFFOLD" api basic "$docs15" directory-boundary-case "通常ディレクトリ拒否" >/dev/null 2>&1; then
  echo "FAIL: 通常実行が宣言ファイルと同名のディレクトリを受理しました" >&2
  exit 1
fi
if bash "$SCAFFOLD" --overwrite api basic "$docs15" directory-boundary-case "上書きディレクトリ拒否" >/dev/null 2>&1; then
  echo "FAIL: --overwriteが宣言ファイルと同名のディレクトリを受理しました" >&2
  exit 1
fi
dryrun15_out="$(bash "$SCAFFOLD" --dry-run api basic "$docs15" directory-boundary-case \
  "ドライランディレクトリ拒否" 2>&1)" && dryrun15_rc=0 || dryrun15_rc=$?
if [ "$dryrun15_rc" -eq 0 ] \
   || printf '%s\n' "$dryrun15_out" | grep -q 'コピー元テンプレート: .*API基本設計書.md'; then
  echo "FAIL: --dry-runが宣言ファイルと同名のディレクトリを拒否せずコピー予定を列挙しました" >&2
  exit 1
fi
if find "$target15" -mindepth 1 -print -quit | grep -q .; then
  echo "FAIL: 宣言ファイルと同名のディレクトリ配下へ書き込みました" >&2
  exit 1
fi
echo "PASS: 宣言ファイルと同名のディレクトリを全書込モードで拒否"

# 16. phase名と同名の通常ファイルは通常実行・dry-runとも拒否する
docs16="$tmp/docs16"
mkdir -p "$docs16"
bash "$SCAFFOLD" api detail "$docs16" phase-file-case "phase通常ファイル" >/dev/null
unit16="$docs16/docs/design/apis/api-phase-file-case"
phase16="$unit16/基本設計"
printf 'phaseパスsentinel\n' > "$phase16"
snapshot16_before="$(find "$unit16" -type d -print | sort; find "$unit16" -type f -exec cksum {} + | sort)"
if bash "$SCAFFOLD" api basic "$docs16" phase-file-case "通常phase拒否" >/dev/null 2>&1; then
  echo "FAIL: 通常実行が通常ファイルのphaseパスを受理しました" >&2
  exit 1
fi
dryrun16_out="$(bash "$SCAFFOLD" --dry-run api basic "$docs16" phase-file-case \
  "ドライランphase拒否" 2>&1)" && dryrun16_rc=0 || dryrun16_rc=$?
if [ "$dryrun16_rc" -eq 0 ] || printf '%s\n' "$dryrun16_out" | grep -q 'コピー元テンプレート:'; then
  echo "FAIL: --dry-runが通常ファイルのphaseパスを拒否せずコピー予定を列挙しました" >&2
  exit 1
fi
snapshot16_after="$(find "$unit16" -type d -print | sort; find "$unit16" -type f -exec cksum {} + | sort)"
if [ "$snapshot16_before" != "$snapshot16_after" ] \
   || ! grep -q '^phaseパスsentinel$' "$phase16"; then
  echo "FAIL: 通常ファイルのphaseパス境界でunit配下へ書き込みました" >&2
  exit 1
fi
echo "PASS: 通常ファイルのphaseパスを拒否してunit配下を保持"

echo "PASS: test-design-unit-scaffold.sh 全16項目"
