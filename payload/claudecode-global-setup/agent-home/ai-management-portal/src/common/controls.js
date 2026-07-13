// ai-management-portal 共通: ボタン生成・フラッシュ表示・portalRoot 解決の共有ヘルパー。
// header.js と page-actions.js の両方から import する（循環 import 回避のための分離）。

export function makeBtn({ iconName, ariaLabel, labelText, onClick }) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "dp-btn";
  btn.setAttribute("aria-label", ariaLabel);
  btn.title = ariaLabel;
  const ic = document.createElement("span");
  ic.className = "material-symbols-outlined";
  ic.setAttribute("aria-hidden", "true");
  ic.setAttribute("translate", "no");
  ic.textContent = iconName;
  btn.appendChild(ic);
  if (labelText) {
    const lab = document.createElement("span");
    lab.className = "dp-btn-label";
    lab.textContent = labelText;
    btn.appendChild(lab);
  }
  btn.addEventListener("click", onClick);
  return { btn, iconEl: ic, labelEl: btn.querySelector(".dp-btn-label") };
}

export function flashBtn(ctl, msg) {
  const prev = ctl.labelEl?.textContent;
  if (ctl.labelEl) ctl.labelEl.textContent = msg;
  setTimeout(() => { if (ctl.labelEl && prev != null) ctl.labelEl.textContent = prev; }, 1500);
}

export function findPortalRoot() {
  const u = new URL(location.href);
  const pieces = u.pathname.split("/");
  const i = pieces.lastIndexOf("ai-management-portal");
  if (i < 0) return null;
  pieces.length = i + 1;
  return u.origin + pieces.join("/") + "/";
}
