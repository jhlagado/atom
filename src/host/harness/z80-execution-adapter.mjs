import { createZ80Runtime, parseIntelHex } from "@jhlagado/z80-runtime";

/**
 * Adapt the Debug80 CPU runtime to the Atom runner's memory, CPU and step
 * interface. The caller supplies the resident image, entry address and ROM
 * ranges. Other CPU adapters can supply this interface without changing the
 * runner's host-service dispatch.
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
