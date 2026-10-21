# agent.md — 菜谱小本本（iOS）开发指南

> 给 AI / 二次开发者看的仓库说明书。读完这份，应该能在不看全部源码的情况下判断
> 「这个项目在做什么、改某个东西要动哪些文件、哪些地方不能碰」。

---

## 1. 项目是什么

**菜谱小本本**：一个纯本地的 iOS 菜谱 App。把下厨房（xiachufang.com）的菜谱详情页抓进手机，
形成**离线可用、数据只在手机上**的菜谱库，并提供：搜索 / 标签 / 排序、详情、待做清单、
以及多菜统筹的「开干模式」（时间线 + 开工顺序）。

关键特性：

- **无服务器、无账号**：数据全在 App 沙盒，不上传任何东西。
- **零三方依赖**：只用 SwiftUI + WebKit + UniformTypeIdentifiers，无 SPM / CocoaPods。
- **自己抓自己解析**：App 内用 WKWebView 人工登录 + 纯 HTTP 抓页 + WKWebView 跑 JS 解析 + 图片落到沙盒。
- **内置种子数据**：出厂自带 317 道菜（`Resources/Seed/recipes.json`），首次启动拷进沙盒。

> 历史：早期还有一个 Node.js 电脑端（`src/`，Express + Playwright + SQLite），负责批量抓取并导出种子。
> 现已整体移除。它唯一被 App 依赖的文件 `parse.js` 已迁到 `ios/RecipeBook/RecipeBook/Resources/parse.js`。

---

## 2. 环境与构建

- Xcode 16+，**部署目标 iOS 17.0**，Bundle ID `com.cook.recipebook`，显示名 **菜谱小本本**。
- 没有共享 scheme（scheme 在 `xcuserdata/`，已被 gitignore）。命令行构建用：

```bash
cd ios/RecipeBook
xcodebuild -target RecipeBook -sdk iphonesimulator build      # 模拟器
xcodebuild -target RecipeBook -sdk iphoneos build             # 真机（需签名）
```

- **调试后门**：`RecipeBookApp.swift` 的 `PreviewRoot` 读 `UserDefaults["screen"]`，
  配合 `xcrun simctl launch` 直达某个页面做截图/调试：`plan / stats / scrape / cook / detail`
  （`detail` 硬编码菜谱 id `15013`）。正式入口是 `RootView`。
- 无 Info.plist 文件（`GENERATE_INFOPLIST_FILE = YES`），**没有配 ATS 例外** — 站点图床是 https，
  若将来要拉 http 图片会静默失败（只显示占位图）。

---

## 3. 目录结构

```
ios/RecipeBook/
  RecipeBook.xcodeproj/
    project.pbxproj              工程配置（注意 Seed 必须是 folder reference）
  RecipeBook/
    App/RecipeBookApp.swift      @main 入口 + TabView 根 + PreviewRoot 调试入口
    Models/
      Recipe.swift               Recipe / IngredientItem / IngredientGroups / RecipeStep / SeedManifest
      RecipeStore.swift          沙盒数据层（增删改查、待做、备份恢复）
    Services/
      SiteClient.swift           HTTP 客户端：手动接管重定向 + Cookie Jar + 风控识别
      SessionStore.swift         Cookie 持久化与过滤规则
      RecipeParser.swift         WKWebView 跑 Resources/parse.js 解析 HTML
      RecipeParser 用到的 Resources/parse.js（App 内置）
      ScrapeService.swift        抓取总控（@MainActor）
      ImageDownloader.swift      图片下载 + 缩档 + 写沙盒
      RecipeImageLoader.swift    图片读取：沙盒 → Bundle 种子 → 远程
      IngredientClassifier.swift 主料 / 调料白名单分类
      TimeEstimator.swift        步骤用时估算 + 时间格式化
      CookScheduler.swift        多菜统筹调度 + 食材聚合
      TextIndex.swift            检索索引 / 分词
      StepText.swift             步骤文本里的时间片段切片（高亮用）
      Format.swift               展示格式化（ISOStamp 也定义在这里）
    Views/
      RecipeListView.swift       列表：搜索 / 标签 / 排序 / 分页
      RecipeDetailView.swift     详情：用料分组 / 步骤 / 小贴士
      PlanView.swift             待做清单 → 开干
      CookModeView.swift         开干模式：食材汇总 / 时间线 / 开工顺序 / 全部步骤
      ScrapeView.swift           抓取：粘贴 ID、登录态、进度与日志
      LoginView.swift            WKWebView 登录 / 过滑块
      StatsView.swift            统计 + 备份导出/导入 + 说明
      RecipeImageView.swift      图片小组件
    Resources/
      Assets.xcassets            AppIcon + BrandMark
      parse.js                   页面解析脚本（务必随包，缺了会解析失败）
      Seed/                      recipes.json + manifest.json + images/（图片 162MB，不入库）
```

