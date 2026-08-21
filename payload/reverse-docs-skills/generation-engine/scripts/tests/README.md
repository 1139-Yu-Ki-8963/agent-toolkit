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

### test-basic-design-jsx-authored-flow.sh

**必要性**: 改善課題1-167の残作業（検収方法3「新規抽出→basic-designが封印検証を通過しAUTHORED（`基本設計著述完了`）に到達すること」）は、実データ（jsx構造を持つ画面・撮影済みoriginal.png）がこの検証環境に存在しないため実データでは検証不能だった。`scaffold-screen.sh`→`seal-facts.sh`→`validate-reverse-authoring-inputs.py screen-composition`→著述（Phase 3の実装用語・内部成果物名grep検査）という複数スクリプトを跨ぐ一気通貫を、jsx構造を持つ合成facts.ymlで固定的に再現し、退行時に機械検知できるようにする必要がある。単発のBashツール直叩きでは、次回の改修で同じ経路が壊れても検知できない。

**代替案を採用しなかった理由**: Bashツール直叩きは1回限りの確認に留まり回帰検知にならない。既存`generation-engine/scripts/tests/test-python-facts-flow.sh`はprofile=pythonのfacts-only経路（screen-composition判定を経由しない）を検証しており、screenプロファイルのroute=facts-structure判定とPhase 3grep検査は対象外のため、既存テストへの追記ではなく独立したテストが必要。このリポジトリはMakefile/package.json scriptsによるテスト定義基盤を持たない。

**保守責任者**: 人手（`reverse-docs-skills`保守者）。`validate-reverse-authoring-inputs.py`のscreen-composition判定式、または`generating-reverse-basic-design/SKILL.md`のPhase 3 grep式を変更した場合、本テストのgolden文書・grep式を同時に更新する。

**廃棄条件**: この検証環境に実際にjsx構造を持つ画面（またはoriginal.png撮影済みの画面）が用意され、実データでAUTHORED到達を確認できるようになった時、または改善課題1-167自体が完全解消し台帳から削除された時。
