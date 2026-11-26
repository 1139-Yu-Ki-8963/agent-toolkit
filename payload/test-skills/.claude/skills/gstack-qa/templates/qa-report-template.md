# QA の報告: {APP_NAME}

| 項目 | 値 |
|-------|-------|
| **日付** | {DATE} |
| **URL** | {URL} |
| **ブランチ** | {BRANCH} |
| **コミット** | {COMMIT_SHA} ({COMMIT_DATE}) |
| **PR** | {PR_NUMBER} ({PR_URL}) か "—" |
| **段階** | Quick / Standard / Exhaustive |
| **範囲** | {SCOPE か "Full app"} |
| **Probe budget / guarded command time** | {CONFIGURED LIMIT / SUM OF MEASURED COMMAND SPANS} |
| **訪れたページ** | {COUNT} |
| **スクリーンショット** | {COUNT} |
| **フレームワーク** | {DETECTED か "Unknown"} |
| **電話** | {まねた Chromium のデバイスのプロファイルか "—"}。実機がまだ要るもの(/ios-qa): {何か、または "—"} |

## Health Score: {SCORE}/100

| Category | Score |
|----------|-------|
| Console | {0-100} |
| Links | {0-100} |
| Visual | {0-100} |
| Functional | {0-100} |
| UX | {0-100} |
| Performance | {0-100} |
| Accessibility | {0-100} |

## Top 3 Things to Fix

1. **{ISSUE-NNN}: {title}** — {1 行の説明}
2. **{ISSUE-NNN}: {title}** — {1 行の説明}
3. **{ISSUE-NNN}: {title}** — {1 行の説明}

## Console Health

| エラー | 回数 | 最初に見た場所 |
|-------|-------|------------|
| {エラーのメッセージ} | {N} | {URL} |

## まとめ

| 重大度 | 件数 |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| **合計** | **0** |

## 問題

### ISSUE-001: {短い題}

| 項目 | 値 |
|-------|-------|
| **重大度** | critical / high / medium / low |
| **分類** | visual / functional / ux / content / performance / console / accessibility |
| **URL** | {ページの URL} |

**説明:** {何が誤っているか。期待と実際}

**再現の手順:**

1. {URL} を開く
   ![Step 1](screenshots/issue-001-step-1.jpg)
2. {操作}
3. **観察:** {何がおかしくなるか}
   ![Result](screenshots/issue-001-result.jpg)

---

## 入れた直し(あるとき)

| 問題 | 直しの状態 | コミット | 変えたファイル |
|-------|-----------|--------|---------------|
| ISSUE-NNN | verified / best-effort / reverted / deferred | {SHA} | {files} |

### 直す前と後の証拠

#### ISSUE-NNN: {title}
**直す前:** ![Before](screenshots/issue-NNN-result.jpg) — Phase 5 の証拠(静的なバグでは `issue-NNN.png`)
**直した後:** ![After](screenshots/issue-NNN-after.jpg)

---

## Regression Tests

| 問題 | テストのファイル | 状態 | 説明 |
|-------|-----------|--------|-------------|
| ISSUE-NNN | path/to/test | committed / deferred / skipped | 説明 |

### Deferred Tests

#### ISSUE-NNN: {title}
**Precondition:** {バグを起こす準備の状態}
**操作:** {ユーザーが行うこと}
**期待:** {正しい振る舞い}
**先送りにした理由:** {理由}

---

## 出荷できるか

| 指標 | 値 |
|--------|-------|
| Health score | {before} → {after} ({delta}) |
| 見つけた問題 | N |
| 入れた直し | N (verified: X, best-effort: Y, reverted: Z) |
| 先送り | N |

**PR Summary:** "QA found N issues, fixed M, health score X → Y."

---

## 回帰(あるとき)

| 指標 | baseline | 今 | 差 |
|--------|----------|---------|-------|
| Health score | {N} | {N} | {+/-N} |
| 問題 | {N} | {N} | {+/-N} |

**baseline から直ったもの:** {一覧}
**baseline から新しく出たもの:** {一覧}
