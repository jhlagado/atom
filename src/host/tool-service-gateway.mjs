export const ATOM_TOOL_SERVICE = Object.freeze({
  consoleRead: "consoleRead",
  consoleWrite: "consoleWrite",
  exitSuccess: "exitSuccess",
  exitFailure: "exitFailure",
  sourceRead: "sourceRead",
  begin: "begin",
  image: "image",
  patch: "patch",
  commit: "commit",
  abort: "abort",
});

export const ATOM_TOOL_STATUS = Object.freeze({
  success: 0,
  unavailable: 2,
  invalid: 0xfe,
});

function status(value) {
  const result = value === undefined ? ATOM_TOOL_STATUS.success : value;
  return Number.isInteger(result) && result >= 0 && result <= 0xff
    ? result
    : ATOM_TOOL_STATUS.invalid;
}

function byte(value) {
  return Number.isInteger(value) && value >= 0 && value <= 0xff
    ? value
    : undefined;
}

/**
 * Build Atom's private direct-host tool-service gateway. The resident core
 * retains its compact source and publication entries; this gateway is the
 * single provider dispatch point beneath those entries.
 */
export function createAtomToolServiceGateway({ sourceRead, sink, console } = {}) {
  if (typeof sourceRead !== "function") {
    throw new TypeError("Atom tool services require sourceRead()");
  }
  for (const operation of ["begin", "image", "patch", "commit", "abort"]) {
    if (typeof sink?.[operation] !== "function") {
      throw new TypeError(`Atom tool services require sink.${operation}()`);
    }
  }

  return Object.freeze({
    dispatch(operation, request = Object.freeze({})) {
      switch (operation) {
        case ATOM_TOOL_SERVICE.consoleRead: {
          if (typeof console?.read !== "function") {
            return Object.freeze({ status: ATOM_TOOL_STATUS.unavailable });
          }
          const value = byte(console.read());
          return value === undefined
            ? Object.freeze({ status: ATOM_TOOL_STATUS.invalid })
            : Object.freeze({ status: ATOM_TOOL_STATUS.success, value });
        }
        case ATOM_TOOL_SERVICE.consoleWrite: {
          const value = byte(request.value);
          if (value === undefined) {
            return Object.freeze({ status: ATOM_TOOL_STATUS.invalid });
          }
          return Object.freeze({
            status:
              typeof console?.write === "function"
                ? status(console.write(value))
                : ATOM_TOOL_STATUS.unavailable,
          });
        }
        case ATOM_TOOL_SERVICE.exitSuccess:
          return Object.freeze({
            status:
              typeof console?.exitSuccess === "function"
                ? status(console.exitSuccess())
                : ATOM_TOOL_STATUS.unavailable,
          });
        case ATOM_TOOL_SERVICE.exitFailure: {
          const value = byte(request.status);
          if (value === undefined || value === 0) {
            return Object.freeze({ status: ATOM_TOOL_STATUS.invalid });
          }
          return Object.freeze({
            status:
              typeof console?.exitFailure === "function"
                ? status(console.exitFailure(value))
                : ATOM_TOOL_STATUS.unavailable,
          });
        }
        case ATOM_TOOL_SERVICE.sourceRead: {
          const value = byte(sourceRead(Object.freeze({ ...request })));
          return value === undefined
            ? Object.freeze({ status: ATOM_TOOL_STATUS.invalid })
            : Object.freeze({ status: ATOM_TOOL_STATUS.success, value });
        }
        case ATOM_TOOL_SERVICE.begin:
        case ATOM_TOOL_SERVICE.image:
        case ATOM_TOOL_SERVICE.patch:
        case ATOM_TOOL_SERVICE.commit:
          return Object.freeze({
            status: status(sink[operation](Object.freeze({ ...request }))),
          });
        case ATOM_TOOL_SERVICE.abort:
          return Object.freeze({ status: status(sink.abort()) });
        default:
          return Object.freeze({ status: ATOM_TOOL_STATUS.unavailable });
      }
    },
  });
}
