#!/usr/bin/env bash
# 実サンプルfixtureによるfull rebuild決定性・child失敗・commit途中rollback試験。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/screen-rebuild-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

commit="${SCREEN_REBUILD_FIXTURE_COMMIT:-97f981267b8d36904486e309a99a6e0713edf3b2}"
bash "$SCRIPT_DIR/prepare-screen-rebuild-sample-fixture.sh" \
  --repo-root "$REPO_ROOT" --commit "$commit" --output "$tmp/fixture"
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
    mode="$(stat -f '%Lp' "$root/$rel" 2>/dev/null || stat -c '%a' "$root/$rel")"
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