---

## 4. 数据契约

### 4.1 `Recipe`（`Models/Recipe.swift`，JSON 键由 `CodingKeys` 定义）

```jsonc
{
  "id": 106125193,                 // 下厨房菜谱 ID，全局主键
  "url": "https://www.xiachufang.com/recipe/106125193/",
  "title": "红烧肉", "description": "", "coverImage": "/images/covers/106125193.jpg",
  "author": "", "servings": "2 人份",
  "ingredients": [{ "name": "五花肉", "amount": "500g" }],
  "ingredientGroups": { "main": [...], "seasoning": [...] },
  "steps": [{ "index": 1, "text": "…", "image": "/images/steps/106125193-1.jpg" }],
  "tips": "", "tags": ["家常菜"],
  "madeCount": "1.2万", "favCount": "300",      // 都是 String
  "sourceUrl": "", "collectedAt": "2026-09-17T09:03:52.802Z", "updatedAt": "…"
}
```

- 时间是 **ISO8601 字符串**（带毫秒），由 `Format.swift` 里的 `ISOStamp` 读写，别当成 Date 解析。
- `searchIndex` 是运行时算的派生索引，**不在 CodingKeys 里**，不会写进 JSON。
- `Recipe.init(from:)` 全用 `(try? decode(...)) ?? 默认值` —— **结构错了不报错，静默降级**。
  好处是容错强，代价是 JSON 变形时很难发现。
- 图片路径约定：**`/images/` 开头 = 本地**（沙盒优先，找不到再回退 Bundle 内的 `Seed/images/`）；
  `http(s)` = 远程，请求时带 `Referer: https://www.xiachufang.com/`（防盗链）。

### 4.2 沙盒持久化（`RecipeStore`）

```
~/Library/Application Support/RecipeBook/
  recipes.json   权威菜谱数组（全量重写）
  images/covers/  images/steps/
  state.json     { updatedAt: [Int:String], deletedIds: [Int], plan: [PlanItem] }
  cookies.json   登录态
```

- 首次启动从 Bundle 的 `Seed/recipes.json` 拷一份；之后永远读写沙盒。
- `updatedOverrides[id]` 覆盖 `updatedAt`（本地 touch 过的时间要能盖住种子里的旧时间）。
- 删除 = 记入 `deletedIds` + 移出数组 + 同时重写 `recipes.json` 和 `state.json`；
  `load()` 会再按 `deletedIds` 过滤一次。
- 排序默认 `.updated`，分页默认 24（`RecipeQuery`）。

### 4.3 备份格式（`RecipeBackup`，对应旧的 `import-ios`）

```jsonc
{ "exportedAt": "…", "recipes": [...], "plan": [...], "deleted": [123], "updatedAt": {"123": "…"} }
```

恢复语义：按 `updatedAt` 新者胜；`deleted` 直接应用；`plan` 覆盖。**备份不含图片。**

---

## 5. 抓取链路（最容易踩坑的部分）

```
ScrapeService（@MainActor，总控）
  ├─ SessionStore.load() → [SiteCookie]
  ├─ SiteClient ── 纯 HTTP：手动接管重定向、逐跳吸收 Set-Cookie
  │     └─ detectChallenge() → .challenge / .loginRequired / .notFound
  ├─ 会话不通 → status = .waitingLogin → ScrapeView 自动弹 LoginView（WKWebView）
  │     └─ 人工登录 / 拖滑块 → 取 Cookie → ScrapeService.finishLogin → 继续
  ├─ RecipeParser（WKWebView 跑 Resources/parse.js，屏蔽一切外网资源）→ RawRecipe
  ├─ normalize() + IngredientClassifier.classify() → Recipe
  ├─ ImageDownloader → coverImage / steps[i].image 变成 "/images/..."
  └─ RecipeStore.upsert()
```

### 5.1 四条铁律

1. **手动接管重定向**：站点在**每一跳**下发风控 Cookie，必须逐跳吸收再原样带回（`RedirectBlocker`）。
2. **忽略 `wait_xcf_clearance`**：它是「待人机校验」标记，本身不给权限，但只要回传且会话里没有
   `xcf_clearance`，**所有请求都会被重定向到滑块页**。
3. **过滑块 ≠ 登录**：拖完滑块只下发 `xcf_clearance`，不会有 session cookie。探测成败靠
   「目标页能不能正常访问」（`SiteClient.probe`），不能只看有没有 session cookie。
