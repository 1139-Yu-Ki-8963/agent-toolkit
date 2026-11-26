# 機能の QA の報告: {TARGET}

| 項目 | 値 |
|---|---|
| 日付 / ブランチ / リビジョン | {日付 / ブランチ / コミットと作業ツリーの入力} |
| 呼び出し元 / 権限 / 深さ | {qa-only、qa、review、ship のどれか。許された書き込み。上限} |
| 面 / 範囲 | {API、CLI、ジョブ、ワーカー、webhook。変わった契約と隣の契約} |
| ランタイム / ネイティブの道具 | {バージョンと、リポジトリが対応しているコマンド} |
| fixture の持ち主 / 行き先 | {隔離したルート、ストア、下流の行き先} |
| Probe budget / guarded command time / stop reason | {CONFIGURED LIMIT / SUM OF CAPTURE durationMs / COMPLETE OR BOUND/BLOCKER} |

## 契約ごとの結果

| 契約と出どころ | プローブそのもの / 証拠 | 期待 → 観察 | 結果 |
|---|---|---|---|
| {契約、文書かテストかユーザーの出どころ} | {コマンドかリクエスト、証拠のパス} | {出力と、残る効果} | pass / fail / blocked / not run / inconclusive / not applicable (reason) |

この機能の節には、見た目のスコアは当てはまらない。両方の面を持つ報告では、
ブラウザの節のスコアと証拠を分けておき、両方の面の再現の証拠と回帰の baseline に
リンクする。両方のスコアや結果を合わせない。

## 見つけたこと

### ISSUE-NNN: {再現した欠陥か、準備の妨げ}

- 分類 / 重大度: {製品の欠陥 / 準備 / 決まらない。影響}。
- 意図した契約と出どころ: {期待する振る舞い。今の実装だけではないもの}。
- 再現: {作業のディレクトリ。安全な準備とリセット。環境変数は名前だけ。合成の値を使った、コマンドそのもの、またはメソッド、パス、ヘッダー、ボディ}。
- 観察: {終了コードかステータス。stdout。stderr。最初と最後の残る状態。再現と再試行の順}。
- Evidence: {EXACT SAFE OUTPUT AND STATE PATHS; REVISION/RUNTIME; REDACTION AND REPRODUCIBILITY LIMITS}.
- 診断 / 次の行動: {原因の証拠か、具体的な前提。推測の直しは書かない}。

## 見つけたことと、残すテスト

Link each `exploration-NNN.json` checkpoint, saved before its next probe, in this report.
チェックポイントの受け取りは、それぞれの `link` を出力する。`.qa-evidence/NNN` の取り込みのフォルダは、チェックポイントではない。
チェックポイントの 1 つごとに、Markdown の項目を 1 つ使う。例:

- [checkpoint 001](exploration-001.json) — この観察が、次のプローブをどう決めたか。

Use the actual filename and a path relative to this report (or its owned absolute
path); plain or backticked filenames are not links.
Include superseded checkpoints as history, not current passing evidence.
これらの元のメモは、報告と一緒に残す。

| 仮説 / 見つけたこと | ネイティブのテストか、提案するケース | 直す前の赤の証拠 | 緑と元と隣の証拠 | 親の扱い |
|---|---|---|---|---|
| {次のプローブを変えた観察} | {UNIT / INTEGRATION / E2E。パスか、報告だけの提案} | {欠陥の失敗そのものか、健全な契約} | {実際の結果か、走らせていないこと} | {許された変更 / 提案 / 先送り} |

## 範囲の限りと片付け

走らせなかった charter、使えなかった前提、断られた効果、はっきりしない契約、
途中で終わった観察、残るリスクを並べる。それらを pass に数えない。片付けた、この実行が持つ
プロセスと状態と、残したものの名前を挙げる。あとの変更が証拠を無効にしたかを書く。
報告だけの実行では、提案と、実際に作ったテストを、分けて示さなければならない。
