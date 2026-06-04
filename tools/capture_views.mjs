import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = process.cwd();
const port = 4327;
const debugPort = 9337;
const baseUrl = `http://127.0.0.1:${port}/2026-05-28my-astro/`;
const screenshotDir = join(root, "screenshots");
const edgeProfile = join(root, ".tmp", `edge-profile-${Date.now()}`);
const edgePath = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";

const shots = [
  ["home", "#home"],
  ["about", "#about"],
  ["works", "#works"],
  ["blog", "#blog"],
  ["contact", "#contact"]
];

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: "inherit",
      windowsHide: true
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}

async function waitForHttp(url, timeoutMs = 15000) {
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return response;
      }
    } catch {
      // Server is not ready yet.
    }

    await delay(300);
  }

  throw new Error(`Timed out waiting for ${url}`);
}

async function openPageTarget(url) {
  const encodedUrl = encodeURIComponent(url);
  const endpoint = `http://127.0.0.1:${debugPort}/json/new?${encodedUrl}`;

  let response = await fetch(endpoint, { method: "PUT" });
  if (!response.ok) {
    response = await fetch(endpoint);
  }
  if (!response.ok) {
    throw new Error(`Could not create browser target: ${response.status}`);
  }

  return response.json();
}

function connectCdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  const pending = new Map();
  const events = new Map();
  let nextId = 1;

  ws.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data));
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        reject(new Error(message.error.message));
      } else {
        resolve(message.result);
      }
      return;
    }

    const listeners = events.get(message.method);
    if (listeners) {
      listeners.forEach((listener) => listener(message.params));
    }
  });

  const opened = new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });

  const send = async (method, params = {}) => {
    await opened;
    const id = nextId++;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
    });
  };

  const once = (method) =>
    new Promise((resolve) => {
      const listener = (params) => {
        const listeners = events.get(method) ?? [];
        events.set(
          method,
          listeners.filter((item) => item !== listener)
        );
        resolve(params);
      };

      events.set(method, [...(events.get(method) ?? []), listener]);
    });

  return { ws, send, once };
}

async function captureSection(cdp, name, selector) {
  await cdp.send("Runtime.evaluate", {
    expression:
      selector === "#home"
        ? "document.documentElement.style.scrollBehavior = 'auto'; window.scrollTo(0, 0);"
        : `document.documentElement.style.scrollBehavior = 'auto'; { const element = document.querySelector(${JSON.stringify(selector)}); if (element) { const top = element.getBoundingClientRect().top + window.scrollY - 88; window.scrollTo(0, Math.max(0, top)); } }`,
    awaitPromise: false
  });
  await delay(700);

  const result = await cdp.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false
  });

  const output = join(screenshotDir, `review-${name}-1440x900.png`);
  await writeFile(output, Buffer.from(result.data, "base64"));
  console.log(`captured ${output}`);
}

await mkdir(screenshotDir, { recursive: true });
await run("cmd.exe", ["/c", "npm.cmd", "run", "build"]);

const preview = spawn(
  "cmd.exe",
  ["/c", "npm.cmd", "run", "preview", "--", "--host", "127.0.0.1", "--port", String(port)],
  {
    cwd: root,
    stdio: "ignore",
    windowsHide: true
  }
);

const edge = spawn(
  edgePath,
  [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--remote-allow-origins=*",
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${edgeProfile}`,
    "about:blank"
  ],
  {
    cwd: root,
    stdio: "ignore",
    windowsHide: true
  }
);

try {
  await waitForHttp(baseUrl);
  await waitForHttp(`http://127.0.0.1:${debugPort}/json/version`);

  const target = await openPageTarget(baseUrl);
  const cdp = connectCdp(target.webSocketDebuggerUrl);
  await cdp.send("Page.enable");
  await cdp.send("Runtime.enable");
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 1440,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false
  });

  const loaded = cdp.once("Page.loadEventFired");
  await cdp.send("Page.navigate", { url: baseUrl });
  await Promise.race([loaded, delay(5000)]);
  await delay(1000);

  for (const [name, selector] of shots) {
    await captureSection(cdp, name, selector);
  }

  cdp.ws.close();
} finally {
  edge.kill();
  preview.kill();
  await rm(edgeProfile, { recursive: true, force: true }).catch(() => {});
}
