import assert from "node:assert/strict";
import test from "node:test";
import { runOneByteGatewayConformance } from "@jhlagado/z80-tool-services";

import {
  ATOM_TOOL_SERVICE,
  ATOM_TOOL_STATUS,
  createAtomToolServiceGateway,
} from "../src/host/providers/tool-service-gateway.mjs";

test("the direct-host gateway preserves source, publication, and console bytes", () => {
  const binary = Uint8Array.of(0x00, 0x1a, 0x7f, 0x80, 0xff);
  const images = [];
  const consoleOutput = [];
  const exits = [];
  let open = false;
  const gateway = createAtomToolServiceGateway({
    sourceRead: ({ offset }) => binary[offset],
    sink: {
      begin() {
        open = true;
      },
      image(operation) {
        assert.equal(open, true);
        images.push(...operation.bytes);
      },
      patch() {},
      commit() {
        open = false;
      },
      abort() {
        open = false;
      },
    },
    console: {
      read: () => 0x7f,
      write(value) {
        consoleOutput.push(value);
      },
      exitSuccess() {
        exits.push(0);
      },
      exitFailure(value) {
        exits.push(value);
      },
    },
  });

  for (let offset = 0; offset < binary.length; offset += 1) {
    assert.deepEqual(
      gateway.dispatch(ATOM_TOOL_SERVICE.sourceRead, { part: 0, offset }),
      { status: 0, value: binary[offset] },
    );
  }
  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.begin), { status: 0 });
  assert.deepEqual(
    gateway.dispatch(ATOM_TOOL_SERVICE.image, {
      bank: 0,
      address: 0x100,
      bytes: binary,
    }),
    { status: 0 },
  );
  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.commit), { status: 0 });
  assert.deepEqual(images, [...binary]);

  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.consoleRead), {
    status: 0,
    value: 0x7f,
  });
  for (const value of binary) {
    assert.deepEqual(
      gateway.dispatch(ATOM_TOOL_SERVICE.consoleWrite, { value }),
      { status: 0 },
    );
  }
  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.exitSuccess), {
    status: 0,
  });
  assert.deepEqual(
    gateway.dispatch(ATOM_TOOL_SERVICE.exitFailure, { status: 0x55 }),
    { status: 0 },
  );
  assert.deepEqual(consoleOutput, [...binary]);
  assert.deepEqual(exits, [0, 0x55]);
});

test("the gateway reports unavailable and malformed operations without effects", () => {
  const lifecycle = [];
  const gateway = createAtomToolServiceGateway({
    sourceRead: () => 0x100,
    sink: {
      begin: () => lifecycle.push("begin"),
      image: () => lifecycle.push("image"),
      patch: () => lifecycle.push("patch"),
      commit: () => lifecycle.push("commit"),
      abort: () => lifecycle.push("abort"),
    },
  });

  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.consoleRead), {
    status: ATOM_TOOL_STATUS.unavailable,
  });
  assert.deepEqual(
    gateway.dispatch(ATOM_TOOL_SERVICE.consoleWrite, { value: 0x100 }),
    { status: ATOM_TOOL_STATUS.invalid },
  );
  assert.deepEqual(
    gateway.dispatch(ATOM_TOOL_SERVICE.exitFailure, { status: 0 }),
    { status: ATOM_TOOL_STATUS.invalid },
  );
  assert.deepEqual(gateway.dispatch(ATOM_TOOL_SERVICE.sourceRead), {
    status: ATOM_TOOL_STATUS.invalid,
  });
  assert.deepEqual(gateway.dispatch("unknown"), {
    status: ATOM_TOOL_STATUS.unavailable,
  });
  assert.deepEqual(lifecycle, []);
});

test("the direct-host gateway passes the shared one-byte conformance vectors", () => {
  const result = runOneByteGatewayConformance(
    {
      create: (fixtures) => {
        const effects = [];
        const gateway = createAtomToolServiceGateway({
          sourceRead: ({ offset }) =>
            typeof offset === "number"
              ? fixtures.sourceBytes[offset]
              : fixtures.sourceReadMalformedValue,
          sink: {
            begin() {
              effects.push("begin");
              return fixtures.sinkMalformedStatus;
            },
            image(operation) {
              effects.push(`image:${[...operation.bytes]}`);
            },
            patch() {},
            commit() {
              effects.push("commit");
            },
            abort() {
              fixtures.thrownHostOperation();
            },
          },
          console: {
            read: () => fixtures.consoleReadMalformedValue,
          },
        });
        return { gateway, effects };
      },
    },
    {
      operations: {
        sourceRead: ATOM_TOOL_SERVICE.sourceRead,
        consoleRead: ATOM_TOOL_SERVICE.consoleRead,
        consoleWrite: ATOM_TOOL_SERVICE.consoleWrite,
        exitFailure: ATOM_TOOL_SERVICE.exitFailure,
        begin: ATOM_TOOL_SERVICE.begin,
        image: ATOM_TOOL_SERVICE.image,
        commit: ATOM_TOOL_SERVICE.commit,
        abort: ATOM_TOOL_SERVICE.abort,
        unknown: "unknown",
      },
      policy: {
        success: ATOM_TOOL_STATUS.success,
        unavailable: ATOM_TOOL_STATUS.unavailable,
        invalid: ATOM_TOOL_STATUS.invalid,
        exception: 0xef,
      },
    },
  );

  assert.deepEqual(result, { vectors: 3, assertions: 14 });
});
