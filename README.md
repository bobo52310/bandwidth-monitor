# 網路峰值監控器 (Network Peak Monitor)

一個現代化的 macOS 選單列應用程式，用於監控網路速度峰值，幫助您決定是否需要升級網路方案。

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-compatible-green)

## 🚀 主要功能

- **即時網速顯示** - 在選單列顯示當前上傳/下載速度
- **峰值記錄追蹤** - 自動記錄今日峰值和歷史最高峰值
- **1小時峰值追蹤** - 顯示最近1小時內的最高速度和發生時間
- **接近峰值計數器** - 記錄每日接近合約速度的次數和時間點
- **智能警示提醒** - 當速度接近方案上限時顯示警示
- **選單列顯示自訂** - 可選擇顯示上傳、下載或兩者，支援簡潔模式
- **一鍵退出功能** - 從選單列直接退出應用程式
- **方案設定管理** - 輕鬆設定您的網路方案速度
- **數據持久化** - 自動保存歷史峰值記錄
- **開機自啟動** - 可設定登入時自動啟動
- **輕量級設計** - 極低的系統資源佔用

## 📋 系統需求

- macOS 12.0 (Monterey) 或更新版本
- Xcode 15.0+ (僅開發時需要)
- Apple Silicon (M1/M2/M3) 或 Intel 處理器

## 🛠️ 安裝方式

### 方法一：從原始碼建置 (推薦)

1. **克隆專案**
   ```bash
   git clone https://github.com/bobo52310/bandwidth-monitor-claude.git
   cd bandwidth-monitor-claude
   ```

2. **開啟 Xcode**
   ```bash
   open NetworkPeakMonitor.xcworkspace
   ```

3. **建置並執行**
   - 在 Xcode 中選擇 `NetworkPeakMonitor` scheme
   - 按下 `Cmd+R` 或點擊執行按鈕
   - 或使用命令列：
   ```bash
   # 建置
   xcodebuild -workspace NetworkPeakMonitor.xcworkspace -scheme NetworkPeakMonitor -configuration Debug build

   # 執行
   open ~/Library/Developer/Xcode/DerivedData/NetworkPeakMonitor-*/Build/Products/Debug/NetworkPeakMonitor.app

   # 或使用便利腳本 (建置並執行)
   ./build.sh        # Debug 版本
   ./build.sh Release # Release 版本
   ```

### 方法二：使用 Claude Code Xcode Build Tools

如果您有安裝 XcodeBuildMCP：
```bash
# 建置
mcp_xcode_build build_macos --workspace NetworkPeakMonitor.xcworkspace --scheme NetworkPeakMonitor

# 取得 app 路徑並執行
mcp_xcode_build get_mac_app_path --workspace NetworkPeakMonitor.xcworkspace --scheme NetworkPeakMonitor
mcp_xcode_build launch_mac_app --appPath [取得的路徑]
```

### 方法三：CLI 快速建置

專案包含便利腳本 `build.sh`，讓您輕鬆從命令列建置和執行：

```bash
# 建置 Debug 版本並自動執行
./build.sh

# 建置 Release 版本並自動執行
./build.sh Release

# 手動命令 (如果您喜歡完整控制)
# Debug 版本
xcodebuild -workspace NetworkPeakMonitor.xcworkspace \
           -scheme NetworkPeakMonitor \
           -configuration Debug \
           build

# Release 版本
xcodebuild -workspace NetworkPeakMonitor.xcworkspace \
           -scheme NetworkPeakMonitor \
           -configuration Release \
           build

# 清理建置快取
xcodebuild -workspace NetworkPeakMonitor.xcworkspace \
           -scheme NetworkPeakMonitor \
           clean

# 執行建置好的應用程式
open ~/Library/Developer/Xcode/DerivedData/NetworkPeakMonitor-*/Build/Products/Debug/NetworkPeakMonitor.app
```

**建議工作流程：**
1. 使用 `./build.sh` 進行日常開發測試
2. 使用 `./build.sh Release` 建置發行版本
3. 出現問題時使用 `clean` 清理後重新建置

