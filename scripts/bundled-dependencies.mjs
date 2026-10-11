import { cp, lstat, mkdir, readFile, readdir, realpath, rename, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const modulesRoot = path.join(packageRoot, "node_modules");
const scopeRoot = path.join(modulesRoot, "@jhlagado");
const markerPath = path.join(modulesRoot, ".atom-pack-dependency-links.json");
const dependencies = ["z80-runtime", "z80-tool-services"];
const packageManifestPath = path.join(packageRoot, "package.json");
const bundledDependencies = dependencies.map((name) => `@jhlagado/${name}`);
const dependencyPath = (name) => path.join(scopeRoot, name);
const backupPath = (name) => path.join(scopeRoot, `.atom-pack-${name}-backup`);

async function removeMapReferences(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await removeMapReferences(file);
    else if (/\.(?:js|ts)$/.test(entry.name)) {
      const original = await readFile(file, "utf8");
      const cleaned = original.replace(/^\/\/# sourceMappingURL=.*(?:\r?\n|$)/gm, "");
      if (cleaned !== original) await writeFile(file, cleaned);
    }
  }
}

async function stageDependency(name) {
  const installedPath = dependencyPath(name);
  const backup = backupPath(name);
  try {
    await lstat(backup);
    throw new Error("Atom pack dependency backup already exists; run cleanup first");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  await rename(installedPath, backup);
  try {
    const sourceRoot = await realpath(backup);
    const metadata = JSON.parse(await readFile(path.join(sourceRoot, "package.json"), "utf8"));
    await mkdir(installedPath);
    for (const name of ["package.json", ...metadata.files]) {
      const source = path.join(sourceRoot, name);
      await cp(source, path.join(installedPath, name), {
        recursive: true,
        // Ship runtime code, type declarations and licences, with Atom’s own guides.
        filter: (file) => !file.endsWith(".map") && !file.endsWith(".md"),
      });
    }
    delete metadata.scripts;
    delete metadata.devDependencies;
    await writeFile(path.join(installedPath, "package.json"), `${JSON.stringify(metadata, null, 2)}\n`);
    await removeMapReferences(installedPath);
  } catch (error) {
    await restoreDependency(name);
    throw error;
  }
}

async function restoreDependency(name) {
  const installedPath = dependencyPath(name);
  const backup = backupPath(name);
  try {
    await lstat(backup);
  } catch (error) {
    if (error?.code === "ENOENT") return;
    throw error;
  }
  await rm(installedPath, { recursive: true, force: true });
  await rename(backup, installedPath);
}

async function prepare() {
  try {
    await lstat(markerPath);
    throw new Error("Atom pack is already prepared; run cleanup first");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  const originalManifest = await readFile(packageManifestPath, "utf8");
  const manifest = JSON.parse(originalManifest);
  if (Object.hasOwn(manifest, "bundledDependencies")) {
    throw new Error("package.json must not bundle dependencies outside npm pack");
  }
  await mkdir(scopeRoot, { recursive: true });
  const created = [];
  const staged = [];
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
    await writeFile(
      markerPath,
      `${JSON.stringify({ version: 3, created, originalManifest, preparedManifest })}\n`,
      "utf8",
    );
    for (const name of dependencies) {
      await stageDependency(name);
      staged.push(name);
    }
    await writeFile(packageManifestPath, preparedManifest, "utf8");
  } catch (error) {
    for (const name of staged.reverse()) await restoreDependency(name);
    for (const { linkPath } of created.reverse()) await rm(linkPath);
    await writeFile(packageManifestPath, originalManifest, "utf8");
    await rm(markerPath, { force: true });
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
  if (marker.version !== 3) throw new Error("unknown Atom pack marker version");
  const currentManifest = await readFile(packageManifestPath, "utf8");
  if (currentManifest !== marker.preparedManifest && currentManifest !== marker.originalManifest) {
    throw new Error("package.json changed while Atom was being packed");
  }
  for (const name of [...dependencies].reverse()) await restoreDependency(name);
  for (const { linkPath, realPath } of marker.created) {
    try {
      if (await realpath(linkPath) !== realPath) {
        throw new Error(`Atom pack dependency link changed before cleanup: ${linkPath}`);
      }
      await rm(linkPath);
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
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
