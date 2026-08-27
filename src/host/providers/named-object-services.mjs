import {
  NAMED_OBJECT_OPERATION as SHARED_NAMED_OBJECT_OPERATION,
  NAMED_OBJECT_REQUEST as SHARED_NAMED_OBJECT_REQUEST,
  NAMED_OBJECT_STATUS as SHARED_NAMED_OBJECT_STATUS,
} from "@jhlagado/z80-tool-services";

export {
  MemoryNamedObjectProvider as MemoryNamedObjectServices,
  NAMED_OBJECT_ABI_VERSION,
  NAMED_OBJECT_REQUEST_SIZE,
  NamedObjectClient,
} from "@jhlagado/z80-tool-services";

// Preserve Atom's existing immutable public constant objects while the shared
// package remains their numeric authority.
export const NAMED_OBJECT_REQUEST = Object.freeze({
  ...SHARED_NAMED_OBJECT_REQUEST,
});
export const NAMED_OBJECT_OPERATION = Object.freeze({
  ...SHARED_NAMED_OBJECT_OPERATION,
});
export const NAMED_OBJECT_STATUS = Object.freeze({
  ...SHARED_NAMED_OBJECT_STATUS,
});