## ✅ 功能驗證清單

安裝完成後，請依照以下步驟驗證所有功能是否正常運作：

### 基本功能驗證

1. **選單列顯示**
   - [ ] 選單列出現 `↑ X.X ↓ X.X Mbps` 格式的網速顯示
   - [ ] 數值每秒更新一次
   - [ ] 無網路活動時顯示接近 0 的數值

2. **詳細資訊視窗**
   - [ ] 點擊選單列圖示彈出詳細視窗
   - [ ] 顯示下載和上傳的即時速度
   - [ ] 顯示今日峰值和歷史總峰值
   - [ ] 顯示1小時峰值和發生時間
   - [ ] 顯示今日接近峰值的次數和時間點
   - [ ] 視窗包含設定按鈕、重置按鈕和退出按鈕

3. **峰值記錄功能**
   - [ ] 下載大檔案時觀察峰值是否正確記錄
   - [ ] 重啟應用程式後峰值資料是否保存
   - [ ] 隔天使用時今日峰值是否重置

### 設定功能驗證

4. **網路方案設定**
   - [ ] 能夠設定下載速度上限 (如 300 Mbps)
   - [ ] 能夠設定上傳速度上限 (如 300 Mbps)
   - [ ] 設定值在重啟後是否保存

5. **顯示設定**
   - [ ] 可在 Mbps 和 MB/s 之間切換顯示單位
   - [ ] 可選擇選單列顯示模式（顯示兩者/僅下載/僅上傳/簡潔模式）
   - [ ] 設定中有即時預覽功能
   - [ ] 切換後選單列和詳細視窗都正確顯示

6. **峰值警示功能**
   - [ ] 當峰值超過設定方案的 90% 時顯示橘色/紅色
   - [ ] 警示文字 "(!! 高 !!)" 正確顯示

### 進階功能驗證

7. **重置功能**
   - [ ] 點擊重置按鈕清除所有峰值記錄
   - [ ] 重置後峰值數值歸零
   - [ ] 重置後接近峰值計數器歸零

8. **退出功能**
   - [ ] 點擊退出按鈕可完全關閉應用程式
   - [ ] 退出後選單列圖示消失

9. **開機自啟動**
   - [ ] 設定中可開啟/關閉 "登入時開啟"
   - [ ] 重新登入系統後應用程式自動啟動

### 性能驗證

10. **系統資源使用**
    - [ ] 使用活動監視器檢查 CPU 使用率 < 1%
    - [ ] 記憶體使用量 < 50MB
    - [ ] 無異常崩潰或錯誤

## 📖 使用指南

### 首次設定

1. **啟動應用程式**
   - 應用程式圖示會出現在右上角選單列
   - 初始顯示為 `↑ 0.0 ↓ 0.0 Mbps`

2. **設定網路方案**
   - 點擊選單列圖示
   - 點擊設定按鈕 (⚙️)
   - 輸入您的網路方案速度 (如 300/300 Mbps)
   - 勾選 "登入時開啟" (建議)

3. **開始監控**
   - 設定完成後，應用程式會自動開始監控
   - 選單列會顯示即時網路速度

### 如何判斷是否需要升級網路

1. **觀察峰值趨勢**
   - 定期查看今日峰值和歷史峰值
   - 如果經常接近或達到方案上限，考慮升級

2. **識別瓶頸時段**
   - 注意何時出現橘色/紅色警示
   - 這些時段可能是您需要更高頻寬的時候

3. **數據分析建議**
   - 如果峰值經常超過方案的 80-90%，建議升級
   - 偶爾達到峰值是正常的，不必急於升級

### 介面說明

#### 選單列顯示格式

根據設定的顯示模式，選單列會顯示不同格式：

- **顯示兩者**: `↑ 15.2 ↓ 288.9 Mbps`
- **僅顯示下載**: `↓ 288.9 Mbps`
- **僅顯示上傳**: `↑ 15.2 Mbps`
- **簡潔模式**: `15.2/288.9 Mbps` (上傳/下載)

