# 菜谱小本本 · App Store 上架素材汇总

> 本文件供 AI / 协作者下次直接复用。所有文案以中文（简体）为准，App 已声明 `CFBundleDevelopmentRegion = zh_CN`。
> 项目根：`ios/RecipeBook`，App 显示名 **菜谱小本本**，Bundle ID `com.rongweiwei.myrecipes`，版本 `1.1`。
> **1.1 新增**：语音搜索（按住麦克风说话搜菜）、成就页（记录完成的菜与用时）、App 内隐私政策页；搜索框交互优化（聚焦/失焦、历史记录可点、聚焦态麦克风始终可按）。

---

## 1. 基本信息（App Store Connect）

| 字段 | 值 |
|---|---|
| App 名称（≤30） | 菜谱小本本 |
| 副标题（≤30） | 收藏菜谱 · 智能计时 · 开干不打乱 |
| 主要类别 | 美食与饮品（Food & Drink） |
| 次要类别 | 效率（Productivity） |
| 年龄分级 | 4+（无不当内容） |
| 价格 | 免费 |
| 语言 | 简体中文（zh_CN） |
| 隐私政策网址 | `https://drizzlee.cn/recipebook-privacy-policy.html` |
| 技术支持网址 | 同上或项目主页 |
| 营销网址（可选） | 同上 |

> 年龄分级 4+ 理由：纯菜谱浏览与家庭烹饪，无账户、无 UGC、无位置/通讯录权限、无内购、无广告。

---

## 2. 推广文本（Promotional Text，≤170，可免审核更新）

```
收藏别人的好菜谱，也能把自己琢磨出的方子存下来。按住麦克风说句菜名
就能搜；做好的菜会记进成就页，今天、本周做了几道一目了然。智能解析
步骤里的“腌十五分钟”“炖半小时”，一键倒计时；开干模式把多道菜的步骤
和食材按菜归拢，手不慌、火不糊。
```

---

## 3. 描述（Description）

```
【菜谱小本本】是一款专注“存得下、找得到、做得顺”的本地菜谱本。

· 随手收藏
  从下厨房等公开菜谱站一键抓取，或自己新建菜谱，全部存在本机，断网也能看。

· 搜索与历史
  按菜名、用料、步骤全文搜索；最近搜过的关键词按时间倒序保留，点一下再搜。

· 语音搜菜（1.1 新增）
  不用打字——按住搜索框右侧的麦克风说出菜名，说完自动转成文字开始搜，
  手上沾着面粉也能查菜谱。

· 按菜归类的食材清单
  开干前把几道菜一起加进清单，食材自动去重并按“各菜独有 → 共用”分组，
  同色块标出属于哪道菜，买菜不重不漏。

· 步骤智能计时
  自动识别“腌制十五分钟”“小火炖二十五分钟”等中文时长，步骤上直接挂计时器，
  到点本地通知提醒，开干时手上有油也不怕忘。

· 开干模式
  多道菜步骤按时间轴铺开，吸顶显示当前在做哪一步；屏幕保持常亮，方便边做边看。

· 下次做
  清单里右滑把菜设为“下次做”，这次开干不带它，也不从清单删掉，留着下次。

· 成就记录（1.1 新增）
  在「待做」清单里把做好的菜右滑「完成」，成就页会按今天 / 本周统计你
  做过的菜和每道菜的用时，做饭这件事也有了看得见的积累。

所有数据只保存在你的设备上，无账号、无广告、不收集个人信息。
App 内菜谱页右上角“ⓘ”可查看完整隐私政策。
```

---

## 4. 关键词（Keywords，≤100 字符，逗号分隔，不含“菜谱小本本”本身）

```
菜谱,食谱,下厨房,美食,家常菜,做饭,计时,食材,收藏,备菜,语音搜索,成就,厨房
```
> 字符数（含逗号）：约 41，远低于 100 上限，可随 ASO 调整。

---

## 5. 审核信息备注（App Review Information → Notes）

