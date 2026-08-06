#!/usr/bin/env bash
# 抽出エンジン: APIマニフェストへのメタデータ付与(拡張マニフェスト生成)。
# 入力マニフェストの既存フィールドは一切変更せず、抽出できたフィールドだけを units[] の
# 各要素へ追加した拡張マニフェストを出力する。検出根拠が弱い値は出力しない(誤った値より
# 欠落を優先する fail-safe。欠落は任意フィールドの不在として扱われる)。
#
# Usage: extract-api-metadata.sh <api-manifest.json> <source-dir> <output.json> \
#          [--screen-manifest <extended-screen-manifest.json>] [--table-manifest <table-manifest.json>] \
#          [--survey-doc-path <architecture-survey.md>]
#        extract-api-metadata.sh --self-test
#
# 入力契約:
#   <api-manifest.json>   : unitKind=api のユニットマニフェスト(validate-manifest.sh PASS 済み想定)
#   <source-dir>          : 原本コードのルート(現状は sourceFile が絶対/相対パスで解決できることの
#                           確認にのみ使用。sourceFile が相対パスの場合は source-dir 起点で解決する)
#   --screen-manifest     : relatedApis 抽出済みの拡張画面マニフェスト(callers 逆引きに使用。省略可)
#   --table-manifest      : テーブルマニフェスト(targetTables 抽出に使用。省略可)
#   --survey-doc-path     : アーキテクチャ調査書のパス(省略可)。「ルーティング方式」の記載が
#                           メソッドチェーン呼び出し系(Express/Fastify/Hono等)を明示している場合のみ、
#                           関数ブロック検査をメソッド呼び出し境界(次のルート呼び出し行またはEOFまで)
#                           でも試みる(デコレータ境界に次ぐ第2の手がかり)。未指定時・不一致時は
#                           従来のデコレータ境界のみで判定し、挙動は変わらない
#
# 出力契約:
#   <output.json> に拡張マニフェストを書き出す。追加されうるフィールド
#   (スキーマ正本: shared/references/manifest-schema-extensions.md「apis(API)」節):
#     method       : string   GET/POST/PUT/PATCH/DELETE のいずれか
#     authRequired : boolean  認証の要否
#     callers      : string[] 呼び出し元画面の screenKey 配列(空なら付けない)
#     targetTables : string[] 参照テーブルの unitKey 配列(空なら付けない)
#     ioSummary    : string   「<入力> → <出力>」形式の 1 行要約
#   既存フィールドと衝突した場合は既存値を保持する(上書きしない)。
#   加えて detectionSummary.diagnostics.fallback に以下を記録する(検出できなかった事実の可視化):
#     count/total  : 関数ブロックを特定できずファイル単位・近傍窓へフォールバックしたユニット数/全体数
#     ratio        : count/total(totalが0ならratio=0・warning=false)
#     threshold    : 0.5(固定)
#     warning      : ratio > threshold
#   出力は validate-manifest.sh <output.json> --unit-kind api で検証可能。
#
# 検査範囲(関数ブロック):
#   authRequired / targetTables / ioSummary の検査範囲は、当該エンドポイントの「関数ブロック」に
#   限定する。関数ブロック = identifier の method+path に合致するルートデコレータ行
#   (@router.get("/path") 等。path は閉じ引用符付きで突合)から、次のデコレータ行の直前
#   またはファイル末尾まで。同一ルーターファイル内の別エンドポイントの認証依存・テーブル参照を
#   誤帰属させないための範囲限定(F2 再照合で実測された混線の修正)。
#   デコレータ行を特定できない場合(非デコレータ方式のルーティング等)は従来のファイル単位
#   検査へフォールバックし、その旨を stderr に WARN 出力する(fail-safe)。
#
# 検出ヒューリスティック一覧(すべて grep/sed/awk ベース):
#   1. method       : identifier の先頭語(空白区切り)が GET/POST/PUT/PATCH/DELETE に完全一致する
#                     場合を最優先で採用する。無い場合はframework factoryへ静的に1回だけ束縛され、
#                     全receiver使用がその束縛またはroute callだけの識別子から一意のmethodを採用する。
#                     再代入・shadowing・引数や式での使用があれば根拠外とする
#   2. authRequired : 関数ブロック内(フォールバック時はパス部の最初のヒット行の前 3 行〜後 20 行)に
#                     認証パターン
#                       Depends(get_current_user / @login_required / requireAuth / verify_token / IsAuthenticated
#                     があれば true。認証除外パターン(単語境界付き)
#                       AllowAny / public
#                     があれば false。検査範囲が取れない・どちらのパターンも無い場合は付けない
#   3. callers      : --screen-manifest の screens[](または units[])の relatedApis[] が、この API の
#                     unitKey / identifier / パス部のいずれかに一致する要素の screenKey を収集。
#                     0 件なら付けない
#   4. targetTables : --table-manifest の各ユニット(kind=unresolved を除く)の identifier(物理名)を
#                     関数ブロック内(フォールバック時は sourceFile 全体)で grep -qwF(単語境界・
#                     固定文字列)し、ヒットしたテーブルの unitKey を収集。0 件なら付けない
#   5. ioSummary    : 関数ブロック(フォールバック時はエンドポイント近傍窓)内から
#                       出力: response_model=<Name>(FastAPI) または ): Promise<Name>(TypeScript)
#                       入力: 型注釈 : <Name> のうち接尾辞 Create/Update/Request/Input/Payload/Body/Form/Schema
#                             を持つもの(Pydantic リクエストモデル風)
#                     を sed -nE で抽出し、出力が取れた場合のみ「<入力> → <出力>」を付ける。
#                     入力が取れない場合の入力部は「なし」とする。出力が取れなければ付けない

set -euo pipefail

AUTH_POSITIVE_ERE='Depends\(get_current_user|@login_required|requireAuth|verify_token|IsAuthenticated'
AUTH_NEGATIVE_ERE='(^|[^A-Za-z0-9_])(AllowAny|public)([^A-Za-z0-9_]|$)'

# --- --self-test モード ---
# FastAPI 風フィクスチャ(認証付き GET /api/users が users テーブルを SELECT + 認証情報の無い
# POST /api/ping)で、method/authRequired/callers/targetTables/ioSummary の抽出値と、
# 根拠が無い場合のフィールド欠落(fail-safe)、既存フィールド無変更、validate-manifest.sh PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local validate="$script_dir/../unit-list/validate-manifest.sh"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-api-metadata-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/api"

  # 認証付きエンドポイント(users テーブルを SELECT)
  cat > "$tmp/src/api/users.py" <<'EOF'
from fastapi import APIRouter, Depends
router = APIRouter()

