# agent.md — 项目开发指南（给 AI / 二次开发者）

> 目标：让 AI 或新接手的人在**不读全部源码**的情况下，能准确理解这个仓库在做什么、
> 各模块边界在哪、改动该落到哪个文件、有哪些不能踩的坑。
>
> 阅读顺序建议：第 1 节（全局）→ 第 3 节（数据契约）→ 第 4 节（抓取链路）→ 第 8 节（改哪里）→ 第 9 节（坑）。

---

## 1. 项目是什么

**「菜谱小本本」**（产品名 / iOS App 显示名；代码里的工程名仍是 `RecipeBook`）：
把下厨房（xiachufang.com）的菜谱详情页半自动抓到本地，形成一个
**完全离线、数据在自己机器上**的个人菜谱库，并提供搜索 / 排序 / 标签 / 详情 / 多菜统筹「开干模式」。

仓库里有**两个端**，共用同一份解析逻辑与数据契约：

| 端 | 技术栈 | 定位 |
| --- | --- | --- |
| **Web 端**（`src/`） | Node.js ≥ 22.5（`node:sqlite`）+ Express 4 + Playwright + 原生 HTML/CSS/JS（无构建） | 主力：抓取 + 本地库 + 浏览/开干 |
| **iOS 端**（`ios/RecipeBook/`） | SwiftUI + WebKit，**零三方依赖**，iOS 17+，Bundle ID `com.cook.recipebook`，显示名 **菜谱小本本** | 移动端：看菜谱 + 离线开干 + 现场抓取 |

数据流向（双向）：

```
电脑抓取 ──npm run export:ios──> iOS 种子包（打包进 App）
                                     │ 手机上看 / 手机上抓
手机备份 ──npm run import:ios──> 电脑 SQLite 库
```

---

## 2. 环境与常用命令

### 前置条件
- Node.js **≥ 22.5**（用了内置 `node:sqlite` 的 `DatabaseSync`，低于此版本直接跑不起来）
- Playwright 的 Chromium（`postinstall` 会自动 `playwright install chromium`）
- iOS 端：Xcode 16+，iOS 17+ 目标；`export:ios` 的图片压缩依赖 macOS 自带 `sips`

### Web 端
```bash
npm install          # 安装依赖（会下载 Chromium）
npm start            # 启动服务，http://localhost:5180（PORT 环境变量可覆盖）
npm run dev          # --watch 模式

npm run login        # 半自动登录：开 Chromium → 人工登录/拖滑块 → 存 data/cookies.json
npm run scrape -- --ids "106125193,107691482"
npm run fetch-images # 把库里还是远程地址的图片补抓到本地

npm run export:ios   # SQLite → iOS 种子（默认输出到 ios/RecipeBook/RecipeBook/Resources/Seed）
npm run import:ios -- 菜谱备份.json   # iOS 备份 → SQLite
```

抓取脚本参数（`src/scraper/scrape.js`）：
`--ids`（换行/逗号/空格分隔的 ID 或 URL）、`--force`（覆盖已有）、`--delay`（默认 1200ms）、
`--wait-login`（默认 600s）、`--no-images`、`--image-size`（默认 1000，0=原图）、`--debug`、`--dry-run`。

### iOS 端
- 用 Xcode 打开 `ios/RecipeBook/RecipeBook.xcodeproj`，直接 Run（**没有 .xcscheme**，命令行构建用 `-target RecipeBook`）。
- 调试预览：`RecipeBookApp.swift` 的 `PreviewRoot` 读 `UserDefaults["screen"]`（`plan/stats/scrape/cook/detail`），
  用于 `xcrun simctl launch` 直达某个页面截图。正式入口是 `RootView`。

---

## 3. 数据契约（改字段前必读）

### 3.1 权威 JSON 契约（camelCase）
`/api/recipes`、`Seed/recipes.json`、iOS `Recipe` 的 `CodingKeys` **三者键名完全一致**：

