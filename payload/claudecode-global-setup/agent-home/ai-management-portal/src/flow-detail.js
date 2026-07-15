// フロー詳細ページ（#/flow/<id>）。
// data/flows/index.js が export する getFlow(id) でフロー定義を引き、
// 概要・トリガー・ステップ・図・関連スキル・注意を 1 画面に描画する。
// master-table-detail.js のパンくず／セクション様式を範に、依存は dom.js の el のみ。
// orchestrating-dev-flow は専用レンダラー renderOrchestratingFlow で描画する。
import { getFlow } from "../data/flows/index.js?v=4";
import { el } from "./dom.js?v=4";

const CATEGORY_META = {
  routines: { href: "catalog/routines.html", label: "Routines 一覧" },
};
const DEFAULT_PARENT = { href: "#/category/flow", label: "フロー一覧" };

function parentOf(def) {
  if (def && def.parentCategory) return CATEGORY_META[def.parentCategory] || DEFAULT_PARENT;
  return DEFAULT_PARENT;
}

function backLink(def) {
  const p = parentOf(def);
  return el("div", { class: "back-link" },
    el("a", { href: p.href }, `← ${p.label}へ戻る`),
  );
}

// 1 ステップを番号付きカードで描画する。skill があれば右肩にバッジを出す。
function stepCard(step) {
  const card = el("div", { class: "card is-visual group-flow flow-step" });
  card.appendChild(el("div", { class: "card-head" }, [
    el("span", { class: "flow-step-no" }, String(step.n)),
    el("span", { class: "card-title" }, step.title),
    step.skill ? el("span", { class: "card-badge" }, step.skill) : null,
  ]));
  if (step.detail) card.appendChild(el("div", { class: "card-desc" }, step.detail));
  return card;
}

// ─── orchestrating-dev-flow 専用レンダラー ───────────────────────────────────

const ODF_CSS_ID = "odf-phase-css";

