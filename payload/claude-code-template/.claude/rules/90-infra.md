---
paths:
  - "_adapt_pending_/**"
---

<!-- ADAPT:detect:infra-paths | 上の paths を実在するインフラ関連のディレクトリに書き換える（例: infra/**、.github/**、docker/**）。インフラ設定が存在しない場合はこのファイルを削除する -->

# インフラ規範

1. **適用系コマンドは plan/diff を提示してから実行する。destroy は提案しない**: terraform apply・kubectl apply 等は、事前に plan/diff の結果を提示する。destroy は自分からは提案しない
2. **CI 変更は権限影響を明記する**: CI/CD パイプラインの変更は、権限影響（pull_request_target 等のセキュリティ上重要な設定）を明記する
3. **Dockerfile のタグを固定し、秘密情報を焼き込まない**: ベースイメージには固定タグを使い、ビルド時に秘密情報をイメージ内に含めない
4. **環境差分は設定で表現する**: 開発・ステージング・本番の差異はコード分岐ではなく、環境変数や設定ファイルで表現する

<!-- ADAPT:ask:infra-conventions | プロジェクト固有のインフラ規約があれば追記し、無ければこのマーカー行だけ削除する -->
