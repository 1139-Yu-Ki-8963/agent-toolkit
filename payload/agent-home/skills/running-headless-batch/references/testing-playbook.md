# 実機検証手順（正本）

`running-headless-batch` の改修後の再検証にも使う。Test A〜D を実行コマンド例・合格基準付きで記載する。

## Test A: E2E（結合テスト。一連の流れを通しで確認するテスト）＋マーカー冪等性

**目的**: ループが実対象に対してマーカーを付与し、既付与の対象を再実行時にスキップすることを確認する。

**手順**:

```bash
WORK=$(mktemp -d)
printf 'target1\n' > "$WORK/t1.txt"
printf 'target2\nDONE:running-headless-batch\n' > "$WORK/t2.txt"   # 事前マーカー付与済み
printf 'target3\n' > "$WORK/t3.txt"
ls "$WORK"/t*.txt > "$WORK/targets.txt"

# 安価モデル・極小プロンプトでループを1回実行する（実際の claude -p 呼び出しを伴う）
# CHECK_CMD 例: grep -q -F -- "DONE:running-headless-batch" "$TARGET"
# PER_ITEM_PROMPT 例: 「$TARGET の末尾に DONE:running-headless-batch を1行追記して終了する」
```

**合格基準**:

- 3件全てにマーカーがある
- t2 は claude 呼び出しなしでスキップされている（ログで確認）
- claude 呼び出し回数は2回（t1・t3のみ）
- 同一設定で再実行すると、claude 呼び出し回数は0回で即座に「残ゼロ」判定になる

## Test B: 成否判定がマーカー実在で行われることの確認

**目的**: `claude -p` が終了コード0を返してもマーカーが付かない状況で、ループが正しく「未完了」と判定し、K回失敗後に failed リストへ退避することを確認する。

**手順**:

```bash
WORK=$(mktemp -d)
printf 'readonly_target\n' > "$WORK/t.txt"
chflags uchg "$WORK/t.txt"   # macOSのユーザー変更不可属性。chmod 444 は Edit ツールの削除・再作成方式に回避されるため使わない
echo "$WORK/t.txt" > "$WORK/targets.txt"

# claude -p 呼び出しには timeout コマンドで上限を付け、検証時間を制御する
# 例: OUTPUT=$(timeout 60 claude -p "$PROMPT" --model haiku ... 2>&1)
# FAIL_LIMIT_K=3 で実行する
```

**実測済みの注記**: 対象ファイルを `chmod 444` にしても、現行 Claude Code（2.1.206）の Edit ツールはファイルを削除・再作成する方式で書き込みに成功してしまう（inode が変わることを実測確認済み）。親ディレクトリの `chmod 555` も実行後に 755 へ戻されて回避される。macOS の `chflags uchg`（ユーザー変更不可属性）なら chmod では解除できず、マーカー付与を実際に阻止できる。

**合格基準**:

- ループが「未完了」と判定し、失敗カウントを加算する（ログに `fail_count=1,2,3` の順で出る）
- K回（3回）失敗した時点で failed リストへ退避し、以後その対象をスキップする
- 全対象が failed リスト入りした時点で周回が終了する（発散検知）

**後片付け**（必須。忘れると一時ディレクトリの削除が失敗する）:

```bash
chflags nouchg "$WORK/t.txt"
```

## Test C: limit耐性（モック。実物の代わりに模した呼び出しで検証する手法）

**目的**: limit 検知パターンにヒットした際、待機してから処理を再開し、次周回の再試行で完走することを確認する。

**手順**:

```bash
# claude 呼び出し部分を以下のモック関数に差し替えた1コマンドで実行する（API呼び出し不要、サンドボックス内で実行可）
call_claude_mock() {
  local n_file="$1.call_count"
  local n=$(cat "$n_file" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" > "$n_file"
  if [ "$n" -eq 1 ]; then
    echo "You've reached your usage limit for this session."
  else
    echo "DONE:running-headless-batch" >> "$1"
    echo "ok"
  fi
}
# WAIT_SECONDS はテスト用に 2 秒へ短縮する
```

**合格基準**:

- 1回目の呼び出しで limit 文言を検知し、ログに「limit検知 -> 2秒待機」の記録が出る
- 待機後に処理が再開され、次周回の再試行（2回目の呼び出し）でマーカーが付与される
- 周回が正常に完走し「残ゼロ」で終了する

## Test D: バックグラウンド生存確認

**目的**: `nohup` + `disown` で起動したループが、メインセッションの応答完了後も生存し続けることを確認する。

**手順**:

```bash
# Test A 相当の設定を nohup/disown 付きで起動する
nohup bash -c '...(Test A の内容)...' >> "$WORK/run.log" 2>&1 &
disown
PID=$!
sleep 10
kill -0 "$PID" && echo "10秒後も生存中" || echo "10秒以内に終了した（要調査）"
```

**合格基準**:

- 起動10秒後以降も `kill -0 $PID` が生存を示す
- `$WORK/run.log` のファイルサイズまたは行数が時間経過とともに増加している（ループが実際に進行している証拠）
