<!-- AUTO-GENERATED from vet-the-number.md.tmpl — do not edit directly -->
<!-- Regenerate: bun run gen:skill-docs -->
<!-- The seven questions derive from pstack's benchmark-checklist skill (Lauren Tan, MIT), rewritten for gstack. See NOTICE.md. -->
## Vet the number

性能の数は 1 つの主張であり、次の 7 つの問いは、誰かがその数で動く前に、その主張を試す。
それぞれの問いには、実行の結果から答え、コードを読んで答えることは決してしない。A one-run ballpark the user asked for is allowed: say it is one run,
still answer questions 4 and 7, and skip the rest unless the run looks wrong.
2 つの選択肢から 1 つを選ぶ比べは、大まかな計測としない。

何かを実行する前に、出すつもりの文(「ダッシュボードのページで、LCP が中央値で 1.6 s →
1.1 s」)を書き、計測のスクリプトが何の時間を計り、何を数え、何を無視するかを読む。`uptime` と
`nproc` を確かめる。忙しいマシンでは、両方の側が同じ雑音を受けるように、2 つの側を交互に
実行し、そうしたことを書く。

1. **Why not double?** Name the limiter: 時間を使っている 1 つの資源か段階(100% の 1 つの
   コア、3 MB のスクリプトの解析、直列のリクエストの連なり、回線の帯域)を名指す。プロファイラは
   処理を遅くするので、プロファイルは、報告しない実行の中で取る。変更が数を動かさなかったときは、
   律速の箇所がその理由であり、変更を役に立たないと言う前に、その箇所を見つける。
2. **Was it tuned?** 両方の側を、本番と同じように実行する。本番のビルドとフラグ、同じデータ、
   ユーザーが受けるのと同じだけ温まったか冷えたキャッシュ、同じ版を使う。片方の側が既定の設定
   (デバッグのビルド、冷えたキャッシュ、ないインデックス)で動くと、この比べは、実装の比べでは
   なく、設定の比べになる。設定を整えて計り直すか、勝ちを決めない。
3. **Did it break a limit?** 計算をする。1 秒あたりのバイト数を回線と比べ、1 秒あたりの操作の
   数と 1 回の費用の積をコアと比べ、短くなった時間を、取り除いた部分にかかっていた時間と比べる。
   Removing a piece that took 10%
   of the run makes the run at most about 11% faster; 限界を超えた結果は、その処理とは別のもの
   (キャッシュ、何もしない処理、バグ)を計っている。
4. **Did it error?** 失敗、時間切れ、再試行、成功でない応答を数え、出力があるかだけでなく、
   出力が正しいかを確かめる。拒否は速く、再試行は遅い。スクリプトがエラーを数えないときは、
   時間を信じる前に、エラーを数える処理を足す。
5. **Does it reproduce?** 各側で 5 回以上、alternating A, B, A, B で実行し、温まり、遅延の
   初期化、キャッシュ、ずれがどちらの側にも有利に働かないようにする。中央値と範囲を報告する。
   A gap smaller than the run-to-run variation
   is no difference; 判断がきわどいときは、計測の道具そのものの統計か、順位和の検定を使う。
6. **Does it matter?** 小さな部分の数を、ユーザーが待つ端から端までの道のりの数と並べ、現実に
   近いデータと同時実行の数で、全体に対する割合として報告する。ページの 1% を占める段階は、
   ページを最大でも 1% しか速くできない。
7. **Did it even happen?** 処理が、計った範囲の中で実行されたことを確かめる。リクエストが
   サーバーに届いた、バイトを取得した、フレームを描いた、結果を使った、のそれぞれを確かめる。
   遅延のコード(誰も待たない promise、誰も最後まで読まない generator)と時間切れは、実行されな
   かった処理の数を生む。

### レポート

Lead with the verdict: faster, slower, no measurable difference, or
inconclusive. 数は、単位、実行の回数、範囲、律速の箇所とともに書く(「LCP 1.6 s → 1.1 s、
各側 7 回の交互の実行の中央値、変更の後の範囲は 1.0 から 1.2 s、hero image のデコードが律速」)。
Call the verdict
inconclusive when you claim a difference but cannot name the limiter, when a
side ran untuned, or when questions 4 and 7 went unanswered, and say which.
PR の本文は、主な数を 1 つ持つ。実行の記録、範囲、律速の箇所の証拠は、このスキルが Phase 9 で
書くレポートのファイルに入れる。