function injectOrchestratingCSS() {
  if (document.getElementById(ODF_CSS_ID)) return;
  const style = document.createElement("style");
  style.id = ODF_CSS_ID;
  style.textContent = `
/* ── orchestrating-dev-flow Phase カード ──── */
.odf-tab-bar {
  display: flex; margin: 0 0 20px;
  border: 1px solid var(--accent); border-radius: 8px;
  overflow: hidden; background: var(--panel); font-size: 13px;
}
.odf-tab {
  flex: 1; display: flex; align-items: center; justify-content: center;
  padding: 9px 14px; border: none; border-right: 1px solid var(--accent);
  background: var(--panel); color: var(--accent);
  font-weight: 600; cursor: pointer; text-align: center; line-height: 1.2;
  transition: background 0.12s, color 0.12s;
}
.odf-tab:last-child { border-right: none; }
.odf-tab:hover { background: var(--accent-soft); }
.odf-tab.active { background: var(--accent); color: #fff; }
.odf-tab-panel[hidden] { display: none; }
.odf-section-title {
  margin: 0 0 14px; font-size: 15px; font-weight: 700; color: var(--accent);
  padding-bottom: 6px; border-bottom: 2px solid var(--accent);
}
.odf-features {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 12px; margin: 0 0 28px;
}
.odf-feature-card {
  padding: 14px 16px; background: var(--panel);
  border: 1px solid var(--border); border-left: 3px solid var(--accent);
  border-radius: 6px;
}
.odf-feature-card h3 { margin: 0 0 6px; font-size: 14px; font-weight: 700; color: var(--accent); }
.odf-feature-card ul { margin: 4px 0 0; padding-left: 16px; font-size: 12px; color: var(--text-sub); line-height: 1.75; }
.odf-route-table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 0 0 28px; }
.odf-route-table th {
  padding: 10px 12px; text-align: left; background: var(--panel-2);
  border-bottom: 2px solid var(--accent); color: var(--accent);
  font-size: 12px; letter-spacing: 0.04em; white-space: nowrap;
}
.odf-route-table td { padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
.odf-route-table tr:last-child td { border-bottom: none; }
.odf-route-table tr:hover td { background: var(--panel-2); }
.odf-route-table code {
  font-size: 11px; background: var(--panel-2); color: var(--accent);
  padding: 1px 6px; border-radius: 3px; border: 1px solid var(--border);
  font-family: var(--mono); word-break: break-all;
}
.odf-badge-yes { display: inline-block; padding: 1px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; background: var(--accent-soft); color: var(--accent); }
.odf-badge-no  { display: inline-block; padding: 1px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; background: var(--panel-2); color: var(--text-muted); }
/* ── ステータスバー表示例 ── */
.odf-status-demo {
  margin: 0 0 24px; padding: 16px 20px;
  background: var(--panel-2); border-radius: 8px;
  border: 1px solid var(--border);
}
.odf-status-demo h4 {
  margin: 0 0 6px; font-size: 13px; font-weight: 700;
  color: var(--accent); letter-spacing: 0.02em;
}
.odf-status-desc {
  margin: 0 0 12px; font-size: 12.5px; color: var(--text-sub); line-height: 1.6;
}
.odf-status-line {
  display: flex; align-items: center; gap: 8px;
  padding: 8px 14px; border-radius: 6px;
  background: #1a1a2e; color: #00d4ff;
  font-family: var(--mono); font-size: 13px; font-weight: 600;
  letter-spacing: 0.02em;
  overflow-x: auto;
}
.odf-status-icon { font-size: 14px; }
.odf-status-phase { color: #00d4ff; }
.odf-status-name { color: #e0e0e0; }
.odf-status-bar { color: #00d4ff; letter-spacing: 1px; }
.odf-status-count { color: #aaa; font-size: 12px; }
.odf-status-step { color: #e0e0e0; font-size: 12px; }
.odf-prereq {
  margin: 0 0 16px; padding: 14px 18px;
  background: var(--panel-2); border-left: 4px solid var(--gold); border-radius: 6px;
}
.odf-prereq h3 { margin: 0 0 8px; font-size: 14px; font-weight: 700; color: var(--gold); }
.odf-prereq ul { margin: 0; padding-left: 16px; font-size: 12.5px; color: var(--text-sub); line-height: 1.75; }
.odf-prereq code { font-size: 11px; background: var(--panel); color: var(--text); padding: 1px 6px; border-radius: 3px; border: 1px solid var(--border); font-family: var(--mono); }
.odf-intro-note {
  margin: 0 0 16px; padding: 12px 14px;
  background: var(--panel-2); border-left: 4px solid var(--accent);
  border-radius: 6px; font-size: 13px; color: var(--text-sub); line-height: 1.7;
}
.odf-route-filter-bar { display: flex; gap: 8px; flex-wrap: wrap; margin: 0 0 16px; align-items: center; }
.odf-filter-label { font-size: 12px; font-weight: 700; color: var(--text-muted); }
.odf-route-btn {
  padding: 6px 14px; border: 1px solid var(--accent); border-radius: 6px;
  background: var(--panel); color: var(--accent); font-size: 12.5px;
  font-weight: 600; cursor: pointer; transition: background 0.12s, color 0.12s;
}
.odf-route-btn:hover { background: var(--accent-soft); }
.odf-route-btn.active { background: var(--accent); color: #fff; }
.odf-phase-cards { display: flex; flex-direction: column; gap: 18px; }
.odf-phase-card {
  --phase-color: var(--accent);
  border: 1px solid var(--border);
  border-left: 6px solid var(--phase-color);
  border-radius: var(--radius);
  background: var(--panel);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
}
.odf-phase-card[hidden] { display: none; }
.odf-phase-card.color-gold    { --phase-color: var(--gold); }
.odf-phase-card.color-danger  { --phase-color: var(--danger); }
.odf-phase-banner {
  display: block;
  padding: 16px 20px 14px;
  background: var(--panel-2);
  border-bottom: 1px solid var(--border);
}
.odf-phase-eyebrow {
  display: inline-block;
  font-size: 11px; font-weight: 700; letter-spacing: 0.08em;
  padding: 2px 8px; border-radius: 4px;
  background: var(--phase-color); color: #fff;
  margin-right: 10px; vertical-align: 2px;
}
.odf-phase-title {
  display: inline; font-size: 17px; font-weight: 800;
  color: var(--phase-color); line-height: 1.3; margin: 0;
}
.odf-phase-sub {
  display: block; margin: 6px 0 0;
  font-size: 14px; color: var(--text-sub); line-height: 1.55;
}
.odf-phase-goal {
  display: inline-block; padding: 1px 8px; border-radius: 4px;
  font-size: 11px; font-weight: 700; letter-spacing: 0.03em;
  background: var(--phase-color); color: #fff;
  vertical-align: 1px; margin-right: 6px;
}
.odf-phase-flow-line {
  font-size: 13px; color: var(--text-sub);
}
.odf-skill-badge {
  display: inline-block; margin: 8px 6px 0 0; padding: 2px 8px;
  border-radius: 4px; font-size: 11px; font-weight: 600;
  background: var(--accent-soft); color: var(--accent);
  border: 1px solid var(--accent-border);
  font-family: var(--mono);
}
.odf-stop-badge {
  display: inline-block; margin-top: 8px; padding: 2px 10px;
  border-radius: 4px; font-size: 11.5px; font-weight: 700;
  background: var(--danger-soft); color: var(--danger);
  border: 1px solid var(--danger);
}
.odf-phase-meta {
  display: grid; grid-template-columns: auto 1fr; gap: 4px 12px;
  margin-top: 10px; font-size: 12px; color: var(--text-sub);
}
.odf-phase-meta dt { font-weight: 700; white-space: nowrap; }
.odf-setup-steps { display: flex; flex-direction: column; gap: 16px; margin: 0 0 24px; }
.odf-setup-step {
  display: grid; grid-template-columns: 40px 1fr;
  gap: 0 14px; align-items: start;
  padding: 16px; background: var(--panel);
  border: 1px solid var(--border); border-radius: 6px;
}
.odf-setup-num {
  width: 40px; height: 40px; border-radius: 50%;
  background: var(--accent); color: #fff;
  display: flex; align-items: center; justify-content: center;
  font-size: 16px; font-weight: 800; flex-shrink: 0; margin-top: 2px;
}
.odf-setup-body h3 { margin: 0 0 6px; font-size: 15px; font-weight: 700; color: var(--accent); }
.odf-setup-body p  { margin: 0; font-size: 13px; color: var(--text); line-height: 1.65; }
.odf-compare-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 24px; }
.odf-compare-card { border: 1px solid var(--border); border-radius: var(--radius); background: var(--panel); padding: 16px 20px; height: 100%; box-sizing: border-box; }
.odf-compare-card.is-before { border-left: 6px solid var(--danger); }
.odf-compare-card.is-after { border-left: 6px solid var(--accent); }
.odf-compare-card h4 { margin: 0 0 8px; font-size: 15px; font-weight: 700; }
.odf-compare-card.is-before h4 { color: var(--danger); }
.odf-compare-card.is-after h4 { color: var(--accent); }
@media (max-width: 768px) { .odf-compare-row { grid-template-columns: 1fr; } }
.odf-feature-card {
  border: 1px solid var(--border);
  border-left: 6px solid var(--accent);
  border-radius: var(--radius);
  background: var(--panel);
  padding: 16px 20px;
  margin-bottom: 12px;
}
.odf-feature-card h4 {
  margin: 0 0 8px;
  font-size: 15px;
  font-weight: 700;
  color: var(--accent);
}
.odf-section-title {
  font-size: 17px;
  font-weight: 800;
  color: var(--accent);
  margin: 24px 0 12px;
  padding-bottom: 8px;
  border-bottom: 2px solid var(--accent);
}
@media (max-width: 768px) {
  .odf-features { grid-template-columns: 1fr; }
  .odf-route-table { display: block; overflow-x: auto; }
  .odf-tab { padding: 8px 8px; font-size: 12px; }
}
@media (max-width: 768px) {
  .odf-compare-row { flex-direction: column; }
}
/* ── Phase テーブル ── */
.odf-phase-flow {
  width: 100%; table-layout: fixed; border-collapse: collapse;
  font-size: 15px; line-height: 1.6; background: transparent;
  color: var(--text); font-variant-numeric: tabular-nums;
}
.odf-phase-flow col.col-num { width: 48px; }
.odf-phase-flow col.col-when { width: 90px; }
.odf-phase-flow col.col-refs { width: 220px; }
.odf-phase-flow col.col-check { width: 220px; }
/* col-step は幅指定なし → 残り幅を全て使う */
.odf-phase-flow thead th {
  padding: 10px 12px; text-align: left; white-space: nowrap;
  font-weight: 700; font-size: 13px; letter-spacing: 0.04em;
  color: var(--phase-color); background: var(--panel-2);
  border-bottom: 2px solid var(--phase-color);
}
.odf-phase-flow thead th.col-num,
.odf-phase-flow thead th.col-when { text-align: center; }
.odf-phase-flow tbody td {
  padding: 10px 12px; vertical-align: top;
  border-bottom: 1px solid var(--border);
  word-break: break-word; overflow-wrap: anywhere; background: transparent;
}
.odf-phase-flow tbody tr:last-child td { border-bottom: none; }
.odf-phase-flow tbody tr:hover td { background: var(--panel-2); }
.odf-phase-flow tbody td.cell-num {
  font-family: var(--mono); font-weight: 700;
  color: var(--phase-color); text-align: center; white-space: nowrap;
}
.odf-phase-flow tbody td.cell-when { text-align: center; }
.odf-step-detail {
  display: block; margin-top: 4px; font-size: 13px;
  color: var(--text-sub); line-height: 1.55;
}
.odf-step-completion {
  display: block; margin-top: 6px; padding: 3px 8px;
  font-size: 11px; font-weight: 600;
  color: var(--accent); line-height: 1.5;
  background: var(--accent-soft, rgba(99,102,241,0.08));
  border-left: 3px solid var(--accent);
  border-radius: 2px;
}
.odf-step-completion::before {
  content: "完了条件: ";
  font-weight: 700;
}
.odf-timing-tag {
  display: inline-block; padding: 1px 7px; border-radius: 4px;
  font-size: 10.5px; font-weight: 600; white-space: normal;
  background: var(--panel-2); color: var(--text-sub);
  border: 1px solid var(--border); word-break: keep-all;
}
.odf-skill, .odf-module, .odf-rule, .odf-hook-block, .odf-hook-notify, .odf-hook-guard,
.odf-agent-explore, .odf-context, .odf-muted {
  display: block; margin: 3px 0; padding: 2px 6px 2px 4px;
  border-left: 3px solid var(--border); border-radius: 2px;
  font-size: 12px; font-family: var(--mono); line-height: 1.6;
  background: transparent; color: var(--text); white-space: normal;
}
.odf-skill, .odf-module, .odf-rule, .odf-hook-block, .odf-hook-notify, .odf-hook-guard,
.odf-agent-explore, .odf-context { border-left-color: var(--accent); }
.odf-muted { color: var(--text-muted); border-left-color: var(--border); }
.odf-skill::before { content: "Skill: "; color: var(--accent); font-weight: 700; }
.odf-module::before { content: "Module: "; color: var(--accent); font-weight: 700; }
.odf-rule::before { content: "Rule: "; color: var(--accent); font-weight: 700; }
.odf-hook-block::before { content: "Hook（停止）: "; color: var(--accent); font-weight: 700; }
.odf-hook-notify::before { content: "Hook（通知）: "; color: var(--accent); font-weight: 700; }
.odf-hook-guard::before { content: "Hook（制御）: "; color: var(--accent); font-weight: 700; }
.odf-agent-explore::before { content: "Agent: "; color: var(--accent); font-weight: 700; }
.odf-context::before { content: "Context: "; color: var(--accent); font-weight: 700; }
@media (max-width: 768px) {
  .odf-phase-flow {
    display: block;
    padding: 0 12px 0 10px;
  }
  .odf-phase-flow colgroup,
  .odf-phase-flow thead {
    display: none;
  }
  .odf-phase-flow tbody {
    display: block;
  }
  .odf-phase-flow tbody tr {
    display: block;
    border: none;
    border-top: 1px solid var(--border);
    border-radius: 0;
    margin: 0;
    padding: 12px 0;
    background: transparent;
  }
  .odf-phase-flow tbody tr:first-child {
    border-top: none;
  }
  .odf-phase-flow tbody tr:hover td {
    background: transparent;
  }
  .odf-phase-flow tbody td {
    display: block;
    padding: 2px 0;
    border-bottom: none;
    text-align: left !important;
  }
  .odf-phase-flow tbody td.cell-num {
    font-size: 14px;
    font-weight: 700;
    color: var(--phase-color, var(--accent));
    margin-bottom: 4px;
  }
  .odf-phase-flow tbody td.cell-num::before {
    content: "Step ";
  }
  .odf-phase-flow tbody td.cell-step {
    font-size: 15px;
    font-weight: 600;
    margin-bottom: 6px;
  }
  .odf-phase-flow tbody td.cell-when {
    margin-bottom: 6px;
  }
  /* 参照・検査列にラベルを追加 */
  .odf-phase-flow tbody td:nth-child(4)::before {
    content: "参照: ";
    font-weight: 700;
    font-size: 11px;
    color: var(--text-sub);
    display: block;
    margin-bottom: 2px;
  }
  .odf-phase-flow tbody td:nth-child(5)::before {
    content: "検査: ";
    font-weight: 700;
    font-size: 11px;
    color: var(--text-sub);
    display: block;
    margin-bottom: 2px;
  }
  .odf-phase-flow tbody td:nth-child(4),
  .odf-phase-flow tbody td:nth-child(5) {
    margin-top: 6px;
    padding-top: 6px;
    border-top: 1px solid var(--border);
  }
  .odf-phase-banner {
    padding: 12px 14px 10px;
  }
  .odf-phase-title {
    font-size: 15px;
  }
  .odf-phase-sub {
    font-size: 13px;
  }
  .odf-phase-meta {
    font-size: 11px;
  }
}
/* ── Pill 詳細ポップオーバー ── */
.odf-pill-clickable {
  cursor: pointer;
  text-decoration: underline dotted;
  text-underline-offset: 2px;
}
.odf-pill-popover {
  background: var(--panel); border: 1px solid var(--border);
  border-radius: 8px; padding: 14px 16px;
  box-shadow: 0 4px 20px rgba(0,0,0,0.3);
  max-width: 360px; min-width: 240px;
}
.odf-popover-title {
  margin: 0 0 8px; font-size: 13px; font-weight: 700;
  color: var(--accent); font-family: var(--mono);
}
.odf-popover-desc {
  margin: 0 0 10px; font-size: 13px; color: var(--text); line-height: 1.6;
}
.odf-popover-meta {
  margin: 0 0 4px; font-size: 11px; color: var(--text-sub);
}
.odf-popover-close {
  display: block; margin: 10px auto 0; padding: 4px 16px;
  border: 1px solid var(--border); border-radius: 4px;
  background: var(--panel-2); color: var(--text);
  font-size: 12px; cursor: pointer;
}
.odf-popover-close:hover { background: var(--accent); color: #fff; }
.odf-popover-overlay {
  position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 9998;
}
.odf-bottom-sheet {
  position: fixed; bottom: 0; left: 0; right: 0;
  border-radius: 16px 16px 0 0; max-width: none;
  z-index: 9999; padding: 20px 16px 24px;
  animation: odf-slide-up 0.2s ease-out;
}
@keyframes odf-slide-up {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}
/* ── サンプル画像ギャラリー ── */
.odf-sample-gallery {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 12px; margin: 12px 0 0;
}
.odf-sample-figure {
  margin: 0; border: 1px solid var(--border); border-radius: 6px; overflow: hidden;
}
.odf-sample-img {
  width: 100%; height: auto; display: block;
}
.odf-sample-caption {
  padding: 8px 10px; font-size: 11px; color: var(--text-sub);
  background: var(--panel-2); line-height: 1.5;
}
`;
  document.head.appendChild(style);
}

