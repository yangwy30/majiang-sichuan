# iOS App（1.0）

1.0（build 2）2026-10-31 已提交 App Store 审核，产品页和送审情况见 [docs/app-store.md](../docs/app-store.md)。

```
app/
  Majiang.xcodeproj   Xcode 工程（需要 Xcode 16 或更新；源码目录自动同步，加文件不用改工程）
  MajiangApp/         SwiftUI 界面，iOS 17+
  MajiangKit/         纯逻辑的 Swift 包：牌、算番、牌局账本、识别。能在 Linux 上编译和跑测试
```

## 怎么跑

- **App**：用 Xcode 打开 `app/Majiang.xcodeproj`，选一个 iPhone 模拟器运行。真机要在 Signing 里选自己的开发者 Team。
  识别方式默认「自动」：填了 Gemini Key 又装了端侧模型就双读，只有一样就用那一样，**两样都没有才用演示数据**。演示数据不看照片，按顺序给出三手示例牌（清一色带一张待确认的牌、带碰和暗杠的混一色、认错一张不成和的花龙），核对页标题会写「演示数据，没看你的照片」。
- **用 Gemini 认牌**：开发版长按首页的「拍照算番」标题打开设置 → 填 Gemini API Key（只存在手机钥匙串里）。识别方式保持「自动」就会用上；设置页「现在用」显示实际走哪一路。正式版没有设置页。
  - 省掉粘贴：编译前在 Mac 上 `mkdir -p app/MajiangApp/Resources/DevSecrets && cp ~/.config/gemini/api_key app/MajiangApp/Resources/DevSecrets/GeminiDevKey.txt`，开发版第一次打开会自动存进钥匙串。这个目录已被 `.gitignore` 挡住；文件会打进 App 包，所以**打 TestFlight / 上架包之前一定删掉它**。
