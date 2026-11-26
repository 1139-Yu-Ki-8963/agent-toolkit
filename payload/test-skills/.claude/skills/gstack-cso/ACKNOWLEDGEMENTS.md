# CSO の調査と、出典の版

CSO は、根拠のある静的な証拠、仮説、提案する直しの候補、今のソースでの閉じを分けて扱う。この設計は、[Mozilla's account of hardening Firefox](https://hacks.mozilla.org/2026/05/behind-the-scenes-hardening-firefox/) から考えを得ており、アプリケーションの文脈と、確かめられる証拠が、作業の流れを形づくる。その結果は、CSO を計測したものではない。

`sections/audit-phases.md` の領域の指示は、使う版を示す。

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/0x00_2025-Introduction/)。例外の状態と、改めたサプライチェーンの分類を含む。
- [OWASP API Top 10:2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)。
- [ASVS 5.0.0](https://owasp.org/www-project-application-security-verification-standard/) から選んだ制御。要件の ID は、版を持たなければならない。
- [OWASP LLM Top 10 2026](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/) と [Agentic Applications Top 10 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)。2026-09-09 に調べた。監査は、リリースの告知から中身を推し量らず、実際に使った成果物と版を記録する。
- [MCP security guidance dated 2026-07-28](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices)。

スキャナの引数は、それぞれの一次の文書に従う: [Gitleaks](https://github.com/gitleaks/gitleaks/blob/master/README.md)、[Semgrep CLI reference](https://docs.semgrep.dev/cli-reference)、[zizmor usage](https://docs.zizmor.sh/usage/)。

これまでの CSO の作業は、文脈の組み立てと変種の分析で [Trail of Bits' skills](https://github.com/trailofbits/skills) を、報告の前の調査で [Sentry's skills](https://github.com/getsentry/skills) を、そして広いコミュニティのセキュリティのスキルのレビューを参考にした。CSO は、まとめての誤検知の除外と、数の確信度の門を、攻撃者、制御、影響のはっきりした証拠と、独立した反証の試み(challenge)に置き換える。

CSO の正確さ、見落としの少なさ(recall)、直しの候補の正しさは、計測していない。文書があることは、その手順が計測を通ったことを意味しない。