function showPillDetail(item, event) {
  document.querySelectorAll(".odf-pill-popover, .odf-popover-overlay").forEach(e => e.remove());

  const isMobile = window.innerWidth <= 720;

  const content = [];
  content.push(el("h4", { class: "odf-popover-title" }, item.text.split("（")[0].trim()));
  content.push(el("p", { class: "odf-popover-desc" }, item.desc));
  if (item.meta) {
    content.push(el("p", { class: "odf-popover-meta" }, item.meta));
  }
  const closeBtn = el("button", { class: "odf-popover-close", type: "button" }, "閉じる");

  if (isMobile) {
    const bg = el("div", { class: "odf-popover-overlay" });
    const sheet = el("div", { class: "odf-pill-popover odf-bottom-sheet" }, [...content, closeBtn]);
    const close = () => { sheet.remove(); bg.remove(); };
    closeBtn.addEventListener("click", close);
    bg.addEventListener("click", close);
    document.body.appendChild(bg);
    document.body.appendChild(sheet);
  } else {
    const pop = el("div", { class: "odf-pill-popover" }, [...content, closeBtn]);
    closeBtn.addEventListener("click", () => pop.remove());
    const rect = event.target.getBoundingClientRect();
    pop.style.position = "fixed";
    pop.style.zIndex = "9999";
    const spaceBelow = window.innerHeight - rect.bottom;
    if (spaceBelow > 200) {
      pop.style.top = (rect.bottom + 8) + "px";
    } else {
      pop.style.bottom = (window.innerHeight - rect.top + 8) + "px";
    }
    pop.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - 380)) + "px";
    document.body.appendChild(pop);
    setTimeout(() => {
      document.addEventListener("click", function handler(e) {
        if (!pop.contains(e.target)) { pop.remove(); document.removeEventListener("click", handler); }
      });
    }, 10);
  }
}