#### 詳細視窗內容
```
Network Peak Monitor                    ⚙️

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

## 🏗️ 專案架構

使用現代化的 **workspace + SPM package** 架構，實現應用程式殼層與功能代碼的清晰分離。

```
NetworkPeakMonitor/
├── NetworkPeakMonitor.xcworkspace/              # 在 Xcode 中開啟此檔案
├── NetworkPeakMonitor.xcodeproj/                # 應用程式殼層專案
├── NetworkPeakMonitor/                          # 應用程式目標 (最小化)
│   ├── Assets.xcassets/                # 應用程式層級資源
│   ├── NetworkPeakMonitorApp.swift              # 應用程式入口點
│   └── NetworkPeakMonitor.entitlements          # 沙盒設定
├── NetworkPeakMonitorPackage/                   # 🚀 主要開發區域
│   ├── Package.swift                   # 套件配置
│   ├── Sources/NetworkPeakMonitorFeature/       # 功能代碼
│   └── Tests/NetworkPeakMonitorFeatureTests/    # 單元測試
└── NetworkPeakMonitorUITests/                   # UI 自動化測試
```

### 核心組件

- **NetworkMonitor** - 網路監控服務，使用系統 API 獲取流量數據
- **PeakRecorder** - 峰值記錄管理，負責追蹤和持久化峰值數據 (含1小時峰值)
- **PeakApproachTracker** - 接近峰值計數器，記錄每日接近合約速度的次數和時間
- **NetworkMonitorViewModel** - 主要業務邏輯，協調各個服務
- **StatusBarController** - 選單列控制器，管理 UI 顯示
- **UserPreferences** - 使用者偏好設定管理

## ❓ 常見問題與疑難排解

### 安裝問題

**Q: Xcode 建置失敗，出現 "Traditional headermap style is no longer supported" 警告**
A: 這是 Xcode 的正常警告，不影響應用程式運行。可以忽略此警告。

**Q: 建置時出現 Swift 並發相關錯誤**
A: 確保使用 Xcode 15.0 或更新版本，並且 macOS 部署目標設為 12.0+。

**Q: 無法開啟 `.xcworkspace` 檔案**
A: 請確保已安裝 Xcode，並使用 `open NetworkPeakMonitor.xcworkspace` 命令開啟。

### 功能問題

**Q: 選單列不顯示網速**
A:
1. 檢查應用程式是否有網路權限
2. 確認系統偏好設定 > 隱私權與安全性中允許應用程式存取網路
3. 重新啟動應用程式

**Q: 網速顯示為 0 或不準確**
A:
1. 確認電腦有網路連接
2. 嘗試下載檔案或瀏覽網頁以產生網路流量
3. 檢查是否使用 VPN (可能影響測量準確性)

**Q: 峰值數據丟失**
A:
峰值數據儲存在 `UserDefaults` 中，通常不會丟失。如果發生：
1. 檢查是否意外清除了應用程式數據
2. 確認沒有多個版本的應用程式同時運行

**Q: 應用程式佔用太多 CPU 或記憶體**
A:
1. 正常情況下 CPU 使用率應 < 1%，記憶體 < 50MB
2. 如果異常，請重啟應用程式
3. 檢查是否有其他網路監控工具衝突

### 設定問題

**Q: 開機自啟動不工作**
A:
1. 確認在設定中勾選了 "登入時開啟"
2. 檢查系統偏好設定 > 使用者與群組 > 登入項目
3. 手動添加應用程式到登入項目

**Q: 設定無法保存**
A:
1. 確認應用程式有寫入權限
2. 重新啟動應用程式檢查設定是否保存
3. 檢查 `~/Library/Preferences/` 中的設定檔案

## 🚀 開發相關

### 開發環境設定

如果您想參與開發或自定義功能：

1. **克隆並設定專案**
   ```bash
   git clone https://github.com/bobo52310/bandwidth-monitor-claude.git
   cd bandwidth-monitor-claude
   open NetworkPeakMonitor.xcworkspace
   ```

2. **程式碼結構**
   - 主要功能代碼在 `NetworkPeakMonitorPackage/Sources/NetworkPeakMonitorFeature/`
   - 應用程式入口在 `NetworkPeakMonitor/NetworkPeakMonitorApp.swift`

### 建置配置

- **除錯版本**: 適合開發和測試
- **發行版本**: 經過最佳化，適合日常使用
- **測試**: 包含單元測試和 UI 測試

### 新增功能

如需新增功能，請參考現有的 PR 模式：
1. Fork 專案
2. 創建功能分支
3. 實作並測試
4. 提交 Pull Request

## 📄 授權

本專案使用 MIT 授權條款。詳見 [LICENSE](LICENSE) 檔案。

## 🤝 貢獻

歡迎提交 Issue 和 Pull Request！

### 回報問題
- 詳細描述問題和重現步驟
- 提供系統版本和 Xcode 版本
- 如可能，請附上錯誤截圖

### 提交功能建議
- 說明功能的用途和好處
- 考慮是否符合應用程式的設計理念
- 提供 UI 設計稿 (如果相關)

---

## 🔧 技術詳細

### 架構重點

#### Workspace + SPM 結構
- **應用程式殼層**: `NetworkPeakMonitor/` 包含最少的應用程式生命週期代碼
- **功能代碼**: `NetworkPeakMonitorPackage/Sources/NetworkPeakMonitorFeature/` 是主要開發區域
- **分離設計**: 業務邏輯存在於 SPM 套件中，應用程式目標僅導入和顯示

#### Buildable Folders (Xcode 16)
- 新增到檔案系統的檔案會自動出現在 Xcode 中
- 無需手動將檔案添加到專案目標
- 減少團隊開發中的專案檔案衝突

#### 應用程式沙盒
應用程式預設已啟用沙盒，具有基本檔案存取權限。可修改 `Config/NetworkPeakMonitor.entitlements` 來新增所需功能。

### 開發要點

#### 代碼組織
大部分開發工作在 `NetworkPeakMonitorPackage/Sources/NetworkPeakMonitorFeature/` 中進行。

#### 公開 API 要求
向應用程式目標公開的類型需要 `public` 存取權限：
```swift
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        // 您的視圖代碼
    }
}
```

#### 新增依賴項
編輯 `NetworkPeakMonitorPackage/Package.swift` 來新增 SPM 依賴項：
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "NetworkPeakMonitorFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### 測試結構

- **單元測試**: `NetworkPeakMonitorPackage/Tests/NetworkPeakMonitorFeatureTests/` (Swift Testing 框架)
- **UI 測試**: `NetworkPeakMonitorUITests/` (XCUITest 框架)
- **測試計劃**: `NetworkPeakMonitor.xctestplan` 協調所有測試

### 配置

#### XCConfig 建置設定
建置設定透過 `Config/` 中的 **XCConfig 檔案** 管理：
- `Config/Shared.xcconfig` - 共用設定 (bundle ID、版本、部署目標)
- `Config/Debug.xcconfig` - 除錯特定設定
- `Config/Release.xcconfig` - 發行特定設定
- `Config/Tests.xcconfig` - 測試特定設定

#### 應用程式沙盒與權限
應用程式預設已啟用沙盒。編輯 `Config/NetworkPeakMonitor.entitlements` 來新增功能：
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<!-- 根據需要新增其他權限 -->
```

### macOS 特定功能

#### 視窗管理
新增多個視窗和設定面板：
```swift
@main
struct NetworkPeakMonitorApp: App {
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
```

#### 資源管理
- **應用程式層級資源**: `NetworkPeakMonitor/Assets.xcassets/` (應用程式圖示及顏色)
- **功能資源**: 如需要可在 SPM 套件中新增 `Resources/` 資料夾

#### SPM 套件資源
在功能套件中包含資源：
```swift
.target(
    name: "NetworkPeakMonitorFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

---

### 使用 XcodeBuildMCP 生成
此專案使用 [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP) 建立架構，為 AI 輔助的 macOS 開發工作流程提供工具支援。