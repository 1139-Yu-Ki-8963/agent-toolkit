# profile-python: Pythonプロファイルの抽出・再計数契約

`profile=python`は、Python原本をPEP 263の宣言に従って読み、標準ライブラリのASTから決定的にfactsを作る。抽出と再計数は同じ文字コード正規化を使用するが、再計数は生成済みfactsを読まず原本から独立して件数を算出する。

## 実行条件

Python 3.8以上を必須とする。分類間の`source_span`排他検査と関数本文網羅検査にASTの`end_lineno`・`end_col_offset`を使うためである。`extract-python-facts.py`と`recount-python-facts.py`は起動時にバージョンを検査し、Python 3.7以下ではexit 2で停止する。`profile=screen`を含む既存経路のPython 3.6以上という最低要件は変更しない。

## 分類

| 優先順位 | 分類 | 対象 | 値 |
|---:|---|---|---|
| 1 | `measurement_pending` | 関数内代入のうち、右辺が名前・属性・添字参照・呼び出し・await・内包表記などを含み、構文だけでは値が一意に確定しないもの | 値を持たず、代入先ごとにkey・evidence・source_spanを記録 |
| 2 | `exception_handling` | `try`、各`except`、`raise` | 該当構文の本文literal |
| 3 | `import` | `import`、`from ... import ...`の各alias | import文の本文literal |
| 4 | `function` | `def`、`async def` | 宣言先頭から関数本体末尾までの全文literal |
| 5 | `local_assignment` | 関数本体内の`Assign`、`AnnAssign`、`AugAssign` | 代入文の本文literal |
| 6 | `external_call` | 上記分類に消費されない修飾呼び出し | 呼び出し式の本文literal |

同一ASTノードを複数分類へ計上しない。
関数内代入は、右辺が定数literal、literalだけで構成されたコンテナ・演算・比較・条件式・f-string・lambdaなら`local_assignment`とする。
それ以外は`measurement_pending`とし、内部の呼び出しを`external_call`へ重複計上しない。
`raise`内の呼び出しは`exception_handling`へ含める。
関数factのvalueは本文全文を保持する一方、source_spanは宣言ヘッダーだけに限定し、内部構文との包含重複を避ける。
分類追加時は、この排他条件と優先順位を先に更新する。

## 実行

抽出:

```bash
python3 scripts/extract-python-facts.py extract \
  --repo <target_repo_path> \
  --out <facts_dir>/facts.yml \
  --run-id <run_id> \
  <target_file_paths...>
```

独立再計数（抽出器をimportしない`recount-python-facts.py`を使用）:

```bash
bash scripts/recount-facts.sh \
  <facts_dir>/facts.yml <target_repo_path> <target_file_paths...>
```

関数本文の行網羅:

```bash
python3 scripts/extract-python-facts.py verify-bodies \
  --facts <facts_dir>/facts.yml \
  --repo <target_repo_path> \
  <target_file_paths...>
```

## 完了条件

- 6分類の件数が独立再計数と一致する。
- 全関数factのvalueが、ASTの宣言先頭から本体末尾までの原文と一致する。
- `measurement_pending`は固定API名の列挙ではなく、右辺が構文だけで一意に決まるかという判定基準で分類する。
- 異なる分類間でsource spanの完全一致・包含・部分交差がいずれも発生しない。
- 非UTF-8原本はPEP 263の宣言で読み、UTF-8へ正規化した同一文字列を抽出と再計数へ渡す。