@router.get("/api/users", response_model=UserList)
def list_users(current_user=Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.execute("SELECT id, name FROM users")
    return rows
EOF

  # 認証情報もモデルも無いエンドポイント(fail-safe による欠落を検証)
  cat > "$tmp/src/api/ping.py" <<'EOF'
from fastapi import APIRouter
router = APIRouter()

@router.post("/api/ping")
def ping():
    return {"ok": True}
EOF

  # 同一ファイルに認証あり/なしエンドポイントが混在 + 別テーブル参照(関数ブロック帰属を検証):
  #   GET /api/posts      : 認証あり(get_current_user)。posts + orders を参照
  #   GET /api/posts/{id} : 認証除外(AllowAny)。posts のみ参照
  # ファイル単位検査だと detail に authRequired=true と orders が誤帰属する(F2 実測の再現)
  cat > "$tmp/src/api/posts.py" <<'EOF'
from fastapi import APIRouter, Depends
router = APIRouter()

@router.get("/api/posts", response_model=PostList)
def list_posts(current_user=Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.execute("SELECT p.id FROM posts p JOIN orders o ON o.post_id = p.id")
    return rows

@router.get("/api/posts/{id}", response_model=PostDetail, dependencies=[AllowAny])
def get_post(id: int, db: Session = Depends(get_db)):
    row = db.execute("SELECT id, title FROM posts WHERE id = :id")
    return row
EOF

  # 独自ルート方式: framework生成式へ束縛されたreceiverだけを根拠にする。
  cat > "$tmp/src/api/express_routes.js" <<'EOF'
const app = express();
app.get(
  "/api/express-users",
  listUsers,
)
EOF

  cat > "$tmp/src/api/fastify_routes.js" <<'EOF'
const server = Fastify();
server.post('/api/fastify-users', createUsers)
EOF

  cat > "$tmp/src/api/hono_routes.ts" <<'EOF'
const router = new Hono();
router.patch(`/api/hono-users`, updateUsers)
EOF

  # 同一 path の異なる method は根拠が一意でないため、method を推測しない。
  cat > "$tmp/src/api/ambiguous_routes.js" <<'EOF'
const app = express.Router();
app.get('/api/ambiguous-users', listUsers)
app.delete('/api/ambiguous-users', removeUsers)
EOF

  # コメント・文字列に見える疑似ルートは実装根拠にしない。
  cat > "$tmp/src/api/comment_only_routes.js" <<'EOF'
// app.get('/api/comment-only', listUsers)
EOF

  cat > "$tmp/src/api/block_comment_routes.js" <<'EOF'
/*
server.post('/api/block-comment-only', createUsers)
*/
EOF

  cat > "$tmp/src/api/string_only_routes.js" <<'EOF'
const example = "router.patch('/api/string-only', updateUsers)"
EOF

  cat > "$tmp/src/api/http_client_routes.js" <<'EOF'
const httpClient = createHttpClient();
httpClient.get('/api/http-client-only', requestUsers)
EOF

  cat > "$tmp/src/api/unbound_app_routes.js" <<'EOF'
app.get('/api/unbound-app-only', listUsers)
EOF

  cat > "$tmp/src/api/receiver_collision_routes.js" <<'EOF'
const app = express();
const httpapp = createHttpClient();
httpapp.get('/api/collision', requestUsers)
EOF

  cat > "$tmp/src/api/reassigned_receiver_routes.js" <<'EOF'
let app = express();
app = createHttpClient();
app.get('/api/reassigned', requestUsers)
EOF

  cat > "$tmp/src/api/shadowed_receiver_routes.js" <<'EOF'
const app = express();
function configure() {
  const app = createHttpClient();
  app.get('/api/shadowed', requestUsers)
}
EOF

  cat > "$tmp/src/api/parameter_shadow_routes.js" <<'EOF'
const app = express();
function configure(app) {
  app.get('/api/parameter-shadow', requestUsers)
}
EOF

  # 関数/クラス宣言もreceiver名をshadowingする。宣言後のroute callを外側factory束縛へ
  # 帰属させないことを検証する。
  cat > "$tmp/src/api/function_declaration_shadow_routes.js" <<'EOF'
const app = express();
function configure() {
  function app() {}
  app.get('/api/function-declaration-shadow', requestUsers)
}
EOF

  cat > "$tmp/src/api/class_declaration_shadow_routes.js" <<'EOF'
const app = express();
function configure() {
  class app {}
  app.get('/api/class-declaration-shadow', requestUsers)
}
EOF

  cat > "$tmp/src/api/logical_assign_routes.js" <<'EOF'
let app = express();
app ||= createHttpClient();
app.get('/api/logical-assign', requestUsers)
EOF

  cat > "$tmp/src/api/destructured_receiver_routes.js" <<'EOF'
const app = express();
({app} = source);
app.get('/api/destructured', requestUsers)
EOF

  # factory識別子自体が別物へ束縛・引数shadowing・function/class宣言でshadowingされる場合は、
  # そのfactoryから生成されたように見えるreceiverも根拠外とする。
  cat > "$tmp/src/api/factory-rebound_routes.js" <<'EOF'
const express = createHttpClient;
const app = express();
app.get('/api/factory-rebound', listUsers)
EOF

  cat > "$tmp/src/api/factory-parameter-shadow_routes.js" <<'EOF'
function configure(express) {
  const app = express();
  app.post('/api/factory-parameter-shadow', createUsers)
}
EOF

  cat > "$tmp/src/api/factory-function-shadow_routes.js" <<'EOF'
function Fastify() {}
const server = Fastify();
server.put('/api/factory-function-shadow', updateUsers)
EOF

  cat > "$tmp/src/api/factory-class-shadow_routes.js" <<'EOF'
class Hono {}
const router = new Hono();
router.patch('/api/factory-class-shadow', updateUsers)
EOF

  # regex literal内の文字列は、route callの根拠にしない。
  cat > "$tmp/src/api/regex-only_routes.js" <<'EOF'
const app = express();
const regex = /app.get("/api/regex-only",)/;
EOF

  # 除算演算子はregex literalの開始と誤認せず、後続の実ルートを抽出する。
  cat > "$tmp/src/api/division_routes.js" <<'EOF'
const app = express();
const ratio = total / divisor;
app.get('/api/division-safe', listUsers)
EOF

  # 通常のimport/require経由のfactoryは引き続き採用する。
  cat > "$tmp/src/api/imported-express_routes.js" <<'EOF'
import express from "express";
const app = express();
app.get('/api/imported-express', listUsers)
EOF

  cat > "$tmp/src/api/required-fastify_routes.js" <<'EOF'
const Fastify = require("fastify");
const server = Fastify();
server.post('/api/required-fastify', createUsers)
EOF

  cat > "$tmp/src/api/imported-hono_routes.ts" <<'EOF'
import { Hono } from "hono";
const router = new Hono();
router.patch('/api/imported-hono', updateUsers)
EOF

  # APIマニフェスト(独自ルート方式を含む 30 ユニット)
  local api_manifest="$tmp/api-manifest.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg usersFile "$tmp/src/api/users.py" \
    --arg pingFile "$tmp/src/api/ping.py" \
    --arg postsFile "$tmp/src/api/posts.py" \
    --arg expressFile "$tmp/src/api/express_routes.js" \
    --arg fastifyFile "$tmp/src/api/fastify_routes.js" \
    --arg honoFile "$tmp/src/api/hono_routes.ts" \
    --arg ambiguousFile "$tmp/src/api/ambiguous_routes.js" \
    --arg commentOnlyFile "$tmp/src/api/comment_only_routes.js" \
    --arg blockCommentFile "$tmp/src/api/block_comment_routes.js" \
    --arg stringOnlyFile "$tmp/src/api/string_only_routes.js" \
    --arg httpClientFile "$tmp/src/api/http_client_routes.js" \
    --arg unboundAppFile "$tmp/src/api/unbound_app_routes.js" \
    --arg receiverCollisionFile "$tmp/src/api/receiver_collision_routes.js" \
    --arg reassignedReceiverFile "$tmp/src/api/reassigned_receiver_routes.js" \
    --arg shadowedReceiverFile "$tmp/src/api/shadowed_receiver_routes.js" \
    --arg parameterShadowFile "$tmp/src/api/parameter_shadow_routes.js" \
    --arg functionDeclarationShadowFile "$tmp/src/api/function_declaration_shadow_routes.js" \
    --arg classDeclarationShadowFile "$tmp/src/api/class_declaration_shadow_routes.js" \
    --arg logicalAssignFile "$tmp/src/api/logical_assign_routes.js" \
    --arg destructuredReceiverFile "$tmp/src/api/destructured_receiver_routes.js" \
    --arg factoryReboundFile "$tmp/src/api/factory-rebound_routes.js" \
    --arg factoryParameterShadowFile "$tmp/src/api/factory-parameter-shadow_routes.js" \
    --arg factoryFunctionShadowFile "$tmp/src/api/factory-function-shadow_routes.js" \
    --arg factoryClassShadowFile "$tmp/src/api/factory-class-shadow_routes.js" \
    --arg regexOnlyFile "$tmp/src/api/regex-only_routes.js" \
    --arg divisionFile "$tmp/src/api/division_routes.js" \
    --arg importedExpressFile "$tmp/src/api/imported-express_routes.js" \
    --arg requiredFastifyFile "$tmp/src/api/required-fastify_routes.js" \
    --arg importedHonoFile "$tmp/src/api/imported-hono_routes.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 30, unresolvedCount: 0},
      units: [
        {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users",
         unitNameGuess: "ユーザー一覧取得", sourceFile: $usersFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "ping", kind: "endpoint", identifier: "POST /api/ping",
         unitNameGuess: "疎通確認", sourceFile: $pingFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "posts-list", kind: "endpoint", identifier: "GET /api/posts",
         unitNameGuess: "投稿一覧取得", sourceFile: $postsFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "posts-detail", kind: "endpoint", identifier: "GET /api/posts/{id}",
         unitNameGuess: "投稿詳細取得", sourceFile: $postsFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "express-users", kind: "endpoint", identifier: "/api/express-users",
         unitNameGuess: "Expressユーザー取得", sourceFile: $expressFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "fastify-users", kind: "endpoint", identifier: "/api/fastify-users",
         unitNameGuess: "Fastifyユーザー作成", sourceFile: $fastifyFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "hono-users", kind: "endpoint", identifier: "/api/hono-users",
         unitNameGuess: "Honoユーザー更新", sourceFile: $honoFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "ambiguous-users", kind: "endpoint", identifier: "/api/ambiguous-users",
         unitNameGuess: "曖昧なユーザー操作", sourceFile: $ambiguousFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "comment-only", kind: "endpoint", identifier: "/api/comment-only",
         unitNameGuess: "コメントのみのルート", sourceFile: $commentOnlyFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "block-comment-only", kind: "endpoint", identifier: "/api/block-comment-only",
         unitNameGuess: "ブロックコメントのみのルート", sourceFile: $blockCommentFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "string-only", kind: "endpoint", identifier: "/api/string-only",
         unitNameGuess: "文字列のみのルート", sourceFile: $stringOnlyFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "http-client-only", kind: "endpoint", identifier: "/api/http-client-only",
         unitNameGuess: "HTTPクライアントのみ", sourceFile: $httpClientFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "unbound-app-only", kind: "endpoint", identifier: "/api/unbound-app-only",
         unitNameGuess: "未束縛appのみ", sourceFile: $unboundAppFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "receiver-collision", kind: "endpoint", identifier: "/api/collision",
         unitNameGuess: "receiver接尾辞衝突", sourceFile: $receiverCollisionFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "reassigned-receiver", kind: "endpoint", identifier: "/api/reassigned",
         unitNameGuess: "再代入receiver", sourceFile: $reassignedReceiverFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "shadowed-receiver", kind: "endpoint", identifier: "/api/shadowed",
         unitNameGuess: "shadowing receiver", sourceFile: $shadowedReceiverFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "parameter-shadow", kind: "endpoint", identifier: "/api/parameter-shadow",
         unitNameGuess: "引数shadowing", sourceFile: $parameterShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "function-declaration-shadow", kind: "endpoint", identifier: "/api/function-declaration-shadow",
         unitNameGuess: "関数宣言shadowing", sourceFile: $functionDeclarationShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "class-declaration-shadow", kind: "endpoint", identifier: "/api/class-declaration-shadow",
         unitNameGuess: "クラス宣言shadowing", sourceFile: $classDeclarationShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "logical-assign", kind: "endpoint", identifier: "/api/logical-assign",
         unitNameGuess: "論理代入receiver", sourceFile: $logicalAssignFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "destructured-receiver", kind: "endpoint", identifier: "/api/destructured",
         unitNameGuess: "分割代入receiver", sourceFile: $destructuredReceiverFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "factory-rebound", kind: "endpoint", identifier: "/api/factory-rebound",
         unitNameGuess: "別値へ束縛されたfactory", sourceFile: $factoryReboundFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "factory-parameter-shadow", kind: "endpoint", identifier: "/api/factory-parameter-shadow",
         unitNameGuess: "引数shadowingされたfactory", sourceFile: $factoryParameterShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "factory-function-shadow", kind: "endpoint", identifier: "/api/factory-function-shadow",
         unitNameGuess: "関数宣言shadowingされたfactory", sourceFile: $factoryFunctionShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "factory-class-shadow", kind: "endpoint", identifier: "/api/factory-class-shadow",
         unitNameGuess: "class宣言shadowingされたfactory", sourceFile: $factoryClassShadowFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "regex-only", kind: "endpoint", identifier: "/api/regex-only",
         unitNameGuess: "正規表現のみのルート", sourceFile: $regexOnlyFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "division-safe", kind: "endpoint", identifier: "/api/division-safe",
         unitNameGuess: "除算を含むルート", sourceFile: $divisionFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "imported-express", kind: "endpoint", identifier: "/api/imported-express",
         unitNameGuess: "importされたExpress", sourceFile: $importedExpressFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "required-fastify", kind: "endpoint", identifier: "/api/required-fastify",
         unitNameGuess: "requireされたFastify", sourceFile: $requiredFastifyFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "imported-hono", kind: "endpoint", identifier: "/api/imported-hono",
         unitNameGuess: "importされたHono", sourceFile: $importedHonoFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"}
      ]
    }' > "$api_manifest"

  # 拡張画面マニフェスト(relatedApis が users-list を参照)
  local screen_manifest="$tmp/screen-manifest.json"
  jq -n '{
    unitKind: "screen",
    screens: [
      {screenKey: "user-admin", relatedApis: ["users-list"]},
      {screenKey: "dashboard", relatedApis: ["orders-list"]}
    ]
  }' > "$screen_manifest"

  # テーブルマニフェスト(users / orders / posts テーブル)
  local table_manifest="$tmp/table-manifest.json"
  jq -n '{
    unitKind: "table",
    units: [
      {unitKey: "users", kind: "table", identifier: "users"},
      {unitKey: "orders", kind: "table", identifier: "orders"},
      {unitKey: "posts", kind: "table", identifier: "posts"}
    ]
  }' > "$table_manifest"

  local out="$tmp/api-manifest-extended.json"
  if ! bash "$script_path" "$api_manifest" "$tmp/src" "$out" \
       --screen-manifest "$screen_manifest" --table-manifest "$table_manifest" >/dev/null 2>&1; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  check() {
    local label="$1" jq_expr="$2"
    if [ "$(jq -r "$jq_expr" "$out")" = "true" ]; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
      rc=1
    fi
  }

  check "method: GET /api/users から GET を抽出" '.units[0].method == "GET"'
  check "authRequired: Depends(get_current_user) 検出で true" '.units[0].authRequired == true'
  check "callers: relatedApis 逆引きで [\"user-admin\"]" '.units[0].callers == ["user-admin"]'
  check "targetTables: users テーブルの grep ヒットで [\"users\"]" '.units[0].targetTables == ["users"]'
  check "ioSummary: response_model=UserList から生成" '.units[0].ioSummary == "なし → UserList"'
  check "method: POST /api/ping から POST を抽出" '.units[1].method == "POST"'
  check "fail-safe: 根拠の無い authRequired/callers/targetTables/ioSummary は欠落" \
    '.units[1] | (has("authRequired") or has("callers") or has("targetTables") or has("ioSummary")) | not'
  check "混在ファイル posts-list: 自ブロックの get_current_user で authRequired=true" \
    '.units[2].authRequired == true'
  check "混在ファイル posts-list: 自ブロック参照の posts+orders のみ帰属" \
    '.units[2].targetTables == ["orders", "posts"]'
  check "混在ファイル posts-detail: AllowAny で authRequired=false(隣の認証を誤帰属しない)" \
    '.units[3].authRequired == false'
  check "混在ファイル posts-detail: targetTables は posts のみ(orders が混入しない)" \
    '.units[3].targetTables == ["posts"]'
  check "混在ファイル posts-detail: 自ブロックの response_model=PostDetail から ioSummary 生成" \
    '.units[3].ioSummary == "なし → PostDetail"'
  check "独自ルート Express: 動詞なしidentifierからGETを抽出" '.units[4].method == "GET"'
  check "独自ルート Fastify: 動詞なしidentifierからPOSTを抽出" '.units[5].method == "POST"'
  check "独自ルート Hono: 動詞なしidentifierからPATCHを抽出" '.units[6].method == "PATCH"'
  check "独自ルート 曖昧: GETとDELETEが同一pathならmethodを付けない" \
    '.units[7] | has("method") | not'
  check "独自ルート 負例: 行コメントだけならmethodを付けない" \
    '.units[8] | has("method") | not'
  check "独自ルート 負例: ブロックコメントだけならmethodを付けない" \
    '.units[9] | has("method") | not'
  check "独自ルート 負例: 文字列内だけならmethodを付けない" \
    '.units[10] | has("method") | not'
  check "独自ルート 負例: HTTPクライアントreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "http-client-only") | has("method")) | not'
  check "独自ルート 負例: framework束縛のないappならmethodを付けない" \
    '(.units[] | select(.unitKey == "unbound-app-only") | has("method")) | not'
  check "独自ルート 負例: receiver接尾辞を持つ別識別子ならmethodを付けない" \
    '(.units[] | select(.unitKey == "receiver-collision") | has("method")) | not'
  check "独自ルート 負例: 再代入されたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "reassigned-receiver") | has("method")) | not'
  check "独自ルート 負例: 同名shadowingされたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "shadowed-receiver") | has("method")) | not'
  check "独自ルート 負例: 関数引数でshadowingされたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "parameter-shadow") | has("method")) | not'
  check "独自ルート 負例: 関数宣言でshadowingされたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "function-declaration-shadow") | has("method")) | not'
  check "独自ルート 負例: class宣言でshadowingされたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "class-declaration-shadow") | has("method")) | not'
  check "独自ルート 負例: 論理代入に使われたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "logical-assign") | has("method")) | not'
  check "独自ルート 負例: 分割代入に使われたreceiverならmethodを付けない" \
    '(.units[] | select(.unitKey == "destructured-receiver") | has("method")) | not'
  check "独自ルート 負例: 別値へ束縛されたexpress factoryならmethodを付けない" \
    '(.units[] | select(.unitKey == "factory-rebound") | has("method")) | not'
  check "独自ルート 負例: 関数引数でshadowingされたexpress factoryならmethodを付けない" \
    '(.units[] | select(.unitKey == "factory-parameter-shadow") | has("method")) | not'
  check "独自ルート 負例: function宣言でshadowingされたFastify factoryならmethodを付けない" \
    '(.units[] | select(.unitKey == "factory-function-shadow") | has("method")) | not'
  check "独自ルート 負例: class宣言でshadowingされたHono factoryならmethodを付けない" \
    '(.units[] | select(.unitKey == "factory-class-shadow") | has("method")) | not'
  check "独自ルート 負例: 正規表現リテラル内だけならmethodを付けない" \
    '(.units[] | select(.unitKey == "regex-only") | has("method")) | not'
  check "独自ルート: 除算演算子の後でもGETを抽出" \
    '(.units[] | select(.unitKey == "division-safe") | .method) == "GET"'
  check "独自ルート: importされたExpressからGETを抽出" \
    '(.units[] | select(.unitKey == "imported-express") | .method) == "GET"'
  check "独自ルート: requireされたFastifyからPOSTを抽出" \
    '(.units[] | select(.unitKey == "required-fastify") | .method) == "POST"'
  check "独自ルート: importされたHonoからPATCHを抽出" \
    '(.units[] | select(.unitKey == "imported-hono") | .method) == "PATCH"'

  # 既存フィールド無変更: 追加フィールドを除去すると入力と完全一致する
  # (detectionSummary.diagnostics.fallback は本スクリプトが新規に追加するため、
  #  ユニット単位の追加5フィールドと同様に除去してから比較する)
  local stripped="$tmp/stripped.json" expected="$tmp/expected.json"
  jq -S '.units = [.units[] | del(.method, .authRequired, .callers, .targetTables, .ioSummary)]
         | del(.detectionSummary.diagnostics)' "$out" > "$stripped"
  jq -S . "$api_manifest" > "$expected"
  if diff -q "$stripped" "$expected" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド無変更: 追加フィールド除去後に入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド無変更: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  # フォールバック率diagnostics(1-130): 30ユニット中、関数ブロックをデコレータ境界で
  # 特定できたのはusers/ping/posts-list/posts-detailの4件のみ。残り26件は独自ルート方式
  # (デコレータ非対応)でファイル単位・近傍窓へフォールバックする。survey-doc-path未指定なら
  # ratio=26/30(≈0.867) > 0.5 でwarning: trueになるはず
  check "fallback診断: count=26" '.detectionSummary.diagnostics.fallback.count == 26'
  check "fallback診断: total=30" '.detectionSummary.diagnostics.fallback.total == 30'
  check "fallback診断: threshold=0.5" '.detectionSummary.diagnostics.fallback.threshold == 0.5'
  check "fallback診断: ratio>0.5でwarning: true" '.detectionSummary.diagnostics.fallback.warning == true'

  if bash "$validate" "$out" --unit-kind api >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest.sh: 拡張マニフェストが --unit-kind api で PASS"
  else
    echo "  [FAIL] validate-manifest.sh: 拡張マニフェストの検証が FAIL" >&2
    rc=1
  fi

  # --- survey-doc-path によるメソッド呼び出し境界フォールバック(1-130) ---
  # デコレータの無いメソッドチェーン方式(Express風)の2ユニットで、
  # 記法が一致するsurvey-doc-pathを渡すとフォールバックが解消しwarning: falseになり、
  # 記法が不一致(またはsurvey-doc-path省略)ならフォールバックが残りwarning: trueのままになることを検証する。
  mkdir -p "$tmp/callstyle/src"
  cat > "$tmp/callstyle/src/routes.js" <<'EOF'
