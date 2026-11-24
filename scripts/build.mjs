#!/usr/bin/env node

// Build script for Atum npm package
// Builds the Go binary for the current platform

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { platform } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const binDir = join(root, "bin");

const ext = platform() === "win32" ? ".exe" : "";
const outPath = join(binDir, `atum${ext}`);

if (!existsSync(binDir)) {
  mkdirSync(binDir, { recursive: true });
}

console.log("Building Atum server...");

try {
  execFileSync("go", ["version"], { stdio: "inherit" });
} catch {
  console.error("Error: Go is not installed.");
  console.error("Install Go from https://go.dev/dl/");
  process.exit(1);
}

try {
  execFileSync("go", ["build", "-o", outPath, "./cmd/atum"], {
    stdio: "inherit",
    cwd: root,
  });
  console.log(`\nBuild complete: ${outPath}`);
} catch {
  console.error("Build failed.");
  process.exit(1);
}
