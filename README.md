# 我的菜谱库（下厨房单菜谱半自动抓取）

把下厨房菜谱详情页（名称、用料、步骤、小贴士、封面图）按你输入的 ID 或 URL 抓取到本地 SQLite，
并提供一个可以**本地搜索、排序、筛选、查看详情**的 Web 界面。数据完全存在你自己电脑上。

---

## 快速开始
```bash
npm install      # 安装依赖（会自动下载 Playwright 的 Chromium）
npm start        # 启动本地菜谱库，浏览器打开 http://localhost:5180
```

然后在网页右上角点击 **「抓取菜谱」**，在弹窗里粘贴你想要入库的菜谱 ID 或完整 URL（每行一个），点「开始抓取」。
首次运行会弹出一个浏览器窗口，请在里面**手动完成下厨房登录**（遇到滑块验证请拖动一下），
脚本检测到登录成功后会保存会话并自动开始抓取，全程无需再干预。

也可以在命令行里跑：
```bash
npm run login    # 只做登录，保存会话到 data/cookies.json
npm run scrape -- --ids "106125193,107691482"      # 抓取指定菜谱
```

---

## 工作原理
下厨房会对「自动化浏览器」下发滑动验证码，但对普通 HTTP 请求（带正常 Cookie / UA）返回的是
**完整的服务端渲染 HTML**。所以本项目把两件事分开做：

| 阶段 | 方式 |
| --- | --- |
| 登录 / 过验证 | 打开真实 Chromium 窗口，**由你手动登录并拖动滑块**，成功后把 Cookie 存到 `data/cookies.json` |
| 抓取 | 用 HTTP 请求 + 这份 Cookie 抓菜谱详情页，走的是普通请求，不触发风控 |
| 解析 | 把 HTML 交给无头 Chromium 的 DOM 做解析（`page.setContent`，不联网），兼容各种不规范的 HTML |
| 图片 | 封面图与步骤图下载到 `data/images/`，数据库里存本地地址 |

另外实现了一个 Cookie Jar（含手动重定向），因为站点会在每一跳下发风控 Cookie，必须原样带回。

**关于 `wait_xcf_clearance`：** 站点在判定请求可疑时会下发这个标记 Cookie。它不提供任何权限，
但只要被回传、而会话里又没有通过校验的 `xcf_clearance`，**所有请求都会被重定向到滑块页**。
因此本项目在收发 Cookie 时会主动忽略它，避免会话被"污染"后彻底用不了。
真正需要人机校验时，脚本会**自动弹出浏览器**让你拖一下滑块，之后继续抓取。

---

## 命令与参数
```bash
npm start                          # 启动 Web 界面（默认端口 5180，可用 PORT 环境变量覆盖）
npm run login                      # 半自动登录
npm run scrape -- --ids "106125193,107691482"     # 抓取指定菜谱
npm run fetch-images               # 把库里还是远程地址的图片补抓到本地

# 抓取的可选参数
node --no-warnings src/scraper/scrape.js \
  --ids "106125193,107691482"   # 菜谱 ID 或 URL 列表，换行/逗号/空格分隔
  --force                          # 覆盖更新已存在的菜谱（默认跳过）
  --delay 1200                     # 请求间隔毫秒数，越大越稳（默认 1200）
  --wait-login 600                 # 等待人工登录 / 校验的秒数
  --no-images                      # 不下载图片，只记录远程地址
  --image-size 1000                # 图片最长边，下载时自动压缩（默认 1000，0 = 原图）
  --debug                          # 解析异常时把 HTML 存到 data/debug/
  --dry-run                        # 只解析不写库
```

---

## Web 界面功能
- **搜索**：对菜名、简介、作者、份量、用料、步骤、标签做全文匹配；
  空格分隔多个关键词是 AND 关系（例如 `五花 冰糖`），标点会被当作词边界。
- **排序**：抓取时间 / 更新时间 / 菜名 / 用料数量 / 步骤数量 / 菜谱 ID / 随机，支持升序降序切换。
- **标签筛选**：自动汇总所有标签并显示数量，点击即筛选。
- **分页**：每页 12 / 24 / 48 / 96 可选。
- **详情**：点卡片打开右侧抽屉，展示完整用料表、带图步骤和小贴士，附原网页跳转，可单独删除。
- **抓取面板**：底部实时显示抓取进度与日志；首次加载时默认收起，只有正在跑任务时自动展开，可手动展开 / 收起。
- **补抓图片**：把库里仍是远程地址的图片一次性下载到本地。
- **图片**：抓取时自动把封面图 / 步骤图下载到 `data/images/`，页面直接读本地文件；
  旧数据里残留的远程地址则由 `/api/image?url=…` 代抓（图床有防盗链），并做内存缓存。

---