const app = express();
app.get('/api/call-a', handlerA)
app.post('/api/call-b', handlerB)
EOF
  local cs_manifest="$tmp/callstyle/manifest.json" cs_routes="$tmp/callstyle/src/routes.js"
  jq -n --arg f "$cs_routes" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "x", unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "call-a", kind: "endpoint", identifier: "GET /api/call-a",
       unitNameGuess: "呼び出しA", sourceFile: $f, confidence: "high", fileCount: 1, detectionMethod: "manual"},
      {unitKey: "call-b", kind: "endpoint", identifier: "POST /api/call-b",
       unitNameGuess: "呼び出しB", sourceFile: $f, confidence: "high", fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$cs_manifest"

  echo "## ルーティング方式
Express のメソッドチェーン呼び出し(app.get/app.post)でルーティングを定義する。" > "$tmp/callstyle/survey-match.md"
  echo "## ルーティング方式
FastAPI のデコレータでルーティングを定義する。" > "$tmp/callstyle/survey-mismatch.md"

  local cs_out_none="$tmp/callstyle/out-none.json" \
        cs_out_match="$tmp/callstyle/out-match.json" \
        cs_out_mismatch="$tmp/callstyle/out-mismatch.json"

  bash "$script_path" "$cs_manifest" "$tmp/callstyle/src" "$cs_out_none" >/dev/null 2>&1
  bash "$script_path" "$cs_manifest" "$tmp/callstyle/src" "$cs_out_match" \
    --survey-doc-path "$tmp/callstyle/survey-match.md" >/dev/null 2>&1
  bash "$script_path" "$cs_manifest" "$tmp/callstyle/src" "$cs_out_mismatch" \
    --survey-doc-path "$tmp/callstyle/survey-mismatch.md" >/dev/null 2>&1

  check_file() {
    local label="$1" file="$2" jq_expr="$3"
    if [ "$(jq -r "$jq_expr" "$file" 2>/dev/null)" = "true" ]; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
      rc=1
    fi
  }

  check_file "survey-doc-path未指定: メソッド呼び出し境界を試みずfallback.warning: true" \
    "$cs_out_none" '.detectionSummary.diagnostics.fallback.warning == true'
  check_file "survey-doc-path一致(Express明記): fallbackが解消しwarning: false" \
    "$cs_out_match" '.detectionSummary.diagnostics.fallback == {count:0, total:2, ratio:0, threshold:0.5, warning:false}'
  check_file "survey-doc-path不一致(FastAPI明記): fallbackが残りwarning: true" \
    "$cs_out_mismatch" '.detectionSummary.diagnostics.fallback.warning == true'

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

USAGE="Usage: extract-api-metadata.sh <api-manifest.json> <source-dir> <output.json> [--screen-manifest <json>] [--table-manifest <json>] [--survey-doc-path <md>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT="${3:?$USAGE}"
shift 3 || true

SCREEN_MANIFEST=""
TABLE_MANIFEST=""
SURVEY_DOC_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-manifest) SCREEN_MANIFEST="${2:-}"; shift 2 ;;
    --table-manifest)  TABLE_MANIFEST="${2:-}";  shift 2 ;;
    --survey-doc-path) SURVEY_DOC_PATH="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
