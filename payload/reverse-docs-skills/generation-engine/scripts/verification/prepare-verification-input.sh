#!/usr/bin/env bash
# prepare-verification-input.sh — 疑似入力の設計文書を検証用に整備する
#
# 目的: delivery-payload/templates/リバース検証/ 配下の雛形37件は scaffold-screen.sh /
# scaffold-design-unit.sh が複製元とする雛形であり、frontmatter に未置換のプレースホルダを
# 持つ。これを portal-input/build-manifests-from-docs.sh へそのまま与えると、プレースホルダの
# 文字列が一覧の値として載ってしまう。本スクリプトは雛形を出力先ディレクトリへ複製し、
# frontmatter のプレースホルダ（および frontmatter の識別子語を再掲する見出し行）を検証用の
# 固定値で埋めた設計文書を配置する。
#
# 対象範囲（スコープ判断）: 置換対象は frontmatter と、frontmatter の識別子語をそのまま
# 見出しに再掲する行（例: `# <REPORTNAME> 帳票基本設計書`）に限る。本文中の自由記述プレース
# ホルダ（`<実測: 実行コマンド>` 等、実際にコードを読んで埋める前提の項目）は対象外とする。
# 理由: build-manifests-from-docs.sh は frontmatter しか読まない（extract_frontmatter_value）。
# 本文の自由記述プレースホルダは何百通りもあり、機械的に「意味の分かる」値を割り当てる根拠が
# 無い。frontmatter とその直接反映箇所だけを対象にすることで、検証パイプラインの実際の消費者
# （build-manifests-from-docs.sh）が必要とする範囲に限定して確実に埋める。
#
# Usage:
#   prepare-verification-input.sh --output <出力先ディレクトリ> [--repo <リポジトリのパス>]
#   prepare-verification-input.sh --self-test
#
#   --output   雛形を複製・置換して配置する先。build-manifests-from-docs.sh の
#              <output_dir> 引数としてそのまま渡せる構造で配置する。
#   --repo     このリポジトリ（reverse-docs-skills）のパス。省略時は本スクリプト自身の
#              位置から解決したリポジトリルートを使う。
#   --self-test  一時ディレクトリで検査を行い、雛形には一切書き込まない。
#
# 配置構造:
#   API/テーブル/バッチ/帳票/外部連携: <kind>UnitRoot/<kind>-<key>/{基本設計,詳細設計}/<file>
#     （scaffold-design-unit.sh と同じ命名規則。design-unit-layout.json の phases に従う）
#   機能: featureUnitRoot/feature-<key>/基本設計/<同名ファイル>（detail は持たない）
#   画面: screenUnitRoot/screen-<key>/{基本設計,詳細設計,テスト設計}/<file>
#     （画面は doc-extraction.json の対象外だが、実際のスキルが生成する構造に合わせる）
#   プロジェクト共通: commonRoot/<同名ファイル>（フラット）
#
# 識別子の決め方: 各種別につき、対応する疑似コード一覧（generation-engine/samples/source/
# <種別英語キー>/）を再帰列挙し、相対パスを辞書順ソートして先頭の1件を代表として選ぶ
# （決定的・冪等）。識別子キーはそのファイル名から機械的に導出する（拡張子除去 → 先頭の
# 連番プレフィックスと "create_" 接頭辞を除去。テーブルのマイグレーションファイル名
# 001_create_users.sql → users のみに作用し、他種別は無変化）。source_ref はその疑似コードの
# 相対パスをそのまま入れる。
#
# 日付は固定値 2026-01-01 を使う（現在時刻を使うと再現性判定と衝突するため）。
#
# 保守責任者: 人手（ユーザー）。雛形にフィールドを追加・変更した場合は、本ファイルの
# fill_* 関数と ALLCAPS_TOKENS / BRACKET_TOKENS（self-test 用）を同時に更新する。
# macOS bash 3.2 互換（連想配列を使わない。添字配列のみ使用）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

REPO_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXED_DATE="2026-01-01"
DUMMY_COMMIT="0000000000000000000000000000000000000000"

usage() {
  cat <<'EOF'
Usage:
  prepare-verification-input.sh --output <出力先ディレクトリ> [--repo <リポジトリのパス>]
  prepare-verification-input.sh --self-test
EOF
}

# ---- token置換ヘルパー ----
# ファイル内の全出現箇所を置換する。token は正規表現メタ文字を含まない前提
# （本スクリプトが扱う token はすべて英数字・山括弧・コロン・ハイフンのみ）。
replace_token() {
  local file="$1" token="$2" value="$3"
  local esc_value
  esc_value="$(printf '%s' "$value" | sed -e 's/[\&|]/\\&/g')"
  sed -i.bak "s|${token}|${esc_value}|g" "$file"
  rm -f "${file}.bak"
}

fill_dates() {
  local file="$1"
  # より具体的なパターンを先に処理する（<実測: YYYY-MM-DD> は <YYYY-MM-DD> を包含しない
  # 別文字列だが、意図を明確にするため長い方から処理する）。
  replace_token "$file" '<実測: YYYY-MM-DD>' "$FIXED_DATE"
  replace_token "$file" '<YYYY-MM-DD>' "$FIXED_DATE"
}

