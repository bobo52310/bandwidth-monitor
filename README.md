# 網路峰值監控器 (Bandwidth ECG)

一個現代化的 macOS 選單列應用程式，用於即時監控網路速度並追蹤峰值，幫助您用數據決策是否需要升級網路方案。

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.0+-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-compatible-green)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📸 螢幕截圖

> **注意**: 專案開發中，螢幕截圖即將新增。

<!--
TODO: 新增以下截圖
- 選單列顯示
- 詳細資訊彈出視窗
- 設定介面
- 圖表視圖（1小時/24小時）
-->

---

## ✨ 核心特色

### 🎯 一目了然的網路狀態
- **選單列即時顯示** - 上傳/下載速度一眼掌握
- **多時段圖表** - 1分鐘、5分鐘、15分鐘、30分鐘、1小時、24小時
- **互動式圖表** - 滑鼠懸停顯示精確時間和速度
- **統計卡片** - 即時、峰值、平均速度一次看清

### 📊 智能峰值追蹤
- **今日峰值** - 自動記錄當天最高速度
- **歷史峰值** - 追蹤有史以來的最高紀錄
- **時段峰值** - 1小時內峰值及發生時間
- **接近峰值計數** - 記錄每日接近合約速度的次數

### 🎨 彈性顯示選項
- **多種單位** - Mbps / MB/s 自由切換
- **顯示模式** - 上傳+下載 / 僅下載 / 僅上傳 / 簡潔模式
- **即時預覽** - 設定中即時查看效果
- **視覺警示** - 接近方案上限時橘色/紅色提醒

### ⚡ 輕量高效
- **CPU 使用率** < 1%
- **記憶體佔用** < 50MB
- **自動啟動** - 支援登入時自動開啟
- **選單列應用** - 預設僅顯示在選單列（不顯示在 Dock，可在設定中啟用）

---

## 🚀 快速開始

### 系統需求

- macOS 13.0 (Ventura) 或更新版本
- Xcode 15.0+ (僅開發時需要)
- Apple Silicon (M1/M2/M3/M4) 或 Intel 處理器

### 安裝方式

#### 方法一：從原始碼建置

```bash
# 1. 克隆專案
git clone https://github.com/bobo52310/bandwidth-monitor-claude.git
cd bandwidth-monitor-claude

# 2. 開啟專案
open BandwidthECG.xcworkspace

# 3. 在 Xcode 中按 Cmd+R 建置並執行
```

#### 方法二：使用建置腳本

```bash
# Debug 版本
./build.sh

# Release 版本
./build.sh Release
```

### 首次設定

1. **啟動應用程式**
   - 應用程式圖示會出現在選單列（右上角）
   - 預設不會顯示在 Dock 中（如需顯示，請在設定中開啟「顯示在 Dock」）

2. **設定網路方案**
   - 點擊選單列圖示 → 設定 (⚙️)
   - 輸入您的網路方案速度（例如：300/300 Mbps）
   - 建議勾選「登入時開啟」

3. **開始監控**
   - 設定完成後即自動開始監控
   - 選單列會顯示即時網路速度

---

## 📖 功能說明

### 選單列顯示格式

根據設定的顯示模式，選單列會顯示不同格式：

- **顯示兩者**: `↑ 15.2 ↓ 288.9 Mbps`
- **僅顯示下載**: `↓ 288.9 Mbps`
- **僅顯示上傳**: `↑ 15.2 Mbps`
- **簡潔模式**: `15.2/288.9 Mbps` (上傳/下載)

### 詳細資訊視窗

點擊選單列圖示後會顯示：

```
Bandwidth ECG                    ⚙️

▼ 下載 (Download)
   即時: 288.9 Mbps
   今日峰值: 295.4 Mbps (!! 高 !!)
   歷史總峰值: 298.1 Mbps
   1小時峰值: 290.2 Mbps (14:35)

▲ 上傳 (Upload)
   即時: 15.2 Mbps
   今日峰值: 250.7 Mbps
   歷史總峰值: 280.5 Mbps
   1小時峰值: 245.1 Mbps (14:22)

⚠️ 今日接近峰值
   次數: 3
   時間: 09:15 13:42 14:35

[重置峰值記錄]  [退出應用程式]
```

### 如何判斷是否需要升級網路

1. **觀察峰值趨勢**
   - 定期查看今日峰值和歷史峰值
   - 如果經常接近或達到方案上限，考慮升級

