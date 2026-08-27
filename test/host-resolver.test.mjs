import assert from "node:assert/strict";
import test from "node:test";

let api;
try {
  api = await import("../src/host/project-preparation/index.mjs");
} catch {
  api = {};
}

const encoder = new TextEncoder();

function resolverApi() {
  assert.equal(typeof api.resolveSourceProject, "function", "resolveSourceProject export is missing");
  assert.equal(typeof api.passthroughProfile, "object", "passthroughProfile export is missing");
  return api;
}

function location(logicalIdentity, offset) {
  return Object.freeze({ logicalIdentity, offset, line: 1, column: offset + 1 });
}

function snapshot(logicalIdentity, dependencyIdentity = logicalIdentity) {
  return Object.freeze({
    physicalPath: `/project/${logicalIdentity}`,
    dependencyIdentity,
    logicalIdentity,
    originalBytes: encoder.encode(logicalIdentity),
  });
}

function fixture(graph, overrides = {}) {
  const sources = new Map(Object.keys(graph).map((name) => [name, snapshot(name)]));
  for (const [name, value] of Object.entries(overrides)) sources.set(name, value);
  return {
    reader: Object.freeze({
      async resolveEntry(name) {
        const source = sources.get(name);
        if (source === undefined) throw new api.SourcePreparationError("dependency", "missing-source", name);
        return source;
      },
      async resolveDependency(_importer, specifier) {
        const source = sources.get(specifier);
        if (source === undefined) throw new api.SourcePreparationError("dependency", "missing-source", specifier);
        return source;
      },
    }),
    profile: Object.freeze({
      inspectEntry(input) {
        return inspect(input, Object.freeze({ marker: "frozen" }), true);
      },
      inspectDependency(input, state) {
        assert.equal(Object.isFrozen(state), true);
        assert.equal(state.marker, "frozen");
        return inspect(input, state, false);
      },
    }),
  };

  function inspect(input, state, entry) {
    const dependencies = (graph[input.logicalIdentity] ?? []).map((specifier, index) => ({
      specifier,
      location: location(input.logicalIdentity, index),
    }));
    const part = {
      compilerBytes: input.originalBytes,
      dependencies,
      maskedRanges: [],
    };
    return entry ? { ...part, state } : part;
  }
}

const limits = Object.freeze({
  maxParts: 255,
  maxDepth: 64,
  maxLogicalPathBytes: 255,
  maxRetainedPathBytes: 64 * 1024,
  maxBank: 255,
});

async function resolve(graph, options = {}) {
  const { reader, profile } = fixture(graph, options.overrides);
  return resolverApi().resolveSourceProject({
    reader,
    entry: options.entry ?? "main",
    profile,
    configuration: Object.freeze({}),
    limits: options.limits ?? limits,
  });
}

async function assertResolverError(action, code, check = () => {}) {
  await assert.rejects(action, (error) => {
    assert.equal(error?.name, "SourcePreparationError");
    assert.equal(error?.category, "dependency");
    assert.equal(error?.code, code);
    check(error);
    return true;
  });
}

test("resolver emits deterministic postorder and includes a diamond once", async () => {
  const result = await resolve({
    main: ["display", "input"],
    display: ["hardware"],
    input: ["hardware"],
    hardware: [],
  });

  assert.deepEqual(
    result.parts.map(({ logicalIdentity }) => logicalIdentity),
    ["hardware", "display", "input", "main"],
  );
  assert.equal(result.parts.filter(({ logicalIdentity }) => logicalIdentity === "hardware").length, 1);
  assert.ok(result.parts.every(Object.isFrozen));
  for (const part of result.parts) assert.strictEqual(part.compilerBytes, part.originalBytes);
});

test("resolver inspects a diamond dependency exactly once", async () => {
  const graph = {
    main: ["display", "input"],
    display: ["hardware"],
    input: ["hardware"],
    hardware: [],
  };
  const sources = new Map(Object.keys(graph).map((name) => [name, snapshot(name)]));
  const inspections = new Map();
  const reader = {
    async resolveEntry(name) { return sources.get(name); },
    async resolveDependency(_importer, name) { return sources.get(name); },
  };
  const inspect = (input, entry) => {
    inspections.set(input.logicalIdentity, (inspections.get(input.logicalIdentity) ?? 0) + 1);
    const part = {
      compilerBytes: input.originalBytes,
      dependencies: graph[input.logicalIdentity].map((specifier, index) => ({
        specifier,
        location: location(input.logicalIdentity, index),
      })),
      maskedRanges: [],
    };
    return entry ? { ...part, state: undefined } : part;
  };
  const profile = {
    inspectEntry(input) { return inspect(input, true); },
    inspectDependency(input) { return inspect(input, false); },
  };

  await resolverApi().resolveSourceProject({ reader, entry: "main", profile, limits });
  assert.deepEqual(Object.fromEntries(inspections), {
    main: 1,
    display: 1,
    hardware: 1,
    input: 1,
  });
});