# ---- 関連図(状態遷移図・ER図・画面遷移図)の材料を埋めるヘルパー ----
# 配る雛形（delivery-payload/templates/リバース検証/）には触れず、複製後のファイル
# （destfile）へ、疑似入力であることが読んで分かる固定の行を1回だけ足す。
# 既存のプレースホルダ行（<実測: ...> を含む行）はそのまま残す（抽出器が捏造防止の
# ためこの行だけをスキップする設計を壊さないため。データ行の1つとして混ざっても、
# 抽出器の <実測 検出により当該行だけが無視されるので害はない）。
#
# marker を含む行の直後へ content（改行区切りの1行以上）を挿入する。marker は
# ファイル内で1箇所だけに一致する前提（雛形のプレースホルダ行はいずれも1回しか
# 出現しない列構成のため）。
#
# content を awk の -v へ直接渡さない理由: macOS/BSD awk は -v の値に生の改行文字が
# 含まれると「newline in string」で構文エラーになる（GNU awk は許容するが本スクリプトは
# macOS bash 3.2 互換を前提にしており BSD awk 依存を避けられない）。改行を含む content は
# 一時ファイルへ書き出し、marker 一致時に getline で読み込んで展開する。
insert_after_marker() {
  local file="$1" marker="$2" content="$3"
  local tmp="${file}.ins" content_file="${file}.content"
  printf '%s\n' "$content" > "$content_file"
  awk -v marker="$marker" -v content_file="$content_file" '
    { print }
    index($0, marker) > 0 {
      while ((getline line < content_file) > 0) print line
      close(content_file)
    }
  ' "$file" > "$tmp"
  rm -f "$content_file"
  mv "$tmp" "$file"
}

# データ設計.md §6 状態遷移表（列: エンティティ|状態|遷移前|契機|遷移後。改善課題1-240で
# 根拠パス列が削除され現行5列）。「疑似検証エンティティ」が下書き→受付中→完了と遷移する
# 2行を足す（extract-entity-state-page-data.sh は 状態→遷移前→遷移後 の初出順でnodesを
# 集めるため、3節2辺になる）。marker は §1 データモデル概要のプレースホルダ行にも
# 現れる「<実測: エンティティ名>」ではなく、§6 の行にしか出現しない「遷移前の状態」を使う。
fill_state_transition_rows() {
  local f="$1"
  local rows
  rows='| 疑似検証エンティティ | 受付中 | 下書き | 疑似検証データの遷移1 | 受付中 |
| 疑似検証エンティティ | 完了 | 受付中 | 疑似検証データの遷移2 | 完了 |'
  insert_after_marker "$f" '遷移前の状態' "$rows"
}

# テーブル定義書.md §6.3 外部キー
# （列: カラム|参照先のテーブル|参照先のカラム|削除時の動作|関連の種別|出典参照）。
# このパイプラインでは代表テーブル1件しか展開されないため、参照先を自テーブル
# （$TABLE_KEY）自身にした自己参照FK行を1件足す（階層構造でよくある parent_id 相当。
# extract-er-page-data.sh の解決は table_key の一致だけを見ており自己参照を除外しない）。
fill_foreign_key_rows() {
  local f="$1"
  local row
  row="| 疑似検証FK | ${TABLE_KEY} | id | RESTRICT | 一対多 | \`疑似検証データ\` |"
  insert_after_marker "$f" '<実測: 外部キーカラム名>' "$row"
}

# 画面基本設計書.md §6 画面遷移の業務文脈
# （列: 遷移元画面|引き継ぐ業務情報|遷移先画面|引き渡す業務情報|遷移する業務上の契機）。
# このパイプラインでは代表画面1件しか展開されないため、遷移元・遷移先の両方を
# 「自画面」にした行を1件足す（同一画面内のタブ切替等で成立する自己遷移。
# extract-transition-page-data.sh の resolve() は「自画面」をownKey(自身の
# screenKey)へ直接解決するため、他画面のラベル一致を要さない）。
fill_screen_transition_rows() {
  local f="$1"
  local row
  row="| 自画面 | 疑似検証データ | 自画面 | 疑似検証データ | 疑似検証データの契機 |"
  insert_after_marker "$f" '<画面名または「なし（起点画面）」>' "$row"
}

fill_api() {
  local f="$1"
  replace_token "$f" '<API名>' "$API_KEY"
  replace_token "$f" "APIKEY" "$API_KEY"
  replace_token "$f" "APIID" "api-$API_KEY"
  replace_token "$f" "METHOD" "GET"
  replace_token "$f" "PATH" "/api/$API_KEY"
  replace_token "$f" "FEATUREKEY" "$FEATURE_KEY"
  replace_token "$f" "SOURCEREF" "$API_SRC"
}

fill_table() {
  local f="$1"
  replace_token "$f" '<TABLENAME>' "$TABLE_KEY"
  replace_token "$f" "TABLEKEY" "$TABLE_KEY"
  replace_token "$f" "TABLEID" "table-$TABLE_KEY"
  replace_token "$f" "TABLENAME" "$TABLE_KEY"
  replace_token "$f" "SOURCEREF" "$TABLE_SRC"
  replace_token "$f" "TABLESUBKIND" "table"
}

fill_batch() {
  local f="$1"
  replace_token "$f" '<BATCHNAME>' "$BATCH_KEY"
  replace_token "$f" "BATCHKEY" "$BATCH_KEY"
  replace_token "$f" "BATCHID" "batch-$BATCH_KEY"
  replace_token "$f" "BATCHNAME" "$BATCH_KEY"
  replace_token "$f" "SOURCEREF" "$BATCH_SRC"
  replace_token "$f" "BATCHTRIGGERTYPE" "scheduled"
}

fill_report() {
  local f="$1"
  replace_token "$f" '<REPORTNAME>' "$REPORT_KEY"
  replace_token "$f" "REPORTKEY" "$REPORT_KEY"
  replace_token "$f" "REPORTID" "report-$REPORT_KEY"
  replace_token "$f" "REPORTNAME" "$REPORT_KEY"
  replace_token "$f" "SOURCEREF" "$REPORT_SRC"
  replace_token "$f" "REPORTENGINE" "template"
}

fill_external() {
  local f="$1"
  replace_token "$f" '<EXTERNALNAME>' "$EXTERNAL_KEY"
  replace_token "$f" "EXTERNALKEY" "$EXTERNAL_KEY"
  replace_token "$f" "EXTERNALID" "external-$EXTERNAL_KEY"
  replace_token "$f" "EXTERNALNAME" "$EXTERNAL_KEY"
  replace_token "$f" "SOURCEREF" "$EXTERNAL_SRC"
  replace_token "$f" "EXTERNALDIRECTION" "client"
}

