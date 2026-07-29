#!/usr/bin/env bash
# 実サンプルfixtureによるfull rebuild決定性・child失敗・commit途中rollback試験。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/screen-rebuild-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# フィクスチャは shared/samples/ 配下のchecked-in実ファイルを直接参照する。
# 旧実装はprepare-screen-rebuild-sample-fixture.sh経由で固定commitのGit履歴を参照していたが、
# (1) 固定commitがチェックアウト環境のGit履歴に存在しない場合に「ERROR: commit not found」で
#     即時停止し、(2) 当該スクリプトの`git show <commit>:shared/samples/...`は--repo-rootをGitの
#     トップレベルと同一視する設計のため、本リポジトリがモノレポのサブディレクトリとして配置される
#     環境ではパス解決が破綻していた。REPO_ROOTはこのスクリプト自身の相対位置から求めた実在ディレクトリ
#     であり、Gitのトップレベルか否かによらず常に正しいため、Git・commitへの依存を排し実ファイルを
#     直接読む方式に変更する。
screen_html="$REPO_ROOT/shared/samples/一覧/画面一覧/画面一覧.html"
api_html="$REPO_ROOT/shared/samples/一覧/API一覧/API一覧.html"
[ -f "$screen_html" ] || { echo "ERROR: fixture source not found: $screen_html" >&2; exit 1; }
[ -f "$api_html" ] || { echo "ERROR: fixture source not found: $api_html" >&2; exit 1; }
mkdir -p "$tmp/fixture/raw"
node - "$screen_html" screen-manifest "$tmp/fixture/raw/screen-manifest.json" \
  "$api_html" unit-manifest "$tmp/fixture/raw/api-manifest.json" <<'NODE'
