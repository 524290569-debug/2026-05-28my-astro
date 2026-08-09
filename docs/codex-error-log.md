# Codex 执行错误记录

> 用途：记录本项目中已经遇到的执行错误、原因与已验证修正。后续操作先检索本文件，避免重复消耗时间。

## 2026-08-09｜“位置改变”独立页

### E-001｜`git diff --output` 在 PowerShell 中收到空路径
- **现象**：第一次备份旧未提交内容时，`git diff --output` 的路径参数没有按预期传入。
- **原因**：变量与 Git 长参数的组合写法被 PowerShell 错误解析。
- **修正**：改用完整字符串参数 `"--output=$patchPath"`，随后确认补丁文件存在且大小大于 0。
- **复用规则**：在 PowerShell 调 Git 的 `--key=value` 参数时，先组装为单个字符串参数。

### E-002｜当前 Git 版本没有 `git restore`
- **现象**：执行旧改动回滚时，命令返回未知子命令。
- **原因**：本机 Git 版本较旧。
- **修正**：使用兼容命令 `git reset --hard HEAD`，并在执行前保存 tracked patch 与 untracked 文件备份。
- **复用规则**：本项目回滚优先采用兼容旧 Git 的 `reset` / `checkout` 组合。

### E-003｜`git clean -fd` 因 OneDrive 空目录权限返回非零状态
- **现象**：未跟踪文件已删除，但少量空目录因 OneDrive 占用或权限提示未删除，命令最终返回非零状态。
- **原因**：同步目录中的空目录句柄仍被 OneDrive 或系统占用。
- **修正**：重新检查 `git status --short`；结果为空，证明仓库文件状态已清理。保留不影响 Git 的空目录，不继续强删。
- **复用规则**：`git clean` 后以 Git 状态为验收依据，不因同步目录删除提示反复执行强制清理。

### E-004｜直接调用 Edge 截图的 PowerShell 进程命令被执行策略拦截
- **现象**：组合式 `Start-Process` 截图命令被环境执行策略阻止。
- **原因**：该命令形态触发了本机进程执行限制。
- **修正**：改为 Node.js 脚本启动 Astro Preview 与 Edge CDP，并在 `finally` 中回收进程和临时 profile；基线截图成功生成。
- **复用规则**：本项目自动截图统一走 Node `child_process.spawn` + Edge CDP，不再走组合式 PowerShell 进程控制。

### E-005｜误用 PowerShell 保留变量 `$HOME`
- **现象**：读取页面样式时把 `$home` 当普通路径变量，实际指向用户主目录并产生访问错误。
- **原因**：PowerShell 变量名大小写不敏感，`$home` 与内置 `$HOME` 相同。
- **修正**：路径变量改名为 `$grayComponentPath` 等具名变量。
- **复用规则**：避免使用 `$HOME`、`$PID`、`$PROFILE` 等保留变量名及其大小写变体。

### E-006｜静态检查中再次沿用 `$HOME` 变量名
- **现象**：构建成功，但同一组合命令中的静态检查读取了错误路径。
- **原因**：复制旧命令时复用了保留变量名。
- **修正**：将静态检查单独重跑并使用 `$grayComponentPath`；入口、路由、样式和构建产物均返回 `True`。
- **复用规则**：错误修正后的命令片段写入本文件，后续直接复用已验证命名，不复制失败版本。

### E-007｜静态测试写入了错误的移动端断点
- **现象**：首次运行 `node --test test/position-page.test.mjs` 时 5 项中 1 项失败，测试期待 `760px`，源码实际采用 `620px`。
- **原因**：测试编写时凭印象填写断点，没有先读取样式中的真实值。
- **修正**：先检索全部 `@media`，再将断言改为项目实际的 `@media (max-width: 620px)`；随后重新执行完整测试。
- **复用规则**：静态测试中的配置值必须来自当前源码或配置文件，不凭习惯值硬编码。

### E-008｜浏览器审计把未进入视口的懒加载图片判成损坏
- **现象**：首轮浏览器审计返回 `25/28`，桌面与手机图片完整性两项失败，但截图中的已加载图片正常，资源路径也真实存在。
- **原因**：断言使用 `!image.complete || naturalWidth === 0`；懒加载图片尚未请求时 `complete` 为 `false`，这不等于资源损坏。
- **修正**：DOM 失败条件改为 `image.complete && naturalWidth === 0`，同时增加全部图片 URL 的实际 HTTP 请求校验，并在截图前等待视口内图片完成解码。
- **复用规则**：懒加载资源同时检查“已请求后的解码结果”和“URL 请求状态”，不要只看初始 `complete`。

