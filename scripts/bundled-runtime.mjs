import { lstat, mkdir, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const runtimeRoot = path.resolve(packageRoot, "../debug80-runtime");
const scopeRoot = path.join(packageRoot, "node_modules", "@jhlagado");
const linkPath = path.join(scopeRoot, "debug80-runtime");
const markerPath = path.join(packageRoot, "node_modules", ".atom-pack-runtime-link");

async function prepare() {
  await mkdir(scopeRoot, { recursive: true });
  try {
    await lstat(linkPath);
    return;
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  await symlink(path.relative(scopeRoot, runtimeRoot), linkPath, "dir");
  await writeFile(markerPath, `${await realpath(linkPath)}\n`, "utf8");
}

async function cleanup() {
  let expected;
  try {
    expected = (await readFile(markerPath, "utf8")).trim();
  } catch (error) {
    if (error?.code === "ENOENT") return;
    throw error;
  }
  if (await realpath(linkPath) !== expected) {
    throw new Error("Atom pack runtime link changed before cleanup");
  }
  await rm(linkPath);
  await rm(markerPath);
}

switch (process.argv[2]) {
  case "prepare":
    await prepare();
    break;
  case "cleanup":
    await cleanup();
    break;
  default:
    throw new Error("usage: bundled-runtime.mjs prepare|cleanup");
}