fill_feature() {
  local f="$1"
  replace_token "$f" '<機能名>' "$FEATURE_KEY"
  replace_token "$f" "FEATUREKEY" "$FEATURE_KEY"
  replace_token "$f" "FEATUREID" "feature-$FEATURE_KEY"
  replace_token "$f" "CATEGORY" "共通コンポーネント"
  replace_token "$f" "SOURCEREF" "$FEATURE_SRC"
}

fill_screen_common() {
  local f="$1"
  replace_token "$f" '<画面ID>' "$SCREEN_KEY"
  replace_token "$f" '<画面名>' "$SCREEN_KEY"
}

# ---- 画面一覧(screen-manifest.json)の組み立て ----
# 画面はdoc-extraction.jsonの対象外(frontmatterの体系がscreenKey/route/entryFileという
# 他種別と異なる体系であるため。doc-extraction.jsonの"excluded"節参照)であり、
# build-manifests-from-docs.shが組み立てる非画面6種別とは別に、本関数で組み立てる。
#
# 画面の検出(unit-list/detect-screens.sh)はソースコードのimport文をBFSで辿る走査方式で
# あり、このリポジトリ自身はアプリケーションコードを持たないため、疑似入力のままでは
# screens: [] のまま埋まらない。extract-transition-page-data.sh は画面基本設計書.mdの
# 置かれたディレクトリ名(screen-<画面ID>)をscreenIdとしてscreen-manifest.jsonのidMapへ
# 引き、screenKeyへ解決してから§6を読む。screen-manifest.jsonが空だとこの解決が
# §6を読む前に必ず失敗し、画面遷移図の経路が一度も試されない。
#
# 実在するかのような値を作らないため、kind=unresolved・confidence=lowとする
# (build-manifests-from-docs.shの非画面6種別と同じ慣例。導けない項目は捏造せず
# 代替値で埋めるという同ファイルの設計判断を踏襲する)。entryFile(原本コードのパス)は
# 疑似入力に対応する原本コードが無いため空文字のまま埋めない。screenType は
# validate-manifest.shの項目11(screenType-必須+値域)がkindを問わず全screensへ要求する
# 技術的な分類フィールド(業務上の実在を主張する値ではない)であり、固定値"list"を使う。
# generatedAtは他の日付項目と同じ理由(FIXED_DATE直上のコメント参照。現在時刻を使うと
# 冪等-2回一致のself-testと衝突する)で固定値を使う。
build_screen_manifest() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  jq -n \
    --arg generatedAt "${FIXED_DATE}T00:00:00Z" \
    --arg sourceDir "$SCREEN_ROOT" \
    --arg screenId "screen-$SCREEN_KEY" \
    --arg screenKey "$SCREEN_KEY" \
    --arg route "/$SCREEN_KEY" \
    --arg name "疑似検証画面" \
    '{
      generatedAt: $generatedAt,
      sourceDir: $sourceDir,
      strategy: { extractionMethod: "verification-fixture", approvedByUser: true, screenIdRegex: null },
      detectionSummary: { screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 1 },
      screens: [
        {
          screenId: $screenId,
          screenKey: $screenKey,
          kind: "unresolved",
          route: $route,
          entryFile: "",
          confidence: "low",
          screenType: "list",
          screenNameGuess: $name
        }
      ]
    }' > "$dest"
}

fill_screen_detail() {
  local f="$1"
  fill_screen_common "$f"
  replace_token "$f" "SOURCEREPOPATH" "."
  replace_token "$f" "SOURCECOMMIT" "$DUMMY_COMMIT"
  replace_token "$f" "SOURCEENCODING" "UTF-8"
  replace_token "$f" "SOURCELINEENDING" "LF"
  replace_token "$f" "SCREENTYPE" "single-page"
  replace_token "$f" "COMMONSPECVERSION" "1.0.0"
  # NOTREADYSELECTOR は READYSELECTOR を部分文字列として含むため、先に処理する。
  replace_token "$f" "NOTREADYSELECTOR" '[data-testid="loading"]'
  replace_token "$f" "READYSELECTOR" '[data-testid="root"]'
  replace_token "$f" "TABLESELECTOR" '[data-testid="list"]'
  replace_token "$f" "TEXTSELECTOR" '[data-testid="title"]'
  replace_token "$f" "MASKSELECTOR" '[data-testid="timestamp"]'
  replace_token "$f" "SCENARIONAME" "初期表示"
  replace_token "$f" "ROUTEPATH" "/$SCREEN_KEY"
  replace_token "$f" "QUERYKEY" "id"
  replace_token "$f" "QUERYVALUE" "1"
  replace_token "$f" "PARAMNAME" "id"
  replace_token "$f" "PARAMVALUE" "1"
}

# DESIGN.md（画面/プロジェクト共通の両方）の colors/typography/rounded/spacing に
# 繰り返し現れる "<実測値>" を、直前のラベル行込みで一意に固定値へ置換する。
fill_design_values() {
  local f="$1"
  # on-surface は surface を部分文字列として含むため、必ず先に処理する。
  sed -i.bak \
    -e 's/^  on-surface: "<実測値>"/  on-surface: "#1A1A1A"/' \
    -e 's/^  primary: "<実測値>"/  primary: "#1A73E8"/' \
    -e 's/^  surface: "<実測値>"/  surface: "#FFFFFF"/' \
    -e 's/^  error: "<実測値>"/  error: "#D93025"/' \
    -e 's/^  heading: "<実測値>"/  heading: "16px\/24px, 700"/' \
    -e 's/^  body: "<実測値>"/  body: "14px\/20px, 400"/' \
    -e 's/^  label: "<実測値>"/  label: "12px\/16px, 500"/' \
    -e 's/^rounded: "<実測値>"/rounded: "4px"/' \
    -e 's/^spacing: "<実測値>"/spacing: "8px"/' \
    "$f"
  rm -f "${f}.bak"
}