test("resolver inspects the entry first and passes one frozen state to dependencies", async () => {
  const calls = [];
  const main = snapshot("main");
  const dependency = snapshot("dependency");
  const state = Object.freeze({ enabled: 1 });
  const reader = {
    async resolveEntry() { return main; },
    async resolveDependency() { return dependency; },
  };
  const profile = {
    inspectEntry(input) {
      calls.push(`entry:${input.logicalIdentity}`);
      return {
        state,
        compilerBytes: input.originalBytes,
        dependencies: [{ specifier: "dependency", location: location("main", 0) }],
        maskedRanges: [],
      };
    },
    inspectDependency(input, received) {
      calls.push(`dependency:${input.logicalIdentity}`);
      assert.strictEqual(received, state);
      return { compilerBytes: input.originalBytes, dependencies: [], maskedRanges: [] };
    },
  };

  await resolverApi().resolveSourceProject({ reader, entry: "main", profile, configuration: {}, limits });
  assert.deepEqual(calls, ["entry:main", "dependency:dependency"]);
});

test("resolver imports repeated direct dependencies once", async () => {
  const result = await resolve({ main: ["shared", "shared"], shared: [] });
  assert.deepEqual(
    result.parts.map(({ logicalIdentity }) => logicalIdentity),
    ["shared", "main"],
  );
});

test("resolver reports a complete ordered dependency cycle", async () => {
  await assertResolverError(
    () => resolve({ main: ["a"], a: ["b"], b: ["a"] }),
    "dependency-cycle",
    (error) => {
      assert.deepEqual(error.cycle.map(({ from, to }) => [from, to]), [
        ["a", "b"],
        ["b", "a"],
      ]);
      assert.deepEqual(error.location, location("b", 0));
    },
  );
});

test("resolver attaches dependency locations to missing-source failures", async () => {
  await assertResolverError(
    () => resolve({ main: ["missing"] }),
    "missing-source",
    (error) => assert.deepEqual(error.location, location("main", 0)),
  );
});

test("resolver rejects one dependency identity with conflicting logical identities", async () => {
  const canonical = snapshot("canonical", "same-physical-file");
  const conflicting = snapshot("conflicting", "same-physical-file");
  await assertResolverError(
    () => resolve(
      { main: ["canonical", "conflicting"], canonical: [], conflicting: [] },
      { overrides: { canonical, conflicting } },
    ),
    "identity-alias",
    (error) => assert.deepEqual(error.location, location("main", 1)),
  );
});

test("resolver enforces part and depth capacities at the exact boundary", async () => {
  const graph = { main: ["a"], a: [] };
  assert.equal((await resolve(graph, { limits: { ...limits, maxParts: 2, maxDepth: 2 } })).parts.length, 2);
  await assertResolverError(
    () => resolve(graph, { limits: { ...limits, maxParts: 1, maxDepth: 2 } }),
    "part-capacity",
  );
  await assertResolverError(
    () => resolve(graph, { limits: { ...limits, maxParts: 2, maxDepth: 1 } }),
    "depth-capacity",
  );
});

test("resolver rejects excess depth before inspecting the excess part", async () => {
  const main = snapshot("main");
  const dependency = snapshot("dependency");
  let dependencyInspections = 0;
  const reader = {
    async resolveEntry() { return main; },
    async resolveDependency() { return dependency; },
  };
  const profile = {
    inspectEntry(input) {
      return {
        state: undefined,
        compilerBytes: input.originalBytes,
        dependencies: [{ specifier: "dependency", location: location("main", 0) }],
        maskedRanges: [],
      };
    },
    inspectDependency(input) {
      dependencyInspections += 1;
      return { compilerBytes: input.originalBytes, dependencies: [], maskedRanges: [] };
    },
  };

  await assertResolverError(
    () => resolverApi().resolveSourceProject({
      reader,
      entry: "main",
      profile,
      limits: { ...limits, maxDepth: 1 },
    }),
    "depth-capacity",
  );
  assert.equal(dependencyInspections, 0);
});

test("resolver enforces logical and retained path bytes at exact boundaries", async () => {
  const graph = { main: ["a"], a: [] };
  assert.equal((await resolve(graph, {
    limits: { ...limits, maxLogicalPathBytes: 4, maxRetainedPathBytes: 5 },
  })).parts.length, 2);
  await assertResolverError(
    () => resolve(graph, {
      limits: { ...limits, maxLogicalPathBytes: 3, maxRetainedPathBytes: 5 },
    }),
    "path-capacity",
  );
  await assertResolverError(
    () => resolve(graph, {
      limits: { ...limits, maxLogicalPathBytes: 4, maxRetainedPathBytes: 4 },
    }),
    "retained-path-capacity",
  );
});

test("passthrough profile preserves the exact original byte object", async () => {
  const main = snapshot("main");
  const result = await resolverApi().resolveSourceProject({
    reader: { async resolveEntry() { return main; } },
    entry: "main",
    profile: api.passthroughProfile,
    configuration: undefined,
    limits,
  });
  assert.strictEqual(result.parts[0].compilerBytes, main.originalBytes);
  assert.deepEqual(result.parts[0].maskedRanges, []);
});
