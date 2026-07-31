# rebuilding-code-from-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 白紙化ゲート-全消しフォールバック禁止 | 対象ファイル一覧の取得に失敗する | Phase 3を実行する | 環境全体を削除せずERRORとしてPhase 8へ直行する | 手動 |
| 白紙化ゲート-user-approved必須 | user-approvedが渡されない | Phase 3を実行する | status=BLOCKEDとして差し戻す | 手動 |
| STYLE-GATE-トークン欠落の差し戻し | DESIGN.mdの数値トークンが実装に出現しない | Step 4-5を実行する | 欠落1件でもStep 3へ差し戻す | 手動 |
| 凍結検証-HEAD不一致の検出 | 凍結コミット後にreverse worktreeへ変更が加わる | check-freeze.shを実行する | 現状との不一致を検出し終了コードが非0になる | check-freeze.shのself-testケース「HEAD不一致で凍結検証FAIL」 |
| 凍結検証-引数不足の検出 | worktreeパスまたは凍結ハッシュが渡されない | check-freeze.shを実行する | 終了コードが非0になる | check-freeze.shのself-testケース「引数不足でexit非0」 |
| 列位置ずれ耐性-未記入行の検出 | 実体形状列が追加され配置ディレクトリ列の位置がずれる | audit-consistency.shを実行する | 未記入行を正しく検出する | audit-consistency.shのself-testケース「実体形状列追加による配置ディレクトリ列の位置ずれでも未記入行を正しく検出する」 |
| ネスト構造対応-配置差異での完走 | 設計書が詳細設計配下にネストして配置される | audit-consistency.shを実行する | 監査が完走し設計書を正しく解決する | audit-consistency.shのself-testケース「ネスト構造陽性: 詳細設計/画面詳細設計書.md 配下配置でも監査が完走し設計書を正しく解決する」 |
| judge判定-static_diffを判定材料にしない | compare_result.statusがFAILでもstatic_diffだけが原因である | Phase 7の判定を行う | env_checkとdynamicのみでPASS相当として扱う | 手動 |
| 達成宣言の規律-内容一致単独では未達 | 内容一致のみが揃いL3・L2 ARIAが未達である | 合否宣言の規律を確認する | 達成と書かず視覚未達と明記する | 手動 |
| E2E作成責務-元コードでのベースライン実測 | Step 4-2でE2Eテストを作成する | mode=implementを実行する | オリジナルコード環境で実行しベースラインを検証記録に残す | 手動 |
| 単体テスト保護-上流提供分の改変禁止 | 上流が保存した単体テストコードが壊れている | Phase 5で自己完結チェックを行う | 実装で辻褄を合わせずstatus=BLOCKEDで差し戻す | 手動 |
| 最終報告-未実施ゼロの原則 | テストケース識別子別の実行結果表を作る | Phase 9の最終報告を作成する | 未実施が1件でもあればstatus=PASSにできない | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、rebuilding-code-from-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