# ---- 識別子の機械的導出 ----

# ソートにロケール既定の照合順位ではなく LC_ALL=C（バイト単位・常に一意な順序）を使う理由:
# 実行環境の LANG/LC_ALL（ja_JP.UTF-8 等）によって辞書順ソートの結果が変わりうるため、
# 素直な形（ロケール指定なしの sort）は「先頭の1件を代表として選ぶ」（本関数）や
# hash_dir() のディレクトリ内容ハッシュの決定性を環境依存にしてしまう。この決定性は
# self_test() の「雛形-不変」ケース（TEMPLATE_ROOT のハッシュが実行前後で変わらないこと
# の検証）と、複数回実行での再現性（run-layer-full-pipeline.sh の第3層2回実行との整合）が
# 前提にしている。この理由は本関数と hash_dir()・run_prepare()・collect_frontmatter() の
# 4箇所すべてに共通する（同一の LC_ALL=C sort 使用箇所）。
# 環境依存: 依存する。開発機のロケール設定（例: C や en_US.UTF-8）でソート順が偶然
# ロケール非依存に見える場合があっても、それを理由に LC_ALL=C を外すな。
# 過去に消えて再発した経緯: 記録なし。
# ディレクトリ配下を再帰列挙し、相対パスを辞書順ソートして先頭を返す（決定的・冪等）。
first_fixture_relpath() {
  local dir="$1"
  find "$dir" -type f | sed "s#^${dir}/##" | LC_ALL=C sort | head -n 1
}

# ---- 疑似コードの配置 ----
# 設計文書の source_ref/sourceFile は各種別の疑似コード一覧（$FIXTURES_BASE/<種別英語キー>/
# 配下）の相対パスをそのまま使う（first_fixture_relpath）。この相対パスを
# 種別別抽出（extract-*-metadata.sh）が解決できるようにするには、抽出の起点
# （source-dir 引数）配下に同じ相対パスでファイルが実在する必要がある。
# ここでは種別ごとの fixtures ツリーを丸ごと
# ${output_dir}/verification-source/<種別英語キー>/ へ複製し、抽出の起点として使える
# 状態にする（呼び出し側は run-layer-full-pipeline.sh の resolve_extraction_source_dir）。
# fixtures は読み取り専用（generation-engine/samples/ を変更しない）。
# 画面(screen)は対象外: detect-screens.sh はディレクトリ規約からの検出方式であり、
# 疑似コードの寄せ集めを渡すと弱いフォールバック検出が発火し後続の一覧生成が
# validate-manifest.sh で拒否される（run-layer-full-pipeline.sh 側の判断と対になる）。
stage_fixture_code() {
  local output_dir="$1"
  local stage_root="$output_dir/verification-source"
  rm -rf "$stage_root"
  mkdir -p "$stage_root"
  local kind_en src dest
  for kind_en in api table batch report external feature; do
    src="$FIXTURES_BASE/$kind_en"
    dest="$stage_root/$kind_en"
    if [ -d "$src" ]; then
      mkdir -p "$dest"
      cp -R "$src/." "$dest/"
    fi
  done
}

# validate-manifest.shのsourceFile-実在検査は、マニフェストのsourceDirフィールド
# (例: docs/design/tables。設計文書ルート相対パス)と、resolve_base(.git祖先が
# 無ければマニフェスト自身の置き場所=dest_dirへフォールバックする)を組み合わせて
# sourceFileの絶対パスを解決する(詳細設計書「触ると壊れる箇所」節参照)。
# run-layer-full-pipeline.shはdest_dirを${output_dir}/docs/manifestsに固定して
# いるため、validate-manifest.shが実際に探すパスは
# ${output_dir}/docs/manifests/<unitRootRel>/<sourceFile>になる。
# stage_fixture_code()が置くverification-source/<kind_en>/は
# extract-*-metadata.shの走査起点であり別の目的を持つため削除せず、こちらへ
# 追加で同じ代表fixtureを複製する。validate-manifest.shの解決ロジック自体は
# 変更しない(実在検査を弱めない)。
# 環境依存: しない。過去に消えて再発した経緯: 記録なし(今回新設)。
stage_fixture_for_sourcefile_check() {
  local output_dir="$1" layout_json="$2"
  local manifests_dir="$output_dir/docs/manifests"
  local kind_en unit_root_rel src rel dest_file
  for kind_en in api table batch report external; do
    unit_root_rel="$(output_layout_get "$layout_json" "${kind_en}UnitRoot" 2>/dev/null)" || continue
    [ -z "$unit_root_rel" ] && continue
    src="$FIXTURES_BASE/$kind_en"
    [ -d "$src" ] || continue
    rel="$(first_fixture_relpath "$src")"
    [ -z "$rel" ] && continue
    dest_file="$manifests_dir/$unit_root_rel/$rel"
    mkdir -p "$(dirname "$dest_file")"
    cp "$src/$rel" "$dest_file"
  done
}

# ファイル名から拡張子・連番プレフィックス・"create_" 接頭辞を除いた識別子語を導く。
derive_key_from_relpath() {
  local relpath="$1" base
  base="$(basename "$relpath")"
  base="${base%.*}"
  base="$(printf '%s' "$base" | sed -E 's/^[0-9]+_//; s/^create_//')"
  printf '%s' "$base"
}

