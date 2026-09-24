import { createZ80Runtime, parseIntelHex } from "@jhlagado/z80-runtime";

/**
 * The smallest execution seam needed by the native Atom host.
 *
 * A production host supplies the pinned native Atom image and the address of
 * its entry point. The returned execution object intentionally exposes only
 * the machine surface used by the runner: `hardware.memory`, `cpu` and
 * `step()`. Debug80 is the development/reference adapter today; another host
 * can implement this factory without importing Debug80 into the runner.
 */
export const createDebug80ExecutionAdapter = () => {
  const parseImage = (hexText) => {
    if (typeof hexText !== "string") {
      throw new TypeError("execution image must be Intel HEX text");
    }
    return parseIntelHex(hexText);
  };
  return Object.freeze({
    parseImage,
    create({ hexText, entry, romRanges }) {
      if (!Number.isInteger(entry) || entry < 0 || entry > 0xffff) {
        throw new TypeError("execution entry must be a Z80 address");
      }
      if (!Array.isArray(romRanges)) {
        throw new TypeError("execution ROM ranges must be an array");
      }
      return createZ80Runtime(parseImage(hexText), entry, undefined, {
        romRanges,
      });
    },
  });
};