4. **404 可能是风控伪装**：`ScrapeService`/`SiteClient` 里对 404 有专门的提示文案。

### 5.2 解析

`Resources/parse.js` 的 `extractRecipeInPage` 负责详情页 → 数据。它是**在浏览器上下文里执行**的，
所以里面的函数必须**自包含**（不能引用外部作用域变量）。解析不全时会返回 `warnings`
（`ingredients:root-not-found`、`steps:not-found` 等）。

App 侧 `RecipeParser` 用 `WKContentRuleList` 屏蔽所有外部资源，注入 `<base href>` 后
`loadHTMLString`，再用假的 `module` 对象兜住 `module.exports` 执行脚本。

### 5.3 图片

图床地址形如 `<hash>_3000w_4000h.jpg`，`resizedURL` 换成 `_1000w_1333h` 再下；
下载后若长边仍超过 size 用 `UIGraphicsImageRenderer` 压 JPEG(q=0.88)；`< 64 bytes` 视为失败。
命名：封面 `covers/<id>.<ext>`，步骤 `steps/<id>-<stepIndex>.<ext>`。

---

## 6. 应用层算法

- **搜索**（`TextIndex`）：`normalize` = 小写 + 去 `\u{00A0}` + 去所有空白 + 去标点集合；
  `tokens` 把标点/破折号当词边界切词；`matches` 是**纯子串 + 多词 AND**。全内存，几百条无压力。
- **主料 / 调料**（`IngredientClassifier`）：硬编码白名单，`isSeasoning` 是**子串包含**匹配
  （「姜末」「郫县豆瓣酱」能命中根词）。副作用：任何含「水/油/葱姜蒜」的复合名都会归到调料。
- **步骤时长**（`TimeEstimator`）：优先解析文本里的显式时间（支持中文数字，`半=0.5`、`几=2`，多匹配累加），
  否则按动词表估算（烤 25 / 慢炖 45 / 焖 30 / 蒸 18 / 炸 6 / 煎 5 / 炒 3 / 腌制 30 / 醒发 60 / 切 2 …，兜底 1 分钟）。
  数字后紧跟英文字母（`ml`/`kg`）不算时长。
- **统筹调度**（`CookScheduler`）：**单厨师 + 多锅并行**的事件驱动模拟。
  - 一道菜 = 一条 lane；时长为 0 的步骤直接丢弃。
  - 被动步骤（命中 `炖|焖|煮|蒸|烤|煲|卤|焙|烩|熬|煨|沸`，纯关键词）一到就绪就开火，**只占锅不占厨师**。
  - 主动步骤 `start = max(自己的 cursor, 厨师空闲时刻)`，占用**唯一**厨师。
  - 厨师空闲时优先级：① 完成后能解锁的被动时长最长 ② 剩余被动总时长 ③ 原始顺序
    —— 即「先把火烧上，炖着的时候去忙别的菜」。
- **步骤时间高亮**（`StepText`）：切片出时间片段（数字时间 + 中文时间），供详情与开干页做富文本。

---

## 7. 界面结构

- 根是 `TabView`：**菜谱**（`RecipeListView`）/ **待做**（`PlanView`，badge 显示清单数）/ **我的**（`StatsView`）。
  每个 tab 内各包一个 `NavigationStack`；**全项目没有 `NavigationLink`**，跨页一律 sheet / fullScreenCover：
  - 列表 → 详情 `.sheet(item:)`；列表 → 抓取 `.sheet`；待做 → 开干 `.fullScreenCover`；
    抓取 → 登录 `.sheet`（`status == .waitingLogin` 自动弹出）。
- `ScrapeView` 的「进度」区：进度条 + 百分比 + 当前菜名 + 日志 + 停止按钮；
  运行中会提示**切后台/锁屏会暂停抓取**。App 进后台时 `ScrapeService.noteBackgrounded()` 写一条日志说明。
- 公共小组件散落在 View 文件里：`Card` / `FlowLayout` / `RecipeCard` / `CookPlanManagerView` /
  `RecipeBackupDocument` / `SiteLoginWebView`，改动时注意复用点。

---

## 8. 改动速查表

