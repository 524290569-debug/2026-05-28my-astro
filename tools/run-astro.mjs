import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const astroBin = fileURLToPath(new URL("../node_modules/astro/bin/astro.mjs", import.meta.url));
const args = process.argv.slice(2);
const env = {
  ...process.env,
  ASTRO_TELEMETRY_DISABLED: process.env.ASTRO_TELEMETRY_DISABLED || "1"
};

const child = spawn(process.execPath, [astroBin, ...args], {
  env,
  stdio: "inherit"
});

child.on("exit", (code, signal) => {
  if (signal) {
    console.error(`Astro exited with signal ${signal}`);
    process.exit(1);
  }

  process.exit(code ?? 0);
});
