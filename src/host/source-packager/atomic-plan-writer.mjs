import * as nodeFilesystem from "node:fs/promises";
import path from "node:path";

import { SourcePackagerError } from "./errors.mjs";
import { parseSourcePlan, serializeSourcePlan } from "./source-plan.mjs";

let temporaryOrdinal = 0;

function outputError(code, message, cause) {
  const error = new SourcePackagerError("output", code, message);
  error.cause = cause;
  return error;
}

export async function writeSourcePlanAtomically(
  destination,
  plan,
  { filesystem = nodeFilesystem, limits } = {},
) {
  const bytes = serializeSourcePlan(plan, limits);
  parseSourcePlan(bytes, limits);

  temporaryOrdinal += 1;
  const temporaryPath = path.join(
    path.dirname(destination),
    `.${path.basename(destination)}.tmp-${process.pid}-${temporaryOrdinal}`,
  );
  let handle;
  let ownsTemporaryPath = false;
  try {
    try {
      handle = await filesystem.open(temporaryPath, "wx");
      ownsTemporaryPath = true;
      await handle.writeFile(bytes);
      await handle.sync();
      await handle.close();
      handle = undefined;
    } catch (error) {
      throw outputError("plan-write-failed", "cannot write temporary source plan", error);
    }

    try {
      await filesystem.rename(temporaryPath, destination);
    } catch (error) {
      throw outputError("plan-rename-failed", "cannot publish source plan", error);
    }
  } catch (error) {
    if (handle !== undefined) {
      try { await handle.close(); } catch { /* retain the original failure */ }
    }
    if (ownsTemporaryPath) {
      try { await filesystem.unlink(temporaryPath); } catch { /* temp may not exist */ }
    }
    throw error;
  }
  return bytes;
}
