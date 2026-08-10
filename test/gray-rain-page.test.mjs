import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("位置改变独立页面、组件和样式已移除", async () => {
  for (const path of [
    "src/pages/position.astro",
    "src/components/RainPositionExperience.astro",
    "src/styles/rain-position.css",
  ]) {
    await assert.rejects(access(new URL(`../${path}`, import.meta.url)), undefined, `${path} 仍然存在`);
  }
});

test("灰雨电台导航移除位置改变并保留其他独立入口", async () => {
  const source = await read("src/components/GrayRainExperience.astro");
  assert.doesNotMatch(source, /href=\{`\$\{basePath\}position\/`\}|位置改变/);
  for (const label of ["偏航试验场", "Z.A.T.O.", "工具", "MD 阅读器", "AI 管理", "GitHub 高分项目"]) {
    assert.ok(source.includes(label), `缺少导航入口：${label}`);
  }
  assert.doesNotMatch(source, /ROUTE SELECT|href="#routes"|id="routes"/);
});

test("三个频道分别切换三张旧页面图片", async () => {
  const source = await read("src/components/GrayRainExperience.astro");
  for (const name of ["position-high.webp", "position-hero.webp", "position-below.webp"]) {
    assert.equal((source.match(new RegExp(name, "g")) ?? []).length, 1, `${name} 应只绑定一个频道`);
  }
  assert.match(source, /data-channel-background=\{channel\.id\}/);
  assert.match(source, /background\.toggleAttribute\("data-active"/);
  assert.match(source, /page\.dataset\.channel = channel\.id/);
});

test("现场切片换成扫描框和信号轨迹但保持原有外框尺寸", async () => {
  const source = await read("src/components/GrayRainExperience.astro");
  const css = await read("src/styles/home.css");
  assert.match(source, /position-between\.webp/);
  assert.match(source, /gr-scene-frame/);
  assert.match(source, /gr-readout-trace/);
  assert.match(source, /data-hotspot-state/);
  assert.match(source, /SIGNAL \/ LOCKED/);
  assert.match(source, /SIGNAL \{scene\.signal\}/);
  assert.match(css, /\.gr-scene-console \{[^}]*width:min\(100%,1480px\)/);
  assert.match(css, /\.gr-scene-viewport \{[^}]*aspect-ratio:16\/8\.1;[^}]*min-height:480px/);
  assert.match(css, /\.gr-scene-index button \{[^}]*min-height:112px/);
});

test("频道与现场交互仍支持点击、键盘和自动切换", async () => {
  const source = await read("src/components/GrayRainExperience.astro");
  for (const token of [
    'button.addEventListener("click", () => setChannel(index, true))',
    'window.setInterval(() => setChannel(activeChannel + 1), 9000)',
    'data-scene-prev',
    'data-scene-next',
    'event.key === "ArrowLeft"',
    'event.key === "ArrowRight"',
    'data-hotspot',
  ]) assert.ok(source.includes(token), `缺少交互实现：${token}`);
});

test("移动端与减少动态模式继续受控", async () => {
  const css = await read("src/styles/home.css");
  assert.match(css, /@media \(max-width: 680px\)/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.doesNotMatch(css, /gr-pointer-glow|--pointer-x|--pointer-y|cursor:\s*none/);
});
