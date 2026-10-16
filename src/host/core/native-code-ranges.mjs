// Code and immutable-table ranges of a native Atom core, by ledger name.
const CODE_RANGE_NAMES = Object.freeze([
  ["AtomRadix40CodeStart", "AtomRadix40CodeEnd"],
  ["AtomRecognitionCodeStart", "AtomRecognitionCodeEnd"],
  ["AtomEncoderCoreStart", "AtomEncoderCoreEnd"],
  ["AtomSymbolCodeStart", "AtomSymbolCodeEnd"],
  ["AtomTokenizerCodeStart", "AtomTokenizerCodeEnd"],
  ["AtomExpressionCodeStart", "AtomExpressionCodeEnd"],
  ["AtomPatchCodeStart", "AtomPatchCodeEnd"],
  ["AtomParserCodeStart", "AtomParserCodeEnd"],
  ["AtomReferenceCodeStart", "AtomReferenceCodeEnd"],
  ["AtomOutputCodeStart", "AtomOutputCodeEnd"],
  ["AtomStatementCodeStart", "AtomStatementCodeEnd"],
  ["AtomDriverCodeStart", "AtomDriverCodeEnd"],
  ["AtomFrontCodeStart", "AtomFrontCodeEnd"],
  ["AtomHostServiceCodeStart", "AtomHostServiceCodeEnd"],
]);

// Use the ranges this core defines, in address order. A range nested in
// another, such as an older core's packer inside its encoder, adds nothing.
export function nativeCodeRanges(symbols) {
  return Object.freeze(CODE_RANGE_NAMES
    .filter(([startName, endName]) => Number.isInteger(symbols[startName]) && Number.isInteger(symbols[endName]))
    .map(([startName, endName]) => ({ start: symbols[startName], end: symbols[endName] }))
    .sort((left, right) => left.start - right.start || right.end - left.end)
    .filter((range, index, ranges) => !ranges.slice(0, index).some((outer) => range.start >= outer.start && range.end <= outer.end))
    .map((range) => Object.freeze(range)));
}