```jsonc
{
  "id": 106125193,                  // 下厨房菜谱 ID，全局主键
  "url": "https://www.xiachufang.com/recipe/106125193/",
  "title": "红烧肉", "description": "", "coverImage": "/images/covers/106125193.jpg",
  "author": "", "servings": "2 人份",
  "ingredients": [{ "name": "五花肉", "amount": "500g" }],
  "ingredientGroups": { "main": [...], "seasoning": [...] },
  "steps": [{ "index": 1, "text": "…", "image": "/images/steps/106125193-1.jpg" }],
  "tips": "", "tags": ["家常菜"],
  "madeCount": "1.2万", "favCount": "300",   // 都是 String，不是数字
  "sourceUrl": "", "collectedAt": "2026-09-17T09:03:52.802Z", "updatedAt": "…"   // ISO8601 字符串
}
```

- 时间**一律是 ISO8601 字符串**，不是 Date。
- `coverImage` / `steps[].image` 约定：**以 `/images/` 开头 = 本地**（covers/steps 子目录），
  **以 `http(s)://` 开头 = 远程**需代抓（图床有防盗链，必须带 `Referer: https://www.xiachufang.com/`）。
  这个 `/images/` 前缀约定被三处共用：Web 静态路由、iOS 沙盒、iOS Bundle 内置种子。
- `search_text`（SQLite 列）/ `searchIndex`（iOS 属性）是**派生产物**，不出现在 JSON 里，运行时/写入时计算。

### 3.2 SQLite 表（`src/db.js`）
```sql
recipes(                       -- 列名 snake_case，由 rowToRecipe() 转成 camelCase 输出
  id INTEGER PRIMARY KEY, url, title, description, cover_image, author, servings,
  ingredients TEXT,            -- JSON: [{name, amount}]
  ingredient_groups TEXT,       -- JSON: {main:[], seasoning:[]}
  steps TEXT,                   -- JSON: [{index, text, image}]
  tips, tags TEXT, made_count, fav_count,
  search_text,                 -- 归一化全文索引（去空白去标点小写）
  source_url, collected_at, updated_at
)
scrape_runs(...)                -- 每次抓取的结果记录
meta(key, value)                -- 如 app.plan（iOS 回写的待做清单）
```
- `db.js` 自带**老库兼容**：缺 `ingredient_groups` 列会 `ALTER TABLE` 补上（L59-65）。
- 搜索靠 `search_text LIKE %token%` 多词 AND；排序键见 `SORTS`（L361-369）。

---

## 4. 抓取链路（本项目最核心、最容易踩坑的部分）

### 4.1 为什么这么设计
下厨房对**自动化浏览器**下发滑动验证码，但对**带正常 Cookie/UA 的普通 HTTP 请求**返回完整的服务端渲染 HTML。
所以把两件事拆开：

| 阶段 | 实现 |
| --- | --- |
| 登录 / 过滑块 | 打开可见 Chromium（`src/scraper/login.js`），**人手动操作**；成功后把 Cookie 存 `data/cookies.json` |
| 抓 HTML | 纯 HTTP（`src/scraper/session.js` 的 `SiteClient`），不触发风控 |
| 解析 | 把 HTML 喂给**无头 Chromium 的 DOM**（`src/scraper/dom.js`，`page.setContent` + 屏蔽一切外网请求）跑 `parse.js` |
| 图片 | 下载到 `data/images/`，库里改存本地路径（`src/scraper/images.js`） |

### 4.2 三个必须记住的规则
1. **必须手动接管重定向**（`session.js` L174-197）：站点在**每一跳**下发风控 Cookie，必须逐跳吸收 `Set-Cookie` 再原样带回，否则必被弹滑块。
2. **必须忽略 `wait_xcf_clearance`**（`session.js` L77）：它是「待人机校验」标记，本身不给任何权限，
   但一旦回传且会话里没有 `xcf_clearance`，**所有请求都会被重定向到滑块页**。残留了就把 `data/cookies.json` 删掉重登录。
3. **过滑块 ≠ 登录**：过滑块只会拿到 `xcf_clearance`，**不会**产生 session cookie。
   所以判断「是否通过」要靠**探测目标页能否正常访问**（`login.js` 的 `probeTargetInBrowser`），不能只看有没有 session cookie。
   （历史上这里 bug 过：拖完滑块永远判定不通过，界面看起来卡死。）

### 4.3 风控识别（`detectChallenge`）
- finalUrl 命中 `/auth/humancheck` → `CHALLENGE`
- finalUrl 命中 `/account/(login|signup)` → `LOGIN_REQUIRED`
- HTML 前 4000 字符含 `<title>滑动验证` / `humancheck_captcha` → `CHALLENGE`
- **404 也可能是风控伪装**（`scrape.js` L116-119 有提示文案）

