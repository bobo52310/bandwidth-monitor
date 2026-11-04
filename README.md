# 網路峰值監控器 (Bandwidth ECG)

一個現代化的 macOS 選單列應用程式，用於即時監控網路速度並追蹤峰值，幫助您用數據決策是否需要升級網路方案。

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2+-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-compatible-green)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 🎬 簡介動畫

![Bandwidth ECG · 28 秒看完](docs/promo/intro-zh-tw.gif)

> **28 秒看懂**：你付了 1 Gbps 的錢，實際上只用了 18% — Bandwidth ECG 在選單列安靜地量你 30 天，最後給你一個結論：升級、降級、還是維持現狀。

**[🎞️ English version](docs/promo/intro-en.gif)** · [下載 MP4 (zh-TW)](docs/promo/intro-zh-tw.mp4) · [Download MP4 (EN)](docs/promo/intro-en.mp4)

> 動畫原始檔（HyperFrames composition）：[`docs/design/promo-intro/`](docs/design/promo-intro/) · [`docs/design/promo-intro-zh-tw/`](docs/design/promo-intro-zh-tw/)

---

## ✨ 核心特色

### 🎯 一目了然的網路狀態
- **選單列即時顯示** - 下載/上傳速度一眼掌握
- **多時段圖表** - 1分鐘、5分鐘、15分鐘、30分鐘、1小時，另有 3、6、12、24 小時的延伸範圍
- **互動式圖表** - 滑鼠懸停顯示精確時間和速度
- **24 小時歷史** - 圖表以每 10 秒一點（平均值與最大值）保存 24 小時，重新啟動後仍在
- **統計卡片** - 即時速度、今日／歷史／1 小時峰值一次看清

### 📊 智能峰值追蹤
- **今日峰值** - 自動記錄當天最高速度
- **歷史峰值** - 追蹤有史以來的最高紀錄
- **時段峰值** - 1小時內峰值及發生時間
- **接近峰值計數** - 持續 30 秒達到方案速度 80% 以上算一次，記錄每日次數與時間
- **月度報告** - 以每日「持續 3 秒」峰值統計整月，並給出升級／維持／降級建議（見下方說明）
- **連線品質** - 延遲、抖動、斷線次數與總中斷時間

### 🎨 彈性顯示選項
- **多種單位** - Mbps / MB/s 自由切換
- **顯示模式** - 下載+上傳 / 僅下載 / 僅上傳 / 簡潔模式
- **即時預覽** - 設定中即時查看效果
- **視覺警示** - 選單列在達到通知閾值（預設 95%）時變橘色並加 ▲ 標記，達到方案速度時變紅色並加 ▲▲ 標記；標記不依賴顏色，開啟「提高對比」時顏色會關閉、標記保留
- **多語系** - 繁體中文、English、日本語、한국어，可在設定中切換（切換語言需重新啟動）

### ⚡ 輕量高效
- **原生輕量設計** - 以 macOS 原生 API 開發，常駐選單列
- **自動啟動** - 可在設定中開啟「登入時開啟」（預設關閉；使用系統「登入項目」，由 SMAppService 註冊）
- **選單列應用** - 預設僅顯示在選單列（不顯示在 Dock，可在設定中啟用）

---

## 🚀 快速開始

### 系統需求

- macOS 14.0 (Sonoma) 或更新版本
- Xcode 26 (僅開發時需要)
- Apple Silicon (M1/M2/M3/M4) 或 Intel 處理器

### 安裝方式

#### 方法一：從原始碼建置

```bash
# 1. 克隆專案
git clone https://github.com/bobo52310/bandwidth-monitor.git
cd bandwidth-monitor

# 2. 開啟專案
open BandwidthECG.xcworkspace

# 3. 在 Xcode 中按 Cmd+R 建置並執行
```

#### 方法二：使用建置腳本

```bash
# Debug 版本（只建置，不啟動）
./build.sh

# Debug 版本，建置後啟動
./build.sh debug --run

# Release 版本（Universal，只建置；不能搭配 --run）
./build.sh release
```