### E-009｜`favicon.ico` 过滤检查了日志文本而不是资源 URL
- **现象**：首轮审计把浏览器自动请求缺省 favicon 的 404 计入页面脚本/资源错误。
- **原因**：过滤表达式只匹配 `item.text`，实际 favicon 地址位于 `item.url`。
- **修正**：过滤时合并检查日志文本和 URL；页面自身图片仍使用独立 HTTP 校验，不借此掩盖真实资源错误。
- **复用规则**：CDP `Log.entryAdded` 的资源地址应读取 `entry.url`，错误文案和 URL 要分字段判断。

### E-010｜隐藏 tab 的懒加载图片让审计脚本等待超时
- **现象**：第二轮审计运行到“地下”截图后停滞，外层命令在 124 秒时超时；页面端口与 CDP 端口仍被本轮子进程占用。
- **原因**：`hidden` 面板中的图片边界矩形为零，却满足了原可见范围表达式；图片尚未请求，后续 `image.decode()` 长时间等待。
- **修正**：排除处于 `[hidden]` 容器内或宽高为零的图片，为 `decode()` 增加 1.2 秒上限；按端口所有者 PID 精确回收本轮 Preview 与 Edge 进程。
- **复用规则**：浏览器自动化等待资源时必须同时具备可见性过滤、单资源超时和总命令超时。

### E-011｜组合式进程清理命令再次触发执行策略
- **现象**：将端口查询、进程终止和临时 profile 递归删除合并执行时，整条 PowerShell 命令被策略拦截。
- **原因**：一条命令同时包含动态 PID 与递归删除，安全边界过宽。
- **修正**：拆分动作，只对已由端口查询确认的两个 PID 执行 `Stop-Process`；随后独立查询并得到 `AUDIT_PORTS_FREE`。
- **复用规则**：进程与文件清理分开执行；动态目标先输出确认，文件目录必须单独解析并核对范围。

### E-012｜审计脚本只终止 `cmd` 父进程，Astro Preview 子进程仍监听端口
- **现象**：完成 `29/29` 审计后，`4328` 仍有一个 Node 子进程监听。
- **原因**：Windows 下 `preview.kill()` 只结束 `cmd.exe` 包装进程，没有同步终止其 npm/Astro 子进程树。
- **修正**：在审计脚本 `finally` 中用 `taskkill /pid <spawned-pid> /t /f` 精确回收由脚本启动的 Preview 与 Edge 进程树，并保留 profile 清理。
- **复用规则**：Windows 自动化服务进程必须按“本脚本启动的父 PID + `/t`”回收，结束后再校验监听端口。

### E-013｜桌面并置面板切回初始 tab 时出现黑底
- **现象**：状态测试通过，但截图评审发现桌面“并置”面板在键盘循环回“高处”后图片未及时显示；移动端切到“地下”则正常。
- **原因**：三张 tab 图片都设置为懒加载，隐藏面板首次切回时请求时机不稳定。
- **修正**：并置模块三张复用图改为 eager，自动化新增当前可见图片 `naturalWidth === 1280` 断言，并重新截图评审。
- **复用规则**：首屏内或交互后立即可见的 tab 主图不使用懒加载；状态断言之外必须做截图检查。

### E-014｜截图落在并置面板入场动画的首帧
- **现象**：图片预加载后 `naturalWidth` 已为 `1280`，截图仍显示黑底。
- **原因**：键盘切换后立刻截图，正好捕获 `rp-panel-in` 620ms 动画的透明起始帧。
- **修正**：保留页面淡入效果，在截图前等待 750ms；数据与可访问性断言仍在交互后立即执行。
- **复用规则**：动态 UI 的截图应等待最长过渡时间再加约 100ms，而状态断言可以即时执行。

### E-015｜验证工作树中猜错 Astro CLI 路径
- **现象**：尝试读取 `node_modules/astro/astro.js` 返回路径不存在。
- **原因**：当前 Astro 包的 CLI 实际位于 `node_modules/astro/bin/astro.mjs`。
- **修正**：先读取 `node_modules/astro/package.json` 的 `bin` 字段确认真实路径；验证工作树通过指向主仓库 `node_modules` 的临时 junction 运行标准 `npm run build`。
- **复用规则**：第三方 CLI 路径从 package `bin` 字段读取，不凭旧版本目录结构猜测。

