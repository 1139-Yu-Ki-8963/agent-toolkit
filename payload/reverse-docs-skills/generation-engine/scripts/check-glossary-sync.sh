#!/usr/bin/env bash
set -euo pipefail

# check-glossary-sync.sh — docs/guides/用語集.md とガイドHTML用語パネルの同期を検査する
#
# 使い方:
#   check-glossary-sync.sh <repo_root> [--list-unregistered]
#   check-glossary-sync.sh --self-test
#
# 検査1: .claude/skills/*/references/guide.html の「用語」節（<span class="sec-num">§N</span>用語
#         という見出しを持つ section）から抽出した用語が docs/guides/用語集.md に登録されているか。
#         用語パネルの実装は <dt>/<dd> 対（dl.def または div.def）と、
#         <table><tr><th>用語</th><th>意味</th></tr>...<tr><td>用語</td><td>意味</td></tr>...</table>
#         の2形式が実在する（22ガイド中20件がdt/dd、2件がtable）。両方を検査対象にする。
# 検査2: 用語集とガイドの両方に登録済みの用語について、説明が実質的に食い違っていないかを検査する。
#         完全一致は求めず、用語集側の説明から抽出した内容語（漢字2文字以上の連続・カタカナ2文字以上の
#         連続・英数字識別子2文字以上のいずれか）が1つでもガイド側の説明に部分一致すれば整合とみなす。
#         ひらがなの助詞・助動詞は抽出対象に含まれないため、機能語の混入は構造的に避けられる。
# 検査3（不合格対象外・情報のみ）: 用語集にあるがどのガイドの全文にも現れない語を報告する。
#         終了コードに影響しない。
#
# 除外（用語集への登録対象としない <dt> テキスト）:
#   次の3種は「語」ではなくファイル名・設定の鍵の名前・プレースホルダそのものであり、
#   用語集へ載せる対象ではない（用語集とガイドの食い違いを解消する指示書 §「やること」2 の目安に基づく）。
#   この除外は検査1（未登録判定）の対象からのみ除外し、検査2（食い違い判定）には影響しない。
#   すでに用語集へ登録済みの語（facts・manifest・symlink・worktree 等の英字小文字語）が
#   誤って除外され食い違い検査を素通りしないよう、除外判定は「未登録の語」にのみ適用する。
#     (a) ファイル名: 拡張子（yml/yaml/json/md/html/sh/cjs/mjs）で終わる英数字トークン。
#         末尾に「（注記）」を伴う場合（例: config.yml（スキルフォルダ直下））も対象。
#         例: facts.yml・page-data.json・env-config.json
#     (b) 設定の鍵の名前: 区切り記号（空白・/・=・*・_・-・／・・）を除去すると
#         英数字のみになり、かつ日本語文字（漢字・かな）を含まないトークン。
#         例: nodes・unresolved・prerequisites / steps / allocations・mode=append
#         ただし drvfs のような英字だけの略語で意味を持つ語は対象外（手動判断が必要なため、
#         用語集で個別に定義する）。drvfs は本ルールに一致するが、意味不透明な略語を
#         無断使用しない規約（略語制限）に照らし手動で用語集へ登録済みであるため実害はない。
#     (c) 山括弧のプレースホルダ: `<system>`・`<scope>` のように全体が `<...>` の形の語。
#
# 終了コード: 0=検査1・検査2とも0件 / 1=いずれかに不一致 / 2=前提不足（用語集が無い等）
#
# 設計判断（ADR）は .claude/rules/scoped/portal/page-conventions/rule.md の
# 「設計判断」節 > check-glossary-sync.sh を参照。