建置產物在 `.build/DerivedData/Build/Products/<Debug|Release>/BandwidthECG.app`。

> **Debug 與 Release 使用不同的 Bundle ID。** Debug 為 `com.bobo52310.BandwidthECG.debug`，Release 為 `com.bobo52310.BandwidthECG`。App 在沙盒內執行，兩者的資料各在自己的容器裡，所以開發時的 Debug 版不會讀寫正式版的資料。

### 首次設定

1. **啟動應用程式**
   - 第一次啟動會先顯示新手引導視窗（之後可在設定中重新顯示）
   - 應用程式圖示會出現在選單列（右上角）
   - 預設不會顯示在 Dock 中（如需顯示，請在設定中開啟「顯示在 Dock」）

2. **設定網路方案**
   - 點擊選單列圖示 → 設定 (⚙️)
   - 輸入您的網路方案速度（下載與上傳分開設定，例如：300/300 Mbps）
   - 建議勾選「登入時開啟」（App 需放在「應用程式」資料夾，必要時要到「系統設定 > 一般 > 登入項目」允許）

3. **開始監控**
   - 設定完成後即自動開始監控
   - 選單列會顯示即時網路速度

---

## 📖 功能說明

### 選單列顯示格式

根據設定的顯示模式，選單列會顯示不同格式：

- **顯示兩者**: `↓ 288.9 ↑ 15.2 Mbps`
- **僅顯示下載**: `↓ 288.9 Mbps`
- **僅顯示上傳**: `↑ 15.2 Mbps`
- **簡潔模式**: `↓288.9/↑15.2 Mbps`（下載在前）

下載與上傳都和各自的方案速度比較，取較高的那一個決定警示等級：

| 速度 | 選單列 |
|---|---|
| 低於通知閾值（預設方案的 95%，可選 90／95／98%） | 一般顯示 |
| 達到通知閾值 | 橘色，前面加 `▲`，例如 `▲ ↓ 288.9 ↑ 15.2 Mbps` |
| 達到方案速度 | 紅色，前面加 `▲▲` |

警示等級升高會立刻顯示，降回去則會保留 3 秒，避免速度在門檻附近時一秒閃一次。

### 操作方式

- **左鍵點選單列圖示** - 開啟或關閉詳細資訊視窗；已釘選時則切換釘選面板
- **右鍵（或 Control+點擊）選單列圖示** - 開啟選單：「開啟 Bandwidth ECG」、「結束」
- **再次開啟 App**（從 Finder 或 Spotlight） - 會顯示面板，選單列太滿而圖示被擠出時，這是叫出面板的方法；面板以釘選面板的形式出現
- **按 Esc 或點視窗外** - 關閉詳細資訊視窗（釘選面板不受影響）

### 詳細資訊視窗

點擊選單列圖示後會顯示（示意，實際數值與排版依你的設定與視窗大小而定）：

```
Bandwidth ECG                              [釘選] [設定]

  [1分鐘 5分鐘 15分鐘 30分鐘 1小時]  [更長時間範圍 ▾]
  （圖表：下載／上傳曲線，滑鼠移上去顯示時間與速度）

接近速率上限 (↓300 / ↑300 Mbps)                  3 次
  觸發時間：09:15  13:42  14:35

下載統計                        上傳統計
  今日峰值: 295.4 Mbps           今日峰值: 250.7 Mbps
  歷史總峰值: 298.1 Mbps  (x)    歷史總峰值: 280.5 Mbps  (x)
  1小時峰值: 290.2 Mbps          1小時峰值: 245.1 Mbps
            14:35                          14:22

網路狀態：穩定
連線品質：延遲 24 ms   抖動 3.1 ms
斷線記錄：今日斷線 0 次

[導出數據 ▾]  [查看月度報告]  [重置峰值記錄]  [退出應用程式]
```