```
本 App 无需登录，也没有演示账号：所有功能在首次打开后即可直接使用。

- 数据全部保存在设备本地（应用沙盒），无后端服务器、无账号体系。
- “抓取菜谱”功能在用户主动触发时，从公开第三方菜谱网站（如下厨房）获取公开内容，
  仅用于本机保存与浏览，不提交任何个人信息。
- 步骤倒计时使用系统本地通知，不需要网络。
- 语音搜索：按住顶部搜索框右侧的麦克风时请求麦克风权限，语音经系统语音识别
  （Apple Speech 框架）转为文字用于搜索；本 App 不录制、不上传、不存储任何录音。
- 无内购、无广告、无第三方追踪/统计 SDK。
- 隐私政策：App 内菜谱页右上角“ⓘ”按钮可打开完整隐私政策；
  网页版：https://drizzlee.cn/recipebook-privacy-policy.html

测试建议（按界面路径）：
1. 「菜谱」Tab：浏览菜谱网格；点右上“↓”可从公开菜谱站抓取示例菜谱。
2. 点开顶部搜索框（未输入）→ 显示「最近搜索」列表，可点任一历史词直接搜索，
   右上角可“清空”；输入关键词即出搜索结果（搜索范围：菜名/用料/步骤）；
   按住搜索框右侧麦克风说话可语音搜索（首次会请求麦克风权限，请点「好」）。
3. 点开任意菜谱 → 详情页可看用料、步骤；步骤中的中文时长（如“腌制十五分钟”）
   会高亮，点“计时”即挂倒计时。
4. 「待做」Tab：把菜加入待做清单后，左滑/右滑可设「下次做」（保留在清单、不进本次开干）；
   点“🔥 开干”进入开干模式——多道菜步骤按时间轴铺开、食材按菜分组、
   屏幕保持常亮，步骤计时到点走系统本地通知。
5. 「成就」Tab：在「待做」清单里右滑某道菜点「完成」，回到成就页会看到
   今天 / 本周完成的菜与用时统计（首次无记录时显示引导空状态）。
```

---

## 6. 隐私（Privacy）

- App 内页面：`ios/RecipeBook/RecipeBook/Views/PrivacyPolicyView.swift`（工具栏右上 “ⓘ” 打开）
- 独立网页：`appstore/recipebook-privacy-policy.html`（内容与 App 内一致，上线前替换为真实托管 URL）
- 关键声明：不收集个人信息、数据仅存本机、无广告/统计 SDK、可选抓取公开菜谱；
  1.1 起新增「语音搜索与麦克风」说明：按住麦克风才拾音、经系统语音识别转文字，
  不录制/不上传/不存储任何录音（App 内与网页版均已同步此说明）。
- App Store Connect「App 隐私」标签：本 App 不收集任何数据（麦克风音频经系统识别、不留存），
  如上架时被问及麦克风用途，按「语音搜索：按住麦克风说话转文字搜索，不保存录音」填写。

---

## 7. 截图与预览（screenshots/）

App Store Connect 当前接受的尺寸（像素，竖屏，2026-10 版）：

| ASC 设备 Tab | 接受尺寸 | 我们的文件 |
|---|---|---|
| 带灵动岛的 iPhone（中等显示屏，6.1"/6.3"） | 1179×2556、1206×2622 | `iphone-6.3-*.png`（原生 1206×2622）、`iphone-6.1-*.png`（1179×2556） |
| iPhone Duo | 1398×2034、2007×2853 | `iphone-duo-*.png`（2007×2853）、`iphone-duo-1398-*.png`（1398×2034） |
| iPad 12.9"/13" | 2048×2732、2064×2752 等 | `ipad-13-*.png`（原生 2064×2752） |

> 旧 6.9"（1320×2868）截图已从本目录移除——新 ASC 设备列表不再接受该尺寸。

每套 7 张，对应屏（`*` 为通配）：
- `*-home` 首页菜谱网格
- `*-searchHistory` 点开搜索框、未输入 →「最近搜索」列表（可清空）
- `*-search` 搜索结果（“土豆”）
- `*-detail` 菜谱详情（用料、步骤、中文时长高亮）
- `*-plan` 待做清单（含「下次做」行）
- `*-cook` 开干模式（时间轴 + 食材按菜分组 + 计时器）
- `*-achievements` 成就页（今天 / 本周完成的菜与用时统计）—— 1.1 新增

> **成就页截图进度（2026-11-05）**：仅 6.3 套已补齐（`iphone-6.3-achievements.png`，1206×2622，
> 示例数据填充）。其余尺寸（6.1 / duo / duo-1398 / ipad-13）的 `*-achievements` 待补齐，可复用同一抓取方式。
>
> 抓取方式：临时给 App 加了 `-shot <tabIndex>` 启动参数（启动即跳到对应 Tab，跳过通知授权弹窗，
> 并注入示例完成记录让成就页非空），iPhone 17 模拟器上 `-shot 2` 截取；抓完已撤回临时代码。
> 若日后要补其余尺寸，可临时恢复同款 `-shot` 逻辑（跳 Tab + 种子数据）后用下述命令重抓。

