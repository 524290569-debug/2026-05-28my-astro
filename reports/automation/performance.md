# Performance Report

## 构建结果

- `ASTRO_TELEMETRY_DISABLED=1 npm.cmd run build`：通过。
- 构建输出：2 个页面，静态构建完成。
- 项目未配置 `lint` / `test` 脚本，本轮未强行新增。

## 图片检查

- 首页现有图片保留 `width`、`height`、`loading`、`decoding` 与 `sizes` 设置。
- 本轮没有新增图片资源，未增加首屏图片负担。
- 截图脚本生成 `screenshots/auto-2026-06-18-1049-v031-*.png`，用于本地验证，不纳入提交范围。

## 脚本检查

- 新增城市广播交互使用少量原生 JavaScript。
- 没有新增依赖、动画库或状态管理。
- 广播按钮更新 `aria-pressed`、频道标题、正文、信号状态与 CSS 变量，交互范围局限在模块内部。

## 样式检查

- 新增样式集中在 `.city-broadcast` 与 `.broadcast-*` 命名空间。
- 移动端在 390px 视口复测无横向滚动：`scrollWidth === clientWidth`。
- CSS 避免使用兼容性不稳的百分比乘法 `calc()`，信号条使用 `min()` 控制宽度。

## 已优化项

- 新增首页城市广播模块，补充世界观内容和用户可触发交互。
- 修正 `#broadcast` hash 直达的重定位支持，使新增模块可被直接定位。
- 完成本轮构建、截图和浏览器 DOM 复测。

## 待优化项

- `tools/capture_views.mjs` 默认 `CAPTURE_BASE_URL` 仍是旧路径；本轮通过环境变量覆盖，后续可考虑更新脚本默认值。
- 默认截图计划尚未单独包含 `#broadcast`，后续可把广播模块加入自动截图清单。