- 峰值達到通知閾值時，數字會變橘色並加粗，旁邊顯示是多久以前發生的
- 歷史總峰值旁的 `(x)` 可以單獨清除該方向的歷史峰值（清除前會確認）
- 「釘選」會把視窗變成固定在畫面上的面板，位置會被記住，重新啟動後仍在
- 延遲監測關閉時，連線品質區塊會顯示「延遲監測已關閉」

### 月度報告

點「查看月度報告」可以看每個月的統計：下載／上傳峰值、平均速度、方案速度、方案使用率、接近上限次數、斷線次數、平均延遲與抖動、監控天數，並可匯出成 CSV（CSV 另含總中斷時間）。

- 報告由每天的完整紀錄推導，不是定時抓一張快照，所以傍晚或夜間的尖峰也算得進去
- 峰值是「持續 3 秒」的速度（連續 3 筆樣本中最低的那一筆），單秒尖峰不會把結果拉高
- 只計算這台 Mac 的流量，包含區網傳輸
- 當天累積監測至少 10 分鐘，才算一個監控天數
- 每天用當天的方案速度計算，月中改方案不會回頭改寫前面的天數
- 重置峰值記錄不會清掉月度報告的資料，但會一併清除接近上限計數與 24 小時圖表歷史

### 導出數據

「導出數據」選單有兩種格式，都是 CSV，並透過系統的儲存視窗讓你選位置：

- **導出最近 24 小時數據** - 最近 24 小時每 10 秒一筆，含平均與最大值
- **導出峰值記錄** - 今日、歷史與 1 小時峰值

### 資料與隱私

- **網路請求** - 延遲監測每 30 秒對 `www.apple.com` 送一次 HTTPS `HEAD` 請求來量測延遲，請求內容不含你的監控資料。可在「設定 > 網路設定 > 啟用延遲監測」關閉，關閉後不再送出。這是 App 唯一的對外網路請求，沒有帳號、沒有廣告。
- **資料位置** - App 在沙盒內執行，資料都在容器裡：`~/Library/Containers/com.bobo52310.BandwidthECG/Data/Library/Application Support/BandwidthECG/`
  - `daily-records.json` - 每日紀錄（月度報告的來源，保留 400 天）
  - `history-10s.json` - 圖表的 24 小時歷史
  - `error_log.txt` - 錯誤日誌，超過 1 MB 會換成 `error_log.1.txt`，只保留一份舊檔
  - 偏好設定在容器的 `Library/Preferences/com.bobo52310.BandwidthECG.plist`
- **匯出權限** - 匯出的 CSV 只會寫到你在儲存視窗中選的位置（沙盒的「使用者選取的檔案」權限）

### 如何判斷是否需要升級網路

月度報告會依下列規則給出建議，所有門檻集中在 `ReportRules.swift`：

| 建議 | 條件 |
|---|---|
| 資料不足 | 監控天數少於 7 天 |
| 建議升級方案 | 至少 3 天的持續峰值超過方案的 90%（下載或上傳任一方向） |
| 可考慮降級方案 | 監控至少 14 天、沒有任何一天超過 90%，且下載與上傳每日持續峰值的 P95 都低於方案的 30% |
| 目前方案合適 | 其餘情況 |

自己觀察時也可以：

1. **看峰值趨勢** - 今日峰值和歷史峰值經常貼近方案上限時，考慮升級
2. **找出瓶頸時段** - 選單列出現橘色／紅色警示、或「接近速率上限」次數增加的時段，就是頻寬吃緊的時候
3. **偶爾達到峰值是正常現象** - 不必急著升級；看的是「持續」而不是單次尖峰

---

## 🏗️ 專案架構

使用現代化的 **workspace + SPM package** 架構：

