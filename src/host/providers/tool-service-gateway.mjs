import {
  dispatchConsoleExitFailure,
  dispatchConsoleExitSuccess,
  dispatchConsoleRead,
  dispatchConsoleWrite,
  dispatchSourceByteRead,
  normalizeOneByteStatus,
} from "@jhlagado/z80-tool-services";

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

const ATOM_STATUS_POLICY = Object.freeze({
  success: ATOM_TOOL_STATUS.success,
  unavailable: ATOM_TOOL_STATUS.unavailable,
  invalid: ATOM_TOOL_STATUS.invalid,
  exception: ATOM_TOOL_STATUS.invalid,
});

const status = (value) => normalizeOneByteStatus(value, ATOM_STATUS_POLICY);

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
        case ATOM_TOOL_SERVICE.consoleRead:
          return Object.freeze(dispatchConsoleRead(console, ATOM_STATUS_POLICY));
        case ATOM_TOOL_SERVICE.consoleWrite:
          return Object.freeze(
            dispatchConsoleWrite(
              console,
              Object.freeze({ ...request }),
              ATOM_STATUS_POLICY,
            ),
          );
        case ATOM_TOOL_SERVICE.exitSuccess:
          return Object.freeze(
            dispatchConsoleExitSuccess(console, ATOM_STATUS_POLICY),
          );
        case ATOM_TOOL_SERVICE.exitFailure:
          return Object.freeze(
            dispatchConsoleExitFailure(
              console,
              Object.freeze({ ...request }),
              ATOM_STATUS_POLICY,
            ),
          );
        case ATOM_TOOL_SERVICE.sourceRead: {
          return Object.freeze(
            dispatchSourceByteRead(
              {
                read(part, offset) {
                  return sourceRead(Object.freeze({ part, offset }));
                },
              },
              Object.freeze({ ...request }),
              ATOM_STATUS_POLICY,
            ),
          );
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
