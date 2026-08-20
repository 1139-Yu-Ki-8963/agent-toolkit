// フロー詳細データのレジストリ。
// 各セクションのフロー定義をまとめ、id → 定義の Map で引けるようにする。
import { DEV_FLOWS } from "./dev.js";
import { REVIEW_FLOWS } from "./review.js";
import { OPS_FLOWS } from "./ops.js";
import { WRITING_FLOWS } from "./writing.js";
import { ENFORCE_FLOWS } from "./enforce.js";
import { OBSERVE_FLOWS } from "./observe.js";
import { ORCHESTRATION_FLOWS } from "./orchestration.js";

const ALL = [
  ...DEV_FLOWS,
  ...REVIEW_FLOWS,
  ...OPS_FLOWS,
  ...WRITING_FLOWS,
  ...ENFORCE_FLOWS,
  ...OBSERVE_FLOWS,
  ...ORCHESTRATION_FLOWS,
];

const BY_ID = new Map(ALL.map((f) => [f.id, f]));

export function getFlow(id) {
  return BY_ID.get(id) || null;
}

export const FLOW_COUNT = ALL.length;