```
BandwidthECG/
├── BandwidthECG.xcworkspace/      # 在 Xcode 中開啟此檔案
├── BandwidthECG.xcodeproj/        # 應用程式殼層
├── BandwidthECG/                  # 應用程式目標（最小化）
│   ├── Assets.xcassets/                 # 應用程式資源（含 App 圖示）
│   ├── Localizable.xcstrings            # 在地化字串（繁中、英、日、韓）
│   ├── BandwidthECG.xctestplan          # 測試計畫（不會打包進 App）
│   └── BandwidthECGApp.swift      # 應用程式入口
├── Config/                        # XCConfig 建置設定與 entitlements
│   ├── Shared.xcconfig / Debug.xcconfig / Release.xcconfig / Tests.xcconfig
│   └── BandwidthECG.entitlements  # 沙盒設定
├── BandwidthECGPackage/           # 主要開發區域
│   ├── Package.swift                    # 套件配置
│   ├── Sources/BandwidthECGFeature/     # 功能代碼
│   └── Tests/                           # 單元測試（Swift Testing）
├── BandwidthECGUITests/           # UI 測試（目前只有範例，不在預設測試計畫內）
├── build.sh                       # 建置腳本
├── website/                       # 官網（Astro）
└── docs/                          # 文件與宣傳動畫
```

### 核心組件

- **NetworkMonitor** - 每秒取樣網路流量
- **PeakRecorder** - 今日／歷史／1 小時峰值
- **PeakApproachTracker** - 接近峰值事件計數
- **NetworkHistoryRecorder** - 圖表歷史（每 10 秒的平均與最大值，保存 24 小時）
- **DailyRecordStore** - 每日紀錄，月度報告的資料來源
- **MonthlyReportService** - 由每日紀錄推導月度報告與方案建議
- **LatencyMonitor** / **DisconnectTracker** / **NetworkAnomalyDetector** - 延遲、斷線與異常偵測
- **NotificationService** - 接近方案上限的通知
- **DataExportService** - CSV 匯出
- **NetworkMonitorViewModel** - 主要業務邏輯
- **StatusBarController** - 選單列控制器
- **UserPreferences** - 使用者偏好設定

---

## 🛠️ 開發指南

### 開發環境設定

```bash
git clone https://github.com/bobo52310/bandwidth-monitor.git
cd bandwidth-monitor
open BandwidthECG.xcworkspace
```

### 專案結構

- 主要功能代碼：`BandwidthECGPackage/Sources/BandwidthECGFeature/`
- 應用程式入口：`BandwidthECG/BandwidthECGApp.swift`
- 單元測試：`BandwidthECGPackage/Tests/`
- UI 測試：`BandwidthECGUITests/`

### 建置配置

建置設定透過 `Config/` 中的 **XCConfig 檔案** 管理：

- `Config/Shared.xcconfig` - 共用設定（Bundle ID、部署目標 macOS 14.0、Info.plist 鍵：選單列 App 不顯示 Dock 圖示、App 分類、版權）
- `Config/Debug.xcconfig` - Debug 設定（Bundle ID 加上 `.debug`）
- `Config/Release.xcconfig` - Release 設定
- `Config/Tests.xcconfig` - 測試設定
- `Config/BandwidthECG.entitlements` - 沙盒、對外網路連線、使用者選取檔案的讀寫

專案的 Swift 語言模式為 Swift 6。

### 執行測試

```bash
# 只跑套件的單元測試（不編譯 App，最快）
swift test --package-path BandwidthECGPackage

# 透過 Xcode 的 scheme 跑（預設測試計畫只含單元測試）
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS,arch=arm64'
```

`BandwidthECGUITests` 目前只有一個範例測試，已從預設測試計畫移除，所以上面的指令不會啟動 App。

### 手動測試時不要動到正式資料

App 在沙盒內執行，正式版的偏好設定與資料都在 `~/Library/Containers/com.bobo52310.BandwidthECG`。`CFFIXED_USER_HOME` 之類的環境變數**無法**隔離它。

