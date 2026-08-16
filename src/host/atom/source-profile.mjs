import { inspectAtomSource } from "./directives.mjs";

export function createAtomSourceProfile() {
  return Object.freeze({
    inspectEntry(input, configuration) {
      return inspectAtomSource(input, { entry: true, configuration });
    },
    inspectDependency(input, state) {
      return inspectAtomSource(input, { entry: false, state });
    },
  });
}
