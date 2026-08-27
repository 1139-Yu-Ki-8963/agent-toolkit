# samples-api-only

画面を持たず API だけを持つプロジェクトの納品物の見本です。画面を対象外と宣言し、API・テーブル・バッチ・帳票・外部連携・機能の 6 種別を持つ対象で、生成連鎖が作る納品物の一式をそのまま置いています。全種別を持つ見本（`samples/`）と、全種別を持たない見本（`samples-no-screen/`）の間に位置します。

対象の輪郭は `docs/scope-and-progress/excluded-kinds.json` が定義します。画面だけに依存する納品物（画面遷移図・権限画面マトリクス・デザインシステム・コンポーネント棚卸し・アイコンカタログ）は「対象なし」になり、API があれば成立する納品物（CRUD 図・画面-API-テーブル対応表・権限機能マトリクス・テスト観点表・テストケース一覧・確認事項質問票）は生成されます。

再生成:

```
bash generation-engine/scripts/verification/run-layer-full-pipeline.sh --output <版管理外の出力先>/samples-api-only --profile api-only --keep
rsync -a --exclude verification-source --exclude .matrix-data --exclude '.*-page-data.json' <出力先>/samples-api-only/ generation-engine/samples-api-only/
bash generation-engine/scripts/check-derived-drift.sh record generation-engine/samples-api-only
```

出力先の名前を `samples-api-only` にするのは、生成物のプロジェクト名が出力先の名前から決まるためです。設計は `docs/design/画面なしAPIのみ対象の設計.md` を参照してください。