- 用 `./build.sh debug --run` 啟動 Debug 版：它的 Bundle ID 是 `com.bobo52310.BandwidthECG.debug`，容器與正式版分開。
- **不要啟動 Release 版**，它用的是正式 Bundle ID。需要手動檢查 Release 行為時，複製一份 `.app`，把 `Info.plist` 的 `CFBundleIdentifier` 改成臨時 ID，用 `codesign --force --sign -` 重新簽章，只啟動這份複本，並且不要從專案資料夾內啟動。

---

## ❓ 常見問題

### 安裝問題

**Q: 建置失敗，出現 Swift 並發相關錯誤**
A: 確保使用 Xcode 26 或更新版本，並且 macOS 部署目標為 14.0+（專案使用 Swift 6 語言模式）

**Q: 無法開啟 `.xcworkspace` 檔案**
A: 請確保已安裝 Xcode，並使用 `open BandwidthECG.xcworkspace` 命令開啟

### 功能問題

**Q: 選單列看不到圖示或網速**
A:
1. 選單列太滿時，圖示可能被擠出螢幕。再次開啟 Bandwidth ECG（從 Finder 或 Spotlight）會顯示面板
2. 在設定中改用「簡潔模式」或「僅顯示下載／上傳」，縮短選單列的寬度
3. 重新啟動應用程式

**Q: 網速顯示為 0 或不準確**
A:
1. 確認電腦有網路連接
2. 嘗試下載檔案或瀏覽網頁以產生網路流量
3. 檢查是否使用 VPN（可能影響測量準確性）

**Q: 應用程式佔用太多資源**
A:
1. 視窗關閉、只顯示選單列時，CPU 用量應該很低；開著視窗看圖表時用量較高，關閉後會回落
2. 如果異常，請重啟應用程式

### 設定問題

**Q: 如何讓應用程式顯示在 Dock 中？**
A:
1. 點擊選單列圖示 → 設定 (⚙️)
2. 在「系統與維護」區塊中勾選「顯示在 Dock」
3. Dock 圖示會立即出現，設定會自動儲存

**Q: 登入時開啟不工作**
A:
1. 把 App 移到「應用程式」資料夾（`/Applications` 或 `~/Applications`）後再勾選「登入時開啟」。從磁碟映像檔或「下載」資料夾執行時，登入項目重啟後會失效，所以設定中的開關會停用並提示先移動 App
2. 如果設定中出現需要允許的提示，到「系統設定 > 一般 > 登入項目」允許 Bandwidth ECG
3. 開關反映的是系統目前的登入項目狀態；若在系統設定中手動移除，下次開啟設定時會顯示為關閉

**Q: 月度報告一直顯示「資料不足」**
A: 需要至少 7 個監控天數才會給建議，而且當天要累積監測至少 10 分鐘才算一天

**Q: 不想讓 App 對外送出任何請求**
A: 到「設定 > 網路設定」關閉「啟用延遲監測」。延遲監測是唯一會對外連線的功能（每 30 秒對 apple.com 送一次 HEAD 請求）

---

## 🤝 貢獻

歡迎提交 Issue 和 Pull Request！

### 回報問題

- 詳細描述問題和重現步驟
- 提供 macOS 版本和 Xcode 版本
- 如可能，請附上錯誤截圖

### 提交功能建議

- 說明功能的用途和好處
- 考慮是否符合應用程式的設計理念
- 提供 UI 設計稿（如果相關）

### 開發流程

1. Fork 專案
2. 創建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

---

## 📄 授權

本專案使用 MIT 授權條款。詳見 [LICENSE](LICENSE) 檔案。

---

## 🙏 致謝

- 使用 [SwiftUI Charts](https://developer.apple.com/documentation/charts) 製作圖表
- 專案架構受 [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP) 啟發

---

## 📬 聯絡

如有問題或建議，請透過以下方式聯絡：

- 提交 [GitHub Issue](https://github.com/bobo52310/bandwidth-monitor/issues)
- 發起 [GitHub Discussion](https://github.com/bobo52310/bandwidth-monitor/discussions)

---

**⭐ 如果這個專案對您有幫助，請給我們一個 Star！**