# ---- 配置先パスの決定 ----
dest_path_for() {
  local relpath="$1"
  case "$relpath" in
    "API/API基本設計書.md") printf '%s/api-%s/基本設計/API基本設計書.md' "$API_ROOT" "$API_KEY" ;;
    "API/APIテスト設計書.md") printf '%s/api-%s/%s/APIテスト設計書.md' "$API_ROOT" "$API_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "API/API単体テスト設計書.md") printf '%s/api-%s/%s/API単体テスト設計書.md' "$API_ROOT" "$API_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "API/API詳細設計書.md") printf '%s/api-%s/詳細設計/API詳細設計書.md' "$API_ROOT" "$API_KEY" ;;
    "テーブル/論理データモデル.md") printf '%s/table-%s/基本設計/論理データモデル.md' "$TABLE_ROOT" "$TABLE_KEY" ;;
    "テーブル/テーブルテスト設計書.md") printf '%s/table-%s/%s/テーブルテスト設計書.md' "$TABLE_ROOT" "$TABLE_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "テーブル/テーブル単体テスト設計書.md") printf '%s/table-%s/%s/テーブル単体テスト設計書.md' "$TABLE_ROOT" "$TABLE_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "テーブル/テーブル定義書.md") printf '%s/table-%s/詳細設計/テーブル定義書.md' "$TABLE_ROOT" "$TABLE_KEY" ;;
    "バッチ/バッチ基本設計書.md") printf '%s/batch-%s/基本設計/バッチ基本設計書.md' "$BATCH_ROOT" "$BATCH_KEY" ;;
    "バッチ/バッチテスト設計書.md") printf '%s/batch-%s/%s/バッチテスト設計書.md' "$BATCH_ROOT" "$BATCH_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "バッチ/バッチ単体テスト設計書.md") printf '%s/batch-%s/%s/バッチ単体テスト設計書.md' "$BATCH_ROOT" "$BATCH_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "バッチ/バッチ詳細設計書.md") printf '%s/batch-%s/詳細設計/バッチ詳細設計書.md' "$BATCH_ROOT" "$BATCH_KEY" ;;
    "帳票/帳票基本設計書.md") printf '%s/report-%s/基本設計/帳票基本設計書.md' "$REPORT_ROOT" "$REPORT_KEY" ;;
    "帳票/帳票テスト設計書.md") printf '%s/report-%s/%s/帳票テスト設計書.md' "$REPORT_ROOT" "$REPORT_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "帳票/帳票単体テスト設計書.md") printf '%s/report-%s/%s/帳票単体テスト設計書.md' "$REPORT_ROOT" "$REPORT_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "帳票/帳票詳細設計書.md") printf '%s/report-%s/詳細設計/帳票詳細設計書.md' "$REPORT_ROOT" "$REPORT_KEY" ;;
    "外部連携/外部連携基本設計書.md") printf '%s/external-%s/基本設計/外部連携基本設計書.md' "$EXTERNAL_ROOT" "$EXTERNAL_KEY" ;;
    "外部連携/外部連携テスト設計書.md") printf '%s/external-%s/%s/外部連携テスト設計書.md' "$EXTERNAL_ROOT" "$EXTERNAL_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "外部連携/外部連携単体テスト設計書.md") printf '%s/external-%s/%s/外部連携単体テスト設計書.md' "$EXTERNAL_ROOT" "$EXTERNAL_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "外部連携/外部連携詳細設計書.md") printf '%s/external-%s/詳細設計/外部連携詳細設計書.md' "$EXTERNAL_ROOT" "$EXTERNAL_KEY" ;;
    "機能/機能設計書.md") printf '%s/feature-%s/基本設計/機能設計書.md' "$FEATURE_ROOT" "$FEATURE_KEY" ;;
    "機能/機能テスト設計書.md") printf '%s/feature-%s/%s/機能テスト設計書.md' "$FEATURE_ROOT" "$FEATURE_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "機能/機能単体テスト設計書.md") printf '%s/feature-%s/%s/機能単体テスト設計書.md' "$FEATURE_ROOT" "$FEATURE_KEY" "$UNIT_TEST_DESIGN_DIR" ;;
    "画面/基本設計/画面基本設計書.md") printf '%s/screen-%s/基本設計/画面基本設計書.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/詳細設計/画面詳細設計書.md") printf '%s/screen-%s/詳細設計/画面詳細設計書.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/詳細設計/DESIGN.md") printf '%s/screen-%s/詳細設計/DESIGN.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/詳細設計/結合テスト観点表.md") printf '%s/screen-%s/詳細設計/結合テスト観点表.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/詳細設計/単体テスト観点表.md") printf '%s/screen-%s/詳細設計/単体テスト観点表.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/テスト設計/画面テスト設計書.md") printf '%s/screen-%s/テスト設計/画面テスト設計書.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/テスト設計/画面単体テスト設計書.md") printf '%s/screen-%s/テスト設計/画面単体テスト設計書.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "画面/テスト設計/操作シナリオ仕様書.md") printf '%s/screen-%s/テスト設計/操作シナリオ仕様書.md' "$SCREEN_ROOT" "$SCREEN_KEY" ;;
    "プロジェクト共通/DESIGN.md") printf '%s/DESIGN.md' "$COMMON_ROOT" ;;
    "プロジェクト共通/"*) printf '%s/%s' "$COMMON_ROOT" "$(basename "$relpath")" ;;
    *)
      echo "ERROR: 未知のテンプレートです（配置先マッピング未定義）: $relpath" >&2
      return 1
      ;;
  esac
}