if [ "${1:-}" = "--self-test" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required but not found in PATH" >&2
    exit 1
  fi

  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-sync-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT
  SELF="${BASH_SOURCE[0]}"

  pass=0 fail=0

  make_guide() {
    # $1=case_dir $2=skill名 $3=dt/dd or table本文
    local dir="$1" skill="$2" body="$3"
    mkdir -p "${dir}/.claude/skills/${skill}/references"
    cat > "${dir}/.claude/skills/${skill}/references/guide.html" <<HTML
<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8"><title>${skill}</title></head>
<body>
<section id="s3">
  <h2><span class="sec-num">§3</span>用語</h2>
${body}
</section>
</body></html>
HTML
  }

  # --- ケース1: すべて登録済みで一致している状態 ---
  c1="${tmp}/case1"
  mkdir -p "${c1}/docs/guides"
  cat > "${c1}/docs/guides/用語集.md" <<'MD'
# 用語集

| 語 | 種別 | 1 行定義 |
|---|---|---|
| facts | ドメイン用語（このツール固有） | 原本コードから抽出した宣言的契約の事実表 |
MD
  make_guide "$c1" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>原本コードから抽出した宣言的契約の事実表を指す。</dd>
  </dl>'
  if bash "$SELF" "$c1" >/dev/null 2>&1; then
    echo "PASS: ケース1（すべて登録済み・一致）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: ケース1で終了コード0になるべき"; fail=$((fail + 1))
  fi

  # --- ケース2: 未登録の用語があるとき検査1で不合格 ---
  c2="${tmp}/case2"
  mkdir -p "${c2}/docs/guides"
  cat > "${c2}/docs/guides/用語集.md" <<'MD'
# 用語集

| 語 | 種別 | 1 行定義 |
|---|---|---|
| facts | ドメイン用語（このツール固有） | 原本コードから抽出した宣言的契約の事実表 |
MD
  make_guide "$c2" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>原本コードから抽出した宣言的契約の事実表を指す。</dd>
    <dt>未登録語ゼータ</dt>
    <dd>用語集に存在しない造語。</dd>
  </dl>'
  out2="$(bash "$SELF" "$c2" 2>&1)" && rc2=0 || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q "未登録語ゼータ"; then
    echo "PASS: ケース2（未登録の用語）で終了コード1・該当語を報告"; pass=$((pass + 1))
  else
    echo "FAIL: ケース2で終了コード1・未登録語ゼータの報告が必要 (rc=$rc2)"; fail=$((fail + 1))
  fi
  out2list="$(bash "$SELF" "$c2" --list-unregistered 2>&1 || true)"
  if [ "$out2list" = "未登録語ゼータ" ]; then
    echo "PASS: --list-unregistered が未登録語のみを1行1語で出力"; pass=$((pass + 1))
  else
    echo "FAIL: --list-unregistered の出力が想定と不一致: ${out2list}"; fail=$((fail + 1))
  fi

  # --- ケース3: 説明が食い違うとき検査2で不合格 ---
  c3="${tmp}/case3"
  mkdir -p "${c3}/docs/guides"
  cat > "${c3}/docs/guides/用語集.md" <<'MD'
# 用語集

| 語 | 種別 | 1 行定義 |
|---|---|---|
| facts | ドメイン用語（このツール固有） | 原本コードから抽出した宣言的契約の事実表 |
MD
  make_guide "$c3" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>ユーザーへ提示する完了報告のひな型。</dd>
  </dl>'
  out3="$(bash "$SELF" "$c3" 2>&1)" && rc3=0 || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q "食い違い"; then
    echo "PASS: ケース3（説明の食い違い）で終了コード1"; pass=$((pass + 1))
  else
    echo "FAIL: ケース3で終了コード1・食い違い報告が必要 (rc=$rc3)"; fail=$((fail + 1))
  fi

  # --- ケース4: 使われていない語があっても終了コードに影響しない ---
  c4="${tmp}/case4"
  mkdir -p "${c4}/docs/guides"
  cat > "${c4}/docs/guides/用語集.md" <<'MD'
# 用語集

| 語 | 種別 | 1 行定義 |
|---|---|---|
| facts | ドメイン用語（このツール固有） | 原本コードから抽出した宣言的契約の事実表 |
| 未使用語 | ドメイン用語（このツール固有） | どのガイドにも現れない語の見本 |
MD
  make_guide "$c4" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>原本コードから抽出した宣言的契約の事実表を指す。</dd>
  </dl>'
  out4="$(bash "$SELF" "$c4" 2>&1)" && rc4=0 || rc4=$?
  if [ "$rc4" -eq 0 ] && printf '%s' "$out4" | grep -q "未使用語"; then
    echo "PASS: ケース4（未使用語は報告されるが終了コード0）"; pass=$((pass + 1))
  else
    echo "FAIL: ケース4で終了コード0・未使用語の報告が必要 (rc=$rc4)"; fail=$((fail + 1))
  fi

  # --- ケース6: ファイル名・設定の鍵の名前は未登録判定から除外される。
  #     ただし登録済みの英字語（facts）は除外規則に一致しても食い違い検査は素通りしない ---
  c6="${tmp}/case6"
  mkdir -p "${c6}/docs/guides"
  cat > "${c6}/docs/guides/用語集.md" <<'MD'
# 用語集

| 語 | 種別 | 1 行定義 |
|---|---|---|
| facts | ドメイン用語（このツール固有） | 原本コードから抽出した宣言的契約の事実表 |
MD
  make_guide "$c6" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>ユーザーへ提示する完了報告のひな型。</dd>
    <dt>page-data.json</dt>
    <dd>設定の鍵の名前そのものであり、語ではない。</dd>
    <dt>nodes</dt>
    <dd>設定の鍵の名前そのものであり、語ではない。</dd>
  </dl>'
  out6="$(bash "$SELF" "$c6" 2>&1)" && rc6=0 || rc6=$?
  if [ "$rc6" -eq 1 ] \
    && printf '%s' "$out6" | grep -q "食い違い" \
    && ! printf '%s' "$out6" | grep -q "page-data.json" \
    && ! printf '%s' "$out6" | grep -q "^用語: nodes "; then
    echo "PASS: ケース6（ファイル名・設定キーは未登録から除外・登録済み語の食い違いは検出）"; pass=$((pass + 1))
  else
    echo "FAIL: ケース6の除外規則または食い違い検出に問題あり (rc=$rc6): ${out6}"; fail=$((fail + 1))
  fi

  # --- ケース5: 用語集が無いとき終了コード2 ---
  c5="${tmp}/case5"
  mkdir -p "${c5}/docs"
  make_guide "$c5" "sample-skill" '  <dl class="def">
    <dt>facts</dt>
    <dd>説明。</dd>
  </dl>'
  if bash "$SELF" "$c5" >/dev/null 2>&1; then
    rc5=0
  else
    rc5=$?
  fi
  if [ "$rc5" -eq 2 ]; then
    echo "PASS: ケース5（用語集が無い）で終了コード2"; pass=$((pass + 1))
  else
    echo "FAIL: ケース5で終了コード2になるべき (rc=$rc5)"; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH" >&2
  exit 1
fi

REPO_ROOT="${1:?usage: check-glossary-sync.sh <repo_root> [--list-unregistered]}"
LIST_MODE="${2:-}"

GLOSSARY="${REPO_ROOT}/docs/guides/用語集.md"
if [ ! -f "$GLOSSARY" ]; then
  echo "ERROR: glossary not found: $GLOSSARY" >&2
  exit 2
fi

python3 - "$REPO_ROOT" "$GLOSSARY" "$LIST_MODE" <<'PY'
import glob
import html
import os
import re
import sys

repo_root, glossary_path, list_mode = sys.argv[1], sys.argv[2], sys.argv[3]

TAG_RE = re.compile(r"<[^>]+>")


def strip_tags(s: str) -> str:
    return html.unescape(TAG_RE.sub("", s)).strip()


CONTENT_WORD_RE = re.compile(
    r"[一-鿿ー]{2,}|[ァ-ヽー]{2,}|[A-Za-z0-9_.\-]{2,}"
)


def content_words(text: str):
    return set(CONTENT_WORD_RE.findall(text))


FILENAME_TERM_RE = re.compile(
    r"^[A-Za-z0-9_.\-]+\.(?:yml|yaml|json|md|html|sh|cjs|mjs)(?:（[^）]*）)?$"
)
BRACKET_TERM_RE = re.compile(r"^<[^>]+>$")
JAPANESE_CHAR_RE = re.compile(r"[぀-ヿ一-鿿]")
TERM_SEPARATOR_RE = re.compile(r"[\s/=*_\-・／]")


def is_unregistrable_key_or_filename(term: str) -> bool:
    """ファイル名・設定の鍵の名前・山括弧プレースホルダは登録対象外とする。

    語とファイル名・設定キーを分ける規則（用語集とガイドの食い違いを解消する
    指示書 §「やること」2 参照）。日本語文字を含む語は対象外のまま個別判断する。
    """
    if FILENAME_TERM_RE.match(term):
        return True
    if BRACKET_TERM_RE.match(term):
        return True
    stripped = TERM_SEPARATOR_RE.sub("", term)
    if not stripped:
        return False
    if JAPANESE_CHAR_RE.search(stripped):
        return False
    return bool(re.match(r"^[A-Za-z0-9]+$", stripped))


def parse_glossary(path: str):
    text = open(path, encoding="utf-8").read()
    terms = {}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cols = [c.strip() for c in line.strip("|").split("|")]
        if len(cols) < 3:
            continue
        term_field = cols[0]
        if term_field in ("語",) or re.match(r"^-+$", term_field):
            continue
        definition = cols[2]
        for t in re.split(r"\s*/\s*", term_field):
            t = t.strip()
            if t:
                terms[t] = definition
    return terms


SECTION_RE = re.compile(
    r'<section id="([^"]+)">\s*<h2><span class="sec-num">§\d+</span>用語</h2>(.*?)</section>',
    re.S,
)
DTDD_RE = re.compile(r"<dt>(.*?)</dt>\s*<dd>(.*?)</dd>", re.S)
TABLE_ROW_RE = re.compile(r"<tr>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*</tr>", re.S)


def parse_guide(path: str):
    text = open(path, encoding="utf-8").read()
    out = []
    for sec_match in SECTION_RE.finditer(text):
        sec_id = sec_match.group(1)
        body = sec_match.group(2)
        for m in DTDD_RE.finditer(body):
            term = strip_tags(m.group(1))
            definition = strip_tags(m.group(2))
            if term:
                out.append((sec_id, term, definition))
        for m in TABLE_ROW_RE.finditer(body):
            term = strip_tags(m.group(1))
            definition = strip_tags(m.group(2))
            if term:
                out.append((sec_id, term, definition))
    return out


registered = parse_glossary(glossary_path)

guide_paths = sorted(
    glob.glob(os.path.join(repo_root, ".claude/skills/*/references/guide.html"))
)

unregistered = []  # (term, guide_rel, sec_id)
mismatches = []  # (term, gloss_def, guide_def, guide_rel)

bodies = {}
for p in guide_paths:
    rel = os.path.relpath(p, repo_root)
    bodies[rel] = strip_tags(open(p, encoding="utf-8").read())

for p in guide_paths:
    rel = os.path.relpath(p, repo_root)
    for sec_id, term, definition in parse_guide(p):
        if term not in registered:
            if is_unregistrable_key_or_filename(term):
                continue
            unregistered.append((term, rel, sec_id))
        else:
            gloss_def = registered[term]
            words = content_words(gloss_def)
            if words and not any(w in definition for w in words):
                mismatches.append((term, gloss_def, definition, rel))

unused = []
for term in sorted(registered.keys()):
    if not any(term in body for body in bodies.values()):
        unused.append(term)

if list_mode == "--list-unregistered":
    seen = set()
    for term, _rel, _sec in unregistered:
        if term not in seen:
            print(term)
            seen.add(term)
    sys.exit(1 if (unregistered or mismatches) else 0)

unreg_terms = sorted({t for t, _r, _s in unregistered})
print(f"=== 検査1: 未登録の用語 ({len(unreg_terms)}語 / {len(unregistered)}件) ===")
for term, rel, sec_id in unregistered:
    print(f"用語: {term} / ガイド: {rel} / 該当箇所: #{sec_id}")

print(f"=== 検査2: 説明の食い違い ({len(mismatches)}件) ===")
for term, gloss_def, guide_def, rel in mismatches:
    print(f"用語: {term} / ガイド: {rel}")
    print(f"  用語集: {gloss_def}")
    print(f"  ガイド: {guide_def}")

print(f"=== 検査3: 未使用の用語 ({len(unused)}語・情報のみ) ===")
for term in unused:
    print(term)

print(
    f"SUMMARY unregistered={len(unreg_terms)} unregistered_occurrences={len(unregistered)} "
    f"mismatch={len(mismatches)} unused={len(unused)}"
)

sys.exit(1 if (unregistered or mismatches) else 0)
PY