### 4.4 主流程（`src/scraper/scrape.js`）
```
解析 --ids → 去重 ID 列表（支持纯数字 / 完整 URL / 短链）
  → ensureSession()：probe 目标页，不通就弹浏览器让人处理（最多 3 轮；
      若「浏览器已过校验但 HTTP 仍被拦」连续 2 次，直接停止，避免无限弹窗）
  → 逐个 ID：fetchHtml → parser.run(extractRecipeInPage) → normalizeRecipe
      → localizeRecipeImages（失败只警告，保留远程地址，不阻断入库）
      → db.upsertRecipe（默认跳过已存在，--force 才覆盖）
  → finally：存 Cookie、关 parser、写 scrape_runs、emit done
```
单条失败会重试一次（`attempt < 2`），触发风控时会自动重建会话。

### 4.5 解析规则（`src/scraper/parse.js`）
**这个文件里的函数会被 `page.evaluate()` / WKWebView 丢进浏览器执行，因此必须「自包含」：不能引用外部作用域变量。**
- `extractRecipeInPage`：详情页 → 标题/简介/封面/作者/份量/用料（带主料辅料分组）/步骤/小贴士/标签/做过收藏数。
  解析不到会往 `warnings` 里塞标记（`ingredients:root-not-found`、`steps:not-found` 等），`--debug` 时把 HTML 存到 `data/debug/<id>.html`。
- `extractListInPage`：合集/收藏列表页 → 菜谱条目 + 是否有下一页（当前主流程未使用，属预留能力）。

---

## 5. 各模块职责速查

### Web 端 `src/`
| 文件 | 职责 |
| --- | --- |
| `paths.js` | 统一路径。`COOK_DATA_DIR` 可覆盖 `data/` 位置；含 DB、Cookie、browser-profile、images/covers、images/steps、debug |
| `db.js` | SQLite 数据层：建表 + 兼容迁移、upsert、查询/搜索/排序/分页、标签统计、调料白名单分类、索引归一化 |
| `server.js` | Express：REST API、任务管理（子进程）、SSE 日志流、图片代理 |
| `scraper/session.js` | Cookie Jar + HTTP 客户端 + 风控识别 |
| `scraper/browser.js` | Playwright 持久化上下文（`data/browser-profile`）、登录态探测、`USER_AGENT` |
| `scraper/login.js` | 半自动登录 / 过滑块流程，`runLoginFlow({requireLogin, probeUrl})` |
| `scraper/dom.js` | `HtmlParser`：HTML 字符串 → 无头浏览器 DOM → 执行解析函数 |
| `scraper/parse.js` | 页面解析规则（**两端共用**） |
| `scraper/scrape.js` | 抓取主流程 CLI |
| `scraper/images.js` | 图片下载/缩放/本地化 |
| `scraper/fetch-images.js` | 图片补抓 CLI |
| `scripts/export-ios.js` | SQLite → iOS 种子（默认 cover 720 / step 640 / quality 55，`sips` 压缩） |
| `scripts/import-ios.js` | iOS 备份 → SQLite（按 `updatedAt` 新者胜；处理 `deleted`；`plan` 写入 `meta.app.plan`） |
| `scripts/backfill-ingredient-groups.js` | 老数据回填主辅料分组（`--dry-run` 支持） |
| `public/` | 原生前端：`index.html` + `style.css` + `app.js`（约 1800 行，无构建） |

### `public/app.js` 分区（按顺序）
`状态`(L7) → `工具`(L87) → `数据加载`(L149) → `渲染`(L245) → `待做清单+工作模式`(L368)
→ `详情`(L1043) → `任务与日志`(L1338) → `事件绑定`(L1465) → `启动`(L1769)

