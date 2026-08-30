import {
  OutputPublicationError,
  publishOutputFiles,
} from "@jhlagado/z80-tool-services";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

function fail(code, message, cause) {
  throw new AtomAssemblyError("publication", code, message, { cause });
}

export async function publishAtomOutputFiles(outputs, { filesystem } = {}) {
  try {
    return await publishOutputFiles(outputs, {
      filesystem,
      tagPrefix: "atom",
    });
  } catch (error) {
    if (error instanceof OutputPublicationError) {
      const message = error.code === "output-transaction"
        ? "cannot publish the requested Atom outputs"
        : error.message;
      fail(error.code, message, error.cause);
    }
    throw error;
  }
}