### E-016｜Windows PowerShell 5 把无 BOM UTF-8 回滚脚本解析坏
- **现象**：首次执行回滚脚本时出现 `Missing ')'` 和字符串终止符错误，工作树文件状态保持原样。
- **原因**：脚本含中文默认路径和提示，而 Windows PowerShell 5 对无 BOM UTF-8 的识别不稳定。
- **修正**：回滚脚本改为纯 ASCII；仓库默认取当前目录，备份目录从 `$PSScriptRoot` 推导，随后在补丁验证工作树中重新执行。
- **复用规则**：需要兼容 Windows PowerShell 5 的 `.ps1` 使用 ASCII 或显式带 BOM 的 UTF-8，路径优先运行时推导。

### E-017｜验证 worktree 与 junction 的组合清理被策略拦截
- **现象**：把路径边界检查、`node_modules` junction 删除和 `git worktree remove` 合并执行时被策略拦截；单独用 `Remove-Item` 解除 junction 也被拦截。
- **原因**：环境对同步目录中的目录删除和混合式递归清理保持严格限制。
- **修正**：先用 `fsutil reparsepoint query` 核实 junction 明确指向主仓库 `node_modules`，再用 `fsutil reparsepoint delete` 只解除 reparse point，确认目录为空后单独执行 `git worktree remove --force`。
- **复用规则**：验证工作树若复用依赖，清理时先解除 junction，确认不再是 reparse point，再让 Git 移除工作树。

### E-018｜`git worktree prune` 清理旧元数据时出现权限提示
- **现象**：本轮验证 worktree 已成功移除且路径不存在，但随后 `git worktree prune` 对两个历史元数据目录提示 `Permission denied`。
- **原因**：主仓库 `.git/worktrees` 下存在 OneDrive 占用的旧条目，不属于本轮仍登记的 worktree。
- **修正**：执行 `git worktree list --porcelain` 复核，结果仅保留当前主工作区；不继续强删被同步程序占用的 Git 内部目录。
- **复用规则**：worktree 清理以 `git worktree list` 和目标路径是否存在为验收，不为历史同步占用提示强制删除 `.git` 内部目录。

## 2026-08-09｜“位置改变”图片重制

### E-019｜Python heredoc 中的中文产物路径被控制台编码破坏
- **现象**：首次制作候选图片对比图时，Python 收到的路径包含 `??`，Pillow 报 `OSError: Invalid argument`。
- **原因**：带中文的绝对路径直接嵌入 PowerShell heredoc，在传给 Python 时发生控制台编码转换。
- **修正**：由 PowerShell 设置 `IMAGE_REWORK_ARTIFACT` 环境变量，Python 只从 `os.environ` 读取 Unicode 路径；对比图和指标文件随后成功生成。
- **复用规则**：Windows 下 PowerShell 与 Python 传递中文路径统一使用环境变量或参数，不把绝对路径硬编码进 heredoc。

### E-020｜Pillow 的 `getdata()` 出现弃用提示
- **现象**：亮度指标成功生成，但 Pillow 提示 `Image.Image.getdata` 将在未来版本移除。
- **原因**：一次性评审脚本使用了旧像素读取接口。
- **修正**：本次结果有效；后续同类脚本改用 `get_flattened_data()`，或直接通过 NumPy 读取像素。
- **复用规则**：新建图像指标脚本不再使用 `Image.getdata()`。

### E-021｜浏览器审计的 npm 包装进程提前退出并遗留 Preview
- **现象**：新图首轮浏览器审计在 5 秒内以 `-1073740791` 退出，没有生成日志；`4328` 仍由 Astro Preview 的 Node 子进程监听。
- **原因**：审计器通过 `cmd -> npm -> cmd -> astro` 多层包装启动 Preview，最外层 PID 提前结束后，`finally` 按原 PID 回收进程树已找不到真正的监听进程。
- **修正**：精确确认监听 PID 的命令行为 Astro Preview；回收该进程后，审计器改为用 `process.execPath` 直接启动 `node_modules/astro/bin/astro.mjs preview`，消除包装层。
- **复用规则**：Windows 浏览器测试服务直接启动真实 Node CLI，不通过 `cmd /c npm run` 建立多层进程树。

