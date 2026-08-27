export class SourcePreparationError extends Error {
  constructor(category, code, message, location) {
    super(message);
    this.name = "SourcePreparationError";
    this.category = category;
    this.code = code;
    if (location !== undefined) this.location = Object.freeze({ ...location });
  }
}