### iOS 端 `ios/RecipeBook/RecipeBook/`
| 文件 | 职责 |
| --- | --- |
| `App/RecipeBookApp.swift` | 入口；`RootView` = TabView（菜谱 / 待做 / 我的）；`PreviewRoot` 调试后门 |
| `Models/Recipe.swift` | `Recipe` / `IngredientItem` / `IngredientGroups` / `RecipeStep` / `SeedManifest` |
| `Models/RecipeStore.swift` | 沙盒数据层（见下） |
| `Services/SiteClient.swift` | HTTP 客户端（手动接管重定向 + Cookie + 风控识别） |
| `Services/SessionStore.swift` | Cookie 持久化与过滤规则 |
| `Services/RecipeParser.swift` | WKWebView 跑 **同一份 `src/scraper/parse.js`** |
| `Services/ScrapeService.swift` | 抓取总控（`@MainActor`） |
| `Services/ImageDownloader.swift` | 图片下载 + 缩档 + 写沙盒 |
| `Services/RecipeImageLoader.swift` | 图片读取：沙盒 → Bundle Seed → 远程（带 Referer） |
| `Services/IngredientClassifier.swift` | 主料/调料白名单分类 |
| `Services/TimeEstimator.swift` | 步骤用时估算 + 时间格式化 |
| `Services/CookScheduler.swift` | 多菜统筹调度 + 食材聚合 |
| `Services/TextIndex.swift` / `StepText.swift` / `Format.swift` | 检索索引 / 步骤时间高亮切片 / 格式化（**`ISOStamp` 定义在 `Format.swift` 里**） |
| `Views/` | `RecipeListView`（列表）/ `RecipeDetailView`（详情）/ `PlanView`（待做）/ `CookModeView`（开干）/ `ScrapeView` / `LoginView` / `StatsView`（统计+备份）/ `RecipeImageView` |

**iOS 持久化**：`~/Library/Application Support/RecipeBook/`
```
recipes.json   权威菜谱数组（全量重写）
images/covers/  images/steps/
state.json     { updatedAt:[Int:String], deletedIds:[Int], plan:[PlanItem] }
cookies.json
```
首次启动若 `recipes.json` 不存在，从 Bundle 的 `Seed/recipes.json` 拷贝。
**导航结构**：根是 TabView，每个 tab 内各包一个 `NavigationStack`，**全项目没有 `NavigationLink`**，跨页一律 sheet / fullScreenCover。

---

## 6. 任务系统（Web 端）

`server.js` 把抓取/登录/补图都当**子进程**跑（`spawn(node, src/scraper/xxx.js)`），好处是能随时 `kill`、崩溃不拖垮服务。

- 子进程用 `@@EVENT {json}\n` 前缀行输出**结构化事件**，其余 stdout/stderr 当普通日志。
- `server.js` 逐行解析：`start / page / collected / recipe / done` 更新进度，其余广播为 `log`。
- 前端通过 `/api/jobs/stream`（**SSE**）实时接收，`EventSource` 自动重连。
- 同时只能有一个任务（第二个返回 409）；`/api/jobs/cancel` 发 SIGTERM。
- 启动时把上次残留的 `status='running'` 的 `scrape_runs` 标为 `aborted`。

HTTP API（完整列表见 README，注意还有个 README 没写的 `POST /api/recipes/:id/touch`，用于把菜谱 `updated_at` 刷成现在、浮到「按更新时间」最前）。

---

## 7. 搜索 / 排序 / 分类 / 开干算法

- **搜索**：`db.js` 的 `normalizeForIndex` 会去 `\u00a0`、小写、去**所有空白**和标点 →
  所以「红烧 肉」能命中「红烧肉」。查询侧 `tokenizeQuery` 把标点/破折号当词边界，多词是 **AND**。
  iOS 的 `TextIndex.swift` 是同一套规则。
- **主料 / 辅料分类**：`db.js` 的 `SEASONING_KEYWORDS` 白名单，`isSeasoning` 是**子串包含**匹配
  （所以「姜末」「郫县豆瓣酱」能命中根词「姜」「豆瓣酱」）。副作用：任何含「水/油/葱姜蒜」的复合名会归到调料。
  抓取时页面自带「主料/辅料/调料」分组标题就优先用页面的；没有才用白名单兜底。
  iOS 的 `IngredientClassifier.swift` 同源同规则。