## HTTP API
| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/recipes?q=&tag=&sort=&order=&page=&pageSize=` | 查询菜谱列表 |
| GET | `/api/recipes/:id` | 菜谱详情 |
| DELETE | `/api/recipes/:id` | 删除菜谱 |
| GET | `/api/tags` | 标签及数量 |
| GET | `/api/stats` | 统计信息与最近一次抓取结果 |
| GET | `/api/session` | 本地登录态 / 人机校验凭证是否可用 |
| POST | `/api/jobs/login` | 启动登录流程（子进程） |
| POST | `/api/jobs/scrape` | 启动抓取任务，body `{ ids, force?, debug?, delay?, noImages?, imageSize? }` |
| POST | `/api/jobs/images` | 启动图片补抓任务（子进程） |
| POST | `/api/jobs/cancel` | 终止当前任务 |
| GET | `/api/jobs/current` | 当前任务状态与最近日志 |
| GET | `/api/jobs/stream` | SSE 实时进度 / 日志 |
| GET | `/images/*` | 本地缓存的菜谱图片 |

---

## 目录结构
```
src/
  server.js              Express 服务：查询 API、任务管理、图片代理
  db.js                  SQLite 数据层（建表、upsert、搜索、排序、标签、统计）
  paths.js               统一路径（data/ 下存放数据库、Cookie、浏览器 profile）
  scraper/
    login.js             半自动登录：开浏览器 → 等人工登录/过滑块 → 存 Cookie
    session.js           Cookie Jar + HTTP 客户端 + 风控识别
    dom.js               HTML 字符串 → DOM → 解析函数
    parse.js             菜谱详情页解析规则（浏览器上下文执行）
    scrape.js            单菜谱抓取主流程（接受 ID/URL，逐条抓取、增量入库、风控恢复）
    images.js            图片下载与本地化（自动压缩、失败回退原图）
    fetch-images.js      图片补抓脚本（把远程图片一次性本地化）
    browser.js           Playwright 启动与登录态探测
  public/                前端（原生 HTML/CSS/JS，无构建步骤）
data/
  recipes.db             SQLite 数据库
  cookies.json           登录会话
  browser-profile/       Chromium 持久化配置（浏览器登录态）
  images/covers/         本地封面图
  images/steps/          本地步骤图
  debug/                 --debug 时保存的页面 HTML
```

---

## 数据表
```sql
recipes(
  id INTEGER PRIMARY KEY,   -- 下厨房菜谱 ID
  url, title, description, cover_image, author, servings,
                           -- cover_image 为本地地址 /images/covers/<id>.<ext>；
                           -- 若下载失败则保留原始远程地址
  ingredients TEXT,         -- JSON: [{name, amount}]
  steps TEXT,               -- JSON: [{index, text, image}]，image 同样是本地地址
  tips, tags TEXT,          -- JSON: ["家常菜", "红烧"]
  made_count, fav_count,
  search_text,              -- 归一化全文索引字段
  source_url, collected_at, updated_at
)
scrape_runs(...)            -- 每次抓取的结果记录
meta(key, value)
```

---

## 常见问题
**点了「开始抓取」没反应？**
先强制刷新页面（`Ctrl + F5`）。早期版本对前端资源做了强缓存，
浏览器可能还在用旧版 `app.js` 配新版 `index.html`，导致脚本报错但界面无提示。
现在已关闭强缓存，并且所有按钮异常都会弹窗提示。

**卡在「已打开浏览器窗口」不动？**
抓取遇到人机校验时会弹出浏览器窗口，请到那个窗口里拖动滑块。
验证一通过脚本就会**自动继续**，不需要重新点按钮。
窗口可能被主窗口挡住，注意任务栏；如果拖完仍然长时间没进展，
把「请求间隔」调大（如 2500ms）、等几分钟再试。

> 早期版本在这里只等「登录 Cookie」，导致过滑块（不需要登录）时永远等不到，
> 只能干等到超时，看起来就像卡死了。现在改为探测目标页能否正常访问，已修复。

**之前能用，突然所有请求都跳滑块？**
通常是 `data/cookies.json` 里残留了 `wait_xcf_clearance` 标记。
直接删掉该文件，再点「登录下厨房」重新走一次校验即可。

**图片没下载下来？**
单张失败不影响菜谱入库（会保留远程地址）。稍后点「补抓图片」，或执行 `npm run fetch-images`。

## 说明
- 抓取节奏默认每次请求间隔约 1.2 秒（含随机抖动），请勿把 `--delay` 调得过小，
  否则容易触发站点风控。
- 抓到的内容仅供个人收藏整理使用，版权归原作者与下厨房所有。
- 数据库、Cookie、图片与浏览器配置都在 `data/` 目录，已在 `.gitignore` 中忽略。