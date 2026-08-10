import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("位置改变路由装配独立体验组件和页面元信息", async () => {
  const source = await read("src/pages/position.astro");
  assert.match(source, /RainPositionExperience/);
  assert.match(source, /title="位置改变｜雨如何改变人与城市的距离"/);
  assert.match(source, /skipTarget="#position-main"/);
});

test("灰雨电台保留独立页面入口并移除线路选择区与黄色鼠标光圈", async () => {
  const source = await read("src/components/GrayRainExperience.astro");
  const css = await read("src/styles/home.css");
  for (const label of ["位置改变", "偏航试验场", "Z.A.T.O.", "工具", "MD 阅读器", "AI 管理"]) {
    assert.ok(source.includes(label), `缺少导航入口：${label}`);
  }
  for (const token of ["03 / ROUTE SELECT", "选择下一条线路", 'href="#routes"', 'id="routes"']) {
    assert.ok(!source.includes(token), `线路选择残留：${token}`);
  }
  assert.doesNotMatch(css, /gr-routes|gr-route-intro|gr-route-list|gr-footer/);
  assert.doesNotMatch(source, /gr-pointer-glow/);
  assert.doesNotMatch(source, /--gr-pointer-x|--gr-pointer-y/);
});

test("四个节点使用四套不同的结构与交互语法", async () => {
  const source = await read("src/components/RainPositionExperience.astro");
  for (const token of ["rp-high-observatory", "rp-below-frame", "rp-journey", "rp-calibration-console"]) {
    assert.ok(source.includes(token), `缺少独立表现形式：${token}`);
  }
  assert.equal((source.match(/data-rp-high-point/g) ?? []).length, 4, "三个坐标按钮加一个脚本查询");
  assert.match(source, /data-rp-depth type="range"/);
  assert.match(source, /data-rp-journey-toggle/);
  assert.equal((source.match(/data-rp-metric="/g) ?? []).length, 3);
  assert.doesNotMatch(source, /scenes\.map/);
  assert.doesNotMatch(source, /data-rp-chapter/);
});

test("四张主题图片各使用一次且校准与结尾不再重复图片", async () => {
  const component = await read("src/components/RainPositionExperience.astro");
  const css = await read("src/styles/rain-position.css");
  for (const name of ["position-hero.webp", "position-high.webp", "position-below.webp", "position-between.webp"]) {
    assert.equal((component.match(new RegExp(name, "g")) ?? []).length, 1, `${name} 应只使用一次`);
  }
  assert.doesNotMatch(css, /url\(["']?\/assets\/position\//);
  assert.doesNotMatch(component, /rp-compare-stage|data-rp-compare-panel/);
});

test("滚动、坐标、深度、行程和校准均有独立事件实现", async () => {
  const source = await read("src/components/RainPositionExperience.astro");
  for (const token of [
    'addEventListener("scroll"',
    'addEventListener("hashchange"',
    "highPoints.forEach",
    'depthControl?.addEventListener("input"',
    'journeyToggle?.addEventListener("click"',
    'journeyRange?.addEventListener("input"',
    'metricInputs.forEach((input) => input.addEventListener("input"',
    "IntersectionObserver",
  ]) assert.ok(source.includes(token), `缺少交互实现：${token}`);
});

test("页面底部没有页面导航且样式覆盖移动端和减少动态", async () => {
  const component = await read("src/components/RainPositionExperience.astro");
  const css = await read("src/styles/rain-position.css");
  const ending = component.match(/<section id="after"[\s\S]*?<\/section>/)?.[0] ?? "";
  assert.ok(ending.length > 0);
  assert.doesNotMatch(ending, /<a\s|<nav\s/);
  assert.match(css, /@media \(max-width: 620px\)/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /scroll-margin-top:/);
  assert.doesNotMatch(css, /cursor:\s*none/);
});