生成方式（2026-10-30 实抓，UI 为当前版本）：
- iPhone 17 模拟器（7ABB6548，原生 1206×2622）→ `iphone-6.3-*`；cover 裁剪派生 `iphone-6.1-*`（1179×2556）
- iPad Pro 11" 模拟器（00719259，原生 1668×2420，比例 0.689≈Duo 0.687）→ cover 裁剪派生 `iphone-duo-*`（2007×2853）与 `iphone-duo-1398-*`（1398×2034）
- iPad Pro 13" 模拟器（A9CBDD16，原生 2064×2752）→ `ipad-13-*`

复现命令：

```bash
xcodebuild -target RecipeBook -sdk iphonesimulator -destination 'platform=iOS Simulator,id=7ABB6548-6AE0-4CB6-9389-B3A78BC6CDE3' -configuration Debug build
xcrun simctl install <device-id> build/Debug-iphonesimulator/RecipeBook.app
for shot in home detail search searchHistory plan cook; do
  xcrun simctl terminate <device-id> com.rongweiwei.myrecipes
  xcrun simctl launch --args <device-id> com.rongweiwei.myrecipes -shot$shot; sleep 7
  xcrun simctl io <device-id> screenshot appstore/screenshots/iphone-6.3-$shot.png
done
# 派生尺寸用 PIL cover 裁剪（脚本见 git 历史 / 本节说明）
```

营销图（位于 `appstore/graphics/`，1024×1024，多模态生成，可作为 App Store 宣传/预览封面）：
- `title.png` —— 标题/宣传主图（菜谱本 + 手机计时 + 食材，暖橙米白）
- `search.png` —— 搜索功能概念图（手机搜索栏 + 菜谱结果卡片）

### Apple Search Ads（ASA）创意素材尺寸
ASA 的「标题图片 / 搜索结果图片」要求是**横向**尺寸，且必须精确像素。
下表的图由上方两张 1024 方形图做 cover 填充裁剪得到（不变形），已生成在 `appstore/graphics/`：

**标题图片（Title Image）支持的尺寸：**
- `title-5244x2950.png` —— 5244 × 2950
- `title-3840x1646.png` —— 3840 × 1646

**搜索结果图片（Search Results Image）支持的尺寸：**
- `search-5244x2950.png` —— 5244 × 2950
- `search-3840x2560.png` —— 3840 × 2560
- `search-1920x1280.png` —— 1920 × 1280

> 上传 ASA 时，标题图与搜索结果图各选其一尺寸即可；若想换画面，改 prompt 重新生成 1024 方形图后，用同样 cover 裁剪脚本重出横向尺寸。

App 预览视频（App Preview）：建议 15–30s，竖屏 1080×1920，演示
“抓取/收藏 → 搜索 → 加进待做 → 开干计时” 主路径。预览封面可用 `graphics/title.png`。

> 截图由模拟器实抓（见下方命令），上传前可裁掉状态栏/ home indicator 周围的留白；
> 若 App Store 要求 6.5" 兼容尺寸（1242×2688），用 `sips` 把 6.9" 图等比缩放即可。

---

## 8. 素材生成命令记录（可复现）

```bash
# 用 iPhone 18 Pro Max (6.9") 抓首页等截图
xcrun simctl boot 1898AF88-9DF2-4AC6-BE52-A7815FCC7EF3
xcrun simctl io 1898AF88-9DF2-4AC6-BE52-A7815FCC7EF3 screenshot appstore/screenshots/iphone-6.9-01-home.png

# 用 iPad Pro 13" 抓 iPad 截图
xcrun simctl boot A9CBDD16-E3B6-47DE-B6CB-BD610BA98BBF
xcrun simctl io A9CBDD16-E3B6-47DE-B6CB-BD610BA98BBF screenshot appstore/screenshots/ipad-13-01-home.png
```

图标（1024）已在 `ios/RecipeBook/RecipeBook/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`，
可直接作为 App Store 图标上传（需确认无 alpha 通道/透明背景，纯直角）。