# source される側では set -e / CLI ディスパッチが波及しないよう detect-encoding.sh 側で
# ガード済み(BASH_SOURCE[0] != $0 判定)。
_EXTRACT_API_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_API_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-api-metadata-scan.XXXXXX")"

# 調査書のルーティング方式記載がメソッドチェーン呼び出し系を明示している場合のみ、
# endpoint_block のメソッド呼び出し境界フォールバックを有効化する(opt-in。深い構文解析はしない)。
CALL_STYLE_BLOCK_ENABLED="false"
if [ -n "$SURVEY_DOC_PATH" ] && [ -f "$SURVEY_DOC_PATH" ]; then
  survey_scan_path="$(to_utf8_for_scan "$SURVEY_DOC_PATH" "$SCAN_WORKDIR")"
  if grep -A3 -iE 'ルーティング方式' "$survey_scan_path" 2>/dev/null \
    | grep -qiE 'Express|Fastify|Hono|メソッドチェーン|メソッド呼び出し'; then
    CALL_STYLE_BLOCK_ENABLED="true"
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
if [ -n "$SCREEN_MANIFEST" ] && [ ! -f "$SCREEN_MANIFEST" ]; then
  echo "ERROR: screen-manifest not found: $SCREEN_MANIFEST" >&2
  exit 1
