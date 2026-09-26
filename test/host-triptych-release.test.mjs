import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");

test("the current Atom release has a verified Triptych launch image", async () => {
  const packageJson = JSON.parse(
    await readFile(join(repositoryRoot, "package.json"), "utf8"),
  );
  const version = packageJson.version;
  const releaseDirectory = join(repositoryRoot, "site", "releases", version);
  const descriptor = JSON.parse(
    await readFile(join(releaseDirectory, "system.json"), "utf8"),
  );
  const image = await readFile(join(releaseDirectory, descriptor.image.asset));
  const resident = image.subarray(0, 16_384);
  const page = await readFile(join(repositoryRoot, "site", "index.html"), "utf8");

  assert.equal(descriptor.schema, "triptych-external-system-v1");
  assert.equal(descriptor.name, `Atom ${version} for CP/M`);
  assert.equal(descriptor.profile, "triptych-cpu-v0.1-2m-n04");
  assert.equal(descriptor.workDisk, "copy-image");
  assert.deepEqual(descriptor.workDrives, ["B"]);
  assert.equal(image.length, 2_097_152);
  assert.equal(image.length, descriptor.image.bytes);
  assert.equal(hash(image), descriptor.image.sha256);
  assert.equal(
    hash(resident),
    "61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e",
  );
  assert.match(page, new RegExp("releases/" + version.replaceAll(".", "\\.") + "/ATOM\\.COM"));
  assert.match(page, new RegExp("releases/" + version.replaceAll(".", "\\.") + "/atom\\.img"));
  assert.match(page, /jhlagado\.github\.io\/triptych\//);
});