| 想做什么 | 改哪里 |
| --- | --- |
| 页面字段抓错 / 新增解析字段 | `Resources/parse.js`（必要时同步 `RecipeParser.swift` 的 `RawRecipe`） |
| 加调味词 / 改主辅料判定 | `Services/IngredientClassifier.swift` |
| 改搜索规则 | `Services/TextIndex.swift` + 用到它 `RecipeStore.query` |
| 改开干调度 / 时长估算 | `Services/CookScheduler.swift`、`Services/TimeEstimator.swift`（可能还要动 `CookModeView`） |
| 改数据字段 | `Models/Recipe.swift` 的 `CodingKeys` + 相关 View + `RecipeStore` |
| 改存储位置 / 增删改查 | `Models/RecipeStore.swift` |
| 改抓取节流 / 重试 / 风控判定 | `Services/SiteClient.swift`、`Services/ScrapeService.swift` |
| 改图片策略 | `Services/ImageDownloader.swift`、`Services/RecipeImageLoader.swift` |
| 改 Backups 语义 | `RecipeStore.makeBackup/restore`、`Views/StatsView.swift` |
| 更新出厂种子 | 重新生成 `Resources/Seed/`（代码已不再包含导出脚本，需自己产出） |

---

## 9. 已知坑 / 注意事项

1. **`Resources/Seed` 在 pbxproj 里必须是 folder reference**（`lastKnownFileType = folder`）。
   改成 group 会导致内置种子图全丢，因为 `RecipeImageLoader` 依赖 `Bundle/Seed/images/<rel>` 目录结构。
2. **`Resources/parse.js` 必须随包**（pbxproj 里 `PBXFileReference` 路径是 `RecipeBook/Resources/parse.js`，
   PBXBuildFile 挂在 Resources phase）。缺了会报「App 里缺少解析脚本」。
3. **切后台会暂停抓取**：没有 `beginBackgroundTask`、没有后台 URLSession，`ScrapeService` 整体在
   `@MainActor` 上跑。UI 已经明确提示过用户，别指望长任务在后台跑完。
   `RecipeParser.makeBlockRemoteRules()` 用 semaphore 同步等待，**整个抓取只 `create()` 一次**，别改成每条菜谱都新建。
4. **取消登录必须回调**：`waitForLogin` 用 `CheckedContinuation`，只有 `finishLogin` / `cancelLogin` 会 resume。
   `LoginView` 的「取消」按钮与 `onDisappear` 兜底都要调 `onCancel`，否则抓取 Task 永久挂起
   （状态卡 `.waitingLogin`，再也 start 不了）。已修复，改 UI 时别把这个回调弄丢。
5. **删除过的菜谱重新抓回来**：`upsert` 会把 id 从 `deletedIds` 里摘掉并落盘 `state.json`，
   否则本次可见、下次冷启动又被过滤掉（已修复）。若以后新增别的写入路径，记得同样处理。
6. **`checkSession()` 探测写死 ID `106125193`**（`ScrapeService`），`ScrapeView.probeURL` 兜底也用它。
7. **完成态 key 不一致（已知 bug，未修）**：`CookModeView` 里时间线用 `"recipeId-step.index"`，
   开工顺序卡片用 `"recipeId-step.id"`（`step.id` = `"index-Int(start)"`）。
   所以在顺序卡点「完成」后：进度文案恒为 0、时间线与全部步骤的绿色不亮、两处高亮无法互相同步。
8. **开干模式的进度与调度全是内存态**：杀 App / 退出页面不保存；`refreshFromPlan()` 重排后
   不重置 `completed`，清单增删后进度会对不上。
9. `RecipeListView.result` 是 computed property，在 body 里被多次求值，300+ 条时每帧重复过滤排序。
10. `CookPlanManagerView` 与 `PlanView` 有重复的清单管理逻辑，改交互要改两处。
11. 无 `#Preview`、无单元测试、无 UI 测试；预览依赖 `UserDefaults["screen"]` + `PreviewRoot`。
12. `localImageStats` 把 Bundle 内的种子图也算进「图片体积」，看统计时会被带偏。
13. 备份只含 JSON，**不含图片**；换机恢复后图片需要重新抓取。
14. `PreviewRoot` 每次 body 求值都会往沙盒写 `args.log`，`detail` 预览硬编码 id `15013` —— 调试残留，发版前建议清理。

---

## 10. 代码风格约定

- 注释一律中文；关键文件顶部有块注释说明**设计意图与为什么这么做**，新增文件请沿用。
- 错误处理：抓取链路统一用 `ScrapeError(code:)`，`ScrapeCode` 区分可恢复与致命。
- **容错优先**：字段缺失、图片下载失败都不阻断主流程，用 `warnings` / `logs` 记录下来。
- `ScrapeService` 是 `@MainActor`，改的时候不要在里面塞重活；`RecipeParser` 同理（WKWebView 要求主线程）。
- 大的 algorithmic 改动（调度、时长估算、分类、检索）要保证 App 内行为与既有数据兼容 —— 这些规则
  会影响已存进沙盒的历史菜谱如何展示。
