export const passthroughProfile = Object.freeze({
  inspectEntry({ originalBytes }) {
    return {
      state: undefined,
      compilerBytes: originalBytes,
      dependencies: [],
      maskedRanges: [],
    };
  },
  inspectDependency({ originalBytes }) {
    return {
      compilerBytes: originalBytes,
      dependencies: [],
      maskedRanges: [],
    };
  },
});
