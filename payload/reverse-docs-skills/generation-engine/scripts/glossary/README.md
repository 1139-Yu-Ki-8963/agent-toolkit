# Semantic glossary validator

## 設計判断

### validate-semantic-glossary

**必要性**: Python依存をworktree内venvへ限定しながら、Skillとportal投影から同じ正規CLIを繰り返し呼び出すために薄いshell入口を設ける。

**代替案を採用しなかった理由**:

- Bashツール直叩き: 呼び出しごとにPython実行環境の解決が分岐し、契約の正規CLIを提供できない。
- 既存Makefileターゲット拡張: このrepositoryに対象機能のMakefile契約がなく、Skillからの直接呼び出しpathも必要である。
- package.json scripts追加: validatorはPython実装であり、Node.jsを実行前提へ追加する理由がない。

**保守責任者**: Semantic glossary基盤のmaintainer。

**廃棄条件**: 用語validatorが単一の配布済み実行形式になり、Python環境解決が不要になった時。

### test-validate-semantic-glossary

**必要性**: 3 kind、診断report、exit code、実行障害の回帰を1つの決定的な入口で反復検証するために使用する。

**代替案を採用しなかった理由**:

- Bashツール直叩き: 多数のfixtureとexit codeの対応を毎回手作業では再現できない。
- 既存Makefileターゲット拡張: 対象ディレクトリに既存ターゲットがなく、テスト本体の分岐を保持する場所にならない。
- package.json scripts追加: Python CLIの検証にNode.js依存を追加し、テストロジックを埋め込む必要がない。

**保守責任者**: Semantic glossary基盤のmaintainer。

**廃棄条件**: 同じfixtureとexit/report契約を包含する上位テストランナーへ完全移行した時。

## 隔離環境の整備

このディレクトリを作業場所にして、次の順に実行する。

```bash
cd generation-engine/scripts/glossary
python3.13 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

`requirements.txt` は `PyYAML>=6,<7` と `jsonschema[format]>=4.23,<5` を要求する。
このworktreeでは、`python3.13` はPATHになく、fallbackの`python3`もPyYAMLを読み込めない。
そのため2本の検査は `[UNKNOWN]` と終了コード2を返した。
他の環境での結果は、Python実行系と依存の状態により異なる。
`[UNKNOWN]` は成果物のFAILではない。
実行環境が整っていないため未実行である判定を表す。
環境を整備した後に同じ検査を再実行する。
`test-validate-semantic-glossary.sh` の判定不能は `.venv/bin/python` がないことによる。
`test-project-semantic-glossary-race.sh` の判定不能は `python3` へ切り替えた後に PyYAMLを読み込めないことによる。
2本を同じ原因として扱わない。
`.venv` は生成物であり `.gitignore` の対象である。
`.venv` をコミットしてはいけない。

## 承認identity

proposalの二者承認は、`business_approver`と`technical_approver`の両roleに`approved`の判断があることで判定する。同じactorが両roleを兼任できる。外部identity providerとの照合は、このCLIの入力契約に含まれない。

changeの`approved_by`は、businessとtechnicalのrole修飾済みidentityを各1件以上必須とする。
同じactorが兼任する場合も、`business_approver:domain-reviewer`と`technical_approver:domain-reviewer`を別identityとして記録する。
role修飾のない文字列は受理しない。

## Registry文書の分類

registry directory内のYAMLは、kindごとの特徴的なmarkerからglossary、proposal、changeへ分類する。必須項目が欠けたsemantic文書も候補kindへ分類し、対応schemaのerrorとして報告する。複数kindのmarkerを持つ文書や、semantic用のkeyを持つのにkindを決定できない文書は`SGD_PARSE`で停止する。

一般設定などsemantic markerを1つも持たないobject YAMLは、検証対象外として無視する。
listまたはscalarをrootに持つ非semantic YAMLも同様に無視する。
併置した非semantic設定を壊さず、semantic文書の欠落や曖昧さだけをfail-closedで扱う。
CLIの`--input`本体は従来どおりobject rootだけを許可する。

## Operation keyと出力先の保護

proposalの`merge_key`とchangeの`change_key`は、同じoperation-key namespaceで一意にする。同じkind内だけでなく、proposalとchangeの間で同値になる場合も二重適用として拒否する。

`--report`は、`--input`またはregistryから読み込む個々のsource fileと同じ実体を指してはならない。絶対path、symbolic link、hard linkを解決して書き込み前に拒否し、入力とregistryのbyte列を変更しない。registry directory自体はsource fileではない。