fi
if [ -n "$TABLE_MANIFEST" ] && [ ! -f "$TABLE_MANIFEST" ]; then
  echo "ERROR: table-manifest not found: $TABLE_MANIFEST" >&2
  exit 1
fi

# sourceFile を絶対パスへ解決する(相対パスなら source-dir 起点)。解決できなければ空を返す
resolve_source_file() {
  local sf="$1"
  [ -z "$sf" ] && return 0
  if [ -f "$sf" ]; then
    printf '%s' "$sf"
  elif [ -f "$SOURCE_DIR/$sf" ]; then
    printf '%s' "$SOURCE_DIR/$sf"
  fi
}

# JS/TS のコメント・正規表現リテラルと、ルートpath以外の文字列を除去したコードだけを返す。
# 限定的な字句処理に留め、構文を解釈しない。判定不能なら抽出しないことで false-positive を避ける。
route_source_code() {
  awk '
    function route_open(s) {
      return s ~ /\.(get|post|put|patch|delete)[[:space:]]*\([[:space:]]*$/
    }
    function regex_open(s, i, c) {
      for (i = length(s); i >= 1; i--) {
        c = substr(s, i, 1)
        if (c !~ /[[:space:]]/) break
      }
      return i == 0 || c == "=" || c == "(" || c == ":" || c == "," || c == "[" || c == "!" || c == "&" || c == "|" || c == "?" || c == ";" || c == "{"
    }
    {
      text = $0 "\n"
      for (i = 1; i <= length(text); i++) {
        c = substr(text, i, 1)
        next_c = substr(text, i + 1, 1)
        if (state == "line_comment") {
          if (c == "\n") { state = "code"; out = out c }
          continue
        }
        if (state == "block_comment") {
          if (c == "*" && next_c == "/") { state = "code"; i++ }
          continue
        }
        if (state == "string") {
          if (escaped) { escaped = 0 }
          else if (c == "\\") { escaped = 1 }
          else if (c == quote) { state = "code" }
          continue
        }
        if (state == "route_string") {
          out = out c
          if (escaped) { escaped = 0 }
          else if (c == "\\") { escaped = 1 }
          else if (c == quote) { state = "code" }
          continue
        }
        if (state == "regex") {
          if (escaped) { escaped = 0 }
          else if (c == "\\") { escaped = 1 }
          else if (c == "[") { regex_class = 1 }
          else if (c == "]") { regex_class = 0 }
          else if (c == "/" && !regex_class) { state = "code" }
          continue
        }
        if (c == "/" && next_c == "/") { state = "line_comment"; i++; continue }
        if (c == "/" && next_c == "*") { state = "block_comment"; i++; continue }
        if (c == "/" && regex_open(out)) { state = "regex"; regex_class = 0; continue }
        if (c == "#") { state = "line_comment"; continue }
        if (c == "\"" || c == "\047" || c == "`") {
          quote = c
          if (route_open(out)) { state = "route_string"; out = out c }
          else { state = "string" }
          continue
        }
        out = out c
      }
    }
    END { printf "%s", out }
  ' "$1"
}

# factory式の識別子を返す。対象は既知のframework factoryに限定する。
factory_identifier_from_expression() {
  case "$1" in
    express\(*|express.Router\(*) printf '%s' "express" ;;
    Fastify\(*) printf '%s' "Fastify" ;;
    fastify\(*) printf '%s' "fastify" ;;
    new\ Hono\(*) printf '%s' "Hono" ;;
  esac
}

# factory識別子の明示的な別値束縛、関数/class宣言、または引数shadowingを検出する。
# import文とrequire()による一般的な読込みは、factoryを別物へ置換する根拠ではないため許容する。
factory_identifier_is_unshadowed() {
  local compact="$1" factory="$2"
  awk -v text="$compact" -v factory="$factory" '
    function ident(c) { return c ~ /[A-Za-z0-9_$]/ }
    function keyword_before(pos, keyword, start, before) {
      start = pos - length(keyword)
      if (start < 1 || substr(text, start, length(keyword)) != keyword) return 0
      before = (start > 1 ? substr(text, start - 1, 1) : "")
      return start == 1 || !ident(before)
    }
    function token_in(s, token, n, i, before, after) {
      n = length(token)
      for (i = 1; i <= length(s) - n + 1; i++) {
        if (substr(s, i, n) != token) continue
        before = (i > 1 ? substr(s, i - 1, 1) : "")
        after = (i + n <= length(s) ? substr(s, i + n, 1) : "")
        if (!ident(before) && !ident(after)) return 1
      }
      return 0
    }
    function parameters_shadow(open_pos, end_offset, close_pos, params) {
      end_offset = index(substr(text, open_pos + 1), ")")
      if (!end_offset) return 0
      close_pos = end_offset + open_pos
      params = substr(text, open_pos + 1, close_pos - open_pos - 1)
      return token_in(params, factory)
    }
    BEGIN {
      n = length(factory)
      rejected = 0
      for (i = 1; i <= length(text) - n + 1; i++) {
        if (substr(text, i, n) != factory) continue
        before = (i > 1 ? substr(text, i - 1, 1) : "")
        after_pos = i + n
        after = (after_pos <= length(text) ? substr(text, after_pos, 1) : "")
        suffix = substr(text, after_pos)
        declaration = keyword_before(i, "const") || keyword_before(i, "let") || keyword_before(i, "var")
        named_declaration = keyword_before(i, "function") || keyword_before(i, "class")
        if (declaration) {
          if (suffix !~ /^=require\(\)(\.[A-Za-z_$][A-Za-z0-9_$]*)?;/) rejected = 1
          i += n - 1
          continue
        }
        if (named_declaration) {
          rejected = 1
          i += n - 1
          continue
        }
        if (ident(before) || ident(after)) { i += n - 1; continue }
        i += n - 1
      }
      for (i = 1; i <= length(text); i++) {
        if (substr(text, i, 8) == "function" && (i == 1 || !ident(substr(text, i - 1, 1)))) {
          open = index(substr(text, i + 8), "(")
          if (open && parameters_shadow(i + 8 + open - 1)) rejected = 1
        }
        if (substr(text, i, 1) == "(" && parameters_shadow(i)) {
          close_offset = index(substr(text, i + 1), ")")
          if (close_offset && substr(text, i + close_offset + 1, 2) == "=>") rejected = 1
        }
      }
      exit rejected
    }
  '
}

# identifier に method が無い場合の独自ルート定義から、framework生成式へ静的に束縛され、
# factory識別子自身もshadowingされていないreceiver 名だけを返す。コメント・文字列は
# route_source_code で除外済みで、const/let/var の同一行代入以外は根拠にしない。
route_receivers_from_source() {
  local src="$1" route_source compact receiver factory_expr factory candidates
  route_source="$(route_source_code "$src")"
  compact="$(LC_ALL=C tr -d '[:space:]' <<<"$route_source")"
  candidates="$(printf '%s\n' "$route_source" | sed -nE \
    's/^[[:space:]]*(const|let|var)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*=[[:space:]]*(express\(\)|express\.Router\(\)|Fastify\(\)|fastify\(\)|new[[:space:]]+Hono\(\))[[:space:]]*;?[[:space:]]*$/\2 \3/p'
  )"
  while IFS=' ' read -r receiver factory_expr; do
    [ -n "$receiver" ] || continue
    factory="$(factory_identifier_from_expression "$factory_expr")"
    [ -n "$factory" ] || continue
    factory_identifier_is_unshadowed "$compact" "$factory" || continue
    receiver_all_uses_supported "$compact" "$receiver" && printf '%s\n' "$receiver"
  done <<< "$candidates"
}

# sanitized compact source内のreceiver tokenを全走査する。
# 唯一のsupported factory束縛とroute call以外の使用があれば、安全側にreceiver全体を棄却する。
# function/class の同名宣言は、内側か同一解析対象かを問わずreceiver全体を棄却する。
receiver_all_uses_supported() {
  local compact="$1" receiver="$2"
  awk -v text="$compact" -v receiver="$receiver" '
    function ident(c) { return c ~ /[A-Za-z0-9_$]/ }
    function factory_suffix(s) {
      return s ~ /^=(express\(\)|express\.Router\(\)|Fastify\(\)|fastify\(\)|newHono\(\))/
    }
    function route_suffix(s) { return s ~ /^\.(get|post|put|patch|delete)\(/ }
    function keyword_before(pos, keyword, start, before) {
      start = pos - length(keyword)
      if (start < 1 || substr(text, start, length(keyword)) != keyword) return 0
      before = (start > 1 ? substr(text, start - 1, 1) : "")
      return start == 1 || !ident(before)
    }
    BEGIN {
      factory_bindings = 0
      rejected = 0
      n = length(receiver)
      for (i = 1; i <= length(text) - n + 1; i++) {
        c = substr(text, i, 1)
        if (quote != "") {
          if (escaped) escaped = 0
          else if (c == "\\") escaped = 1
          else if (c == quote) quote = ""
          continue
        }
        if (c == "\"" || c == "\047" || c == "`") {
          quote = c
          continue
        }
        if (substr(text, i, n) != receiver) continue
        before = (i > 1 ? substr(text, i - 1, 1) : "")
        after_pos = i + n
        after_char = (after_pos <= length(text) ? substr(text, after_pos, 1) : "")
        suffix = substr(text, after_pos)
        declaration = keyword_before(i, "const") || keyword_before(i, "let") || keyword_before(i, "var")
        named_declaration = keyword_before(i, "function") || keyword_before(i, "class")
        binding = factory_suffix(suffix) && declaration
        if (binding) {
          factory_bindings++
          i += n - 1
          continue
        }
        if (declaration) {
          rejected = 1
          i += n - 1
          continue
        }
        if (named_declaration) {
          rejected = 1
          i += n - 1
          continue
        }
        if (ident(before) || ident(after_char)) {
          i += n - 1
          continue
        }
        if (before != "." && route_suffix(suffix)) {
          i += n - 1
          continue
        }
        rejected = 1
        i += n - 1
      }
      exit !(factory_bindings == 1 && rejected == 0)
    }
  '
}

# receiver は route_receivers_from_source で得た生成式への束縛に限定し、path を第1引数に取る
# 一意の HTTP method だけを返す。送信側クライアントや未束縛識別子は採用しない。
route_method_from_source() {
  local src="$1" path="$2"
  local route_source compact receivers candidates="" receiver candidate lower quote pattern
  [ -z "$path" ] && return 0
  route_source="$(route_source_code "$src")"
  receivers="$(route_receivers_from_source "$src")"
  [ -z "$receivers" ] && return 0
  compact="$(LC_ALL=C tr -d '[:space:]' <<<"$route_source")"
  while IFS= read -r receiver; do
    [ -z "$receiver" ] && continue
    for candidate in GET POST PUT PATCH DELETE; do
      lower="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')"
      for quote in '"' "'" '`'; do
        pattern="${receiver}.${lower}(${quote}${path}${quote},"
        if fixed_call_has_receiver_boundary "$compact" "$pattern"; then
          candidates="${candidates:+$candidates }$candidate"
          break
        fi
      done
    done
  done <<< "$receivers"
  candidates="$(printf '%s\n' "$candidates" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  case "$candidates" in
    GET|POST|PUT|PATCH|DELETE) printf '%s' "$candidates" ;;
  esac
}

# 固定文字列callの直前が識別子・プロパティ継続文字ならreceiver接尾辞衝突として除外する。
fixed_call_has_receiver_boundary() {
  local text="$1" needle="$2"
  awk -v text="$text" -v needle="$needle" 'BEGIN {
    while ((pos = index(text, needle)) > 0) {
      before = (pos > 1 ? substr(text, pos - 1, 1) : "")
      if (pos == 1 || before !~ /[A-Za-z0-9_$.]/) exit 0
      text = substr(text, pos + 1)
    }
    exit 1
  }'
}