function buildOverviewPanel(def) {
  const panel = el("div", { class: "odf-tab-panel" });

  const overviewSteps = (def.steps || []).filter((s) => s.section === "overview");
  const routeSteps = (def.steps || []).filter((s) => s.section === "routes");

  // グループ 1: 対比カード（n:1-2）
  const compareSteps = overviewSteps.filter((s) => s.n === 1 || s.n === 2);
  if (compareSteps.length > 0) {
    panel.appendChild(el("h3", { class: "odf-section-title" }, "チャット実装依頼との違い"));
    const compareRow = el("div", { class: "odf-compare-row" });
    compareSteps.forEach((step) => {
      const isBefore = step.n === 1;
      const bullets = (step.detail || "").split("。").filter((s) => s.trim());
      const ul = el("ul", {});
      bullets.forEach((b) => ul.appendChild(el("li", {}, b.trim())));
      compareRow.appendChild(el("div", { class: `odf-compare-card ${isBefore ? "is-before" : "is-after"}` }, [
        el("h4", {}, step.featureTitle || step.title),
        ul,
      ]));
    });
    panel.appendChild(compareRow);
  }

  // グループ 2: 特徴カード（n:3-5）
  const featureSteps = overviewSteps.filter((s) => s.n >= 3);
  if (featureSteps.length > 0) {
    panel.appendChild(el("h3", { class: "odf-section-title" }, "3 つの特徴"));
    featureSteps.forEach((step) => {
      const bullets = (step.detail || "").split("。").filter((s) => s.trim());
      const ul = el("ul", {});
      bullets.forEach((b) => ul.appendChild(el("li", {}, b.trim())));
      const card = el("div", { class: "odf-feature-card" });
      card.appendChild(el("h4", {}, step.featureTitle || step.title));
      card.appendChild(ul);
      if (step.sampleImages && step.sampleImages.length > 0) {
        const gallery = el("div", { class: "odf-sample-gallery" });
        step.sampleImages.forEach((img) => {
          const figure = el("figure", { class: "odf-sample-figure" });
          figure.appendChild(el("img", { src: img.src, alt: img.alt, class: "odf-sample-img", loading: "lazy" }));
          figure.appendChild(el("figcaption", { class: "odf-sample-caption" }, img.caption));
          gallery.appendChild(figure);
        });
        card.appendChild(gallery);
      }
      // 特徴 2（n:4）にステータスバー表示例を挿入
      if (step.n === 4) {
        const statusDemo = el("div", { class: "odf-status-demo" });
        statusDemo.appendChild(el("p", { class: "odf-status-desc" }, "ステータスライン表示例:"));
        const statusLine = el("div", { class: "odf-status-line" });
        statusLine.appendChild(el("span", { class: "odf-status-icon" }, "⚙"));
        statusLine.appendChild(el("span", { class: "odf-status-phase" }, "Phase 1"));
        statusLine.appendChild(el("span", { class: "odf-status-name" }, "調査 + ルート判定"));
        statusLine.appendChild(el("span", { class: "odf-status-bar" }, "▰▰▰▱▱▱"));
        statusLine.appendChild(el("span", { class: "odf-status-count" }, "3/6"));
        statusLine.appendChild(el("span", { class: "odf-status-step" }, "タスク内容の確認"));
        statusDemo.appendChild(statusLine);
        card.appendChild(statusDemo);
      }
      panel.appendChild(card);
    });
  }

  // グループ 3: ルート一覧テーブル
  if (routeSteps.length > 0) {
    panel.appendChild(el("h3", { class: "odf-section-title" }, "5 ルート一覧"));
    const table = el("table", { class: "odf-route-table" });
    const thead = el("thead", {});
    const headerRow = el("tr", {});
    ["識別子", "日本語名", "用途", "承認"].forEach((h) => {
      headerRow.appendChild(el("th", {}, h));
    });
    thead.appendChild(headerRow);
    table.appendChild(thead);

    const tbody = el("tbody", {});
    routeSteps.forEach((step) => {
      const tr = el("tr", {});
      tr.appendChild(el("td", {}, el("code", {}, step.routeId || "")));
      tr.appendChild(el("td", {}, step.routeName || ""));
      tr.appendChild(el("td", {}, step.useCase || ""));
      tr.appendChild(el("td", {},
        el("span", { class: step.approvalYes ? "odf-badge-yes" : "odf-badge-no" }, step.approval || "")
      ));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    panel.appendChild(table);
  }

  return panel;
}

function buildPhasesPanel(def) {
  const panel = el("div", { class: "odf-tab-panel" });

  const phaseSteps = (def.steps || []).filter((s) => s.section === "phases");

  panel.appendChild(el("p", { class: "odf-intro-note" },
    "ルートフィルターで表示 Phase を絞り込める。承認が必要な停止点は ⛔ で強調表示する。"
  ));

  // ルートフィルターバー
  const routeFilters = [
    { route: "all",      label: "全表示" },
    { route: "full",     label: "フル計画" },
    { route: "quick",    label: "クイック" },
    { route: "config",   label: "設定・docs" },
    { route: "refactor", label: "リファクタ" },
    { route: "incident", label: "障害復旧" },
  ];
  const filterBar = el("div", { class: "odf-route-filter-bar" }, [
    el("span", { class: "odf-filter-label" }, "絞り込み:"),
  ]);
  const filterBtns = {};
  routeFilters.forEach(({ route, label }) => {
    const btn = el("button", {
      class: `odf-route-btn${route === "all" ? " active" : ""}`,
      type: "button",
    }, label);
    filterBtns[route] = btn;
    filterBar.appendChild(btn);
  });
  panel.appendChild(filterBar);

  // Phase カード
  const cardsContainer = el("div", { class: "odf-phase-cards" });
  const phaseCards = [];

  phaseSteps.forEach((step) => {
    const routesAttr = (step.routes || ["all"]).join(" ");
    let colorClass = "";
    if (step.color === "gold")   colorClass = " color-gold";
    if (step.color === "danger") colorClass = " color-danger";

    const card = el("section", {
      class: `odf-phase-card${colorClass}`,
      "data-routes": routesAttr,
    });

    const eyebrow = `Phase ${step.phase || step.n}`;
    const banner = el("header", { class: "odf-phase-banner" });
    banner.appendChild(el("span", { class: "odf-phase-eyebrow" }, eyebrow));
    banner.appendChild(el("span", { class: "odf-phase-title" }, step.phaseTitle || step.title));
    const subText = step.flowSummary || step.detail;
    if (subText) {
      const goalMatch = subText.match(/^「(.+?)」(.+)$/);
      if (goalMatch) {
        const subLine = el("p", { class: "odf-phase-sub" });
        subLine.appendChild(el("span", { class: "odf-phase-goal" }, goalMatch[1]));
        subLine.appendChild(document.createTextNode(" "));
        subLine.appendChild(el("span", { class: "odf-phase-flow-line" }, goalMatch[2].trim()));
        banner.appendChild(subLine);
      } else {
        banner.appendChild(el("p", { class: "odf-phase-sub" }, subText));
      }
    }
    if (step.skill) {
      banner.appendChild(el("span", { class: "odf-skill-badge" }, `Skill("${step.skill}")`));
    }
    if (step.stop) {
      const stopText = step.stopDetail ? `⛔ 停止: ${step.stopDetail}` : "⛔ 停止点";
      banner.appendChild(el("span", { class: "odf-stop-badge" }, stopText));
    }
    // 構造化メタ（適用ルート・完了条件・呼び出しスキル）
    const ROUTE_LABELS = { full: "フル計画", quick: "クイック", config: "設定・docs", refactor: "リファクタ", incident: "障害復旧" };
    const routeLabels = (step.routes || []).map((r) => ROUTE_LABELS[r] || r).join(" / ");
    const metaDl = el("dl", { class: "odf-phase-meta" });
    metaDl.appendChild(el("dt", {}, "適用ルート"));
    metaDl.appendChild(el("dd", {}, routeLabels));
    if (step.completionCondition) {
      metaDl.appendChild(el("dt", {}, "完了条件"));
      metaDl.appendChild(el("dd", {}, step.completionCondition));
    }
    if (step.skill) {
      metaDl.appendChild(el("dt", {}, "呼び出しスキル"));
      metaDl.appendChild(el("dd", {}, `Skill("${step.skill}")`));
    }
    banner.appendChild(metaDl);
    card.appendChild(banner);
    if (step.phaseSteps && step.phaseSteps.length > 0) {
      const table = el("table", { class: "odf-phase-flow" });
      const cg = el("colgroup");
      ["col-num", "col-step", "col-when", "col-refs", "col-check"].forEach((c) =>
        cg.appendChild(el("col", { class: c })));
      table.appendChild(cg);

      const thead = el("thead");
      const hr = el("tr");
      ["#", "ステップ", "タイミング", "参照（規約 / スキル）", "検査（Hook）"].forEach((h, i) => {
        const cls = ["col-num", "col-step", "col-when", "col-refs", "col-check"][i];
        hr.appendChild(el("th", { scope: "col", class: cls }, h));
      });
      thead.appendChild(hr);
      table.appendChild(thead);

      const tbody = el("tbody");
      step.phaseSteps.forEach((ps) => {
        const tr = el("tr");
        tr.appendChild(el("td", { class: "cell-num" }, ps.id));

        const stepTd = el("td", { class: "cell-step" });
        stepTd.appendChild(document.createTextNode(ps.title));
        if (ps.detail) {
          stepTd.appendChild(el("span", { class: "odf-step-detail" }, ps.detail));
        }
        if (ps.completionCondition) {
          const cc = el("span", { class: "odf-step-completion" }, ps.completionCondition);
          stepTd.appendChild(cc);
        }
        tr.appendChild(stepTd);

        const whenTd = el("td", { class: "cell-when" });
        if (ps.timing) whenTd.appendChild(el("span", { class: "odf-timing-tag" }, ps.timing));
        tr.appendChild(whenTd);

        const refsTd = el("td");
        (ps.refs || []).forEach((r) => {
          const span = el("span", { class: "odf-" + r.type }, r.text);
          if (r.desc) {
            span.classList.add("odf-pill-clickable");
            span.addEventListener("click", (e) => { e.stopPropagation(); showPillDetail(r, e); });
          }
          refsTd.appendChild(span);
        });
        tr.appendChild(refsTd);

        const checksTd = el("td");
        (ps.checks || []).forEach((c) => {
          const span = el("span", { class: "odf-" + c.type }, c.text);
          if (c.desc) {
            span.classList.add("odf-pill-clickable");
            span.addEventListener("click", (e) => { e.stopPropagation(); showPillDetail(c, e); });
          }
          checksTd.appendChild(span);
        });
        tr.appendChild(checksTd);

        tbody.appendChild(tr);
      });
      table.appendChild(tbody);
      card.appendChild(table);
    }
    cardsContainer.appendChild(card);
    phaseCards.push(card);
  });

  panel.appendChild(cardsContainer);

  // フィルターイベント
  routeFilters.forEach(({ route }) => {
    filterBtns[route].addEventListener("click", () => {
      routeFilters.forEach(({ route: r }) => {
        filterBtns[r].classList.toggle("active", r === route);
      });
      phaseCards.forEach((card) => {
        const routes = (card.dataset.routes || "").split(" ");
        const show = route === "all" || routes.includes("all") || routes.includes(route);
        card.hidden = !show;
      });
    });
  });

  return panel;
}

function buildSetupPanel(_def) {
  const panel = el("div", { class: "odf-tab-panel" });

  // ── Section 1: 起動前チェック ──────────────────────────────────────
  panel.appendChild(el("h3", { class: "odf-section-title" }, "起動前チェック"));
  panel.appendChild(el("p", { class: "odf-intro-note" },
    "フロー開始時に毎回自動実行され、プロジェクトの前提条件を検証します。"
  ));

  const preflightBox = el("div", { class: "odf-prereq" });
  preflightBox.appendChild(el("h3", {}, "チェック項目"));
  const checkUl = el("ul", {});
  [
    "flow-values.yml の存在確認（存在しなければ初回セットアップを案内）",
    "flow-values.yml の YAML 構文検証",
    "必須ツールの可用性チェック + 自動インストール",
  ].forEach((text) => {
    const li = el("li", {});
    li.textContent = text;
    checkUl.appendChild(li);
  });
  preflightBox.appendChild(checkUl);
  panel.appendChild(preflightBox);

  const resultBox = el("div", { class: "odf-prereq" });
  resultBox.appendChild(el("h3", {}, "実行結果"));
  const resultUl = el("ul", {});
  [
    ["go", "（全 PASS）→ フロー開始"],
    ["no-go", "（FAIL あり）→ 修正方法を案内"],
  ].forEach(([label, rest]) => {
    const li = el("li", {});
    const strong = el("strong", {}, label);
    li.appendChild(strong);
    li.appendChild(document.createTextNode(rest));
    resultUl.appendChild(li);
  });
  resultBox.appendChild(resultUl);
  panel.appendChild(resultBox);

  // ── Section 2: 初回セットアップ ───────────────────────────────────
  panel.appendChild(el("h3", { class: "odf-section-title" }, "初回セットアップ"));
  panel.appendChild(el("p", { class: "odf-intro-note" },
    "初めてのプロジェクトでは creating-new-project スキル（references/scaffolding-flow-structure.md）を実行し、以下のファイルを自動生成します。"
  ));

  const scaffoldTable = el("table", { class: "odf-route-table" });
  const scaffoldThead = el("thead", {});
  const scaffoldHr = el("tr", {});
  ["ファイル", "役割"].forEach((h) => scaffoldHr.appendChild(el("th", {}, h)));
  scaffoldThead.appendChild(scaffoldHr);
  scaffoldTable.appendChild(scaffoldThead);
  const scaffoldTbody = el("tbody", {});
  [
    [".claude/rules/always/project-context/flow-values.yml", "プロジェクト固有の設定（ルート判定閾値・設計書パス・レビューゲート・E2E 設定等）"],
    [".claude/skills/flow-config/layers.yml",       "アーキテクチャ層定義（FE / API / DB の境界）"],
    ["project-portal/",                             "成果物置き場（リリースノート・画面 UI モック履歴）"],
    [".github/pull_request_template.md",            "PR テンプレート"],
  ].forEach(([file, role]) => {
    const tr = el("tr", {});
    tr.appendChild(el("td", {}, el("code", {}, file)));
    tr.appendChild(el("td", {}, role));
    scaffoldTbody.appendChild(tr);
  });
  scaffoldTable.appendChild(scaffoldTbody);
  panel.appendChild(scaffoldTable);

  // ── Section 3: flow-values.yml の構成 ────────────────────────────
  panel.appendChild(el("h3", { class: "odf-section-title" }, "flow-values.yml の構成"));

  const contextTable = el("table", { class: "odf-route-table" });
  const contextThead = el("thead", {});
  const contextHr = el("tr", {});
  ["セクション", "用途", "読み込み Phase"].forEach((h) => contextHr.appendChild(el("th", {}, h)));
  contextThead.appendChild(contextHr);
  contextTable.appendChild(contextThead);
  const contextTbody = el("tbody", {});
  [
    ["context_a",    "プロジェクト基本情報（アーキテクチャ・用語集・技術スタック）", "Phase 1"],
    ["context_b",    "開発規約（デザイン・テスト）",                                "Phase 3"],
    ["classify",     "ルート判定の閾値設定",                                        "Phase 1"],
    ["review_gates", "レビューゲートのスキル名",                                    "Phase 6, 8, 10"],
    ["scripts",      "ユーティリティスクリプトのパス",                              "各 Phase"],
    ["pr",           "PR テンプレート・必須セクション",                             "Phase 9, 11"],
    ["e2e",          "E2E テスト設定",                                             "Phase 8"],
  ].forEach(([section, usage, phase]) => {
    const tr = el("tr", {});
    tr.appendChild(el("td", {}, el("code", {}, section)));
    tr.appendChild(el("td", {}, usage));
    tr.appendChild(el("td", {}, phase));
    contextTbody.appendChild(tr);
  });
  contextTable.appendChild(contextTbody);
  panel.appendChild(contextTable);

  return panel;
}

function renderOrchestratingFlow(def, root) {
  injectOrchestratingCSS();

  const parent = parentOf(def);

  // パンくず
  root.appendChild(el("div", {
    class: "doc-crumbs",
    html: `<a href="#/">TOP</a> / <a href="${parent.href}">${parent.label}</a> / ${def.title}`,
  }));

  // Hero バナー（impl-flow.html に合わせて青いグラデーション）
  const heroDiv = el("div", { class: "hero" });
  heroDiv.appendChild(el("h1", {}, def.title));
  if (def.summary) heroDiv.appendChild(el("p", {}, def.summary));
  root.appendChild(heroDiv);

  // タブバー
  const tabIds = ["overview", "phases", "setup"];
  const tabLabels = { overview: "概要", phases: "フロー解説", setup: "事前準備" };
  const tabBtns = {};
  const tabBar = el("div", { class: "odf-tab-bar" });
  tabIds.forEach((tabId) => {
    const btn = el("button", {
      class: `odf-tab${tabId === "overview" ? " active" : ""}`,
      type: "button",
      "data-tab-id": tabId,
    }, tabLabels[tabId]);
    tabBtns[tabId] = btn;
    tabBar.appendChild(btn);
  });
  root.appendChild(tabBar);

  // パネル生成
  const overviewPanel = buildOverviewPanel(def);
  const phasesPanel   = buildPhasesPanel(def);
  const setupPanel    = buildSetupPanel(def);

  phasesPanel.hidden = true;
  setupPanel.hidden  = true;

  root.appendChild(overviewPanel);
  root.appendChild(phasesPanel);
  root.appendChild(setupPanel);

  // タブ切替ロジック（イベント委任: tabBar 単体にリスナーを置く）
  const panels = { overview: overviewPanel, phases: phasesPanel, setup: setupPanel };
  function switchTab(name) {
    tabIds.forEach((tabId) => {
      tabBtns[tabId].classList.toggle("active", tabId === name);
      panels[tabId].hidden = tabId !== name;
    });
  }
  tabBar.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-tab-id]");
    if (!btn) return;
    switchTab(btn.dataset.tabId);
  });

  root.appendChild(backLink(def));
}

