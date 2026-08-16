export class SourcePackagerError extends Error {
  constructor(category, code, message, location) {
    super(message);
    this.name = "SourcePackagerError";
    this.category = category;
    this.code = code;
    if (location !== undefined) this.location = Object.freeze({ ...location });
  }
}