- **端侧模型 + 双读**：先按下面「端侧模型」把模型放进 App，再填 Key，「自动」就是双读（也可以手动选「只用端侧模型」，不用联网）。
- **截图**：开发版启动参数 `-demo-screen <页面>` 用临时假数据直接停在某一页，见 [用户流程设计](../docs/user-flow.md#截图怎么更新)。
- **测试**：`cd app/MajiangKit && swift test`（Mac 或 Linux 都行）。

## 结构

| 部分 | 内容 |
|---|---|
| `MajiangKit/Sources/CGuobiao` | 国标算番。直接用 [ChineseOfficialMahjongHelper](https://github.com/summerinsects/ChineseOfficialMahjongHelper) 的 C++ 算法（MIT，版权声明见 `vendor/LICENSE`，上架时要在 App 的「致谢」里列出），外面包一层 C 接口 |
| `MajiangKit/Sources/MajiangKit/Tiles` | 牌、副露、手牌，牌的记法解析（`123m456p东东`、`5饼`、`五万`） |
| `MajiangKit/Sources/MajiangKit/Scoring` | `FanCalculator` 算番（81 番 + 明暗杠，花牌单独计、不计入起和），`WinAssistant` 不成和时给改牌建议，`SpecialWin` 特殊情况的置灰规则 |
| `MajiangKit/Sources/MajiangKit/Game` | 牌局：圈风、门风、庄家自动轮转（不连庄，可选每圈换座），自摸/点炮收付，荒庄，错和，手动记分，改或删以前的局（后面的局数、风位、番数、分数重算），最少转账，JSON 存档 |
| `MajiangKit/Sources/MajiangKit/Recognition` | `TileRecognizer` 协议和几种实现，见下 |
| `MajiangApp` | [用户流程](../docs/user-flow.md) 的页面：首页、开局、牌桌（也是账本）、拍照（内嵌取景器）、核对、结果（弹出层）、结算，加改局、家规（`HouseRulesForm`、`GameRulesSheet`）、填邀请码（`InviteView`）、规则说明、直接改分、备份和开发版设置。视觉规范「墨与朱」在 `Support/Theme.swift` |

### 识别

界面只认 `TileRecognizer` 协议，识别方式可以随时换：

- `GeminiRecognizer`：研究里效果最好的方法，附牌面参考图 + 要求逐张数点数（Flash，33 张里 32 张全对；换成 App 自己画的参考图重测也是 32/33。线上用 3.8 Flash 低思考，30/33、约 7 秒，模型由中转站决定）。模型只负责读牌，和没和、几番由规则引擎决定。
- `RuleCheckedRecognizer`：读出的牌凑不成和牌时，带着原因让模型再看一次。
- `OnDeviceRecognizer`：端侧认牌。`CoreMLTileDetector` 跑检测模型（先整图找牌、再把牌区裁出来放大重找），`TileLayout` 按行分组、去掉画面里别人的牌和牌河，排成手牌。分不出吃碰杠，都当立牌。
- `DualReadRecognizer`：端侧和 Gemini 同时跑。端侧几百毫秒先出结果，App 马上进核对页（牌面先锁住，可以先选自摸/点炮）；Gemini 复核完按顺序对齐合并：读得一样的直接用，同一位置不一样的给两个候选，只有一边读到的问「照片里有这张吗」，副露以 Gemini 为准。`RecognitionResolver` 在候选里挑出唯一能和的组合，标成「选这个能和」。Gemini 失败时留着端侧结果并提示。
- `MockRecognizer`：演示数据。

### 端侧模型（只放本地）

用的是开源项目 [AR麻将助手](https://github.com/LYiHub/AR-Mahjong-Assistant-preview) 的 YOLOv8n 认牌模型（42 类，研究见 [on-device-model](../research/on-device-model.md)）。模型文件不进仓库，在本地下载、转换后放进 App；`.gitignore` 已经挡住了 `*.onnx`、`*.mlpackage` 和 `MajiangApp/Resources/Models/`。换别的模型时只要输入输出照下面的约定，代码不用改。

放进 App：

```sh
# 1. 拿 ONNX 权重（weights.onnx，12 MB）
curl -L -o /tmp/weights.onnx https://github.com/LYiHub/AR-Mahjong-Assistant-preview/raw/HEAD/server/models/yolo/weights.onnx
# 2. 转成 Core ML（会核对和 ONNX Runtime 的输出一致）
python3 -m venv /tmp/coreml && /tmp/coreml/bin/pip install torch onnx onnx2torch coremltools onnxruntime numpy
#    Intel 版 Python 3.9 只装得上 torch 2.2，要再装 'numpy<2'，否则报 Numpy is not available
mkdir -p app/MajiangApp/Resources/Models
YOLOV8_ONNX=/tmp/weights.onnx /tmp/coreml/bin/python tools/on-device-model/convert_coreml.py \
    app/MajiangApp/Resources/Models/MahjongTileDetector.mlpackage
```

Xcode 会自动把 `MahjongTileDetector.mlpackage` 编译进 App（目录是同步的，不用改工程）。设置页「端侧模型」显示「已装」就对了。

模型约定：输入 `images`，`1×3×640×640` 浮点 RGB（0–1，等比缩放、四周补灰 114）；输出 `1×(4+类别数)×anchors`（YOLOv8 检测头原样输出，框是 cx cy w h）；类别名写在模型元数据 `names` 里（逗号分隔，认 Jon Chan 的 `5B`/`RD`/`3F` 和我们的 `5s`/`中`）。

在 Mac 上用测试照片评测端侧和双读（走 App 里同一套代码）：

```sh
cd app/MajiangKit
MAJIANG_TILE_MODEL=../MajiangApp/Resources/Models/MahjongTileDetector.mlpackage \
MAJIANG_GEMINI_KEY_FILE=~/.config/gemini/api_key \
swift test --filter OnDeviceEvaluationTests
```

不给 `MAJIANG_GEMINI_KEY_FILE` 就只评测端侧。

### API Key 和后端代理

- Key **不进代码、不进仓库**。开发阶段在 App 设置里填，存钥匙串，请求时放在 `x-goog-api-key` 请求头里（不放在 URL 上）。
- 正式版走后端代理（`server/`，Cloudflare Worker，见 [server/README.md](../server/README.md)）：App 把请求体原样 POST 到代理，带 `X-Majiang-Device`（钥匙串里的随机编号，按手机限次数）和 `X-Majiang-Invite`（邀请码）；代理加上 Key 转发给 Gemini，再把回答原样返回。用哪个模型由代理决定，只放行 Flash / Flash-Lite。代理拒绝时（比如今天次数用完）回一句中文，App 直接显示。
- **邀请码**：AI 认牌是邀请制。走代理时没填码就只用端侧认牌（`AppModel.needsInvite`），拍照页和首页有入口打开 `InviteView` 填 6 位码；码先 POST 到代理的 `/invite` 校验并绑这台手机，存钥匙串（`InviteKeychain`）。代理说码停用了或不对时，`InviteCheckedRecognizer` 把存着的码清掉并提示。码的格式和校验在 MajiangKit 的 `Recognition/InviteCode.swift`（有测试）。
- 开发版默认用自带的 Key 直连；想试代理，在设置里点「用我们的服务器」（这时也要填邀请码）。

### 分享和同步

- **发到微信群**：牌桌右上角和结算页把账本渲染成一张图（`Support/ShareCard.swift`，360 点宽、3 倍），走系统分享面板；结算页另有「复制文字版」。没有服务器，其他牌友在群里看图。
- **iCloud 同步**（`Support/CloudSync.swift`）：CloudKit 私有库 `iCloud.com.yangwy30.majiang`，自定义 zone `Majiang`，每场牌局一条 `Game` 记录（字段 `json` 是那场的 JSON），常用牌友和上次规则一条 `Meta`。打开、回到前台、保存后 2 秒同步：先收再传。该传哪些、两边都改过时留哪份由 MajiangKit 的 `SyncBook` 决定（有测试）。
- **导出 / 导入**：首页「备份与换手机」，导出全部牌局为 JSON 文件，导入时用 `GameArchive.merge` 只加不删。
- 真机要用开发者 Team 93RUQ2A6KX 签名，iCloud 容器要在开发者账号里存在（第一次真机构建时 Xcode 自动注册）。
- **记录类型要先发布到生产环境**：从 Xcode 装的开发版用 CloudKit 开发环境，第一次保存时会自动建 `Game`、`Meta`；TestFlight 和 App Store 版用生产环境，生产环境不会自动建，没发布时会报 “Cannot create new type Game in production schema”。表结构存在 `CloudKit/schema.ckdb`。改了记录类型或字段后：先确认开发环境里有（用开发版同步一次，或 `xcrun cktool import-schema --team-id 93RUQ2A6KX --container-id iCloud.com.yangwy30.majiang --environment development --file app/CloudKit/schema.ckdb`，要先 `xcrun cktool save-token`），再到 [CloudKit Console](https://icloud.developer.apple.com/) → 这个容器 → Deploy Schema Changes 发布到生产。

## 还没做 / 待验证

- iCloud 同步还没在真机上跑过（模拟器没登录 iCloud）。
- 端侧分不出吃碰杠，只有 Gemini 一路时副露要手动加。
- 拍照页的实时检查（牌数、光线、对焦）还没做，取景器里只有一句提示。