# ---- 種別ごとの置換の振り分け ----
apply_kind_fill() {
  local relpath="$1" destfile="$2"
  case "$relpath" in
    API/*) fill_api "$destfile" ;;
    "テーブル/テーブル定義書.md") fill_table "$destfile"; fill_foreign_key_rows "$destfile" ;;
    テーブル/*) fill_table "$destfile" ;;
    バッチ/*) fill_batch "$destfile" ;;
    帳票/*) fill_report "$destfile" ;;
    外部連携/*) fill_external "$destfile" ;;
    機能/*) fill_feature "$destfile" ;;
    "画面/詳細設計/画面詳細設計書.md") fill_screen_detail "$destfile" ;;
    "画面/詳細設計/DESIGN.md") fill_screen_common "$destfile"; fill_design_values "$destfile" ;;
    "画面/基本設計/画面基本設計書.md") fill_screen_common "$destfile"; fill_screen_transition_rows "$destfile" ;;
    画面/*) fill_screen_common "$destfile" ;;
    "プロジェクト共通/DESIGN.md") fill_design_values "$destfile" ;;
    "プロジェクト共通/データ設計.md") fill_state_transition_rows "$destfile" ;;
    プロジェクト共通/*) : ;;
    *)
      echo "ERROR: 未知のテンプレートです（置換の振り分け未定義）: $relpath" >&2
      return 1
      ;;
  esac
}

# ---- メイン処理: 出力先へ複製・置換 ----
run_prepare() {
  local output_dir="$1"

  if [ ! -d "$TEMPLATE_ROOT" ]; then
    echo "ERROR: テンプレートが見つかりません: $TEMPLATE_ROOT" >&2
    return 1
  fi

  mkdir -p "$output_dir"

  local layout_json
  layout_json="$(resolve_output_layout "$output_dir")" || return 1

  API_ROOT="$(output_layout_get "$layout_json" apiUnitRoot)" || return 1
  TABLE_ROOT="$(output_layout_get "$layout_json" tableUnitRoot)" || return 1
  BATCH_ROOT="$(output_layout_get "$layout_json" batchUnitRoot)" || return 1
  REPORT_ROOT="$(output_layout_get "$layout_json" reportUnitRoot)" || return 1
  EXTERNAL_ROOT="$(output_layout_get "$layout_json" externalUnitRoot)" || return 1
  FEATURE_ROOT="$(output_layout_get "$layout_json" featureUnitRoot)" || return 1
  SCREEN_ROOT="$(output_layout_get "$layout_json" screenUnitRoot)" || return 1
  COMMON_ROOT="$(output_layout_get "$layout_json" commonRoot)" || return 1
  UNIT_TEST_DESIGN_DIR="$(output_layout_get "$layout_json" unitTestDesignDir)" || return 1

  API_SRC="$(first_fixture_relpath "$FIXTURES_BASE/api")"
  TABLE_SRC="$(first_fixture_relpath "$FIXTURES_BASE/table")"
  BATCH_SRC="$(first_fixture_relpath "$FIXTURES_BASE/batch")"
  REPORT_SRC="$(first_fixture_relpath "$FIXTURES_BASE/report")"
  EXTERNAL_SRC="$(first_fixture_relpath "$FIXTURES_BASE/external")"
  FEATURE_SRC="$(first_fixture_relpath "$FIXTURES_BASE/feature")"
  SCREEN_SRC="$(first_fixture_relpath "$FIXTURES_BASE/screen")"

  if [ -z "$API_SRC" ] || [ -z "$TABLE_SRC" ] || [ -z "$BATCH_SRC" ] || [ -z "$REPORT_SRC" ] \
    || [ -z "$EXTERNAL_SRC" ] || [ -z "$FEATURE_SRC" ] || [ -z "$SCREEN_SRC" ]; then
    echo "ERROR: 代表とする疑似コードが1件以上見つかりません: $FIXTURES_BASE" >&2
    return 1
  fi

  API_KEY="$(derive_key_from_relpath "$API_SRC")"
  TABLE_KEY="$(derive_key_from_relpath "$TABLE_SRC")"
  BATCH_KEY="$(derive_key_from_relpath "$BATCH_SRC")"
  REPORT_KEY="$(derive_key_from_relpath "$REPORT_SRC")"
  EXTERNAL_KEY="$(derive_key_from_relpath "$EXTERNAL_SRC")"
  FEATURE_KEY="$(derive_key_from_relpath "$FEATURE_SRC")"
  SCREEN_KEY="$(derive_key_from_relpath "$SCREEN_SRC")"

  local file relpath dest
  while IFS= read -r file; do
    relpath="${file#"$TEMPLATE_ROOT"/}"
    dest="$(dest_path_for "$relpath")" || return 1
    mkdir -p "$output_dir/$(dirname "$dest")"
    cp "$file" "$output_dir/$dest"
    fill_dates "$output_dir/$dest"
    apply_kind_fill "$relpath" "$output_dir/$dest" || return 1
  # LC_ALL=C sort の理由は first_fixture_relpath() 直上のコメント参照（ロケール非依存の決定的順序）。
  done < <(find "$TEMPLATE_ROOT" -type f -name '*.md' | LC_ALL=C sort)

  local screen_manifest_rel
  screen_manifest_rel="$(output_layout_get "$layout_json" screenManifest)" || return 1
  build_screen_manifest "$output_dir/$screen_manifest_rel"

  stage_fixture_code "$output_dir"
  stage_fixture_for_sourcefile_check "$output_dir" "$layout_json"
}

# ---- self-test で残存を検査するプレースホルダの正本一覧 ----
# 検査は frontmatter（先頭の --- ... --- ブロック。DESIGN.md の colors/typography 等も
# この内側にある）に限定する。本文の自由記述プレースホルダは本スクリプトの対象外であり
# （ファイル冒頭のスコープ判断コメントを参照）、frontmatter の識別子語と偶然同じ表記
# （例: 画面詳細設計書.md 本文の "METHOD" 列、画面基本設計書.md 本文の "<機能名>" 列）が
# 本文に残っていても、それは本スクリプトが埋める対象ではないため誤検知として扱わない。
ALLCAPS_TOKENS="APIKEY APIID METHOD PATH FEATUREKEY SOURCEREF TABLEKEY TABLEID TABLENAME BATCHKEY BATCHID BATCHNAME REPORTKEY REPORTID REPORTNAME EXTERNALKEY EXTERNALID EXTERNALNAME FEATUREID CATEGORY SOURCEREPOPATH SOURCECOMMIT SOURCEENCODING SOURCELINEENDING SCREENTYPE COMMONSPECVERSION SCENARIONAME ROUTEPATH QUERYKEY QUERYVALUE PARAMNAME PARAMVALUE READYSELECTOR NOTREADYSELECTOR TABLESELECTOR TEXTSELECTOR MASKSELECTOR TABLESUBKIND BATCHTRIGGERTYPE REPORTENGINE EXTERNALDIRECTION"

# LC_ALL=C sort の理由は first_fixture_relpath() 直上のコメント参照
# （ロケール非依存の決定的順序。ここではハッシュ入力の並び順を固定するために使う）。
hash_dir() {
  find "$1" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

# 先頭の --- ... --- ブロック（frontmatter）だけを取り出す。
# build-manifests-from-docs.sh の extract_frontmatter_value と同じ区切り判定を使う。
frontmatter_of() {
  awk '
    BEGIN { delim = 0 }
    /^---[ \t]*$/ {
      delim++
      print
      if (delim == 2) { exit }
      next
    }
    { print }
  ' "$1"
}

# 出力先配下の全 .md ファイルの frontmatter を1ファイルへ連結する。
collect_frontmatter() {
  local dir="$1" dest="$2" f
  : > "$dest"
  while IFS= read -r f; do
    frontmatter_of "$f" >> "$dest"
    printf '\n' >> "$dest"
  # LC_ALL=C sort の理由は first_fixture_relpath() 直上のコメント参照（ロケール非依存の決定的順序）。
  done < <(find "$dir" -type f -name '*.md' | LC_ALL=C sort)
}

self_test() {
  local tmp pass=0 fail=0 total=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/prepare-verification-input-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local hash_before hash_after_run1 hash_after_run2
  hash_before="$(hash_dir "$TEMPLATE_ROOT")"

  local out1="$tmp/out1"
  local run_output run_rc
  run_output="$(run_prepare "$out1" 2>&1)"
  run_rc=$?

  # ケース: 複製-件数一致
  total=$((total + 1))
  local tmpl_count out_count
  tmpl_count="$(find "$TEMPLATE_ROOT" -type f -name '*.md' | wc -l | tr -d ' ')"
  out_count="$(find "$out1" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$run_rc" -eq 0 ] && [ "$tmpl_count" = "$out_count" ] && [ "$tmpl_count" -gt 0 ]; then
    echo "[PASS] 複製-件数一致 — 雛形 ${tmpl_count} 件 / 出力 ${out_count} 件"
    pass=$((pass + 1))
  else
    echo "[FAIL] 複製-件数一致 — 雛形 ${tmpl_count} 件 / 出力 ${out_count} 件 / 実行終了コード ${run_rc}"
    echo "$run_output" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  local frontmatter_all="$tmp/frontmatter-all.txt"
  collect_frontmatter "$out1" "$frontmatter_all"

  # ケース: 置換-大文字残存なし（frontmatter 限定。スコープ判断は ALLCAPS_TOKENS 直上のコメント参照）
  total=$((total + 1))
  local hit token hits=""
  hit=0
  for token in $ALLCAPS_TOKENS; do
    if grep -qF -- "$token" "$frontmatter_all" 2>/dev/null; then
      hit=1
      hits="${hits} ${token}"
    fi
  done
  if [ "$hit" -eq 0 ]; then
    echo "[PASS] 置換-大文字残存なし — 検査対象 $(echo "$ALLCAPS_TOKENS" | wc -w | tr -d ' ') トークンすべて置換済み（frontmatter限定）"
    pass=$((pass + 1))
  else
    echo "[FAIL] 置換-大文字残存なし — 残存トークン:${hits}"
    fail=$((fail + 1))
  fi

  # ケース: 置換-山括弧残存なし（frontmatter 限定）
  total=$((total + 1))
  local bracket_hit=0 bracket_hits=""
  for token in '<YYYY-MM-DD>' '<実測: YYYY-MM-DD>' '<画面ID>' '<画面名>' '<実測値>' '<API名>' '<機能名>' '<BATCHNAME>' '<REPORTNAME>' '<EXTERNALNAME>' '<TABLENAME>'; do
    if grep -qF -- "$token" "$frontmatter_all" 2>/dev/null; then
      bracket_hit=1
      bracket_hits="${bracket_hits} [${token}]"
    fi
  done
  if [ "$bracket_hit" -eq 0 ]; then
    echo "[PASS] 置換-山括弧残存なし — 検査対象の山括弧プレースホルダはすべて置換済み"
    pass=$((pass + 1))
  else
    echo "[FAIL] 置換-山括弧残存なし — 残存トークン:${bracket_hits}"
    fail=$((fail + 1))
  fi

  # ケース: 日付-固定
  total=$((total + 1))
  local date_count
  date_count="$(grep -rlF -- "$FIXED_DATE" "$out1" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$date_count" -gt 0 ]; then
    echo "[PASS] 日付-固定 — ${FIXED_DATE} を含むファイル ${date_count} 件"
    pass=$((pass + 1))
  else
    echo "[FAIL] 日付-固定 — ${FIXED_DATE} を含むファイルが0件"
    fail=$((fail + 1))
  fi

  # 以下3ケースの対象ファイルは find で探す（run_prepare はコマンド置換
  # `run_output="$(run_prepare ...)"` 経由で呼ばれておりサブシェル内で実行される
  # ため、内部で代入する TABLE_ROOT/SCREEN_ROOT/COMMON_ROOT/TABLE_KEY/SCREEN_KEY
  # は呼び出し元の self_test() には残らない。パス自体を再導出せず find で
  # 実体を探すことで、この非公開の実装詳細に依存しない検査にする）。

  # ケース: 関連図材料-状態遷移表
  total=$((total + 1))
  local state_transition_file state_transition_count
  state_transition_file="$(find "$out1" -name 'データ設計.md' | head -n 1)"
  state_transition_count="$(grep -cF '疑似検証エンティティ' "$state_transition_file" 2>/dev/null)"
  if [ -n "$state_transition_file" ] && [ "$state_transition_count" = "2" ]; then
    echo "[PASS] 関連図材料-状態遷移表 — §6に疑似検証行2件を確認"
    pass=$((pass + 1))
  else
    echo "[FAIL] 関連図材料-状態遷移表 — 疑似検証行の件数が2件ではない（実際: ${state_transition_count}件, ファイル: ${state_transition_file:-見つからない}）"
    fail=$((fail + 1))
  fi

  # ケース: 関連図材料-外部キー
  total=$((total + 1))
  local fk_file fk_count
  fk_file="$(find "$out1" -path '*/詳細設計/テーブル定義書.md' | head -n 1)"
  fk_count="$(grep -cF '疑似検証FK' "$fk_file" 2>/dev/null)"
  if [ -n "$fk_file" ] && [ "$fk_count" = "1" ]; then
    echo "[PASS] 関連図材料-外部キー — §6.3に自己参照FK行1件を確認"
    pass=$((pass + 1))
  else
    echo "[FAIL] 関連図材料-外部キー — 疑似検証行の件数が1件ではない（実際: ${fk_count}件, ファイル: ${fk_file:-見つからない}）"
    fail=$((fail + 1))
  fi

  # ケース: 関連図材料-画面遷移
  total=$((total + 1))
  local transition_file transition_count
  transition_file="$(find "$out1" -path '*/基本設計/画面基本設計書.md' | head -n 1)"
  transition_count="$(grep -cF '自画面 | 疑似検証データ | 自画面' "$transition_file" 2>/dev/null)"
  if [ -n "$transition_file" ] && [ "$transition_count" = "1" ]; then
    echo "[PASS] 関連図材料-画面遷移 — §6に自画面遷移行1件を確認"
    pass=$((pass + 1))
  else
    echo "[FAIL] 関連図材料-画面遷移 — 疑似検証行の件数が1件ではない（実際: ${transition_count}件, ファイル: ${transition_file:-見つからない}）"
    fail=$((fail + 1))
  fi

  # ケース: 画面一覧-件数一致
  total=$((total + 1))
  local screen_manifest_file screen_count
  screen_manifest_file="$(find "$out1" -name 'screen-manifest.json' | head -n 1)"
  screen_count="$(jq -r '.screens | length' "$screen_manifest_file" 2>/dev/null)"
  if [ -n "$screen_manifest_file" ] && [ "$screen_count" = "1" ]; then
    echo "[PASS] 画面一覧-件数一致 — screen-manifest.jsonに画面1件を確認"
    pass=$((pass + 1))
  else
    echo "[FAIL] 画面一覧-件数一致 — 画面の件数が1件ではない（実際: ${screen_count}件, ファイル: ${screen_manifest_file:-見つからない}）"
    fail=$((fail + 1))
  fi

  # ケース: 画面一覧-validate通過
  total=$((total + 1))
  local screen_validate_output screen_validate_rc
  screen_validate_output="$(bash "$SCRIPT_DIR/../unit-list/validate-manifest.sh" "$screen_manifest_file" --unit-kind screen 2>&1)"
  screen_validate_rc=$?
  if [ "$screen_validate_rc" -eq 0 ]; then
    echo "[PASS] 画面一覧-validate通過 — validate-manifest.sh --unit-kind screen が全項目PASS"
    pass=$((pass + 1))
  else
    echo "[FAIL] 画面一覧-validate通過 — validate-manifest.shが不合格"
    echo "$screen_validate_output" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  # ケース: 雛形-不変
  total=$((total + 1))
  hash_after_run1="$(hash_dir "$TEMPLATE_ROOT")"
  if [ "$hash_before" = "$hash_after_run1" ]; then
    echo "[PASS] 雛形-不変 — 実行前後で雛形のハッシュが一致"
    pass=$((pass + 1))
  else
    echo "[FAIL] 雛形-不変 — 実行前後で雛形のハッシュが不一致（雛形が変更された可能性）"
    fail=$((fail + 1))
  fi

  # ケース: 冪等-2回一致
  total=$((total + 1))
  hash_after_run1="$(hash_dir "$out1")"
  local run2_output run2_rc
  run2_output="$(run_prepare "$out1" 2>&1)"
  run2_rc=$?
  hash_after_run2="$(hash_dir "$out1")"
  if [ "$run2_rc" -eq 0 ] && [ "$hash_after_run1" = "$hash_after_run2" ]; then
    echo "[PASS] 冪等-2回一致 — 同一出力先へ2回実行しても内容が一致"
    pass=$((pass + 1))
  else
    echo "[FAIL] 冪等-2回一致 — 2回目の実行終了コード ${run2_rc} またはハッシュ不一致"
    echo "$run2_output" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  [ "$fail" -eq 0 ]
}

# ---- 引数解析 ----
OUTPUT_DIR=""
REPO_ROOT="$REPO_ROOT_DEFAULT"
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:?--output には出力先ディレクトリが必要です}"
      shift 2
      ;;
    --repo)
      REPO_ROOT="${2:?--repo にはリポジトリのパスが必要です}"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: 不明な引数です: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

TEMPLATE_ROOT="$REPO_ROOT/delivery-payload/templates/リバース検証"
FIXTURES_BASE="$REPO_ROOT/generation-engine/samples/source"

if [ "$SELF_TEST" -eq 1 ]; then
  if self_test; then
    exit 0
  else
    exit 1
  fi
fi

if [ -z "$OUTPUT_DIR" ]; then
  echo "ERROR: --output は必須です" >&2
  usage >&2
  exit 1
fi

run_prepare "$OUTPUT_DIR"
exit $?