- **开干（统筹调度）**：`public/app.js` 的 `scheduleRecipes`（L396）+ `TimeEstimator`。
  模型是「**单厨师 + 多锅并行**」的事件驱动模拟：
  - 被动步骤（命中 `炖|焖|煮|蒸|烤|煲|卤|焙|烩|熬|煨|沸`，`app.js` L377）一到就绪就开火，**只占锅不占厨师**；
  - 主动步骤 `start = max(自己的 cursor, 厨师空闲时刻)`，占用**唯一**厨师；
  - 厨师空闲时优先级：① 完成后能解锁的被动时长最长 ② 剩余被动总时长 ③ 原始顺序 → 即「先把火烧上，炖着的时候去忙别的菜」。
  - 时长为 0 的步骤直接丢弃，不进时间线。
  - iOS `CookScheduler.swift` 是这份逻辑的**移植**（注释里写明），改一端要同步另一端。
- **步骤时长估算**：优先解析文本里的显式时间（支持中文数字，`半=0.5`、`几=2`，多匹配累加），
  否则按动词查表（烤 25 / 慢炖 45 / 焖 30 / 蒸 18 / 炒 3 / 切 2 …，兜底 1 分钟）。
  数字后紧跟英文字母（`ml`/`kg`）不算时长。

---

## 8. 常见改动该动哪里（速查表）

| 想做的事 | 改哪里 |
| --- | --- |
| 新增/调整页面解析字段（抓取结果不对） | `src/scraper/parse.js`（**iOS 自动同步，因为是同一份文件**） |
| 支持新的列表页/合集页抓取 | `src/scraper/parse.js` 的 `extractListInPage` + `scrape.js` 主流程接入 |
| 加调料词 / 改主辅料判定 | `src/db.js` 的 `SEASONING_KEYWORDS` **和** `ios/.../IngredientClassifier.swift`（两处） |
| 改搜索规则 | `src/db.js` 的 `normalizeForIndex`/`tokenizeQuery` **和** `ios/.../TextIndex.swift`（两处） |
| 改开干调度/时间估算 | `src/public/app.js` 的 `scheduleRecipes`/`estimateStepMinutes` **和** `ios/.../CookScheduler.swift`/`TimeEstimator.swift`（两处） |
| 加 Web API | `src/server.js` 加路由；查询能力优先在 `src/db.js` 加函数 |
| 加前端交互 | `src/public/index.html`（结构）→ `src/public/app.js`（分区内加函数 + `bindEvents`）→ `style.css` |
| 改数据库 schema | `src/db.js` 的 `CREATE TABLE` + **兼容迁移块** + `rowToRecipe`/`upsertRecipe` |
| 改 iOS 数据字段 | `Models/Recipe.swift` 的 `CodingKeys` + 相关 View |
| 调种子包体积 | `npm run export:ios -- --cover-size 900 --step-size 800 --quality 70` |
| 新增一个 CLI 脚本 | 放 `src/scripts/`，在 `package.json` 加 script；若要接前端进度，需走 `server.js` 的 `SCRIPTS` 映射 + `@@EVENT` 协议 |

### 两端共用逻辑清单（**改一处必须同步另一端**）
`src/scraper/parse.js`（iOS 通过 bundle 直接引用）、配料白名单、检索索引规则、
开干调度与步骤高亮、`session.js` 的 Cookie 规则、`images.js` 的图片规则、
`browser.js` 里硬编码的桌面 Chrome UA（L7-8）。

---

## 9. 已知坑 / 注意事项（血泪清单）

### 抓取相关
1. **不要调小 `--delay`**（默认 1200ms + 0~400ms 抖动），容易触发风控。
2. 卡在「已打开浏览器窗口」：窗口可能被主窗口挡住，**看任务栏**；拖完滑块会自动继续，不需要重点按钮。
3. 突然所有请求都跳滑块 → 多半是 `data/cookies.json` 残留 `wait_xcf_clearance`，**删掉该文件重登录**。
4. 点了按钮没反应 → 早期版本有强缓存，强制刷新（Ctrl+F5）。现在已 `no-store`，且所有按钮异常都会弹窗。
5. 图片单张失败**不影响入库**（保留远程地址），之后用「补抓图片」或 `npm run fetch-images` 补。

### Web 端
6. 前端待做清单存在 `localStorage['cook_plan_v1']`，**不在数据库里**；
   iOS 的清单存在 `state.json`，通过备份 `plan` 字段回写到 `meta.app.plan`。三处并不自动打通。
7. Web `/api/recipes` 默认 `sort=collected`，前端 `state.sort` 默认 `'updated'`；
   iOS `RecipeQuery.sort` 默认 `.updated`。**两端默认值不一致**，注意别被误导。
