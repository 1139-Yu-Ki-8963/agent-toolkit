# Nodeテストの依存導入

Node.js 20以上を使う。
テストの依存関係は、リポジトリルートの`package.json`と`package-lock.json`で管理する。

```bash
npm ci
npx playwright install chromium
```

用語ポータルの動的テストは、リポジトリルートで次のコマンドを実行する。

```bash
npm run test:semantic-glossary-page
```

通常の依存導入後は、`NODE_PATH`の指定や別リポジトリの`node_modules`参照を必要としない。

## 設計判断

`test-screen-unit-root-layout.sh`は、画面単位rootを設定するproducerと、その配置を読むconsumerを横断するE2Eとして必要である。個別スクリプトの直叩き、Makefile、package scriptsによる代替は、共通runnerを介した実際の連携を確認できないため採用しない。保守責任者は人手による`reverse-docs-skills`保守者とし、配置契約を廃止するか、共通runnerへ完全移管した時点でこのテストを廃棄する。