// ─────────────────────────────────────────────────────────────────────────────

export function renderFlowDetail(flowId, root) {
  const def = getFlow(flowId);
  root.innerHTML = "";

  if (!def) {
    root.appendChild(el("div", { class: "doc-crumbs", html: `<a href="#/">TOP</a> / <a href="${DEFAULT_PARENT.href}">${DEFAULT_PARENT.label}</a> / 不明なフロー` }));
    root.appendChild(el("p", { class: "card-desc" }, `フローが見つかりません: ${flowId}`));
    root.appendChild(backLink(null));
    return;
  }

  // orchestrating-dev-flow は専用レンダラーで描画する
  if (def.id === "orchestrating-dev-flow") {
    renderOrchestratingFlow(def, root);
    return;
  }

  const parent = parentOf(def);

  // パンくず
  root.appendChild(el("div", {
    class: "doc-crumbs",
    html: `<a href="#/">TOP</a> / <a href="${parent.href}">${parent.label}</a> / ${def.title}`,
  }));

  // 見出し
  root.appendChild(el("div", { class: "section-header" }, [
    el("h2", { class: "section-title" }, def.title),
    def.badge ? el("span", { class: "card-badge" }, def.badge) : null,
  ]));

  // 概要
  if (def.summary) root.appendChild(el("p", { class: "flow-summary" }, def.summary));

  // トリガー（強調ボックス）
  if (def.trigger) {
    root.appendChild(el("div", { class: "flow-trigger" }, [
      el("span", { class: "flow-trigger-label" }, "発火タイミング"),
      el("span", { class: "flow-trigger-body" }, def.trigger),
    ]));
  }

  // ステップ
  const steps = def.steps || [];
  if (steps.length > 0) {
    root.appendChild(el("div", { class: "cat-sub-head" }, [
      el("h3", { class: "cat-sub-title" }, "ステップ"),
      el("span", { class: "cat-sub-count" }, String(steps.length)),
    ]));
    const cards = el("div", { class: "cards" });
    steps.forEach((s) => cards.appendChild(stepCard(s)));
    root.appendChild(cards);
  }

  // 図（ASCII / 矢印）
  if (def.diagram) {
    root.appendChild(el("div", { class: "cat-sub-head" }, [
      el("h3", { class: "cat-sub-title" }, "フロー図"),
    ]));
    root.appendChild(el("pre", { class: "flow-diagram" }, def.diagram));
  }

  // 関連スキル（チップ列）
  const skills = def.relatedSkills || [];
  if (skills.length > 0) {
    root.appendChild(el("div", { class: "cat-sub-head" }, [
      el("h3", { class: "cat-sub-title" }, "関連スキル・hook"),
    ]));
    const chips = el("div", { class: "flow-chips" });
    skills.forEach((s) => chips.appendChild(el("span", { class: "flow-chip" }, s)));
    root.appendChild(chips);
  }

  // 注意
  const notes = def.notes || [];
  if (notes.length > 0) {
    root.appendChild(el("div", { class: "cat-sub-head" }, [
      el("h3", { class: "cat-sub-title" }, "注意・例外"),
    ]));
    const ul = el("ul", { class: "flow-notes" });
    notes.forEach((n) => ul.appendChild(el("li", {}, n)));
    root.appendChild(ul);
  }

  root.appendChild(backLink(def));
}