8. `pageSize` 最大 100（服务端硬限）。
9. `data/` 整个目录在 `.gitignore` 里（DB、Cookie、图片、浏览器 profile 都不入库）。

### iOS 端
10. **`Resources/Seed` 必须是 folder reference**（pbxproj `lastKnownFileType = folder`），
    改成 group 会导致内置种子图全丢（`RecipeImageLoader` 依赖 `Bundle/Seed/images/<rel>` 目录结构）。
11. **删除后重新抓取会「复活又消失」**：`deleteRecipe` 把 id 写进 `deletedIds`，而 `upsert` 不会把它移除；
    同一 ID 重抓后当次可见，下次冷启动 `load()` 又被过滤掉。要支持撤销删除必须同步清理 `deletedIds` + `saveState()`。
12. **登录 continuation 泄漏**：`waitForLogin` 用 `CheckedContinuation`，只有 `finishLogin` 会 resume；
    LoginView 的「取消」只 `dismiss()` 不 resume → Task 永久挂起，`status` 卡 `.waitingLogin`，再也 start 不了。
13. **开干模式完成态 key 不一致（实测 bug）**：`key(lane, step)` = `"recipeId-step.index"`，
    而开工顺序卡片用 `"recipeId-step.id"`（`step.id` = `"index-Int(start)"`）。
    结果：在顺序卡点「完成」后，进度文案恒为 0、时间线与全部步骤的绿色不亮、两处高亮无法互相同步。
14. `CookModeView` 的完成状态、调度结果**全是内存态**，杀 App / 退出页面不保存；
    `refreshFromPlan()` 重排后 `completed` 不清空，清单增减后进度会对不上。
15. `RecipeListView.result` 是 computed property，在 body 里被多次求值，300+ 条时每帧重复过滤排序（性能点）。
16. `CookPlanManagerView` 与 `PlanView` 有重复的清单管理逻辑，改交互要改两处。
17. 工程 `GENERATE_INFOPLIST_FILE = YES`（**没有 Info.plist 文件**），**未配 ATS 例外** → 非 https 图片会静默失败（显示占位）。
18. 无任何 `#Preview` / 单元测试 / UI 测试；预览完全依赖 `UserDefaults["screen"]`。
19. 种子图片约 165 MB，App 体积大，真机安装慢；`localImageStats` 把 Bundle 内种子图也算进「图片体积」，看统计时会被带偏。
20. 备份只含 JSON，**不含图片**；换机恢复后图片需重抓或随种子包重新导出。

---

## 10. 代码风格与约定

- **注释一律中文**，关键文件顶部有块注释说明设计意图（尤其是「为什么这么做」，如 `session.js`、`login.js` 都解释了风控原因）。
  新增文件请沿用。
- 所有 JS 用 `'use strict'` + CommonJS（`require`/`module.exports`），Node 内置模块写 `node:fs` 前缀。
- 脚本 CLI 参数解析都是各自文件里手写的 `parseArgs`（`--key value` / `--flag` 形式），没有统一封装，新增脚本照抄即可。
- 日志前缀约定：`[SCRAPE]` / `[LOGIN]` / `[IMAGES]`；结构化事件前缀 `@@EVENT `。
- 错误处理：抓取链路用 `error.code`（`LOGIN_REQUIRED`/`CHALLENGE`/`NOT_FOUND`/`HTTP_ERROR`）区分可恢复与致命。
- **容错优先**：单张图失败、单个字段解析失败都不阻断主流程，用 `warnings` 记录。请保持这个基调。
- 两端解析/分类/检索/调度的**算法必须保持一致**，改动时请成对修改，并在 commit message 里说明。

---

## 11. 其他

- 数据、Cookie、图片、浏览器配置都在 `data/`，已 gitignore；`COOK_DATA_DIR` 可改位置。
- 抓到的内容仅供个人收藏整理使用，版权归原作者与下厨房所有。
- Git 历史较短，最近两个提交：`e239666 chore: 统一换行符为 LF 并清理遗留产物`、`a117ec6 开干模式：工序卡片详情化 + 完成态三处联动 + 统筹调度`。
- 详细的用户向说明（含完整 API 表、常见问题）见仓库根目录 `README.md`。