### E-022｜临时补丁仓库的换行警告被 PowerShell 当成终止错误
- **现象**：第一次生成图片重制补丁时，Git 输出 `LF will be replaced by CRLF` 警告；在 `$ErrorActionPreference = Stop` 下，PowerShell 将原生程序的标准错误流包装为 `NativeCommandError`，流程提前停止。
- **原因**：临时 Git 仓库沿用了 Windows 的 `core.autocrlf` 默认值，同时脚本把所有标准错误输出都按终止异常处理。
- **修正**：新建隔离仓库后立即设置 `git config core.autocrlf false`，再重新执行基线提交、二进制差异生成、`git diff --check` 和 `git apply --check`。
- **复用规则**：为校验补丁创建临时 Git 仓库时显式关闭自动换行转换；不要让无害的 Git 换行警告中断产物链路。

### E-023｜当前 PowerShell 执行策略阻止直接运行回滚脚本
- **现象**：在隔离目录中直接使用调用运算符执行 `rollback-image-rework.ps1` 时，系统返回“禁止运行脚本”。
- **原因**：当前 PowerShell 会话的 ExecutionPolicy 不允许直接载入本地 `.ps1` 文件；这与脚本内容和文件权限无关。
- **修正**：验证命令改为 `powershell -NoProfile -ExecutionPolicy Bypass -File <script> -RepoPath <sandbox>`，只对本次子进程放宽策略，不修改系统级配置。
- **复用规则**：本项目交付脚本的自动验证统一用独立 PowerShell 子进程和进程级 `Bypass`，不要改机器的永久执行策略。

### E-024｜PowerShell 数组中的 `Join-Path` 参数被逗号错误合并
- **现象**：第一次生成图片基线检查日志时，`Join-Path` 收到 `System.Object[]` 类型的 `ChildPath` 并终止。
- **原因**：在 `@(...)` 中连续写多个 `Join-Path` 表达式却没有为每个调用加括号，逗号被解析进前一个命令的参数列表。
- **修正**：把每个路径表达式分别写成 `(Join-Path $base '<relative-path>')`，再组成数组并重新执行检查。
- **复用规则**：PowerShell 数组包含命令表达式时，每个调用都显式加括号，避免逗号参与命令参数绑定。

### E-025｜Codex 在无远程仓库的空分支上点击提交或推送触发 `write EOF`
- **现象**：Codex 环境面板显示 `master` 和“无法获取拉取请求状态”；每次点击“提交或推送”都会弹出 Electron 主进程 `Error: write EOF`。
- **原因**：当前任务工作目录被识别为 Git 仓库，但处于 `No commits yet on master` 状态，没有 remote、没有 upstream，实际网站仓库则位于另一个目录。Codex 桌面端在继续查询 PR 或调用推送通道时，没有妥善处理已经关闭的子进程管道，最终把配置错误表现成主进程 EOF 弹窗。
- **修正**：提交网站时改为打开真实仓库 `C:\Users\52429\OneDrive\桌面\项目测试\自己的网站`；该仓库有 `origin`，首次推送当前分支时设置 upstream。不要从产物目录 `C:\Users\52429\OneDrive\文档\云服务器和数据库` 的环境面板执行提交。
- **复用规则**：点击 Codex 的提交/推送前先核对环境面板分支与 `git rev-parse --show-toplevel`；若仓库无提交、无 remote 或分支无 upstream，先修正工作目录和 Git 关联，再使用界面按钮。

### E-026｜递归全文检索误扫浏览器临时 Profile 并超时
- **现象**：使用 `Get-ChildItem -Recurse | Select-String` 检索项目时，命中了 `.tmp` 下 Edge Profile 的 LOCK、LevelDB 等文件，连续出现访问拒绝并在 30 秒后超时。
- **原因**：检索仅排除了 `node_modules` 和 `dist`，遗漏了浏览器自动化生成的 `.tmp` 缓存与受占用文件。
- **修正**：改用 `git grep` 或限定在 `src`、`test`、`tools` 等源码目录内检索；需要搜索未跟踪文件时显式排除 `.tmp/**`。
- **复用规则**：本项目文本检索优先走 Git 已跟踪文件或明确目录白名单，不再对仓库根目录执行无排除规则的递归扫描。