# identifier のパス部を sourceFile 内で grep -nF し、最初のヒット行の前3行〜後20行を出力する。
# ヒットしない場合は何も出力しない(endpoint_block が取れない場合のフォールバック専用)
endpoint_window() {
  local src="$1" path="$2"
  local line start
  [ -z "$path" ] && return 0
  line="$(grep -nF -- "$path" "$src" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  [ -z "$line" ] && return 0
  start=$(( line > 3 ? line - 3 : 1 ))
  sed -n "${start},$((line + 20))p" "$src"
}

# 当該エンドポイントの関数ブロックを出力する。
# 開始行 = method(小文字)+path に合致するルートデコレータ行(path は閉じ引用符付きの固定文字列で
# 突合し、"/api/posts" が "/api/posts/{id}" のデコレータへ前方一致ヒットする誤帰属を防ぐ)。
# 終了行 = 次のデコレータ行の直前、またはファイル末尾。
# 特定できない場合は何も出力せず exit 1(呼び出し側でファイル単位へフォールバック)
endpoint_block() {
  local src="$1" path="$2" method="$3"
  [ -z "$path" ] && return 1
  awk -v path="$path" -v method="$method" '
    function is_decorator(l) { return l ~ /^[[:space:]]*@[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\(/ }
    { lines[NR] = $0 }
    END {
      lm = tolower(method)
      start = 0
      for (i = 1; i <= NR; i++) {
        if (!is_decorator(lines[i])) continue
        if (index(lines[i], path "\"") == 0 && index(lines[i], path "\x27") == 0) continue
        if (lm != "" && index(tolower(lines[i]), lm "(") == 0) continue
        start = i; break
      }
      if (start == 0) exit 1
      for (i = start; i <= NR; i++) {
        if (i > start && is_decorator(lines[i])) exit 0
        print lines[i]
      }
    }
  ' "$src"
}

# メソッド呼び出し境界(第2の手がかり。CALL_STYLE_BLOCK_ENABLED=trueのときのみ呼び出し側が使う):
# 開始行 = identifier のパス部を含む最初の行(endpoint_windowと同じgrep -nFで特定)。
# 終了行 = それ以降で最初に .get(/.post(/.put(/.patch(/.delete( のいずれかを含む行の直前、または
# ファイル末尾。デコレータが無いメソッドチェーン方式ルーティング専用のフォールバック。
endpoint_block_call_style() {
  local src="$1" path="$2"
  local start_line end_line total
  [ -z "$path" ] && return 1
  start_line="$(grep -nF -- "$path" "$src" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  [ -z "$start_line" ] && return 1
  total="$(wc -l < "$src" | tr -d ' ')"
  end_line="$(grep -nE '\.(get|post|put|patch|delete)[[:space:]]*\(' "$src" 2>/dev/null \
    | awk -F: -v s="$start_line" '$1 > s { print $1; exit }')"
  if [ -z "$end_line" ]; then
    end_line=$((total + 1))
  fi
  sed -n "${start_line},$((end_line - 1))p" "$src"
}

patches_jsonl="$(mktemp "${TMPDIR:-/tmp}/extract-api-patches.XXXXXX")"
patches_json="$(mktemp "${TMPDIR:-/tmp}/extract-api-patches-arr.XXXXXX")"
trap 'rm -f "$patches_jsonl" "$patches_json"; rm -rf "$SCAN_WORKDIR"' EXIT

fallback_count=0
total_count=0
while IFS= read -r row; do
  [ -z "$row" ] && continue
  total_count=$((total_count + 1))
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  source_file_raw="$(jq -r '.sourceFile // ""' <<<"$row")"
  src_file="$(resolve_source_file "$source_file_raw")"
  # scan_file: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。src_file自体は出力に使う
  # パスのため変更しない。走査(grep/awk/sed)には常にscan_fileを使う
  scan_file=""
  [ -n "$src_file" ] && scan_file="$(to_utf8_for_scan "$src_file" "$SCAN_WORKDIR")"

  # --- 1. method: identifier の先頭語 ---
  method=""
  api_path="$identifier"
  head_word="${identifier%% *}"
  case "$head_word" in
    GET|POST|PUT|PATCH|DELETE)
      method="$head_word"
      api_path="${identifier#* }"
      ;;
  esac
  if [ -z "$method" ] && [ -n "$scan_file" ]; then
    method="$(route_method_from_source "$scan_file" "$api_path")"
  fi

  # --- 検査範囲の決定: 関数ブロック(正)→ 近傍窓(フォールバック) ---
  # block が取れた場合は authRequired / targetTables / ioSummary をブロック内に限定する
  # (同一ファイル内の別エンドポイントの認証・テーブル参照の誤帰属防止)
  block=""
  window=""
  if [ -n "$scan_file" ]; then
    block="$(endpoint_block "$scan_file" "$api_path" "$method" || true)"
    if [ -z "$block" ] && [ "$CALL_STYLE_BLOCK_ENABLED" = "true" ]; then
      block="$(endpoint_block_call_style "$scan_file" "$api_path" || true)"
    fi
    if [ -z "$block" ]; then
      echo "WARN: 関数ブロックを特定できないため従来のファイル単位検査にフォールバック: ${identifier} (${src_file})" >&2
      window="$(endpoint_window "$scan_file" "$api_path" || true)"
    fi
  fi
  if [ -z "$block" ]; then
    fallback_count=$((fallback_count + 1))
  fi
  scan="${block:-$window}"

  # --- 2. authRequired: 検査範囲内の認証/認証除外パターン ---
  auth=""
  if [ -n "$scan" ]; then
    if printf '%s\n' "$scan" | grep -qE -- "$AUTH_POSITIVE_ERE"; then
      auth="true"
    elif printf '%s\n' "$scan" | grep -qE -- "$AUTH_NEGATIVE_ERE"; then
      auth="false"
    fi
  fi

  # --- 3. callers: 拡張画面マニフェストの relatedApis 逆引き ---
  callers_json="[]"
  if [ -n "$SCREEN_MANIFEST" ]; then
    callers_json="$(jq -c \
      --arg uk "$unit_key" --arg ident "$identifier" --arg path "$api_path" \
      '[ (.screens // .units // [])[]
         | select((.relatedApis // []) | any(. == $uk or . == $ident or . == $path))
         | .screenKey // empty ]' "$SCREEN_MANIFEST")"
  fi

  # --- 4. targetTables: テーブル物理名の grep(関数ブロック内。フォールバック時はファイル全体) ---
  tables_json="[]"
  if [ -n "$TABLE_MANIFEST" ] && [ -n "$scan_file" ]; then
    while IFS= read -r trow; do
      [ -z "$trow" ] && continue
      t_key="$(jq -r '.unitKey // ""' <<<"$trow")"
      t_ident="$(jq -r '.identifier // ""' <<<"$trow")"
      if [ -z "$t_key" ] || [ -z "$t_ident" ]; then
        continue
      fi
      if [ -n "$block" ]; then
        printf '%s\n' "$block" | grep -qwF -- "$t_ident" || continue
      else
        grep -qwF -- "$t_ident" "$scan_file" 2>/dev/null || continue
      fi
      tables_json="$(jq -c --arg k "$t_key" '. + [$k]' <<<"$tables_json")"
    done < <(jq -c '(.units // [])[] | select(.kind != "unresolved")' "$TABLE_MANIFEST")
  fi

  # --- 5. ioSummary: 検査範囲内のレスポンス/リクエストモデル名 ---
  io_summary=""
  if [ -n "$scan" ]; then
    resp="$(printf '%s\n' "$scan" \
      | sed -nE 's/.*response_model *= *([A-Za-z_][A-Za-z0-9_]*).*/\1/p' | head -1)"
    if [ -z "$resp" ]; then
      resp="$(printf '%s\n' "$scan" \
        | sed -nE 's/.*\) *: *Promise<([A-Za-z_][A-Za-z0-9_]*)>.*/\1/p' | head -1)"
    fi
    if [ -n "$resp" ]; then
      req="$(printf '%s\n' "$scan" \
        | sed -nE 's/.*: *([A-Z][A-Za-z0-9_]*(Create|Update|Request|Input|Payload|Body|Form|Schema))([^A-Za-z0-9_].*)?$/\1/p' | head -1)"
      io_summary="${req:-なし} → ${resp}"
    fi
  fi

  # --- 抽出できたフィールドだけを持つ patch オブジェクトを 1 行追記 ---
  jq -nc \
    --arg method "$method" --arg auth "$auth" --arg io "$io_summary" \
    --argjson callers "$callers_json" --argjson tables "$tables_json" \
    '{}
     + (if $method != "" then {method: $method} else {} end)
     + (if $auth == "true" then {authRequired: true} elif $auth == "false" then {authRequired: false} else {} end)
     + (if ($callers | length) > 0 then {callers: $callers} else {} end)
     + (if ($tables | length) > 0 then {targetTables: $tables} else {} end)
     + (if $io != "" then {ioSummary: $io} else {} end)' >> "$patches_jsonl"
done < <(jq -c '(.units // [])[]' "$MANIFEST")

jq -s '.' "$patches_jsonl" > "$patches_json"

mkdir -p "$(dirname "$OUTPUT")"

# フォールバック率(検出できなかった事実の記録。1-130): 関数ブロックを特定できずファイル単位・
# 近傍窓へフォールバックしたユニット数/全体数。ratio > 0.5 で warning。ゼロ除算はratio=0・warning=falseにする
fallback_diagnostics_json="$(jq -n \
  --argjson count "$fallback_count" --argjson total "$total_count" --argjson threshold 0.5 \
  '{count: $count, total: $total,
    ratio: (if $total > 0 then ($count / $total) else 0 end),
    threshold: $threshold,
    warning: (if $total > 0 then (($count / $total) > $threshold) else false end)}')"

# 既存フィールドは patch より優先する((patch + 原本) の合成順で原本値が常に勝つ)
jq --slurpfile P "$patches_json" --argjson fb "$fallback_diagnostics_json" \
  '.units = ([(.units // []), $P[0]] | transpose | map(((.[1]) // {}) + .[0]))
   | .detectionSummary.diagnostics.fallback = $fb' \
  "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