const fs=require("fs");
function extract(file,id,out){
 const html=fs.readFileSync(file,"utf8").replace(/<!--[\s\S]*?-->/g,""), esc=id.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
 const found=[...html.matchAll(new RegExp(`<script\\b(?=[^>]*\\btype=["']application/json["'])(?=[^>]*\\bid=["']${esc}["'])[^>]*>([\\s\\S]*?)<\\/script>`,"gi"))];
 if(found.length!==1) throw new Error(`${file}#${id} count=${found.length}`);
 const text=found[0][1].replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"')
   .replace(/&#39;/g,"'").replace(/&#x27;/gi,"'").replace(/&amp;/g,"&");
 fs.writeFileSync(out,JSON.stringify(JSON.parse(text),null,2)+"\n");
}
const a=process.argv.slice(2); extract(a[0],a[1],a[2]); extract(a[3],a[4],a[5]);
NODE
jq '
  del(.manifestContentHash)
  | .strategy.extractionMethod = (.strategy.extractionMethod // "custom")
  | .strategy.approvedByUser = true
  | .strategy.screenIdRegex = (.strategy.screenIdRegex // null)
  | .strategy.excludePatterns = (.strategy.excludePatterns // [])
  | .screens = [.screens[] |
      .screenType = (.screenType // "top")
      | .accountGroup = (.accountGroup // "common")
      | .accountSubType = (.accountSubType // "common")
      | .hasTemplate = (.hasTemplate // true)
      | .parentScreen = (.parentScreen // null)
      | .childComponents = (.childComponents // [])
      | .isProcessingEndpoint = (.isProcessingEndpoint // false)
    ]
' "$tmp/fixture/raw/screen-manifest.json" > "$tmp/fixture/raw/screen-manifest.clean.json"
mv "$tmp/fixture/raw/screen-manifest.clean.json" "$tmp/fixture/raw/screen-manifest.json"
raw="$tmp/fixture/raw/screen-manifest.json"
api="$tmp/fixture/raw/api-manifest.json"

# ソース参照が基準commitの絶対pathでも、抽出は実在しないfileを安全に未抽出扱いする。
run_rebuild() {
  local out="$1"
  mkdir -p "$out"
  cp "$raw" "$out/raw-input.json"
  bash "$SCRIPT_DIR/rebuild-screen-derived-pages.sh" \
    --raw-manifest "$raw" --target-repo "$REPO_ROOT" --api-manifest "$api" \
    --output-root "$out" --generated-at 2026-07-28T00:00:00Z \
    --project-name "sample"
}

run_rebuild "$tmp/out-a"
run_rebuild "$tmp/out-b"

managed=(
  "一覧/画面一覧/screen-manifest.ext.json" "一覧/画面一覧/画面一覧.html"
  "画面遷移図-data.json" "画面遷移図.html"
  "マトリクス・対応表/data/permission-matrix.json"
  "マトリクス・対応表/data/permission-function-matrix.json"
  "マトリクス・対応表/data/crud-matrix.json"
  "マトリクス・対応表/data/traceability.json"
  "マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
  "マトリクス・対応表/権限機能マトリクス/権限機能マトリクス.html"
  "マトリクス・対応表/CRUD図/CRUD図.html"
  "マトリクス・対応表/追跡可能性/追跡可能性.html" "index.html"
)
record() {
  local root="$1" out="$2" rel
  : > "$out"
  for rel in "${managed[@]}"; do
    mode="$(stat -c '%a' "$root/$rel" 2>/dev/null || stat -f '%Lp' "$root/$rel")"
    if command -v shasum >/dev/null 2>&1; then hash="$(shasum -a 256 "$root/$rel" | awk '{print $1}')"
    else hash="$(sha256sum "$root/$rel" | awk '{print $1}')"; fi
    printf '%s\t%s\t%s\n' "$rel" "$mode" "$hash" >> "$out"
  done
}
record "$tmp/out-a" "$tmp/a.record"
record "$tmp/out-b" "$tmp/b.record"
cmp "$tmp/a.record" "$tmp/b.record"
echo "PASS: independent rebuilds are byte/mode/path identical"

tree_record() {
  local root="$1" out="$2"
  node - "$root" "$out" <<'NODE'
const fs=require("fs"),path=require("path"),crypto=require("crypto"),[root,out]=process.argv.slice(2),rows=[];
function walk(p,r=""){for(const n of fs.readdirSync(p).sort()){const q=path.join(p,n),x=r?`${r}/${n}`:n,s=fs.lstatSync(q);if(s.isDirectory())walk(q,x);else rows.push(`${x}\t${s.mode&0o7777}\t${crypto.createHash("sha256").update(fs.readFileSync(q)).digest("hex")}`)}} walk(root);fs.writeFileSync(out,rows.join("\n")+"\n");
NODE
}

# managed pathの既存祖先がsymlinkなら、transaction作成前に拒否し、
# symlink先の外部treeとoutput treeの双方を一切変更しない。
mkdir -p "$tmp/symlink-output" "$tmp/symlink-external"
printf '%s\n' "external-sentinel" > "$tmp/symlink-external/sentinel.txt"
ln -s "$tmp/symlink-external" "$tmp/symlink-output/一覧"
node - "$tmp/symlink-output" "$tmp/symlink-output-before" <<'NODE'
const fs=require("fs"),path=require("path"),crypto=require("crypto"),[root,out]=process.argv.slice(2),rows=[];
function walk(p,r=""){for(const n of fs.readdirSync(p).sort()){const q=path.join(p,n),x=r?`${r}/${n}`:n,s=fs.lstatSync(q);if(s.isDirectory())walk(q,x);else if(s.isSymbolicLink())rows.push(`${x}\t${s.mode&0o7777}\tsymlink:${fs.readlinkSync(q)}`);else rows.push(`${x}\t${s.mode&0o7777}\t${crypto.createHash("sha256").update(fs.readFileSync(q)).digest("hex")}`)}} walk(root);fs.writeFileSync(out,rows.join("\n")+"\n");
NODE
tree_record "$tmp/symlink-external" "$tmp/symlink-external-before"
if bash "$SCRIPT_DIR/rebuild-screen-derived-pages.sh" \
  --raw-manifest "$raw" --target-repo "$REPO_ROOT" --api-manifest "$api" \
  --output-root "$tmp/symlink-output" --generated-at 2026-07-28T00:00:00Z \
  --project-name "sample" >/dev/null 2>&1; then
  echo "FAIL: managed ancestor symlink was accepted" >&2
  exit 1
fi
node - "$tmp/symlink-output" "$tmp/symlink-output-after" <<'NODE'
const fs=require("fs"),path=require("path"),crypto=require("crypto"),[root,out]=process.argv.slice(2),rows=[];
function walk(p,r=""){for(const n of fs.readdirSync(p).sort()){const q=path.join(p,n),x=r?`${r}/${n}`:n,s=fs.lstatSync(q);if(s.isDirectory())walk(q,x);else if(s.isSymbolicLink())rows.push(`${x}\t${s.mode&0o7777}\tsymlink:${fs.readlinkSync(q)}`);else rows.push(`${x}\t${s.mode&0o7777}\t${crypto.createHash("sha256").update(fs.readFileSync(q)).digest("hex")}`)}} walk(root);fs.writeFileSync(out,rows.join("\n")+"\n");
NODE
tree_record "$tmp/symlink-external" "$tmp/symlink-external-after"
cmp "$tmp/symlink-output-before" "$tmp/symlink-output-after"
cmp "$tmp/symlink-external-before" "$tmp/symlink-external-after"
echo "PASS: managed ancestor symlink rejected without changing output or external tree"

for injection in after-matrix commit-5; do
  cp -a "$tmp/out-a" "$tmp/rollback-$injection"
  tree_record "$tmp/rollback-$injection" "$tmp/$injection-before"
  if SCREEN_REBUILD_INJECT_FAIL="$injection" bash "$SCRIPT_DIR/rebuild-screen-derived-pages.sh" \
    --raw-manifest "$raw" --target-repo "$REPO_ROOT" --api-manifest "$api" \
    --output-root "$tmp/rollback-$injection" --generated-at 2026-07-28T00:00:00Z \
    --project-name "sample" >/dev/null 2>&1; then
    echo "FAIL: injected failure unexpectedly succeeded: $injection" >&2
    exit 1
  fi
  tree_record "$tmp/rollback-$injection" "$tmp/$injection-after"
  cmp "$tmp/$injection-before" "$tmp/$injection-after"
  echo "PASS: $injection restored exact target tree"
done

if bash "$SCRIPT_DIR/rebuild-screen-derived-pages.sh" \
  --raw-manifest "$raw" --target-repo "$REPO_ROOT" --api-manifest "$api" \
  --output-root "$tmp/no-clock" >/dev/null 2>&1; then
  echo "FAIL: missing clock accepted" >&2; exit 1
fi
if SOURCE_DATE_EPOCH=0 bash "$SCRIPT_DIR/rebuild-screen-derived-pages.sh" \
  --raw-manifest "$raw" --target-repo "$REPO_ROOT" --api-manifest "$api" \
  --output-root "$tmp/two-clocks" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1; then
  echo "FAIL: two clocks accepted" >&2; exit 1
fi
echo "self-test 全項目 PASS"
