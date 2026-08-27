import { lstat, mkdir, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const modulesRoot = path.join(packageRoot, "node_modules");
const scopeRoot = path.join(modulesRoot, "@jhlagado");
const markerPath = path.join(modulesRoot, ".atom-pack-dependency-links.json");
const dependencies = ["debug80-runtime", "z80-tool-services"];

async function prepare() {
  await mkdir(scopeRoot, { recursive: true });
  const created = [];
  for (const name of dependencies) {
    const linkPath = path.join(scopeRoot, name);
    try {
      await lstat(linkPath);
      continue;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    const dependencyRoot = path.resolve(packageRoot, `../${name}`);
    await symlink(path.relative(scopeRoot, dependencyRoot), linkPath, "dir");
    created.push({ linkPath, realPath: await realpath(linkPath) });
  }
  await writeFile(markerPath, `${JSON.stringify(created)}\n`, "utf8");
}

async function cleanup() {
  let created;
  try {
    created = JSON.parse(await readFile(markerPath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return;
    throw error;
  }
  for (const { linkPath, realPath } of created) {
    if (await realpath(linkPath) !== realPath) {
      throw new Error(`Atom pack dependency link changed before cleanup: ${linkPath}`);
    }
    await rm(linkPath);
  }
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
    throw new Error("usage: bundled-dependencies.mjs prepare|cleanup");
}
