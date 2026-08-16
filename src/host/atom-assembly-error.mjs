export class AtomAssemblyError extends Error {
  constructor(category, code, message, details = {}) {
    super(message, details.cause === undefined ? undefined : { cause: details.cause });
    this.name = "AtomAssemblyError";
    this.category = category;
    this.code = code;
    for (const [key, value] of Object.entries(details)) {
      if (key !== "cause") this[key] = value;
    }
    Object.freeze(this);
  }
}