2. **識別瓶頸時段**
   - 注意何時出現橘色/紅色警示
   - 這些時段可能是您需要更高頻寬的時候

3. **數據分析建議**
   - 峰值經常超過方案的 **80-90%** → 建議升級
   - 偶爾達到峰值 → 正常現象，不必急於升級

---

## 🏗️ 專案架構

使用現代化的 **workspace + SPM package** 架構：

```
BandwidthECG/
├── BandwidthECG.xcworkspace/      # 在 Xcode 中開啟此檔案
├── BandwidthECG.xcodeproj/        # 應用程式殼層
├── BandwidthECG/                  # 應用程式目標（最小化）
│   ├── Assets.xcassets/                 # 應用程式資源
│   ├── BandwidthECGApp.swift      # 應用程式入口
│   └── BandwidthECG.entitlements  # 沙盒設定
├── BandwidthECGPackage/           # 主要開發區域
│   ├── Package.swift                    # 套件配置
│   ├── Sources/                         # 功能代碼
│   └── Tests/                           # 單元測試
└── BandwidthECGUITests/           # UI 測試
```

### 核心組件

- **NetworkMonitor** - 網路監控服務
- **PeakRecorder** - 峰值記錄管理
- **PeakApproachTracker** - 接近峰值計數器
- **NetworkMonitorViewModel** - 主要業務邏輯
- **StatusBarController** - 選單列控制器
- **UserPreferences** - 使用者偏好設定

---

## 🛠️ 開發指南

### 開發環境設定

```bash
git clone https://github.com/bobo52310/bandwidth-monitor-claude.git
cd bandwidth-monitor-claude
open BandwidthECG.xcworkspace
```

### 專案結構

- 主要功能代碼：`BandwidthECGPackage/Sources/BandwidthECGFeature/`
- 應用程式入口：`BandwidthECG/BandwidthECGApp.swift`
- 單元測試：`BandwidthECGPackage/Tests/`
- UI 測試：`BandwidthECGUITests/`

### 建置配置

建置設定透過 `Config/` 中的 **XCConfig 檔案** 管理：

- `Config/Shared.xcconfig` - 共用設定
- `Config/Debug.xcconfig` - Debug 設定
- `Config/Release.xcconfig` - Release 設定
- `Config/Tests.xcconfig` - 測試設定

### 執行測試

```bash
# 執行單元測試
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS'

# 執行 UI 測試
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS' \
                -only-testing:BandwidthECGUITests
```

---

## ❓ 常見問題

### 安裝問題

**Q: 建置失敗，出現 Swift 並發相關錯誤**
A: 確保使用 Xcode 15.0+ 並且 macOS 部署目標設為 13.0+

**Q: 無法開啟 `.xcworkspace` 檔案**
A: 請確保已安裝 Xcode，並使用 `open BandwidthECG.xcworkspace` 命令開啟

### 功能問題

**Q: 選單列不顯示網速**
A:
1. 檢查系統偏好設定 > 隱私權與安全性中允許應用程式存取網路
2. 重新啟動應用程式

**Q: 網速顯示為 0 或不準確**
A:
1. 確認電腦有網路連接
2. 嘗試下載檔案或瀏覽網頁以產生網路流量
3. 檢查是否使用 VPN（可能影響測量準確性）

**Q: 應用程式佔用太多資源**
A:
1. 正常情況下 CPU < 1%、記憶體 < 50MB
2. 如果異常，請重啟應用程式

### 設定問題

**Q: 如何讓應用程式顯示在 Dock 中？**
A:
1. 點擊選單列圖示 → 設定 (⚙️)
2. 在「系統與維護」區塊中勾選「顯示在 Dock」
3. Dock 圖示會立即出現，設定會自動儲存

**Q: 開機自啟動不工作**
A:
1. 確認在設定中勾選了「登入時開啟」
2. 檢查系統偏好設定 > 一般 > 登入項目

---

## 🤝 貢獻

歡迎提交 Issue 和 Pull Request！

### 回報問題

- 詳細描述問題和重現步驟
- 提供系統版本和 Xcode 版本
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

- 提交 [GitHub Issue](https://github.com/bobo52310/bandwidth-monitor-claude/issues)
- 發起 [GitHub Discussion](https://github.com/bobo52310/bandwidth-monitor-claude/discussions)

---

**⭐ 如果這個專案對您有幫助，請給我們一個 Star！**
