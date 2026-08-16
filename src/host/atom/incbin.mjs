import { SourcePackagerError } from "../source-packager/errors.mjs";

const encoder = new TextEncoder();

function fail(code, message, location) {
  throw new SourcePackagerError("preprocessing", code, message, location);
}

function linesOf(bytes) {
  const lines = [];
  let start = 0;
  let number = 1;
  while (start < bytes.length) {
    let newline = start;
    while (newline < bytes.length && bytes[newline] !== 0x0a) newline += 1;
    const contentEnd = newline > start && bytes[newline - 1] === 0x0d ? newline - 1 : newline;
    lines.push(Object.freeze({ start, contentEnd, number }));
    start = newline < bytes.length ? newline + 1 : newline;
    number += 1;
  }
  return lines;
}

function lineText(bytes, start, end) {
  let text = "";
  let ascii = true;
  for (let offset = start; offset < end; offset += 1) {
    const byte = bytes[offset];
    if (byte > 0x7f) ascii = false;
    text += String.fromCharCode(byte);
  }
  return Object.freeze({ text, ascii });
}

function locationFor(part, line, offset) {
  return Object.freeze({
    logicalIdentity: part.logicalIdentity,
    offset,
    line: line.number,
    column: offset - line.start + 1,
  });
}

function incbinAt(part, line) {
  const decoded = lineText(part.compilerBytes, line.start, line.contentEnd);
  const { text } = decoded;
  const head = /^([ \t]*(?:(?:\.[_A-Za-z][_A-Za-z0-9]*|[_A-Za-z][_A-Za-z0-9]*)[ \t]*:[ \t]*)?)INCBIN\b/i.exec(text);
  if (head === null) return undefined;
  const marker = line.start + head[1].length;
  const location = locationFor(part, line, marker);
  if (!decoded.ascii) fail("invalid-incbin", "INCBIN paths must be ASCII", location);
  const complete = /^([ \t]*(?:(?:\.[_A-Za-z][_A-Za-z0-9]*|[_A-Za-z][_A-Za-z0-9]*)[ \t]*:[ \t]*)?)INCBIN[ \t]+"([^"\r\n]+)"[ \t]*(?:;.*)?$/i.exec(text);
  if (complete === null) fail("invalid-incbin", "INCBIN requires one quoted project-relative path", location);
  return Object.freeze({ prefix: complete[1], specifier: complete[2], location });
}

function withLocation(error, location) {
  if (error instanceof SourcePackagerError && error.location === undefined) {
    return new SourcePackagerError(error.category, error.code, error.message, location);
  }
  return error;
}

function freezePart(part, compilerBytes, binaryIncludes, transformedRanges) {
  const frozenIncludes = Object.freeze(binaryIncludes.map((include) => Object.freeze({
    ...include,
    bytes: include.bytes.slice(),
  })));
  const frozenRanges = Object.freeze(transformedRanges.map((range) => Object.freeze({ ...range })));
  return Object.freeze({
    ...part,
    compilerBytes,
    binaryIncludes: frozenIncludes,
    transformedRanges: frozenRanges,
    provenance: Object.freeze({
      ...part.provenance,
      transformedRanges: frozenRanges,
      binaryIncludes: Object.freeze(frozenIncludes.map(({ bytes, ...include }) => Object.freeze({
        ...include,
        byteLength: bytes.length,
      }))),
    }),
  });
}

export async function lowerAtomBinaryIncludes(project, reader) {
  const parts = [];
  for (const part of project.parts) {
    const compilerBytes = part.compilerBytes.slice();
    const binaryIncludes = [];
    const transformedRanges = [];
    for (const line of linesOf(part.compilerBytes)) {
      const directive = incbinAt(part, line);
      if (directive === undefined) continue;
      let snapshot;
      try {
        snapshot = await reader.resolveDependency(part, directive.specifier);
      } catch (error) {
        throw withLocation(error, directive.location);
      }
      if (snapshot.originalBytes.length > 0xffff) {
        fail("incbin-size", "INCBIN input exceeds the 65,535-byte native target limit", directive.location);
      }
      const replacement = `${directive.prefix}DS ${snapshot.originalBytes.length},0`;
      const replacementBytes = encoder.encode(replacement);
      if (replacementBytes.length > line.contentEnd - line.start) {
        fail("incbin-lowering", "INCBIN line cannot retain its source extent", directive.location);
      }
      compilerBytes.fill(0x20, line.start, line.contentEnd);
      compilerBytes.set(replacementBytes, line.start);
      transformedRanges.push(Object.freeze({ start: line.start, end: line.contentEnd }));
      binaryIncludes.push(Object.freeze({
        specifier: directive.specifier,
        logicalIdentity: snapshot.logicalIdentity,
        offset: directive.location.offset,
        line: directive.location.line,
        column: directive.location.column,
        bytes: snapshot.originalBytes.slice(),
      }));
    }
    parts.push(freezePart(part, compilerBytes, binaryIncludes, transformedRanges));
  }
  return Object.freeze({ ...project, parts: Object.freeze(parts) });
}
