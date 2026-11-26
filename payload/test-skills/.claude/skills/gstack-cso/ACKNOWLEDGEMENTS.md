# CSO の調査と、出典の版

CSO v3 は、根拠のある静的な証拠、再現、提案する修正の候補、今のソースでの閉じを分けて扱う。この設計は、[Mozilla's account of hardening Firefox](https://hacks.mozilla.org/2026/05/behind-the-scenes-hardening-firefox/) と [Codex Security's research-preview description](https://openai.com/index/codex-security-now-in-research-preview/) から考えを得ており、アプリケーションの文脈と、再現できる確かめが、作業の流れを形づくる。それらの結果は、CSO を計測したものではない。

`sections/audit-phases.md.tmpl` の領域の指示は、使う版を示す。

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/0x00_2025-Introduction/)。例外の状態と、改めたサプライチェーンの分類を含む。
- [OWASP API Top 10:2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)。
- [ASVS 5.0.0](https://owasp.org/www-project-application-security-verification-standard/) から選んだ制御。要件の ID は、版を持たなければならない。
- [OWASP LLM Top 10 2026](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/) と [Agentic Applications Top 10 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)。September 9, 2026 に調べた。監査は、リリースの告知から中身を推し量らず、実際に使った成果物と版を記録する。
- [MCP security guidance dated 2026-07-28](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices)。

実行の細部は、一次の文書に従う: [Bun compiled executables](https://bun.com/docs/bundler/executables)、[Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/)、[container networking](https://docs.docker.com/engine/network/)、[Docker logging](https://docs.docker.com/engine/logging/configure/)、[npm ci](https://docs.npmjs.com/cli/v11/commands/npm-ci/)、[uv CLI](https://docs.astral.sh/uv/reference/cli/)、[RubyGems commands](https://guides.rubygems.org/command-reference/#gem-fetch)。コンパイルしただけでは、Bun の設定や、実行時に差し込む変数は止まらない。オフラインの依存の準備は、取得の間はローカルの Python のビルドを除き、Gemfile の評価をオフラインの実行まで遅らせなければならない。

これまでの CSO の作業は、文脈の組み立てと変種の分析で [Trail of Bits' skills](https://github.com/trailofbits/skills) を、報告の前の調査で [Sentry's skills](https://github.com/getsentry/skills) を、そして広いコミュニティのセキュリティのスキルのレビューを参考にした。v3 は、受け継いだ、まとめての誤検知の除外と、数の確信度の門を、攻撃者、制御、影響のはっきりした証拠と、独立した反証の試み(challenge)に置き換える。

CSO の正確さ、見落としの少なさ(recall)、準備の成功、修正の正しさは、リリースのときの計測であり、受け継いだ提供元のベンチマークの主張ではない。適格とするには、そろえたモデルと予算、伏せたアサーション、対応する準備の失敗を見落としとして数えること、誤って認定した修正が 0 件であることが要る。文書やアダプタがあることは、その実行環境のイメージやリリースの門を通ったことを意味しない。
