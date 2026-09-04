import { lstat, mkdir, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const modulesRoot = path.join(packageRoot, "node_modules");
const scopeRoot = path.join(modulesRoot, "@jhlagado");
const markerPath = path.join(modulesRoot, ".atom-pack-dependency-links.json");
const dependencies = ["debug80-runtime", "z80-tool-services"];
const packageManifestPath = path.join(packageRoot, "package.json");
const bundledDependencies = dependencies.map((name) => `@jhlagado/${name}`);

async function prepare() {
  const originalManifest = await readFile(packageManifestPath, "utf8");
  const manifest = JSON.parse(originalManifest);
  if (Object.hasOwn(manifest, "bundledDependencies")) {
    throw new Error("package.json must not bundle dependencies outside npm pack");
  }
  await mkdir(scopeRoot, { recursive: true });
  const created = [];
  try {
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
    manifest.bundledDependencies = bundledDependencies;
    const preparedManifest = `${JSON.stringify(manifest, null, 2)}\n`;
    await writeFile(packageManifestPath, preparedManifest, "utf8");
    await writeFile(
      markerPath,
      `${JSON.stringify({ version: 1, created, originalManifest, preparedManifest })}\n`,
      "utf8",
    );
  } catch (error) {
    for (const { linkPath } of created.reverse()) await rm(linkPath);
    await writeFile(packageManifestPath, originalManifest, "utf8");
    throw error;
  }
}

async function cleanup() {
  let marker;
  try {
    marker = JSON.parse(await readFile(markerPath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return;
    throw error;
  }
  if (marker.version !== 1) throw new Error("unknown Atom pack marker version");
  const currentManifest = await readFile(packageManifestPath, "utf8");
  if (currentManifest !== marker.preparedManifest) {
    throw new Error("package.json changed while Atom was being packed");
  }
  for (const { linkPath, realPath } of marker.created) {
    if (await realpath(linkPath) !== realPath) {
      throw new Error(`Atom pack dependency link changed before cleanup: ${linkPath}`);
    }
    await rm(linkPath);
  }
  await writeFile(packageManifestPath, marker.originalManifest, "utf8");
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