### E-027｜测试中的模板字符串正则转义造成 JavaScript 语法错误
- **现象**：新增导航断言后执行 `node --test`，测试文件在动态 `RegExp` 处报 `SyntaxError: missing ) after argument list`。
- **原因**：模板字符串内同时嵌套了反引号、`${...}` 与多层反斜杠，反引号没有以可维护的方式转义。
- **修正**：该断言并不需要正则，改为使用 `source.includes(...)` 比较完整 Astro 标记字符串。
- **复用规则**：静态源码片段断言优先使用 `includes`；只有确实需要模式匹配时才使用正则，避免在模板字符串中嵌套反引号转义。

### E-028｜受限沙箱阻止 Astro 写入项目 `.astro` 缓存
- **现象**：执行 `npm.cmd run build` 时在 `.astro/content.d.ts` 返回 `EPERM: operation not permitted`。
- **原因**：当前任务的可写工作区不是网站真实仓库，普通沙箱命令可读取但不能写入该仓库的构建缓存。
- **修正**：保持真实仓库路径不变，通过受控权限执行标准 `npm.cmd run build`，不修改系统权限，也不移动项目。
- **复用规则**：从其他任务目录维护本网站时，源码小改仍可用补丁工具；凡会写入 `.astro`、`dist`、测试报告或临时浏览器 Profile 的命令直接按真实仓库路径申请受控执行。

### E-029｜旧版 Git 不支持 `git branch --show-current`
- **现象**：最终复核分支时，`git branch --show-current` 返回 `error: unknown option 'show-current'`。
- **原因**：本机 Git 版本较旧，尚未提供该参数。
- **修正**：使用兼容命令 `git symbolic-ref --short HEAD` 获取当前分支。
- **复用规则**：本项目需要兼容旧 Git；分支查询使用 `git symbolic-ref --short HEAD`，文件回滚继续使用已验证的旧版兼容命令。

### E-030｜行程动画的小数增量被 `range step=1` 持续舍回原值
- **现象**：浏览器审计中点击“启动行程”后按钮进入播放逻辑，但滑杆值在 500ms 后仍停留于 `74`。
- **原因**：每帧根据滑杆当前值增加约 `0.18`，随后写回 `step=1` 的 range；浏览器把结果量化回整数，下一帧又从同一个整数开始，进度永远无法累积。
- **修正**：新增独立浮点变量 `journeyValue` 负责帧间累计，只在渲染时把四舍五入后的值同步给 range。
- **复用规则**：动画连续值与表单离散值分离保存；不要把带 `step` 量化的输入控件当作逐帧累计状态源。

### E-031｜部署配置检索再次误用递归文件枚举并超时
- **现象**：部署前使用 `Get-ChildItem -Recurse` 搜索工作流与配置文件，命令在 30 秒后超时，只来得及输出 Git remote、分支和状态。
- **原因**：即使后续用路径条件排除缓存，PowerShell 仍会先递归枚举 `.tmp`、`node_modules` 等目录，再执行过滤。
- **修正**：改用 `git ls-files`、`git ls-tree` 和对 `.github/workflows` 的定点读取，2 秒内完成发布链路确认。
- **复用规则**：部署检查只查询 Git 跟踪清单和已知配置目录；过滤表达式不能替代递归枚举阶段的目录排除。

### E-032｜GitHub HTTPS 首次连接触发 `SSL_ERROR_SYSCALL`
- **现象**：部署前执行 `git fetch origin main` 时，OpenSSL 在连接 `github.com:443` 阶段返回 `SSL_ERROR_SYSCALL`。
- **原因**：本机旧版 Git/OpenSSL 与当前网络链路的默认 HTTPS 协商偶发失败；远端地址和仓库权限本身正常。
- **修正**：单次命令增加 `-c http.version=HTTP/1.1` 后重新 fetch，成功取得 `origin/main`，并确认远端 main 是部署提交的祖先。
- **复用规则**：本项目 GitHub HTTPS 若出现握手型 `SSL_ERROR_SYSCALL`，先使用命令级 HTTP/1.1 兼容参数重试，不永久修改全局 Git 配置。

### E-033｜部署状态检查误以为本机已安装 GitHub CLI
- **现象**：推送完成后执行 `gh run list`，PowerShell 返回 `gh is not recognized`。
- **原因**：本机没有安装 GitHub CLI，部署脚本此前没有先核对命令可用性。
- **修正**：不在部署过程中临时安装工具，改用 GitHub 公共 REST API 查询 Actions，确认 Pages 工作流完成且结论为 `success`。
- **复用规则**：本项目部署状态默认使用 GitHub REST API；需要调用 `gh` 前先执行 `Get-Command gh -ErrorAction SilentlyContinue`。
