# Bandwidth ECG 全面改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan stage-by-stage. Steps use checkbox (`- [ ]`) syntax for tracking. **本計畫不含任何 git commit 步驟**（使用者未要求 commit），檢查點一律用 patch 快照。

**Goal:** 修正四份審查報告的 125 項 finding，讓月報可信、app 在 sandbox 正式設定下功能完整、資源用量真正達標、官網宣稱全部成立。

**Architecture:** 維持 Xcode workspace + SPM package，不重寫架構。先建安全啟動與注入 seam，再把「定時快照」改成「每筆樣本累積的日紀錄」，月報由日紀錄即時推導。歷史改存 Application Support 檔案。網站以 zh-Hant locale 為單一文案來源，其餘語系比照重建，並用 key 檢查防止再漂移。

**Tech Stack:** Swift 6.2（package 為 Swift 6 模式）、Xcode 26.0.1、SwiftUI、Swift Charts、Swift Testing、macOS 14 deployment target；Astro 7.4.4、Tailwind 4、Node 22.23.4。

**Spec:** 下方「定案決策」＋四份審查報告。施工時要查失敗情境與實驗數據就讀報告；報告與本計畫衝突時以本計畫為準（裁決見 R1–R16）。

- `$S/audit/core.md`：CORE-01..32、CORE-02 完整修法、Seams 表。實驗 `$S/audit/core/h1/main.swift` 可改寫成測試。
- `$S/audit/ui.md`：UI-P1-1..6、UI-P2-1..17、UI-P3-1..17、設定接線表、附錄 A。截圖在 `$S/audit/ui/`。
- `$S/audit/perf.md`：PERF-01..15、PERF-16.1..9。工具在 `$S/audit/perf/`。
- `$S/audit/web.md`：WEB-P0-1..6、WEB-P1-1..5、WEB-P2-1..11、WEB-P3-1..7，含 4 語系建議文案。

本計畫把報告內 ID 一律加前綴：`UI-P1-1`（ui.md 的 P1-1）、`WEB-P0-1`（web.md 的 P0-1）、`PERF-16.3`（perf.md §11 第 3 項）。

`$S` 在 `/private/tmp` 下。若 `$S/audit` 不存在，停工回報，不要憑記憶施工。

## 定案決策（不可再議）

- **D1 峰值：** 月報用「持續 3 秒」峰值；即時顯示與 PeakRecorder 的今日／歷史峰值維持 1 秒。
- **D2 方案建議（常數集中一處）：** `daysMonitored < 7` → insufficientData；≥3 個不同日子出現持續飽和（下載或上傳任一方向，持續峰值 >90%）→ considerUpgrade；下載與上傳的每日持續峰值 P95 都 <30%、監測 ≥14 天、且沒有飽和日 → considerDowngrade；其餘 planFits。`PeakApproachTracker` 改成事件計數，不是節流計數。`L10n` 的四個建議字串維持不變（宣傳影片用到「可考慮降級方案」）。
- **D3 LAN：** 只在月報加註「只計算這台 Mac，包含區網傳輸」。不做過濾。
- **D4：** 當日累積監測 ≥10 分鐘才計入 `daysMonitored`。
- **D5 污染峰值：** 提供清除單一歷史峰值的入口；另加防呆阻止新的假尖峰。
- **D6 發行：** 維持 sandbox；修正 entitlements 讓匯出可用；不動簽章與 Team；不加 CI。
- **D7：** 重啟後保留 24 小時歷史（先修降採樣與持久化）。
- **D8：** 最低系統版本一律 macOS 14（修文件與網站，不補 13 fallback）。
- **D9：** 移除「優化記憶體」按鈕。
- **D10：** popover 關閉要釋放內容；需要跨開關保留的選取狀態移到 view model 或 preferences。
- **D11 延遲監測：** 預設開啟、設定可關、官網 FAQ 明寫每 30 秒對 apple.com 送 HEAD。
- **D12 官網定價與散佈：** 中立文案。「價格於發行時公布」＋「無廣告、無帳號」；不提 DMG、GitHub、Mac App Store、下載、免費；CTA 不暗示可下載。
- **D13 效能數字：** 程式修完後重新量測（footprint 當指標），達標才保留「閒置時」條件式宣稱並註明量測條件，否則移除。
- **D14：** ja/ko 定位對齊 zh 的「極簡選單列工具」，不用 enterprise 類字眼；en 與 zh 語彙統一。
- **D15：** 字型不動（品牌取捨，列入「不做」）。
- **D16：** Hero 與 ChartDemo 加「示意數據」標籤；資訊句進 i18n，風格標籤維持英文。
- **D17：** x-default 維持 zh-Hant。
- **D18：** 實作選單列橘／紅警示色（README 與官網都宣稱了），需通過無障礙判斷（不能只靠顏色傳達時要有替代）。
- **D19：** 其他標「需使用者決定」的 UI 小項：採報告建議；無建議者選最保守、最少變動的做法，寫明理由。
- **不做：** 新功能（CSV/PDF 新格式、iOS widget、網路品質評分）、品牌視覺改版、重寫架構、把 Views 大拆檔（除非修 bug 必要）。

## Global Constraints

每個 stage 都適用，違反即驗收失敗。

- **安全啟動：** `CFFIXED_USER_HOME` 不能隔離資料；sandbox 版會讀寫真實容器 `~/Library/Containers/com.bobo52310.BandwidthECG`；UI test target 也會啟動真實 bundle。Stage 1 驗收通過之前，任何人不得啟動 app 或跑 UI 測試。之後的手動實測一律用 `qa-copy.sh` 產生的副本（改 `CFBundleIdentifier`、ad-hoc 重簽），cwd 不可在 repo 內。Release 建置只能 build，不能啟動。
- 真實 bundle ID `com.bobo52310.BandwidthECG` 的 Release 設定與資料位置不可改。
- Toolchain：Xcode 26.0.1、Swift 6.2、macOS 14 deployment target。package 用 Swift 6 模式，不得用 `@preconcurrency` 或 `nonisolated(unsafe)` 掩蓋新錯誤（測試 helper 的 `@unchecked Sendable` 例外）。
- 預設 shell 是 zsh，無 `PIPESTATUS`。要看 exit code 就先把輸出寫進 log 再 `tail`。
- 網站：Node 用 `$S/node-22.23.4/bin`。`website/` 已升到 Astro 7，`astro.config.mjs` 的 `compressHTML: true` 與 `cssTarget` 要保留。
- **不改：** `TODO.md`、`docs/design/`、`docs/promo/`、`website/package.json` 版本、`BUSINESS_STRATEGY.md`、`website/astro.config.mjs`、`website/package-lock.json`。工作樹這些檔案已有使用者未 commit 的修改，不得 revert。
- **不 commit、不 push、不部署。** 不用 `git add -A`、`git stash`、`git checkout --`、`git reset`。
- CORE-01 與 CORE-02 必須同 stage 完成（Stage 4）。
- CORE-16 不可改用 `if_data64`（報告實測同樣回繞）。
- `Calendar.isDateInToday` 繞過注入時鐘，一律改 `isDate(_:inSameDayAs:)`。
- 既有資料相容：UserDefaults／持久化格式若變動，要有遷移或容錯，不能讓舊資料 crash 或靜默消失。污染資料與 decode 失敗要有明確處理（隔離備份＋log），不得 `try?` 吞掉後覆寫。
- Bug 修復走 TDD：先寫測試、跑一次看它失敗（或 crash）、再實作。不得停用或跳過失敗的測試。
- 範圍圍欄：每個 stage 只動白名單內的檔案。發現白名單外必須動的檔案，停下回報。
- 新增使用者可見字串一律加進 `Utilities/L10n.swift`（`defaultValue` 用繁中），翻譯統一在 Stage 11。

## 環境與共用指令

```zsh
export R=/path/to/bandwidth-monitor
export S=$TMPDIR/scratchpad
mkdir -p $S/logs $S/checkpoints $S/build
```

| 代號 | 指令 | 通過條件 |
|---|---|---|
| `TEST` | `swift test --package-path $R/BandwidthECGPackage --scratch-path $S/build/swift > $S/logs/test.log 2>&1; echo exit=$?; tail -5 $S/logs/test.log` | `exit=0`，log 有 `Test run with N tests ... passed` |
| `TEST <Suite>` | 同上，加 `--filter <Suite>` | 同上 |
| `BUILD` | `xcodebuild -workspace $R/BandwidthECG.xcworkspace -scheme BandwidthECG -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $S/build/dd build > $S/logs/build.log 2>&1; echo exit=$?; tail -2 $S/logs/build.log; grep -cE '\.swift:[0-9]+:[0-9]+: warning:' $S/logs/build.log` | `exit=0`、`BUILD SUCCEEDED`、警告數 `0` |
| `RELEASE` | 同 BUILD，改 `-configuration Release`、`-destination 'generic/platform=macOS'`、log 寫 `release.log` | 同上。**只 build，不啟動** |
| `CHECKPOINT N` | `git -C $R add -N <本 stage 新增的檔案逐一列出>; git -C $R diff > $S/checkpoints/stage-N.patch; wc -l $S/checkpoints/stage-N.patch` | patch 非空。`git add -N` 只登記路徑、不算 commit；只列本 stage 新檔，絕不碰 `docs/design/promo-intro-v2-zh-tw/`。遇 `index.lock` 等 5 秒重試 |
| `WEB` | `cd $R/website && PATH=$S/node-22.23.4/bin:$PATH npm run build > $S/logs/web.log 2>&1; echo exit=$?; tail -3 $S/logs/web.log` | `exit=0` |
| `QA` | `$S/tools/qa-copy.sh $S/build/dd/Build/Products/Debug/BandwidthECG.app`，啟動方式見 Stage 1 | 見 Stage 1 |

`swift test` 不編 app target：動到 `BandwidthECG/` 底下或 public API 時一定要再跑 `BUILD`。`swift test` 不會啟動 app，隨時可跑。

CHECKPOINT 是累積快照，含使用者既有修改，不是增量 patch。

## Review Focus

報告與決策沒寫到、但最可能傷到使用者的五種情況。每項的測試已加進負責的 stage。

1. **系統曆法不是西曆**（民國、佛曆、日本曆）：日界與月份 key 必須仍是西元字串，月報不能變成 `0115/11`。測試：Stage 2 `DayKeyTests.nonGregorianCalendar_stillGregorian`。
2. **app 執行中跨時區、日期往回**：同一 dayKey 的紀錄要接續累積，不可覆蓋歸零。測試：Stage 4 `timezoneBackwards_resumesExistingRecord`。
3. **寫檔中斷或磁碟滿**：JSON 截斷要隔離備份、不 crash；寫入失敗要保留記憶體資料、下次重試。測試：Stage 4 `truncatedFile_quarantined`、`writeFailure_keepsDataAndRetries`，Stage 6 同型測試。
4. **月中改方案**：利用率與飽和判定用當日方案，改方案不得回溯改寫前一天。測試：Stage 4 `planChangedMidMonth_usesPerDayRatio`。
5. **睡眠橫跨持續窗**：3 秒窗與 30 秒 approach 窗遇到樣本間斷必須重來，不可把睡前與醒後接起來。測試：Stage 4 `gapResetsWindow`、`approachGap_resetsSustainTimer`。

## 裁決紀錄

抽驗後對報告的修正，以及報告間矛盾的裁決。

| # | 主題 | 報告內容 | 裁決與依據 |
|---|---|---|---|
| R1 | 計數器 64 位元 | PERF-07 建議可改 `if_data64`；CORE-16 實測同樣回繞 | 依 CORE-16，per-interface `UInt32 &-`。`$S/audit/core/exp03_wrap.out` 為證 |
| R2 | 缺 key 數 | UI-P1-6 寫 65，PERF-16.7 寫 66 | **66**。腳本比對 `L10n.swift` 211 key 與 xcstrings 146 key（含 1 孤兒 `chart.requires.macos13`）。Stage 11 用測試比對，不靠清單 |
| R3 | 影子 VM 修法 | CORE-01 只寫 `Settings { EmptyView() }`，並說 accessory app 到不了 | 不完整：CORE-24 修好後 Dock 模式成立，`.regular` 下 app 選單的「Settings…」會開空視窗。再加 `.commands { CommandGroup(replacing: .appSettings) {} }`。scratch 副本已編譯通過 |
| R4 | 圖表快取 | PERF-01 建議 `.onChange(of: oneHourData.count)` | 有 bug：點數達上限後 count 不變，圖表凍結。改用 `revision` 計數器 |
| R5 | `build.sh` 路徑 | PERF-15 建議 `build/DerivedData` | `build/` 未被 `.gitignore` 忽略，改 `.build/DerivedData`（已忽略）。`.gitignore` 有使用者修改，不動 |
| R6 | coverage 修法 | PERF-12 列兩種 | 採 test plan `"codeCoverage": false`。scratch 副本實測：scheme Debug build 的 `llvm_profile` 符號 0 個、bundle ID 正確。不動 `Release.xcconfig` |
| R7 | CORE-12 證據等級 | core 標「僅讀碼」 | 已被 UI-P1-3 與 PERF-02 的 sandbox harness 實測（Code=513）取代，確定失敗。ad-hoc 簽章下 SavePanel 不彈出的原因仍是推論 |
| R8 | Intel 宣稱 | WEB-P0-5 建議先拿掉 | PERF-14 實測 archive 為 `x86_64 arm64`，保留宣稱。Stage 15 重驗 `lipo -archs`；沒有 Intel 實機執行紀錄 |
| R9 | 容器路徑 | WEB-P0-6 說待實機確認 | 已確認：`$S/real-data-backup/container-prefs/` 與 `container-appsupport/` 就是真實容器內容。FAQ 可直接用該路徑 |
| R10 | en 文案 | WEB-P0-2 寫「en 不動」 | D14 優先，en 的定位句改成與 zh 一致 |
| R11 | CORE-21 修法 vs D11 | core 建議改量 TCP 握手 | D11 鎖定 HEAD，官網也要寫 HEAD。改為：丟棄暖機樣本＋門檻改 `good <120ms`、`fair <200ms`（jitter 門檻不變）。5 個既有 `LatencyMonitorTests` 仍過。門檻只由單一線路校準（TCP 19.8 ms、HEAD 86 ms），屬保守估計 |
| R12 | UI-P2-13 統一門檻 vs D2 | UI 建議統一成一個門檻；CORE-04 指定 80% 事件 | approach 維持 80%（屬事件定義）。`isPeakConcerning`、選單列警示改用使用者設定的通知門檻，移除寫死的 90%。標籤分列下載／上傳 |
| R13 | 飽和日範圍 | D2 未說明不足 10 分鐘的日子算不算 | 依 D4，飽和日與 P95 只看計入 `daysMonitored` 的日子。峰值與平均顯示含所有日子 |
| R14 | 持續 3 秒定義 | 報告未定義 | 連續 3 筆樣本的**最小值**。單秒尖峰不會拉高結果。相鄰樣本間隔 >2.5 秒就重算 |
| R15 | D13 門檻 | PERF-03 修補版關閉後 footprint 為 50.4 MB（N=360）、61.8 MB（N=8640） | 「閒置時」含開過再關閉。依現有數據很可能不達 50 MB，Stage 15 依實測判定，不預設結果 |
| R16 | 假尖峰殘餘風險 | CORE-03 要上限檢查 | 回繞差值無法完全區分 reset。上限 10 Gbps 只擋得住約 71% 的 reset（假設計數器值均勻分布）；殘餘尖峰由 D1（月報不受影響）與 D5（可清除）兜底。kernel 是否真的會 reset 未驗證 |

其他抽驗：CORE-01/02/03/05/09/18/24、PERF-03/12、UI-P1-1/P1-2、WEB-P0-5 的 `檔案:行號` 與目前工作樹一致。Swift 程式碼自審查後未變動。

## Stage 總覽

| Stage | 名稱 | 規模 | Model | 相依 | 可否平行 |
|---|---|---|---|---|---|
| 1 | 安全啟動與建置設定 | S，約 80 行 | sonnet | 無 | 與 13、14 可平行 |
| 2 | Seams、測試基礎、CORE-05 | L，約 900 行 | sonnet | 1 | 與 13、14 可平行 |
| 3 | 取樣重寫與峰值防呆 | M，約 400 行 | opus | 2 | 與 13、14 可平行 |
| 4 | 日紀錄、月報、方案建議 | XL，約 1400 行 | opus | 3 | 與 13、14 可平行 |
| 5 | 歷史模型、圖表效能、popover 釋放 | L，約 800 行（淨刪約 300） | opus | 4 | 與 13、14 可平行 |
| 6 | 歷史持久化、保留期、移除記憶體優化 | L，約 600 行（淨刪約 500） | opus | 5 | 與 13、14 可平行 |
| 7 | 延遲、斷線、異常、通知 | L，約 900 行 | opus | 6 | 與 13、14 可平行 |
| 8 | 設定與 app 生命週期接線 | L，約 700 行 | sonnet | 7 | 與 13、14 可平行 |
| 9 | 匯出與 entitlements | M，約 400 行 | sonnet | 8 | 與 13、14 可平行 |
| 10 | 選單列與 popover 打磨 | L，約 700 行 | sonnet | 9 | 與 13、14 可平行 |
| 11 | 在地化補齊 | M，約 300 行程式＋翻譯資料 | sonnet | 10 | 與 13、14 可平行 |
| 12 | 專案中繼資料與文件 | M，約 300 行 | sonnet | 11 | 與 13、14 可平行 |
| 13 | 官網：i18n 防護與內容真實性 | L，翻譯約 200 句 | sonnet | 無（文案已定稿，不需等 Swift stage） | 與 Swift stage 可平行；須在 14 之前 |
| 14 | 官網：互動、無障礙、SEO、標頭 | M，約 400 行 | sonnet | 13 | 與 Swift stage 可平行 |
| 15 | 整體驗收與效能數字定案 | M | opus | 全部 | 不可平行 |

驗收者不得與施工者同一個 agent（writer ≠ verifier）。

## 平行與衝突

- **Swift stage（1–12）全部循序。** 整個 package 是單一 module，兩人同時改，對方半成品會讓 `swift test` 失敗；不能 commit，也無法用 worktree 傳遞中間成果。
- **網站（13、14）可與任何 Swift stage 平行**，兩邊只共用 git index。13 改 locale 與元件，14 改版面與設定，檔案重疊（`Header.astro`、`Footer.astro`、`global.css`），所以 14 排在 13 之後。

### 型別與編譯相依

下表是「改了 A，範圍外的 B 會編不過」的清單，白名單已涵蓋。

| 改動 | 受影響處 | 處理 |
|---|---|---|
| Stage 2 所有 service 的 init 加參數 | 全部呼叫點 | 參數都有預設值，`PeakRecorder()` 仍可編譯 |
| Stage 2 VM 改 `init(dependencies:)` | `OnboardingView.swift:205` 的 `#Preview`、`StatusBarController.swift:12`、`ContentView.swift:75` | 預設 `.live`，不需改 |
| Stage 4 刪 `SettingsView.init()` | `BandwidthECG/BandwidthECGApp.swift:14`（`swift test` 看不到，必須跑 `BUILD`） | 同 stage 改 |
| Stage 4 刪 `recordDailySnapshot`、`currentMonthSummary`、`pastSummaries` | `NetworkMonitorViewModel.swift:230-263`、`MonthlyReportView.swift:26` | 同 stage 改 |
| Stage 4 `MonthlySummary` 加欄位 | `MonthlySummaryTests` 三個建議測試、`MonthlyReportService` | 新欄位 optional 且有預設值；三個測試依 D2 重寫 |
| `MonthlySummary.PlanRecommendation` | `displayName`、`csvValue`、`icon`、`MonthlyReportView.recommendationColor` 四處窮盡 switch | 不新增 case（D2 維持四種），無影響 |
| Stage 5 `NetworkDataPoint` 加 max 欄位 | `NetworkHistoryRecorder`、`DataExportService`、`NetworkChartView`、舊 JSON | 新 init 參數有預設；自訂 `init(from:)` |
| Stage 5 `NetworkChartView.init` 改 binding | `PopoverView.swift:80-86` | 同 stage 改 |
| Stage 5 刪圖表死碼 | 移除對 `twentyFourHourData`、`HourlyDataPoint` 的最後 UI 引用 | Stage 6 才能刪 property 與型別 |
| Stage 6 刪 `twentyFourHourData`、`HourlyDataPoint`、`MemoryOptimizer` | `NetworkMonitorViewModel.swift:88-103`、`ContentView.swift:392-415`、`StatusBarController.swift:134-137`、L10n 記憶體 key | 同 stage 改。`StatusBarController.swift:102-152` 整段死碼一起刪 |
| Stage 9 改 `ExportFormat` case | `DataExportService`、VM、`PopoverView.swift:516-523`；`StatusBarController.handleExportData` 已於 Stage 6 刪除 | 若 Stage 6 未完成會編不過，所以 9 排在 6 之後 |
| Stage 7 `NetworkAnomalyDetector.analyzeSpeed` 改語意 | VM、`PopoverView.swift:330` | 簽章不變，`isConnectionStable` 語意改 |
| Stage 8 `launchAtLogin` 改唯讀 | `ContentView.swift:288` 的 `$viewModel.preferences.launchAtLogin` | 同 stage 改自訂 Binding |
| L10n key 增刪 | `Localizable.xcstrings` | Stage 2–10 只動 `L10n.swift`。缺翻譯時退回繁中是預期狀態，Stage 11 補齊並刪孤兒 |

---

## Stage 1：安全啟動與建置設定

**目標：** 讓 Debug 與測試不可能碰到真實資料，消除 coverage 插樁與 `default.profraw`，建立之後所有手動實測的工具。

**Model／規模：** sonnet／S。**處理：** 安全啟動、PERF-12、PERF-15、PERF-16.9（bundle ID 部分）。

**白名單：** `Config/Debug.xcconfig`、`Config/Tests.xcconfig`、`BandwidthECG/BandwidthECG.xctestplan`、`build.sh`。scratch：`$S/tools/qa-copy.sh`。

**Produces：** Debug bundle ID `com.bobo52310.BandwidthECG.debug`；UI test bundle ID `com.bobo52310.BandwidthECG.uitests`；QA 副本 bundle ID `com.bobo52310.BandwidthECG.qa`。

- [ ] **Step 1：留基準。** `git -C $R diff > $S/checkpoints/stage-0-baseline.patch`；`git -C $R status --short > $S/checkpoints/stage-0-status.txt`；記下真實容器 plist 時間 `stat -f %m ~/Library/Containers/com.bobo52310.BandwidthECG/Data/Library/Preferences/com.bobo52310.BandwidthECG.plist > $S/checkpoints/real-container-mtime.txt`。
- [ ] **Step 2：改 xcconfig。** `Config/Debug.xcconfig` 在 `#include` 後加 `PRODUCT_BUNDLE_IDENTIFIER = com.bobo52310.BandwidthECG.debug`。`Config/Tests.xcconfig:10` 改成 `com.bobo52310.BandwidthECG.uitests`。`Shared.xcconfig`、`Release.xcconfig` 不動。
- [ ] **Step 3：改 test plan。** `defaultOptions` 加 `"codeCoverage" : false`；`testTargets` 移除 `BandwidthECGUITests`，只留 `BandwidthECGFeatureTests`。UI test 目前只有 `app.launch()`，留在專案但不進預設 plan。
- [ ] **Step 4：重寫 `build.sh`。** 介面 `./build.sh [debug|release] [--run]`。要求：`set -euo pipefail`；`cd` 到腳本目錄；設定值不分大小寫，正規化成 `Debug`／`Release`，其他值 exit 2；`-derivedDataPath .build/DerivedData`；Debug 用 `-destination 'platform=macOS,arch=arm64'`，Release 用 `-destination 'generic/platform=macOS'`（universal）；完成後印出 `.build/DerivedData/Build/Products/$CONFIG/BandwidthECG.app`；預設不啟動；`--run` 只對 Debug 有效，Release 加 `--run` 時印出「Release uses the real bundle ID; use the QA copy」並 exit 2。
- [ ] **Step 5：建立 `$S/tools/qa-copy.sh`**（`chmod +x`），內容如下。PlistBuddy 是因為 `plutil` 的 keypath 會把 entitlement 名稱的點當分隔符。

```zsh
#!/bin/zsh
# usage: qa-copy.sh /path/to/BandwidthECG.app  -> prints the QA copy path
set -euo pipefail
R=/path/to/bandwidth-monitor
S=$TMPDIR/scratchpad
QA=$S/qa
mkdir -p $QA
rm -rf $QA/BandwidthECG.app
cp -R "$1" $QA/BandwidthECG.app
plutil -replace CFBundleIdentifier -string com.bobo52310.BandwidthECG.qa $QA/BandwidthECG.app/Contents/Info.plist
cp $R/Config/BandwidthECG.entitlements $QA/qa.entitlements
/usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" $QA/qa.entitlements
codesign --force --sign - --entitlements $QA/qa.entitlements $QA/BandwidthECG.app
echo $QA/BandwidthECG.app
```

QA 啟動規則：`cd $S/qa && nohup ./BandwidthECG.app/Contents/MacOS/BandwidthECG > $S/logs/qa.log 2>&1 &`，記 PID，結束用 `kill <PID>`，只殺自己的 PID。每次前後各比一次真實容器 plist 的 mtime。QA 容器 `~/Library/Containers/com.bobo52310.BandwidthECG.qa` 刪不掉是已知現象（containermanagerd），無害。

**驗收（全部要貼輸出）：**

- [ ] `xcodebuild ... -configuration Debug -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER` 為 `.debug`；Release 為 `com.bobo52310.BandwidthECG`。
- [ ] `BUILD` 後：`plutil -extract CFBundleIdentifier raw <app>/Contents/Info.plist` 為 `.debug`；`nm <app>/Contents/MacOS/BandwidthECG | grep -c llvm_profile` 為 `0`；`codesign -d --entitlements - --xml <app> | plutil -p -` 含 `app-sandbox => true`。
- [ ] `RELEASE` 後：CFBundleIdentifier 為真實 ID；`llvm_profile` 為 `0`；`lipo -archs` 為 `x86_64 arm64`。不啟動。
- [ ] `xcodebuild test -workspace $R/BandwidthECG.xcworkspace -scheme BandwidthECG -destination 'platform=macOS,arch=arm64' -derivedDataPath $S/build/dd-test -resultBundlePath $S/build/stage1.xcresult > $S/logs/xctest.log 2>&1` 結果 `** TEST SUCCEEDED **`，15 個測試，log 內無 `BandwidthECGUITests-Runner`。
- [ ] QA 副本啟動 20 秒後：`~/Library/Containers/com.bobo52310.BandwidthECG.qa/Data/Library/Preferences/` 有 plist；真實容器 mtime 不變；`ls $R/default.profraw` 不存在。
- [ ] `$R/build.sh debug` 成功、不啟動；`$R/build.sh release --run` exit 2 且未開始建置。

- [ ] **CHECKPOINT 1**

---

## Stage 2：Seams、測試基礎、CORE-05

**目標：** 所有 service 可注入時鐘、defaults、外部系統；`swift test` 能實例化 VM；先止血 crash。除 CORE-05 外不改行為。

**Model／規模：** sonnet／L。**處理：** CORE-05、UI-P2-9（model 部分）、Seams 表全部。**Consumes：** Stage 1。

**白名單：** `Sources/BandwidthECGFeature/` 下 `Services/*.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Models/UserPreferences.swift`；新增 `Utilities/AppClock.swift`、`Utilities/DayKey.swift`、`Utilities/AppPaths.swift`、`Utilities/AppDependencies.swift`、`Services/Seams/*.swift`；`Tests/BandwidthECGFeatureTests/**`。

**Produces（後續 stage 依此命名）：**

```swift
public struct AppClock: Sendable {
    public var now: @Sendable () -> Date
    public var monotonic: @Sendable () -> TimeInterval   // seconds, includes sleep
    public var calendar: Calendar
    public static let live: AppClock                     // calendar = .autoupdatingCurrent, monotonic from ContinuousClock
}
public enum DayKey {
    public static func day(for date: Date, calendar: Calendar) -> String   // "2026-10-31"
    public static func month(for date: Date, calendar: Calendar) -> String // "2026-10"
    public static func month(ofDay dayKey: String) -> String
}
public enum AppPaths { public static var supportDirectory: URL }           // Application Support/BandwidthECG

public struct InterfaceCounters: Sendable, Equatable {
    public var rx: UInt32; public var tx: UInt32
    public init(rx: UInt32, tx: UInt32)
    public init(truncatingRx: UInt64, truncatingTx: UInt64)
}
public protocol CounterSource: Sendable { func read() -> [String: InterfaceCounters]? }   // nil = getifaddrs failed
public struct SystemCounterSource: CounterSource { public init() }

public protocol NotificationDelivering: Sendable {
    func requestAuthorization() async -> Bool
    func deliver(title: String, body: String, identifier: String) async throws
}
public struct SystemNotificationDelivery: NotificationDelivering { public init() }

public protocol LatencyProbe: Sendable { func measureSeconds() async throws -> TimeInterval }
public struct HTTPHeadProbe: LatencyProbe { public init() }   // HEAD https://www.apple.com, timeout 10

public struct PathSnapshot: Sendable, Equatable { public var isSatisfied: Bool; public var interfaceType: String }
public protocol PathStatusSource: AnyObject, Sendable {
    func start(_ handler: @escaping @Sendable (PathSnapshot) -> Void)
    func stop()
}
public final class SystemPathStatusSource: PathStatusSource, @unchecked Sendable { public init() }

public protocol BlobStore: Sendable {
    func read(_ name: String) throws -> Data?              // nil = file absent
    func write(_ data: Data, named name: String) throws    // atomic
    func quarantine(_ name: String) throws                 // rename to "<name>.corrupt-<unix-seconds>"
}
public struct AppSupportBlobStore: BlobStore { public init() }

public struct AppDependencies {
    public var defaults: UserDefaults
    public var clock: AppClock
    public var counterSource: any CounterSource
    public var notifications: any NotificationDelivering
    public var latencyProbe: any LatencyProbe
    public var pathSource: any PathStatusSource
    public var blobStore: any BlobStore
    public var logToFile: Bool
    public static var live: AppDependencies { get }
}
```

每個 service 的 init 加有預設值的參數：`init(defaults: UserDefaults = .standard, clock: AppClock = .live, ...)`。`NetworkMonitor.init(source: any CounterSource = SystemCounterSource(), clock: AppClock = .live)`、`NotificationService.init(defaults:clock:delivery:)`、`LatencyMonitor.init(defaults:clock:probe:)`、`DisconnectTracker.init(defaults:clock:pathSource:)`、`UserPreferences.init(defaults:)`、`ErrorHandler.init(logToFile:defaults:)`、`MonthlyReportService.init(userDefaults:clock:)`。VM：`public init(dependencies: AppDependencies = .live)`，所有 `public var x = X()` 改在 init 內賦值。Timer 內呼叫的私有方法改 internal：`NetworkMonitor.tick()`、`LatencyMonitor.measureLatency()`、`DisconnectTracker.handle(_ snapshot: PathSnapshot)`。

- [ ] **Step 1：建測試支援 `Tests/BandwidthECGFeatureTests/Support/TestSupport.swift`。** 內容：`MemoryDefaults`（從 `$S/audit/core/h1/src/AuditSeams.swift` 移植，全記憶體、不碰 cfprefsd）；`final class TestClock: @unchecked Sendable`（`init(start: Date, timeZone: TimeZone)`、`advance(by:)`、`setWall(_:)` 只動牆鐘、`appClock: AppClock`）；`FakeCounterSource`（腳本化回傳，可回 nil）；`FakeNotificationDelivery`（記錄 title/body、`authorizationRequested`，`grantAuthorization` 可設 false，`failNextDelivery` 可讓 deliver throw）；`FakeLatencyProbe`（佇列，含 throw）；`FakePathSource`；`InMemoryBlobStore`（記 `writeCount`、可設 `failNextWrite`、記 `quarantined`）；`extension AppDependencies { static func test(clock:) -> AppDependencies }`（`logToFile: false`）。
- [ ] **Step 2：寫 `DayKeyTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `dayAndMonth_inTaipei` | 2026-10-31 23:59 +08 → `"2026-10-31"`、`"2026-10"` |
| `monthBoundary` | 2026-11-01 00:01 +08 → `"2026-11-01"`、`"2026-11"` |
| `nonGregorianCalendar_stillGregorian` | `Calendar(identifier: .republicOfChina)`、`.buddhist`、`.japanese` 都回 `"2026-..."` |
| `usesCalendarTimeZone` | 同一 Date，`America/New_York` 與 `Asia/Taipei` 回不同 day |
| `dst_newYork` | 2026-03-08 與 2026-11-01 當天 00:30、23:30 都回同一 day |

- [ ] **Step 3：實作 `AppClock`、`DayKey`、`AppPaths`。** `DayKey` 內部一律 `Calendar(identifier: .gregorian)` 並套用傳入 calendar 的 `timeZone`，用 `String(format:)`，不用 `DateFormatter`。跑 `TEST DayKeyTests` 應 PASS。
- [ ] **Step 4：抽 seam 檔到 `Services/Seams/`。** `SystemCounterSource` 只回 `name` 以 `en` 或 `wi` 開頭、`ifa_addr.sa_family == AF_LINK` 的介面（exp01：只有 AF_LINK 有值）；`getifaddrs` 非 0 回 nil。`AppSupportBlobStore.write` 用 `Data.write(to:options:.atomic)`。其餘是把現有呼叫原樣搬進實作。`BlobStoreTests` 測：讀不存在回 nil、寫後讀回、`quarantine` 後原檔不存在且 `.corrupt-` 檔存在（用 `FileManager.temporaryDirectory` 下 UUID 目錄，`AppSupportBlobStore` 加 `init(directory:)`）。
- [ ] **Step 5：逐一改 service 的 init，把 `Date()`、`UserDefaults.standard`、`Calendar.current` 換成注入值。** `NetworkMonitorViewModel.swift:258` 的 `isDateInToday` 改 `isDate(_:inSameDayAs: clock.now())`。`DisconnectTrackerTests` 兩個 tracker 測試改用 `MemoryDefaults` 與 `TestClock`。`NetworkMonitor.tick()` 暫時維持舊公式（對 counters 加總），Stage 3 才重寫。
- [ ] **Step 6：寫 `ViewModelSmokeTests.init_withFakes_doesNotTouchNotificationCenter`。** 用 `AppDependencies.test` 建 VM，斷言 `FakeNotificationDelivery` 的 `authorizationRequested` 在 `await` 後為 true，整個測試不 abort（真實 `UNUserNotificationCenter.current()` 在 host-less 環境 exit 134，見 exp09）。
- [ ] **Step 7：寫 CORE-05 測試並確認失敗。** `Int(inf)` 會讓測試程序 crash，這算預期的失敗；用 `--filter` 單獨跑。

| 測試（`PlanSpeedTests`） | 斷言 |
|---|---|
| `planZero_keepsPrevious` | 設 300 後設 0 → 仍 300 |
| `planNegative_keepsPrevious` | -5 → 300 |
| `planNaN_keepsPrevious`、`planInfinity_keepsPrevious` | `.nan`、`.infinity` → 300 |
| `planHuge_clamped` | `1e300` → `100_000` |
| `storedZero_loadsDefault` | defaults 內 0、-1、`.infinity` → 300 |
| `checkAndNotify_planZero_noTrap` | plan 0、speed 100 → 不 crash、0 則通知 |
| `checkAndNotify_planNegative_noTrap` | plan -1 → 0 則通知 |
| `checkAndNotify_uint64Max_noTrap` | speed `Double(UInt64.max)`、plan 1 → 1 則通知，body 含 `9999` |
| `checkAndNotify_planHuge_noTrap` | plan `1e300`、speed 1 → 不 crash、0 則通知 |

- [ ] **Step 8：實作。** `UserPreferences`：`downloadPlanSpeed`、`uploadPlanSpeed` 的 `didSet` 先驗證；非有限或 ≤0 還原 `oldValue`，>100000 夾到 100000，然後才寫 defaults。`init` 載入時非有限或 ≤0 用 300。常數 `UserPreferences.planSpeedRange = 1.0...100_000.0`。`NotificationService.checkAndNotify`：`guard plan > 0, isFinite`；百分比 `Int(min(ratio * 100, 9999))`。方案值若大於範圍上限也不得進 `Int()`。
- [ ] **Step 9：** `TEST` 全綠（原 15 個加新測試），`BUILD` 通過。

**驗收：** `TEST` exit 0，總數 ≥33；`BUILD` 0 警告。`cd $R/BandwidthECGPackage/Sources/BandwidthECGFeature && grep -rnE 'UserDefaults\.standard|Calendar\.current|isDateInToday' Services Models ViewModels Utilities` 只剩參數預設值與 `AppClock.live`。`Views/` 內的 `UserDefaults.standard` 於 Stage 8 處理。QA 副本啟動 15 秒不 crash。

- [ ] **CHECKPOINT 2**（新檔：`Utilities/AppClock.swift`、`DayKey.swift`、`AppPaths.swift`、`AppDependencies.swift`、`Services/Seams/*`、測試檔）

---

## Stage 3：取樣重寫與峰值防呆

**目標：** 速度計算不再被讀取失敗、時鐘倒退、計數器回繞、介面增減污染；舊污染可清除，新假尖峰進不了峰值。

**Model／規模：** opus／M。**處理：** CORE-03、06、16、20、28、PERF-07、PERF-16.1（timer tolerance）、D5 的防呆與 API。**Consumes：** `AppClock`、`CounterSource`、`InterfaceCounters`。

**白名單：** `Services/NetworkMonitor.swift`、`Services/LatencyMonitor.swift`（只改 timer）、`Services/PeakRecorder.swift`、`Services/PeakApproachTracker.swift`（只改 CORE-06）；新增 `Utilities/SampleGuard.swift`、`Utilities/RepeatingTimer.swift`；測試。

**Produces：**

```swift
public enum SampleGuard {
    public static let maxPlausibleMbps: Double = 10_000
    public static var maxPlausibleBytesPerSecond: Double { maxPlausibleMbps * 125_000 }
    public static let minSampleInterval: TimeInterval = 0.5
    static func delta(previous: UInt32, current: UInt32, elapsed: TimeInterval) -> UInt64
}
public enum RepeatingTimer {
    @MainActor @discardableResult
    public static func schedule(interval: TimeInterval, tolerance: TimeInterval, _ block: @escaping @MainActor () -> Void) -> Timer
}
public enum PeakDirection: Sendable { case download, upload }
extension PeakRecorder { public func clearAllTimePeak(_ direction: PeakDirection) }
```

- [ ] **Step 1：寫 `NetworkMonitorTests` 並確認失敗。** 全用 `FakeCounterSource` 與 `TestClock`，每步 `clock.advance(by:)` 後呼叫 `monitor.tick()`，以 `onSpeedUpdate` 收結果。

| 測試 | 腳本 | 斷言 |
|---|---|---|
| `readFailure_keepsBaseline` | t0 rx=1000；t1 回 nil；t2 rx=1000+250_000 | t1 不發樣本；t2 下載 = 125_000 B/s（dt=2） |
| `oneMbpsLink_readFailure_noGiantSpike` | 重現 CORE-03(a) | 全程 ≤1.1 Mbps，沒有 24,004 |
| `wallClockBackward_noEffect` | `setWall(-60s)`、monotonic +1 | 正常出值，不跳過 |
| `shortInterval_skippedThenAccumulated` | +0.25s（rx+500）、+0.75s（rx+500） | 第一次不發；第二次 = 1000 B/s，dt=1 |
| `wrap_singleInterface` | last 4_294_967_000、cur 1000 | delta 1296 |
| `wrap_atOneGbps_noZeroDips` | 300 秒、每秒 +125_000_000（mod 2³²） | 300 筆全 ≈1000 Mbps，無 0 |
| `wrap_isPerInterface` | en0 回繞、en1 正常 | 兩者 delta 相加正確；舊的「總和比較」會得 0 |
| `newInterface_firstTickContributesZero` | t1 出現 en5 計數 9_000_000 | 不出現尖峰 |
| `interfaceRemovedAndBack_rebaselines` | en1 消失一 tick 再回來 | 回來那 tick 貢獻 0 |
| `counterReset_implausible_rebaselined` | en0 last 1_000_000_000、cur 5_000，dt=1 | 下載 0，非 26 Gbps |
| `manyInterfaces_noOverflow` | 8 介面各 delta 4e9 | 無 trap，合計正確 |
| `truncatingInit_handlesUInt64Max` | `InterfaceCounters(truncatingRx: .max, truncatingTx: 0x1_0000_0005)` | rx=`UInt32.max`、tx=5 |
| `firstTick_baselineOnly_noSpike` | start 後第一 tick | 速度 ≈0 |
| `longSleep_noSpike` | dt 28800s、rx+1000 | 速度 <1 Mbps |

- [ ] **Step 2：實作 `SampleGuard` 與 `NetworkMonitor.tick()`。** 流程：`source.read()` 回 nil 就 return，基準與時間都不動；`dt = monotonic - last`；`dt < minSampleInterval` 就 return（基準不動，下次累積）；逐介面算 delta，只有 baseline 內有的介面才算；`current < previous` 時算 `current &- previous`，若 `Double(差值) / dt > maxPlausibleBytesPerSecond` 視為 reset 回 0；`baseline = counters`（消失的介面自動移除）。其餘差值原樣採用。不用 `if_data64`。
- [ ] **Step 3：寫 `RepeatingTimerTests.firesDuringEventTracking`。** `@MainActor` 測試用 `RepeatingTimer.schedule(interval: 0.1, tolerance: 0.02)`，`RunLoop.main.run(mode: .eventTracking, before: +0.55s)`，斷言觸發 ≥3 次（對照 exp06：default mode 為 0 次）。確認失敗（helper 尚不存在）後實作：`Timer(timeInterval:repeats:)`、`RunLoop.main.add(timer, forMode: .common)`、block 內 `MainActor.assumeIsolated`。
- [ ] **Step 4：`NetworkMonitor` 與 `LatencyMonitor` 的 timer 改用 `RepeatingTimer`**，tolerance 分別 0.2、2。
- [ ] **Step 5：寫 `PeakRecorderTests` 並確認失敗。** 全用 `MemoryDefaults`、`TestClock`。

| 測試 | 斷言 |
|---|---|
| `aboveCap_ignored` | 100 Mbps 後餵 24_004 Mbps → 今日、歷史、1 小時峰值都還是 100 |
| `exactlyCap_accepted` | 10_000 Mbps 被記錄 |
| `clearAllTime_download_keepsUpload` | 清下載後下載 0、time nil，上傳不變；defaults 對應 key 已移除 |
| `clearAllTime_alsoClearsMatchingToday` | 今日峰值等於歷史峰值時一併清 |
| `clearAllTime_keepsDifferentToday` | 今日 50、歷史 664 → 今日保留 |
| `clearAllTime_nextSampleResets` | 清除後餵 80 → 歷史 80 |
| `load_pollutedAllTime_cleared` | defaults 歷史 24_004 → 載入後 0，log 一次 |
| `staleToday_afterEmptySession` | day1 寫入 280；day2 launch 無樣本；day2 再 launch → 今日 0 |
| `staleToday_perDirection` | 現場資料：下載 time=今天、上傳 time=2026-03-03、`lastRecordDate`=今天 → 只丟上傳 |
| `newDay_removesTodayKeys` | 跨日後 defaults 無 `todayPeakDownload` |
| `dst_springForward_day` | `America/New_York` 2026-03-08 跨日正確 |

`PeakApproachTrackerTests` 加：`staleApproach_afterEmptySession`（現場殘留 `todayApproachCount=2`、`lastApproachRecordDate` 為舊日期 → 0，且 key 被清掉）。

- [ ] **Step 6：實作。** `PeakRecorder.recordSpeed` 入口：任一方向 >`maxPlausibleMbps` 就 `logger.warning` 後 return（該次不進今日、歷史、1 小時）。跨日分支同步 `removeObject` 四個 today key。`loadPeakData` 改逐方向判斷 `todayPeak*Time` 是否 `isDate(_:inSameDayAs: now)`，不靠 `lastRecordDate`；舊 key 留在 today 但時間不是今天就移除。載入時歷史峰值 >`maxPlausibleMbps` 就清除並 log。用 `Logger(subsystem: "com.bandwidthecg", category: "Peaks")`。`PeakApproachTracker` 同步移除舊 key。
- [ ] **Step 7：** `TEST` 全綠、`BUILD`。

**驗收：** `TEST` exit 0；`BUILD` 0 警告；`grep -rn "if_data64\|isDateInToday" $R/BandwidthECGPackage/Sources` 無結果；QA 副本跑 60 秒不 crash，`qa.log` 無錯誤。

- [ ] **CHECKPOINT 3**（新檔：`Utilities/SampleGuard.swift`、`RepeatingTimer.swift`、測試檔）

---

## Stage 4：日紀錄、月報、方案建議

**目標：** 月報由每筆樣本累積的日紀錄推導；影子 VM 消失；建議邏輯符合 D1–D4。這是全案資料正確性核心。

**Model／規模：** opus／XL。**處理：** CORE-01、02、04、06（剩餘）、07、08、13、14、25、26、27，UI-P1-5、UI-P2-17、PERF-05、PERF-11。CORE-09 對月報的影響在此消失，重複列本身在 Stage 6 隨功能刪除。**Consumes：** Stage 2、3。

**白名單：** `BandwidthECG/BandwidthECGApp.swift`、`ContentView.swift`（只刪 `init()`）、`Services/MonthlyReportService.swift`、`Services/PeakApproachTracker.swift`、`Services/LatencyMonitor.swift`（只加 callback）、`Services/DisconnectTracker.swift`（只加 callback）、`Models/MonthlySummary.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Views/MonthlyReportView.swift`、`Views/StatusBarController.swift`（只加 flush 與睡眠觀察）、`Utilities/L10n.swift`；新增 `Models/ReportRules.swift`、`Models/DailyRecord.swift`、`Models/SustainedPeakWindow.swift`、`Services/DailyRecordStore.swift`、`Services/LegacyMonthlyImporter.swift`；測試。

**Produces：**（`MonthlySummary`、`MonthlyReportService`、`PeakApproachTracker`、`LatencyMonitor`、`DisconnectTracker`、VM 區塊列的是新增成員，寫在型別本體，不是 extension）

```swift
public enum ReportRules {                       // D2 要求常數集中一處
    public static let sustainedPeakSamples = 3
    public static let sustainedMaxGapSeconds: TimeInterval = 2.5
    public static let minDailySamples = 600     // D4: 10 minutes at 1 Hz
    public static let minDaysForRecommendation = 7
    public static let minDaysForDowngrade = 14
    public static let saturationRatio = 0.90
    public static let saturatedDaysForUpgrade = 3
    public static let downgradeP95Ratio = 0.30
    public static let approachRatio = 0.80
    public static let approachSustainSeconds: TimeInterval = 30
    public static let approachRearmRatio = 0.60
    public static let approachRearmSeconds: TimeInterval = 60
    public static let approachMaxGapSeconds: TimeInterval = 5
    public static let retentionDays = 400
    public static let flushIntervalSeconds: TimeInterval = 60
}
public struct DailyRecord: Codable, Sendable, Equatable {
    public let dayKey: String
    public var sustainedPeakDownloadMbps, sustainedPeakUploadMbps: Double
    public var downloadSum, uploadSum: Double   // Mbps per sample
    public var sampleCount, approachCount: Int
    public var latencySum: Double; public var latencyCount, latencyFailures: Int
    public var jitterSum: Double; public var jitterCount: Int
    public var disconnectCount: Int; public var downtimeSeconds: Double
    public var planDownloadMbps, planUploadMbps: Double
    public var isCounted: Bool { get }          // sampleCount >= minDailySamples
    public var downloadPeakRatio, uploadPeakRatio: Double { get }
    public var isSaturated: Bool { get }        // either ratio > saturationRatio
}
struct SustainedPeakWindow {
    mutating func add(_ mbps: Double, at monotonic: TimeInterval) -> Double?   // min of last 3 once available
}
@MainActor @Observable public final class DailyRecordStore {
    public init(store: any BlobStore, clock: AppClock)
    public private(set) var records: [String: DailyRecord]
    public func ingest(_ speed: NetworkSpeed, planDownloadMbps: Double, planUploadMbps: Double)
    public func recordApproachEvent()
    public func recordLatency(latencyMs: Double, jitterMs: Double)
    public func recordLatencyFailure()
    public func recordDisconnect(start: Date, end: Date)
    public func flush()
    public func records(inMonth monthKey: String) -> [DailyRecord]
    public var monthKeys: [String] { get }
}
extension MonthlySummary {
    public let monthKey: String
    public let saturatedDays: Int?              // nil = legacy blob
    public let downloadDailyPeakP95Ratio, uploadDailyPeakP95Ratio: Double?
    public let latencyFailureCount: Int?
    public static func make(monthKey: String, month: Date, days: [DailyRecord]) -> MonthlySummary
    public static func percentile95(_ values: [Double]) -> Double?   // nearest rank: index = ceil(0.95 * n) - 1
}
extension MonthlyReportService {
    public init(userDefaults: UserDefaults = .standard, dailyStore: DailyRecordStore, clock: AppClock = .live)
    public var currentMonthKey: String { get }
    public var availableMonths: [String] { get }         // newest first, daily + legacy
    public func summary(for monthKey: String) -> MonthlySummary?
}
extension PeakApproachTracker {
    @discardableResult public func checkForApproach(_ speed: NetworkSpeed, downloadPlanSpeed: Double, uploadPlanSpeed: Double) -> Bool
}
public enum LatencyMeasurement: Sendable, Equatable { case success(latencyMs: Double, jitterMs: Double); case failure }
extension LatencyMonitor { public var onMeasurement: ((LatencyMeasurement) -> Void)? }
extension DisconnectTracker { public var onEvent: ((DisconnectEvent) -> Void)? }
extension NetworkMonitorViewModel {
    public let dailyStore: DailyRecordStore
    public func flushPersistence()
}
```

檔名 `daily-records.json`，內容 `{"schemaVersion":1,"records":[...]}`。`MonthlySummary` 既有欄位全保留；`peakDownloadMbps`、`peakUploadMbps` 語意改為持續 3 秒峰值。

### Task 4.1：規則與日紀錄

- [ ] **Step 1：寫 `SustainedPeakWindowTests`、`DailyRecordTests`、`RecommendationTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `singleSecondSpike_ignored` | [1, 276, 1] 每秒一筆 → 最大回傳 1 |
| `threeSeconds_sustained` | [280, 280, 280] → 280 |
| `usesMinimum` | [280, 300, 290] → 280 |
| `gapResetsWindow` | 280、280、間隔 3 秒、280 → 第三筆回 nil |
| `isCounted_boundary` | sampleCount 599 false、600 true |
| `decode_missingFields_defaultsToZero` | JSON 只有 `dayKey` → 其餘 0，不丟錯 |
| `percentile95_nearestRank` | 1...20 → 19；1...14 → 14；空 → nil |

`RecommendationTests` 以 `MonthlySummary.make` 餵日紀錄（方案 300/300，除非註明）：

| 測試 | 資料 | 預期 |
|---|---|---|
| `sixDays_insufficient` | 6 計入日、全飽和 | insufficientData |
| `sevenDays_noSaturation_fits` | 7 日、峰值 150 | planFits |
| `twoSaturatedDays_fits` | 30 日、2 日 280 | planFits |
| `threeSaturatedDays_upgrade` | 30 日、3 日 280 | considerUpgrade |
| `threeSaturatedUploadOnly_upgrade` | 下載 50%、上傳 3 日 95%（CORE-25） | considerUpgrade |
| `exactly90Percent_notSaturated` | 3 日剛好 270 | planFits |
| `oneSpeedTest_notUpgrade` | 30 日閒置、1 日持續 276（CORE-04）；有飽和日所以也不降級 | planFits |
| `low_14days_downgrade` | 14 日、峰值 29% | considerDowngrade |
| `low_13days_fits` | 13 日、29% | planFits |
| `p95Exactly30_fits` | 14 日、30% | planFits |
| `uploadHigh_blocksDowngrade` | 下載 10%、上傳 50% | planFits |
| `saturatedDay_blocksDowngrade` | 20 日、19 日 10%、1 日 95%（P95=10%） | planFits |
| `uncountedDays_ignored` | 3 個 500 樣本的飽和日＋20 日 10% | considerDowngrade（R13） |
| `planChangedMidMonth_usesPerDayRatio` | 前 15 日方案 300 峰值 280；後 15 日方案 1000 峰值 280 | 飽和日 15、considerUpgrade |
| `legacySummary_insufficient` | `saturatedDays: nil`、`daysMonitored: 30` | insufficientData |
| `promoScenario_downgrade` | 方案 1000/600、30 日、最高 284.6/96.2 | considerDowngrade（對應宣傳片） |

重寫 `MonthlySummaryTests` 三個建議測試（舊規則已被 D2 取代）：`upgradeRecommendation_frequentApproaches` 改為 3 個飽和日；`downgradeRecommendation_lowUtilization` 補 P95 欄位；`planFits_moderateUsage` 補 P95 欄位。`planUtilization_calculatesCorrectly` 不動。

- [ ] **Step 2：實作 `ReportRules`、`DailyRecord`（自訂 `init(from:)`，除 `dayKey` 外全 `decodeIfPresent`）、`SustainedPeakWindow`。**
- [ ] **Step 3：實作 `MonthlySummary` 新欄位與 `make`。** 新欄位為 optional，memberwise init 給 `nil` 預設；自訂 `init(from:)`：`monthKey` 缺時由 `month` 以 `DayKey.month` 推得，其餘 `decodeIfPresent`。`make`：`peak*` 取所有日子持續峰值最大值；`avg*` = Σsum / Σcount；方案取該月最後一個 `sampleCount > 0` 的日子；latency、jitter = Σ/Σ；`daysMonitored` = 計入日數；`saturatedDays`、P95 只看計入日。`recommendation` 依 D2 順序重寫，`saturatedDays`、P95 任一為 nil 回 `.insufficientData`。`formattedMonth` 改為 `monthKey` 把 `-` 換 `/`，不用 `DateFormatter`（同時解 CORE-29 的月報部分）。

### Task 4.2：DailyRecordStore

- [ ] **Step 1：寫 `DailyRecordStoreTests` 並確認失敗。** 以 `TestClock`、`InMemoryBlobStore`，樣本用 helper `feed(store, mbps:, seconds:)` 每秒 advance 一次。

| 測試 | 斷言 |
|---|---|
| `eveningPeak_entersDailyRecord` | CORE-02 回歸：31 天、每晚 21:00 持續 10 秒 280 Mbps、每日 ≥10 分鐘，方案 300 → 月報 peak 280、利用率 93.3±0.1%、considerUpgrade，絕不是 downgrade |
| `laptopShortSession_recorded` | 每天只開 50 分鐘 → 30 天 `daysMonitored=30` |
| `midnightNoTraffic_attributesToPreviousDay` | 23:59:59 最後樣本，00:10 下一筆 → 兩筆紀錄，前一天資料不變 |
| `closedAtMidnight_nextLaunchKeepsRecord` | flush、重建 store、隔天 ingest → 昨日紀錄仍在 |
| `sameDayRelaunch_oneRecord` | 同日重建 3 次 → 一筆，sampleCount 累加 |
| `monthlyAvg_isTrueMean` | CORE-09 回歸：1200 筆 10 Mbps＋400 筆 90 Mbps → 月平均 30.0，不是重複列造成的 60.7 型偏差 |
| `monthBoundary_splits` | 10/31 23:59 與 11/01 00:01 分屬 `2026-10`、`2026-11` |
| `dstDay_newYork` | 2026-03-08 與 2026-11-01 各一日，每小時 ingest，只產生一筆當日紀錄 |
| `timezoneBackwards_resumesExistingRecord` | 台北 11/15 00:30 ingest，時區改洛杉磯（dayKey 11/14），再 ingest → 11/14 既有紀錄累加，不歸零 |
| `flush_atMostEvery60s` | 120 秒 ingest → `writeCount` ≤2；再 `flush()` 必寫一次 |
| `truncatedFile_quarantined` | 檔案內容為半截 JSON → 不 crash、`quarantined` 含檔名、從空白開始、之後可寫 |
| `futureSchema_quarantined` | `schemaVersion: 99` → 隔離，不覆寫 |
| `writeFailure_keepsDataAndRetries` | `failNextWrite` → 記憶體資料仍在，下次 flush 成功 |
| `retention_prunes400Days` | 第 401 天的舊紀錄被移除 |
| `latency_dailyAverage` | 成功 100、200、300 → latencySum/Count = 200；failure 不進平均，`latencyFailures=1` |
| `disconnect_acrossMidnight_splits` | 23:50–00:20 → 前一日 600 秒、後一日 1200 秒，兩日 `disconnectCount` 各 +1 |
| `planChange_doesNotRewritePreviousDay` | CORE-26：10/31 方案 300，11/01 改 1000 → 10 月 summary 方案 300、利用率不變 |

- [ ] **Step 2：實作。** dayKey 用 `DayKey.day(for: clock.now(), calendar: clock.calendar)`。`records` 內直接 upsert，不需要「結算」動作（launch 補結算因此自然成立）。`ingest` 用 `clock.monotonic()` 餵 `SustainedPeakWindow`（下載、上傳各一個）。距上次 flush ≥60 秒就 flush。decode 失敗呼叫 `store.quarantine` 並 `logger.error`。寫入失敗 `logger.error`、保留 dirty 旗標。

### Task 4.3：PeakApproachTracker 事件計數

- [ ] **Step 1：寫 `PeakApproachTrackerTests`（方案 300/300）並確認失敗。** 下表「N 秒」指首尾差 N 秒，即 N+1 筆 1 Hz 樣本。

| 測試 | 序列 | 預期 |
|---|---|---|
| `singleSecondSpike_zero` | 1 秒 280 | 0 |
| `sustained29s_zero` | 29 秒 240 | 0 |
| `sustained30s_one` | 30 秒 240 | 1，當下回傳 true |
| `sixtyMinuteDownload_one` | 3600 秒 280 | 1（舊版 12） |
| `rearmAfter60sBelow60Percent` | 30 秒高、60 秒 100、30 秒高 | 2 |
| `notRearmed_59s` | 30 秒高、59 秒 100、30 秒高 | 1 |
| `dipTo70Percent_doesNotRearm` | 高、120 秒 210、高 | 1 |
| `uploadAlsoCounts` | 上傳 240、下載 0 | 1 |
| `approachGap_resetsSustainTimer` | 20 秒高、停 10 秒無樣本、15 秒高 | 0 |
| `longDownloadAcrossMidnight_notDoubleCounted` | 23:50 到 00:10 持續 | 前一日 1、當日 0 |
| `sameKeysStillLoad` | defaults 有 `todayApproachCount=2`、今天日期 | 載入 2（舊資料相容） |

- [ ] **Step 2：實作。** 狀態機 `armed(overSince: TimeInterval?)`／`latched(underSince: TimeInterval?)`，時間用 `clock.monotonic()`。over = 下載 ≥0.8×方案 或 上傳 ≥0.8×方案；under = 兩方向都 <0.6×方案。相鄰樣本間隔 >`approachMaxGapSeconds` 清掉進行中的計時。達 30 秒時 `count += 1`、append timestamp、回傳 true。跨日重設計數但不重設狀態機。門檻全用 `ReportRules`。持久化 key 不變，狀態機不持久化。刪掉 5 分鐘節流。

### Task 4.4：月報服務與舊資料

- [ ] **Step 1：寫 `MonthlyReportServiceTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `reopenShowsReportImmediately` | CORE-07：有日紀錄，new service → `summary(for: current)` 非 nil |
| `pastMonthStillAvailable` | 11/02 時 `availableMonths` 含 `2026-11`、`2026-10`，新到舊 |
| `todayPartialIncluded` | 今日已 ≥600 樣本 → 計入 |
| `monthWithOnlyShortDays_summaryExists` | 只有 <10 分鐘的日子 → summary 非 nil、`daysMonitored=0`、insufficientData |
| `legacyBlob_decodes` | 舊格式 `monthlySummaries`（fixture 無新欄位）→ 出現在 `availableMonths`，建議 insufficientData |
| `legacyBlob_missingField_backedUp` | 缺必要欄位 → 不 crash；原 blob 複製到 key `monthlySummaries.corrupt`；log 一次 |
| `legacyAccumulators_imported` | 舊 `monthlyReportAccumulators` → 轉成一筆 legacy summary，原 key 保留不刪 |
| `dailyTakesPrecedenceOverLegacy` | 同月份兩邊都有 → 用日紀錄 |
| `newCode_neverWritesLegacyKeys` | 操作後 `monthlySummaries` bytes 不變 |
| `tzMonthKey_stable` | CORE-27：台北建立 11 月紀錄，時區改洛杉磯 → 仍是 `2026-11`，不被算成 10 月 |
| `formattedMonth_rocCalendar` | 系統曆法民國 → `2026/11` |
| `csv_containsScopeNote` | `exportToCSV` 含 `Scope,This Mac only; includes LAN traffic` 與 `Latency Probe Failures` 列 |

- [ ] **Step 2：實作 `LegacyMonthlyImporter.load(defaults:) -> [MonthlySummary]`（唯讀）與改寫 `MonthlyReportService`。** 刪除 accumulators、`currentMonthSummary`、`pastSummaries`、`recordDailySnapshot`。新程式碼永不寫入 `monthlySummaries`、`monthlyReportAccumulators`，所以 CORE-13 的「下次 save 覆蓋」不會發生。

### Task 4.5：接線與移除影子 VM

- [ ] **Step 1：寫 `ViewModelIntegrationTests` 並確認失敗。** VM 的 `networkMonitor` 改 internal 讓測試呼叫 `tick()`。`speedSamples_reachDailyStore`：fake counters 餵 3 秒 280 Mbps，`dailyStore.records` 今日持續峰值 ≈280。`approachEvent_reachesDailyStore`：30 秒 240 → `approachCount=1`。`latencyMeasurement_reachesDailyStore`：呼叫 `measureLatency()` 一次成功一次失敗。
- [ ] **Step 2：改 VM。** `onSpeedUpdate` 加 `dailyStore.ingest`，`checkForApproach` 回 true 時 `recordApproachEvent`；`latencyMonitor.onMeasurement`、`disconnectTracker.onEvent` 接到 store。刪 3600 秒 timer、`checkAndRecordDailySnapshot`、`lastDailySnapshotDate`、`recordDailySnapshot`。`flushPersistence()` 呼叫 `dailyStore.flush()`。
- [ ] **Step 3：改 `BandwidthECGApp.swift`：** `Settings { EmptyView() }` 加 `.commands { CommandGroup(replacing: .appSettings) {} }`，並刪 `ContentView.swift:74-76` 的 `init()`。
- [ ] **Step 4：`StatusBarController`：** `cleanUp()` 加 `viewModel.flushPersistence()`；註冊 `NSWorkspace.shared.notificationCenter` 的 `willSleepNotification` 呼叫同一方法。

### Task 4.6：月報畫面

- [ ] **Step 1：改 `MonthlyReportView`。** `.onAppear` 讀一次 `summary` 存 `@State`（不綁每秒更新）；標題下加月份 `Picker`（`availableMonths`，顯示 `yyyy/MM`），預設當月，當月無資料用最新月份。`.insufficientData` 時顯示 `L10n.reportCollectingDays(have, need)`。底部加兩行註記 `L10n.reportScopeNote`「只計算這台 Mac，包含區網傳輸」（D3）、`L10n.reportSustainedNote`「峰值為持續 3 秒的速度」（D1）。

**驗收：** `TEST` exit 0；`BUILD` 0 警告。`grep -rn "NetworkMonitorViewModel()" $R/BandwidthECGPackage/Sources $R/BandwidthECG --include='*.swift'` 只剩 `StatusBarController.swift:12` 與 `OnboardingView.swift` 的 `#Preview`。`grep -rnE "recordDailySnapshot|lastDailySnapshotDate|scheduledTimer\(withTimeInterval: 3600" $R/BandwidthECGPackage/Sources` 無結果。

QA 副本跑 11 分鐘：`~/Library/Containers/com.bobo52310.BandwidthECG.qa/Data/Library/Application Support/BandwidthECG/daily-records.json` 存在、今日 `sampleCount ≥ 600`；`heap <pid> | grep -c 'NetworkMonitorViewModel'` 顯示 1 個實例。以上由 fresh verifier 獨立實跑。

- [ ] **CHECKPOINT 4**（新檔：`Models/ReportRules.swift`、`DailyRecord.swift`、`SustainedPeakWindow.swift`、`Services/DailyRecordStore.swift`、`LegacyMonthlyImporter.swift`、測試檔）

---

## Stage 5：歷史模型、圖表效能、popover 釋放

**目標：** 長時間運行後打開 popover 不再滿載；關閉後釋放內容；10 秒點保留窗口最大值。必須在 Stage 6 恢復 24 小時載入之前完成（D7）。

**Model／規模：** opus／L。**處理：** PERF-01、PERF-03、CORE-17、UI-P2-14、UI-P3-11、UI-P3-15（圖表死碼）、D10。**Consumes：** Stage 2 的 `AppClock`。

**白名單：** `Models/NetworkDataPoint.swift`、`Services/NetworkHistoryRecorder.swift`、`Views/NetworkChartView.swift`、`Views/PopoverView.swift`、`Views/StatusBarController.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Utilities/L10n.swift`；新增 `Models/ChartSnapshot.swift`；測試。

**Produces：**

```swift
public struct NetworkDataPoint: Codable, Identifiable {
    public let id: UUID                   // regenerated on decode, not encoded
    public let timestamp: Date
    public let downloadSpeed, uploadSpeed: Double        // window average, bytes/s
    public let maxDownloadSpeed, maxUploadSpeed: Double  // window max, bytes/s
    public init(timestamp: Date, downloadSpeed: Double, uploadSpeed: Double,
                maxDownloadSpeed: Double? = nil, maxUploadSpeed: Double? = nil)
    public var maxDownloadMbps, maxUploadMbps: Double { get }
}
// NetworkHistoryRecorder 新增成員
public private(set) var revision: Int                   // +1 per new 10-second point
public private(set) var recentSamples: [NetworkDataPoint]   // 1 Hz ring, capacity 900
public func points(since cutoff: Date) -> [NetworkDataPoint] // 10s points older than the ring + ring samples

struct ChartPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let avgDownloadMbps, maxDownloadMbps, avgUploadMbps, maxUploadMbps: Double
}
struct ChartSnapshot {
    let points: [ChartPoint]
    let peakDownloadMbps, peakUploadMbps, averageDownloadMbps, averageUploadMbps: Double
    let availability: NetworkChartView.DataAvailability
    let coverageActual, coverageRequired, coveragePercentage: Double
    static func make(source: [NetworkDataPoint], range: NetworkChartView.TimeRange, now: Date, maxPoints: Int = 300) -> ChartSnapshot
}
// NetworkMonitorViewModel 新增成員（D10：跨 popover 開關保留，不持久化）
public var chartRange: NetworkChartView.TimeRange = .oneHour
public var showDownload = true
public var showUpload = true
public var chartBannerDismissed = false
```

### Task 5.1：10 秒點與逐秒環形緩衝

- [ ] **Step 1：寫 `HistoryBucketTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `pulse_maxPreserved` | CORE-17：每分鐘 8 秒 280 Mbps、52 秒 1 Mbps，5 分鐘 → 所有點 `maxDownloadMbps` 最大值 = 280，平均 38.2±0.5 |
| `oldFormat_decodes` | 舊 JSON（含 `id`，無 max）→ 解碼成功，max 等於 avg |
| `encoded_hasNoId` | 編碼結果不含 `"id"` |
| `ring_capacity900` | 1000 筆 → 900 筆，最舊被丟 |
| `points_mergesRingAndTenSecond` | 2 小時資料，`points(since: now-3600)` 時間遞增且不重複，最近 15 分鐘為 1 秒解析度 |
| `revision_advancesAtCap` | 達 8640 點後再加一點，`revision` 仍 +1（R4） |

- [ ] **Step 2：實作。** `recordSpeed` 每筆累積 sum、count、max，滿 10 秒收成一個點後歸零。`NetworkDataPoint` 自訂 `CodingKeys`（不含 id）與 `init(from:)`（max 用 `decodeIfPresent`，缺則等於 avg）。

### Task 5.2：ChartSnapshot

- [ ] **Step 1：寫 `ChartSnapshotTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `fewPoints_passThrough` | 100 點 → 100 點 |
| `n8640_atMost300` | 24 小時範圍 → `points.count ≤ 300` |
| `bucket_keepsMaxAndWeightedAvg` | 一桶內 [10, 500, 10] → max 500、avg 173.3 |
| `peak_fromFullResolution` | 尖峰只在一個原始點 → `peakDownloadMbps` 等於它 |
| `sortedAscending` | 時間嚴格遞增 |
| `empty_isEmptyAvailability` | 空來源 → `.empty`，不 crash |
| `availability_thresholds` | 涵蓋率 49%→insufficient、50%→partial、100%→complete；範圍 <300 秒有資料→complete |

- [ ] **Step 2：實作。** 依 `range.seconds` 過濾後等寬分桶，邏輯沿用 `NetworkChartView.swift:276-315`。

### Task 5.3：接上圖表、刪死碼

- [ ] **Step 1：改 `NetworkChartView`。** `@State private var selectedTimeRange` 改 `@Binding var timeRange`；`DataCollectionBanner` 的 `isDismissed` 改由 binding 傳入。新增 `@State private var snapshot`，在 `.onAppear`、`.onChange(of: historyRecorder.revision)`、`.onChange(of: timeRange)`、showDownload／showUpload 變動時重算；≤15 分鐘範圍另以 `historyRecorder.recentSamples.last?.timestamp` 當 onChange 依據。body 內不得再過濾資料。`StatisticsCardView` 改接 snapshot 的數值，不接陣列。
- [ ] **Step 2：改 marks。** ≥3 小時範圍只畫 `LineMark`、不畫 `AreaMark`，線用 `maxDownloadMbps`／`maxUploadMbps`；<3 小時維持 Area＋Line，線用 avg。全部 `.interpolationMethod(.monotone)`（解 UI-P3-11 過衝）。tooltip 在 ≥3 小時顯示峰值與平均，沿用既有 `L10n.chartTooltipPeak`、`chartTooltipAverage`。
- [ ] **Step 3：刪死碼。** `shortTermChartBasic`、`twentyFourHourChart*`、`ChartTooltipView24Hour`、`calculateSmartYAxisMax24Hour`、`getMaxYValue24Hour`、`findNearestHourlyDataPoint`。
- [ ] **Step 4：改 `PopoverView`。** `@State showDownload`、`showUpload` 移除，改 `viewModel.showDownload` 等；`NetworkChartView` 呼叫點改傳 `$viewModel.chartRange` 等 binding。

### Task 5.4：popover 釋放

- [ ] **Step 1：改 `StatusBarController`。** 依 `$S/audit/perf/patch-A-B.diff` 第一段：`setupPopover` 不建內容；`showPopover()` 在 `contentViewController == nil` 時新建；`popoverDidClose` 設 `popover?.contentViewController = nil`。該 diff 的第二段（Calendar 迴圈、節流）不採用，實測無效且 Stage 6 會整段刪。

**驗收：** `TEST`、`BUILD`。`grep -c "twentyFourHourData" $R/BandwidthECGPackage/Sources/BandwidthECGFeature/Views/NetworkChartView.swift` 為 0。

QA 副本（`RELEASE` 產物）實測，sampler 用 `python3 -I $S/audit/perf/sampler.py <pid> 45 1 <out.csv>`，開關 popover 用 `$S/audit/perf/ntrial.sh` 內的 `click()` 寫法（需終端機有輔助使用權限），狀態用 `osascript -l JavaScript $S/audit/perf/winlist.js <pid>` 確認：

- [ ] 運行 ≥5 分鐘後開啟再關閉，關閉 90 秒內 CPU mean <1.5%、footprint <70 MB（基準 4.81%／88.4 MB）。
- [ ] 重開 popover 後圖表正常、時間範圍與下載／上傳開關維持原選擇。截圖或 AX dump 佐證（工具在 `$S/audit/tools/`，用法見各 `.swift`）。PERF-03 當時沒有驗證重開後的內容，這是本 stage 必驗項。

- [ ] **CHECKPOINT 5**（新檔：`Models/ChartSnapshot.swift`、測試檔）

---

## Stage 6：歷史持久化、保留期、移除記憶體優化

**目標：** 歷史存檔案、每 60 秒寫一次；重啟保留 24 小時；移除重複的小時彙總與「優化記憶體」。

**Model／規模：** opus／L（淨刪約 500 行）。**處理：** CORE-09、18、19、32，PERF-06、08、09，UI-P2-8，UI-P3-15（剩餘死碼），D7、D9。**Consumes：** Stage 2 `BlobStore`、Stage 5 `NetworkDataPoint`。

**白名單：** `Services/NetworkHistoryRecorder.swift`、`Models/NetworkDataPoint.swift`、`Services/MemoryOptimizer.swift`（刪除）、`Services/ErrorHandler.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`ContentView.swift`、`Views/StatusBarController.swift`、`BandwidthECG/BandwidthECGApp.swift`、`Utilities/L10n.swift`、`Utilities/AppDependencies.swift`；測試。

**Produces：** `NetworkHistoryRecorder.init(defaults: UserDefaults = .standard, clock: AppClock = .live, store: any BlobStore = AppSupportBlobStore())`、`public func flush()`。檔案 `history-10s.json`，內容 `{"schemaVersion":1,"points":[...]}`。`oneHourData` 名稱不改（避免無謂改動，實為 24 小時）。

- [ ] **Step 1：寫 `NetworkHistoryRecorderTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `retention_24hAfterRelaunch` | CORE-18：跑 6 小時（2160 點）、flush、new recorder → 2160 點，舊版只剩 360 |
| `olderThan24h_dropped` | 25 小時前的點載入後被濾掉 |
| `maxPoints_capped` | 不超過 8640 |
| `writes_atMostEvery60s` | 模擬 600 秒 → `writeCount ≤ 11` |
| `tick_doesNotWrite` | 連續 59 秒無寫入 |
| `flush_writesPending` | 有未寫資料時 flush 寫一次，無變動時不寫 |
| `migration_fromDefaults` | 舊 key `networkHistory_oneHour` 有資料、無檔案 → 載入、寫檔、移除三個舊 key（含 `networkHistory_twentyFourHour`、`networkHistory_lastRecordTime`） |
| `migration_badBlob_preservedAndCleared` | 壞 blob → 原始 bytes 寫到 `history-legacy.corrupt`、舊 key 移除、空白開始、log 一次 |
| `truncatedFile_quarantined` | 半截 JSON → 隔離、不 crash |
| `futureSchema_quarantined` | `schemaVersion: 99` → 隔離、不覆寫 |
| `writeFailure_keepsDataAndRetries` | 失敗後資料仍在，下輪成功 |
| `clearHistory_persistsEmpty` | 清除後 new recorder 為空 |
| `encodedSize_8640_under1MB` | 8640 點編碼 <1,000,000 bytes（舊版 1.23 MB） |

- [ ] **Step 2：實作。** 刪 `currentHourData`、`twentyFourHourData`、`createInitialHourlyAggregates`、`startHourlyAggregation`、`checkForHourlyAggregation`、`aggregateHourlyData` 兩個多載、`updateCurrentHourAggregate`、`pruneOldData`、10 秒 timer。`Models/NetworkDataPoint.swift` 刪 `HourlyDataPoint`。寫入時機用 `clock.monotonic()` 判斷 ≥60 秒。
- [ ] **Step 3：`VM.flushPersistence()` 加 `historyRecorder.flush()`。** `AppDependencies.blobStore` 傳進 recorder。
- [ ] **Step 4：D9。** 刪 `Services/MemoryOptimizer.swift`、VM 的 `optimizeMemory`、`getMemoryStats`、`ContentView.swift:392-415` 記憶體區塊。
- [ ] **Step 5：刪死碼。** `StatusBarController.swift:102-152` 五個私有方法與 `import UserNotifications`；`ErrorHandler.migrateDataFromLegacyPath` 與 `BandwidthECGApp.init`（CORE-32：bundle ID 已改，舊資料夾不會出現在新容器）。刪除後用 `grep` 找出無引用的 L10n key 一併刪：`settingsMemory*`、`settingsOptimizeMemory*`、`notificationMemoryOptimized*`、`notificationPeaksReset*`、`notificationExportSuccessBody`。`VM.exportDataWithSavePanel`、`generateCSVContent` 留到 Stage 9 改寫。
- [ ] **Step 6：** `TEST`、`BUILD`。

**驗收：** `grep -rnE "twentyFourHourData|HourlyDataPoint|MemoryOptimizer|MemoryCleanupService|currentHourData|networkHistory_oneHour" $R/BandwidthECGPackage/Sources` 只剩遷移常數。QA 副本連跑 3 分鐘重啟：圖表資料仍在，`history-10s.json` mtime 間隔 ≥55 秒，container plist 沒有每 10 秒更新。

- [ ] **CHECKPOINT 6**（新檔：測試檔）。`MemoryOptimizer.swift` 的刪除會出現在 `git diff`，不需 `git add`。

---

## Stage 7：延遲、斷線、異常、通知

**目標：** 「連線穩定」反映真實連線，正常行為不再報異常，延遲區塊誠實，通知內容正確。

**Model／規模：** opus／L。**處理：** CORE-10、21、22、23、30、31，UI-P2-15、UI-P2-16、UI-P3-16，D11。**Consumes：** Stage 4 `onMeasurement`、`onEvent`。

**白名單：** `Services/LatencyMonitor.swift`、`Services/DisconnectTracker.swift`、`Services/NetworkAnomalyDetector.swift`、`Services/NotificationService.swift`、`Services/Seams/NotificationDelivering.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Views/PopoverView.swift`、`Views/MonthlyReportView.swift`、`Views/StatusBarController.swift`、`ContentView.swift`、`AppDelegate.swift`、`Utilities/L10n.swift`；測試。

**Produces：**

```swift
// LatencyMonitor 新增
public var isEnabled: Bool                       // key "latencyMonitoringEnabled", default true
public private(set) var hasMeasurement: Bool
public private(set) var consecutiveFailures: Int
// DisconnectTracker 新增
public var onConnectivityChange: ((Bool) -> Void)?
public func noteProbe(success: Bool)
public func handleSleep()
public func handleWake()
// NetworkAnomalyDetector 新增
public func updateConnectivity(pathSatisfied: Bool, probeFailures: Int)
public func recordConnectionDrop(duration: TimeInterval)
// NotificationService 新增
public private(set) var isAuthorized: Bool
public private(set) var lastDeliveryError: String?
```

### Task 7.1：延遲（CORE-21、D11、UI-P2-15）

R11 已裁決：維持 HEAD。

- [ ] **Step 1：寫 `LatencyMonitorBehaviorTests` 並確認失敗（`FakeLatencyProbe`）。**

| 測試 | 斷言 |
|---|---|
| `warmupSample_discarded` | 563、86、88 ms → 樣本窗只有 86、88，`onMeasurement` 兩次 success |
| `afterFailure_nextSampleIsWarmup` | 失敗後下一筆丟棄 |
| `jitter_ignoresWarmup` | 同上序列 jitter <5 ms（舊版約 104） |
| `failure_noStaleValue` | 失敗 → `onMeasurement(.failure)`、`hasMeasurement=false`、`qualityScore=.unknown` |
| `quality_thresholds` | 119/9 good、120/9 fair、86/2 good、199/29 fair、200/29 poor、50/10 fair |
| `disabled_sendsNoProbe` | `isEnabled=false` 後 `startMonitoring`：probe 0 次、`.unknown` |
| `toggle_persisted` | 重建後仍 false；預設 true |

既有 5 個 `LatencyMonitorTests` 不改、需維持通過。

- [ ] **Step 2：實作。** `calculateQualityScore`：`latency < 120 && jitter < 10` good、`latency < 200 && jitter < 30` fair。`startMonitoring` 連跑兩次 probe（第一次暖機），讓使用者開啟時立即有值。文件註解說明量的是 HTTPS HEAD 來回，不是 ICMP RTT。`isEnabled` 的 `didSet` 開關 monitoring。
- [ ] **Step 3：改 UI。** `PopoverView.swift:401,411`：`!hasMeasurement` 顯示 `—`；`!isEnabled` 整段改顯示 `L10n.latencyDisabled`。`ContentView` 網路區塊加 `Toggle(L10n.settingsEnableLatency, isOn: $viewModel.latencyMonitor.isEnabled)`，`.help(L10n.settingsLatencyHelp)` 文案：`每 30 秒向 apple.com 送出一次 HEAD 請求以量測延遲，不含你的監控資料。關閉後不再送出。`。`MonthlyReportView` 無延遲資料時顯示 `—`。

### Task 7.2：斷線（CORE-23、CORE-31）

- [ ] **Step 1：在 `DisconnectTrackerTests` 新增並確認失敗（`FakePathSource`、`TestClock`）。**

| 測試 | 斷言 |
|---|---|
| `pathLostThenRestored_oneEvent` | start、end、duration 正確 |
| `ispOutage_twoProbeFailures_oneEvent` | path 一直 satisfied，t0、t30 失敗，t300 成功 → 事件 t0–t300 |
| `singleProbeFailure_noEvent` | 失敗一次後成功 → 無事件 |
| `pathAndProbeOverlap_oneEvent` | 兩來源同時異常 → 只有一筆 |
| `sleep_closesOpenOutage` | t0 斷線、t10 `handleSleep` → 事件結束於 t10 |
| `pathLossDuringSleep_ignored` | sleep 期間 path 變動 → 無事件 |
| `wakeGrace_10s` | wake 後 10 秒內斷又回 → 無事件 |
| `interfaceType_keepsLastKnown` | CORE-31：wifi satisfied 後斷線 → 事件 `wifi`，非 `other` |

- [ ] **Step 2：實作。** `handle(_:)` 只在 satisfied 時更新 `lastKnownInterfaceType`。連續 2 次 probe 失敗視為斷線，開始時間取第一次失敗。手動關 Wi-Fi 無法與斷線區分，維持計入。延遲監測關閉時只靠 path。
- [ ] **Step 3：`StatusBarController` 註冊 `NSWorkspace.didWakeNotification`**，並在 Stage 4 的 `willSleepNotification` 處理內加 sleep。VM 轉呼叫 `disconnectTracker.handleSleep()`／`handleWake()`。

### Task 7.3：異常（CORE-10、CORE-22）

- [ ] **Step 1：寫 `NetworkAnomalyDetectorTests` 並確認失敗。** 情境對應 `$S/audit/core/h1/main.swift` 的 anomaly a–e。

| 測試 | 斷言 |
|---|---|
| `realOutage_notStable_oneDrop` | `updateConnectivity(pathSatisfied: false, ...)` → `isConnectionStable=false`；`recordConnectionDrop(600)` 後 `connectionDrops=1` |
| `sampleGap_noAnomaly` | 樣本間隔 28800 秒 → 無異常（舊版報 high） |
| `timerStall6s_noAnomaly` | 間隔 6 秒 → 無異常 |
| `downloadEnds_noSpeedDrop` | 100 Mbps 降到 0、連線正常 → 無異常 |
| `streaming_noAnomalies` | 分段串流 10 分鐘 → 0 筆 |
| `idleZero_noAnomaly` | 120 秒全 0、path 正常 → 無異常 |
| `pathDown_30sZero_zeroSpeed` | path 不通＋連續 30 秒 0 → 1 筆 |
| `pathDown_29sZero_none` | 29 秒 → 0 筆 |
| `drop_withProbeFailing_recorded` | 連續 5 秒低於均值 70% 且 probe 失敗 ≥2 → 1 筆 speedDrop |

- [ ] **Step 2：實作。** 刪時間差判定與 `lastDataTimestamp`。`speedDrop` 需連續 5 筆低於門檻且連線異常（path 不通或 probe 連續失敗 ≥2）。`zeroSpeed` 需連續 ≥30 筆且 path 不通。`isConnectionStable = pathSatisfied && probeFailures < 2`。刪 `pruneOldAnomalies`（上限 50 筆已足夠，唯一呼叫者於 Stage 6 刪除）。
- [ ] **Step 3：VM 接線。** `disconnectTracker.onEvent` → `recordConnectionDrop`；`onConnectivityChange`、`onMeasurement` → `updateConnectivity`、`noteProbe`。

### Task 7.4：通知（CORE-30、UI-P2-16）

- [ ] **Step 1：寫 `NotificationServiceTests` 並確認失敗（`FakeNotificationDelivery`）。**

| 測試 | 斷言 |
|---|---|
| `title_uploadTrigger_usesUploadPlan` | 方案 300/100、上傳 100 → 標題含 `100`，不含 `300` |
| `title_downloadTrigger_usesDownloadPlan` | 只有下載達標 → 標題含下載方案 |
| `testNotification_doesNotStartCooldown` | 測試通知後達標 → 仍送出 |
| `cooldown_oneHour` | 59 分鐘內第二次不送、60 分鐘後送 |
| `deliverFailure_surfaced` | delivery throw → `lastDeliveryError` 非 nil |
| `denied_flagged` | `requestAuthorization` 回 false → `isAuthorized=false` |

- [ ] **Step 2：實作。** 標題依觸發方向取方案，兩邊都觸發取較大值。刪 `badge` 與 `clearBadge`。`sendTestNotification` 不動 `lastNotificationTime`。
- [ ] **Step 3：前景顯示。** `Services/Seams/NotificationDelivering.swift` 加 `ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate`，`willPresent` 回 `[.banner, .sound]`；`AppDelegate` 啟動時設為 delegate 並持有。`ContentView` 通知區：`!isAuthorized` 顯示 `L10n.settingsNotificationDenied`，`lastDeliveryError` 非 nil 顯示錯誤。

**驗收：** `TEST`、`BUILD`。`grep -n "lastDataTimestamp\|content.badge" -r $R/BandwidthECGPackage/Sources` 無結果。真實斷線、通知橫幅列入人工驗證（ad-hoc 簽章下通知被系統拒絕）。

- [ ] **CHECKPOINT 7**（新檔：測試檔）

---

## Stage 8：設定與 app 生命週期接線

**目標：** 設定值真的生效且持久；破壞性動作要確認；污染峰值可單獨清除。

**Model／規模：** sonnet／L。**處理：** CORE-15、24，PERF-04、PERF-10，UI-P1-1、P1-2、P2-3、P2-5、P2-7、P2-9（UI 部分）、P3-1、P3-2、P3-3、P3-4、P3-9、P3-10、P3-14，D5（UI 入口）。**Consumes：** Stage 3 `clearAllTimePeak`。

**白名單：** `Models/UserPreferences.swift`、`AppDelegate.swift`、`ContentView.swift`、`Views/OnboardingView.swift`、`Views/PopoverView.swift`、`Views/StatusBarController.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Utilities/AppDependencies.swift`、`Utilities/L10n.swift`、`Config/Shared.xcconfig`；新增 `Services/Seams/LoginItemControlling.swift`、`Services/AppRelauncher.swift`、`Models/PanelFrameValidator.swift`；測試。

**Produces：**

```swift
public enum LoginItemStatus: Sendable, Equatable { case enabled, disabled, requiresApproval, unavailable }
public protocol LoginItemControlling: Sendable {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}
public struct SystemLoginItemController: LoginItemControlling { public init() }   // SMAppService.mainApp
// UserPreferences
public init(defaults: UserDefaults = .standard, loginItems: any LoginItemControlling = SystemLoginItemController())
public private(set) var launchAtLogin: Bool
public private(set) var launchAtLoginMessage: String?
public func setLaunchAtLogin(_ enabled: Bool)
enum PanelFrameValidator { static func isVisible(_ frame: CGRect, screens: [CGRect]) -> Bool }
enum AppRelauncher { @MainActor static func relaunch() }
```

### Task 8.1：Dock（CORE-24、PERF-10）

- [ ] **Step 1：寫 `UserPreferencesTests` 並確認失敗。** `showInDock_persistsAcrossInit`（設 true、重建仍 true）、`showInDock_defaultFalse`。`swift test` 下 `NSApp` 為 nil，`didSet` 改 `NSApp?.setActivationPolicy(...)`，否則測試會 crash。
- [ ] **Step 2：實作。** `init` 改 `userDefaults.object(forKey: "showInDock") as? Bool ?? false`，刪強制寫回。`Config/Shared.xcconfig` 加 `INFOPLIST_KEY_LSUIElement = YES`（scratch 已驗證進 Info.plist）。

### Task 8.2：登入時開啟（CORE-15、PERF-04、UI-P1-1）

- [ ] **Step 1：寫測試並確認失敗。**

| 測試（`FakeLoginItems`） | 斷言 |
|---|---|
| `initialValue_fromSystemStatus` | status enabled → `launchAtLogin=true`，不看 defaults |
| `enable_callsRegister` | `setLaunchAtLogin(true)` → fake 收到 true |
| `failure_rollsBackAndReports` | throw → 值回 false、`launchAtLoginMessage` 非 nil |
| `requiresApproval_opensSystemSettings` | status 轉 requiresApproval → 呼叫 `openSystemSettings`、有提示 |
| `oldDefaultsKey_ignoredAndRemoved` | 舊 `launchAtLogin=1`、status disabled → false，舊 key 被移除，不自動註冊 |

- [ ] **Step 2：實作。** `launchAtLogin` 不再寫 defaults。`AppDependencies` 加 `loginItems`。`ContentView.swift:288` 改自訂 `Binding(get:set:)` 呼叫 `setLaunchAtLogin`，下方顯示 message。app 不在 `/Applications` 或 `~/Applications` 時停用開關並顯示 `L10n.settingsLaunchAtLoginMoveHint`（PERF-04：translocation 路徑重開機後失效）。

### Task 8.3：方案欄位與設定預設（UI-P2-3、UI-P2-9）

- [ ] **Step 1：改 `ContentView.swift:66`** `networkSettingsExpanded = true`。
- [ ] **Step 2：抽 `PlanSpeedField`。** 內部 `@State text`，`.onSubmit` 與失焦時解析；空字串或非法值還原目前模型值，畫面不得與模型脫節（UI 實測空欄位顯示 placeholder 但模型仍 300）。Settings 與 Onboarding 共用。
- [ ] **Step 3：Onboarding 最後一頁** 欄位下方加 `L10n.onboardingPlanHint`「預設 300 Mbps，請改成你的方案速度」。

### Task 8.4：語言切換（UI-P2-7）

- [ ] **Step 1：** `ContentView` 語言 Picker 變動時跳 alert：`L10n.settingsLanguageRestartTitle`，按鈕「立即重新啟動」與「稍後」。
- [ ] **Step 2：** `AppRelauncher.relaunch()`：`NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration:)`，`createsNewApplicationInstance = true`，完成後 `NSApp.terminate(nil)`。

### Task 8.5：峰值管理（UI-P2-5、D5）

- [ ] **Step 1：寫 `ViewModelPeakTests.clearAllTimePeak_forwards`、`resetPeaks_keepsDailyRecords`**（重置不影響月報）並確認失敗。
- [ ] **Step 2：** VM 加 `clearAllTimePeak(_:)`。`PopoverView.swift:541` 與 `ContentView.swift:428` 的重置改 `.confirmationDialog`，文案 `L10n.resetConfirmMessage`：`將清除所有峰值與圖表歷史，月度報告不受影響。此動作無法復原，可先用「導出數據」備份。`。不做「重置前自動匯出」：D6 後所有匯出走存檔面板，無法靜默寫檔（對 UI-P2-5 建議的調整）。
- [ ] **Step 3：** `SpeedRow` 加 `onClear: (() -> Void)?`，有值時顯示 `xmark.circle` 小按鈕（`.help(L10n.peakClearHelp)`、`.accessibilityLabel`），按下先確認。`PopoverView` 四個歷史峰值列（雙欄兩個、單欄兩個）傳入。

### Task 8.6：Onboarding 與浮動面板

- [ ] **Step 1：寫 `PanelFrameValidatorTests` 並確認失敗。** `onScreen_true`、`disconnectedDisplay_false`（frame 在螢幕外）、`partialOverlap_100pt_true`、`partialOverlap_10pt_false`、`noScreens_false`。交集面積的寬高都需 ≥100pt 才算可見。
- [ ] **Step 2：** `StatusBarController.getSavedPanelFrame` 不通過時回 nil（UI-P3-10）。`init` 尾端 `isPinned` 為 true 時 `showFloatingPanel()`（UI-P3-9）。
- [ ] **Step 3：** `showOnboarding` 加 `NSApp.activate()`（UI-P3-2）。onboarding 視窗設 delegate，`windowWillClose` 寫 `hasCompletedOnboarding=true`（UI-P3-14）。VM 加 `let defaults: UserDefaults`，`hasCompletedOnboarding`、`floatingPanelFrame` 與 `OnboardingView.swift:118` 改用它。
- [ ] **Step 4：** `OnboardingView.swift:72-82` 的 `TabView` 改 `switch currentPage`（UI-P3-1）；`:176,185` 標籤寬度改 `.fixedSize()`（UI-P3-3）。
- [ ] **Step 5：** `ContentView.swift:203,215,255,298` 的 Picker 加 `.labelsHidden()`，語言 Picker 寬度改 180（UI-P3-4）。

**驗收：** `TEST`、`BUILD`。QA 副本：`hasCompletedOnboarding` 未設時視窗 `active=true`；勾 Dock 後重啟 `lsappinfo info -only ApplicationType <pid>` 為 `Foreground`，取消後為 `UIElement`，且無 Dock 圖示閃現。

人工驗證：登入項目重開機、輸入法下的方案欄位（見人工驗證清單）。

- [ ] **CHECKPOINT 8**（新檔：`Services/Seams/LoginItemControlling.swift`、`Services/AppRelauncher.swift`、`Models/PanelFrameValidator.swift`、測試檔）

---

## Stage 9：匯出與 entitlements

**目標：** 所有匯出在 sandbox 下可用、單位正確、失敗有回報。CORE-11 與 CORE-12 必須同 stage：只修權限會把錯五個數量級的數字交給使用者。

**Model／規模：** sonnet／M。**處理：** CORE-11、12、29，PERF-02、PERF-16.2，UI-P1-3、P1-4、P2-6。**Consumes：** Stage 5 `maxDownloadMbps`、Stage 6（`handleExportData` 已刪）。

**白名單：** `Config/BandwidthECG.entitlements`、`Services/DataExportService.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Views/PopoverView.swift`、`Views/MonthlyReportView.swift`、`Utilities/L10n.swift`；測試。

**Produces：**

```swift
extension DataExportService {
    public enum ExportFormat: Sendable { case recent24Hours, peakHistory }   // replaces the 3-case enum
    static func csv(_ format: ExportFormat, history: NetworkHistoryRecorder, peaks: PeakRecorder,
                    unit: UserPreferences.SpeedUnit, clock: AppClock) -> String
    static func write(_ csv: String, to url: URL) throws
    static func makeTimestampFormatter(timeZone: TimeZone) -> DateFormatter   // en_US_POSIX + gregorian
}
// NetworkMonitorViewModel
public func exportData(format: DataExportService.ExportFormat, completion: @escaping @MainActor (Result<URL?, Error>) -> Void)  // nil = cancelled
```

- [ ] **Step 1：寫 `DataExportTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `recent24h_mbps` | 100 Mbps 點 → 下載欄 `100.00`，不是 `12500000.00` |
| `recent24h_mbytes` | 單位 MB/s → `12.50` |
| `recent24h_includesPeakColumns` | 欄位：時間、平均下載、峰值下載、平均上傳、峰值上傳 |
| `peakHistory_unchanged` | 峰值 CSV 數值正確 |
| `timestamp_rocCalendar` | 系統曆法民國 → 年份 `2026` |
| `timestamp_buddhistCalendar` | 同上 |
| `write_failure_throws` | 寫到不存在目錄 → throw |
| `headers_useL10n` | 標題列等於 `L10n` 對應字串（`L10n.exportColumnTime` 等） |

- [ ] **Step 2：實作 CSV。** 呼叫 `formatSpeed(dataPoint.downloadMbps, unit:)`。`ExportFormat` 兩個 case（UI-P2-6：「今日」與「完整」讀同一陣列，合併為「最近 24 小時」）。檔名與 `DateFormatter` 用 `en_US_POSIX`、gregorian（CORE-29）。寫死的中文全改 L10n，含存檔面板 title、message、prompt。
- [ ] **Step 3：改 VM。** 刪 `generateCSVContent`、`exportDataWithSavePanel`、`DataExportService.exportToCSV` 的 Downloads 路徑。`exportData` 走 `showSavePanel` → `write`。
- [ ] **Step 4：改 entitlements。** `files.user-selected.read-only` 換成 `files.user-selected.read-write`；刪 `network.server`（全專案無 listener）。sandbox、`network.client` 不動。
- [ ] **Step 5：改 UI。** `PopoverView` 匯出選單兩項；成功 alert 文案改 `已成功導出`，加按鈕「在 Finder 中顯示」，不再自動搶焦點。`MonthlyReportView.exportReport` 改 `do/catch`，失敗顯示 alert，成功不寫 `try?`。

**驗收：** `TEST`、`BUILD`。`codesign -d --entitlements - --xml <app> | plutil -p -` 含 `user-selected.read-write`、不含 `read-only` 與 `network.server`。`grep -nP '[\x{4e00}-\x{9fff}]' $R/BandwidthECGPackage/Sources/BandwidthECGFeature/Services/DataExportService.swift` 無結果。

sandbox 實測：以新 entitlements 重簽 `$S/audit/perf/harness-src/` 的 harness，確認 Downloads 直寫路徑已無人使用；SavePanel 存檔列入人工驗證（ad-hoc 下 SavePanel 行為未知，正式判定需人工）。

- [ ] **CHECKPOINT 9**（新檔：測試檔）

---

## Stage 10：選單列與 popover 打磨

**目標：** 選單列警示落地（D18），寬度穩定，圖表與 popover 的顯示問題收尾。

**Model／規模：** sonnet／L。**處理：** D18，UI-P2-1、P2-2、P2-4、P2-10、P2-11、P2-12、P2-13，UI-P3-5、P3-6、P3-7、P3-8、P3-12、P3-13、P3-15（剩餘），PERF-16.1（標題重設）、PERF-16.6、PERF-16.8。**Consumes：** `NotificationService.threshold`（R12）。

**白名單：** `Views/StatusBarController.swift`、`Views/NetworkChartView.swift`、`Views/PopoverView.swift`、`ViewModels/NetworkMonitorViewModel.swift`、`Models/UserPreferences.swift`、`Services/PeakApproachTracker.swift`（只改 formatter）、`Extensions/Color+Adaptive.swift`、`AppDelegate.swift`、`Utilities/L10n.swift`；新增 `Models/MenuBarAlert.swift`、`Models/ChartScale.swift`；測試。

**Produces：**

```swift
public enum MenuBarAlertLevel: Int, Sendable, Comparable { case normal, warning, critical
    static func evaluate(downloadMbps: Double, uploadMbps: Double, planDownloadMbps: Double, planUploadMbps: Double, warningRatio: Double) -> MenuBarAlertLevel
}
struct MenuBarAlertTracker {                                   // holds the highest level for 3 seconds to avoid 1 Hz flicker
    mutating func update(_ level: MenuBarAlertLevel, at monotonic: TimeInterval) -> MenuBarAlertLevel
}
struct MenuBarTitle: Equatable {
    let text: String                                           // includes the non-color cue
    let level: MenuBarAlertLevel
    let accessibilityValue: String?
    static func make(base: String, level: MenuBarAlertLevel) -> MenuBarTitle
}
```

### Task 10.1：選單列（D18、UI-P2-10、11、12、PERF-16.1、16.8）

無障礙判斷：選單列底色隨桌布與深淺模式變動，橘字在淺色選單列對比約 2:1，顏色不足以傳達。因此一律加文字前綴（`▲ ` 警告、`▲▲ ` 超過 100%）與 VoiceOver 值；系統開啟「增強對比」時不上色，只留前綴。

- [ ] **Step 1：寫 `MenuBarAlertTests` 並確認失敗。**

| 測試 | 斷言 |
|---|---|
| `belowThreshold_normal` | 0.94 / 門檻 0.95 → normal |
| `atThreshold_warning` | 0.95 → warning |
| `at100Percent_critical` | 1.00 → critical |
| `uploadAlone_triggers` | 下載 0、上傳達標 → warning |
| `tracker_holds3Seconds` | critical 一筆後轉 normal：2.9 秒仍 critical、3.0 秒 normal |
| `title_hasTextCue` | warning 含 `▲ `；critical 含 `▲▲ `；normal 無 |
| `title_accessibilityValue` | warning、critical 非 nil，normal nil |
| `compactMode_hasArrows` | `.compact` → `↓288.9/↑15.2 Mbps` |
| `isPeakConcerning_usesConfiguredThreshold` | 門檻 0.98、比例 0.96 → false（R12） |

- [ ] **Step 2：實作 `Models/MenuBarAlert.swift`。** VM 的 `isPeakConcerning(speed:planSpeed:)` 改用 `notificationService.threshold`。`menuBarText` compact 改 `↓\(down)/↑\(up) \(unit)`。`.both` 格式不動（宣傳片對應 `↓ 182.4 ↑ 14.8 Mbps`）。刪 `MenuBarDisplayMode.description`、`L10n.settingsLanguageSection`。
- [ ] **Step 3：改 `StatusBarController.updateStatusBarTitle`。** 組 `MenuBarTitle`；與上次相同就 return（PERF-16.1）；`attributedTitle` 字型 `NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)`，warning 用 `.systemOrange`、critical 用 `.systemRed`，`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` 為 true 時不上色；`button.setAccessibilityValue(title.accessibilityValue)`。`withObservationTracking` 同時追蹤 `currentSpeed` 與 `notificationService.threshold`。
- [ ] **Step 4：事件監聽。** `setupEventMonitor` 拿掉 `.keyDown` 與 Esc 分支（PERF-16.8；也消除 UI §6 擔心的輸入監控權限）。`showPopover` 加 `NSApp.activate()`，讓 Esc 由 popover 自行處理。`setupPopover` 的 `contentSize` 改 580x700（UI-P3-6）。
- [ ] **Step 5：備援入口（UI-P3-12）。** `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`；右鍵顯示 `NSMenu`，項目「開啟 Bandwidth ECG」「結束」。選單列已滿時右鍵也按不到，所以再加 `AppDelegate.applicationShouldHandleReopen` → `statusBarController?.showPanelFromReopen()`（設 `isPinned = true`），使用者從 Finder 或 Spotlight 再開一次 app 就能叫出面板。不做「僅圖示模式」（新功能）。

### Task 10.2：圖表（UI-P2-1、2、4、P3-8、P3-13）

- [ ] **Step 1：寫測試並確認失敗。** `TimeRangeTests.segmentedSelection`：`.oneHour → .oneHour`、`.twentyFourHours → nil`。`ChartScaleTests`（把 `getMaxYValueShortTerm` 抽成純函式 `ChartScale.maxValue(mode:unit:...)`）：`fixedMBs_planBelowFloor`：MB/s、方案 300、無流量 → 上限 = 37.5×1.1 = 41.25，不是 110。
- [ ] **Step 2：參考線。** 方案值 > Y 軸上限時不畫 `RuleMark`，圖例在方案項目後加 `L10n.chartPlanOffscale(值)`「方案 300（超出範圍）」。
- [ ] **Step 3：分段控制。** `Picker` 綁 `Binding<TimeRange?>`，tag 用 `Optional(range)`；extended 被選時無高亮，點任一標準項都會觸發 set（解 UI-P2-2「回不到 1 小時」）。
- [ ] **Step 4：固定 Y 軸。** `:984` 改 `convertSpeed(100)` 為下限；`yAxisModeButtonLabel` 用換算後的值與單位。`L10n.chartYAxisFixedLabel` 參數改 `String`。
- [ ] **Step 5：** `pointerCursor` 加 `@State isHovering`，`.onDisappear` 時若仍 hovering 就 `NSCursor.pop()`。tooltip 兩列前加 `↓`／`↑`（UI-P3-8：不只靠顏色與形狀）。

### Task 10.3：popover

- [ ] **Step 1：`PopoverView.swift:95`** 改 `L10n.approachingSpeedLimit(down, up)`，顯示 `接近速率上限 (↓300 / ↑100 Mbps)`；help 說明「持續 30 秒達方案 80% 算一次」。
- [ ] **Step 2：** `SpeedRow`、`HourlyPeakRow` 標籤拿掉 `.frame(maxWidth: 80)`，用 `.lineLimit(1).fixedSize()`（UI-P3-5）。
- [ ] **Step 3：無障礙（UI-P3-7）。** 裝飾圖示 `.accessibilityHidden(true)`；Pin 與圖例按鈕加 `.accessibilityValue(on/off)`；Y 軸按鈕加 `.accessibilityLabel(L10n.chartYAxisAccessibility)`；`clock.arrow.circlepath` 選單加 label。
- [ ] **Step 4：對比（UI-P3-8）。** `Color.Adaptive.warning` 淺色模式改 `#9A3412`（pale orange 底上 ≥4.5:1），深色維持 `.orange`。其他 `.orange` 前景不動。
- [ ] **Step 5：`DateFormatter` 重用（PERF-16.6）。** `PopoverView.swift:585-589`、`PeakApproachTracker.swift:83-87`、`ChartTooltipView` 改 `static let`。

**驗收：** `TEST`、`BUILD`。QA 副本：`open $S/qa/BandwidthECG.app` 第二次 → 面板出現（winlist 佐證）；`sample <pid> 10` 閒置時 `setTitle` 次數為 0。選單列顏色肉眼確認列入人工驗證（本機選單列已滿）。淺色模式對比列入人工驗證。

- [ ] **CHECKPOINT 10**（新檔：`Models/MenuBarAlert.swift`、`Models/ChartScale.swift`、測試檔）

---

## Stage 11：在地化補齊

**目標：** en/ja/ko 介面不再混入繁中，並用測試防止再漏。必須在所有新增字串完成後做。

**Model／規模：** sonnet／M。**處理：** UI-P1-6、PERF-16.7、UI-P3-17（圖表系列名）。**Consumes：** Stage 2–10 新增的 L10n key。

**白名單：** `BandwidthECG/Localizable.xcstrings`、`BandwidthECG.xcodeproj/project.pbxproj`（只動 `knownRegions`）、`Views/NetworkChartView.swift`、`Utilities/L10n.swift`；新增 `Tests/BandwidthECGFeatureTests/L10nCatalogTests.swift`。scratch：`$S/tools/fill-xcstrings.py`、`$S/translations.json`。

- [ ] **Step 1：寫 `L10nCatalogTests` 並確認失敗。** 用 `#filePath` 定位 `Utilities/L10n.swift` 與 `BandwidthECG/Localizable.xcstrings`。

| 測試 | 斷言 |
|---|---|
| `everyKeyInCatalog` | `String\(localized:\s*"([^"]+)"` 抓到的 key 全在 xcstrings |
| `noOrphanKeys` | xcstrings 沒有 L10n 以外的 key（現況孤兒 `chart.requires.macos13`） |
| `everyKeyTranslated` | 每個 key 都有 `en`、`ja`、`ko`、`zh-Hant`，`state == "translated"`，值非空 |
| `formatSpecifiersMatch` | 各語系 `%@`、`%d`、`%lld` 數量與型別一致，與 `defaultValue` 相同 |

- [ ] **Step 2：準備 `$S/translations.json`（key → en/ja/ko/zh-Hant）。** 涵蓋 R2 的 66 個缺 key 與 Stage 4–10 新增 key。用語沿用 xcstrings 既有翻譯。`report.recommend.*` 的 zh-Hant 值維持 `L10n.swift` 現值（D2）。
- [ ] **Step 3：寫 `$S/tools/fill-xcstrings.py` 並執行。** 讀寫時保留 Xcode 格式（`"key" : value`，鍵排序，`ensure_ascii=False`，2 空白縮排）；entry 結構照現有 key：`extractionState: manual`、`localizations.<lang>.stringUnit.{state,value}`。刪孤兒與 Stage 6、9、10 移除的 key。
- [ ] **Step 4：程式碼內寫死字串。** `NetworkChartView` 的 `series: .value("Type", "上傳"/"下載")` 改 `L10n.statsUpload`／`statsDownload`；`Picker("Time Range")` 改 L10n key。
- [ ] **Step 5：`project.pbxproj` 的 `knownRegions` 補 `"zh-Hant"`、`ja`、`ko`。**

**驗收：** `TEST`、`BUILD`。`plutil -convert json -o - <app>/Contents/Resources/ja.lproj/Localizable.strings` 筆數等於 L10n key 數。`grep -nP '[\x{4e00}-\x{9fff}]' -r $R/BandwidthECGPackage/Sources --include='*.swift'` 只剩 `L10n.swift` 的 `defaultValue`、註解、`errorHandler.log` 內部 log、`NetworkMonitorError.errorDescription`（log 用，不顯示於 UI）。QA 副本加 `-AppleLanguages '(ja)'` 啟動，popover 與月報截圖無繁中（與 `$S/audit/ui/30-ja-after-restart.png` 對照）。

- [ ] **CHECKPOINT 11**（新檔：`L10nCatalogTests.swift`）

---

## Stage 12：專案中繼資料與文件

**目標：** Info.plist、圖示、語言模式與文件全部與現況一致。README 的效能數字留給 Stage 15。

**Model／規模：** sonnet／M。**處理：** PERF-14（網站以外部分）、PERF-16.3、16.4、16.5、16.9，UI-P2-12（README）、UI-P3-17，D8（文件）。

**白名單：** `BandwidthECG.xcodeproj/project.pbxproj`、`Config/Shared.xcconfig`、`BandwidthECG/Assets.xcassets/AppIcon.appiconset/*`、`Services/ErrorHandler.swift`、`Tests/BandwidthECGFeatureTests/BandwidthECGFeatureTests.swift`（刪除）、`README.md`、`AGENTS.md`、`CLAUDE.md`、`IMPLEMENTATION_PLAN.md`；測試。

以下 Step 1–3 已在 `$S/plan-verify` 副本驗證：app 與 UI test target 都能編譯（`build-for-testing` 通過），`xctestplan` 不再進 Resources，Info.plist 鍵正確。

- [ ] **Step 1：pbxproj 例外。** 在 `/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */` 前加：

```
		8BD71C1F2DEE424400CEDD92 /* Exceptions for "BandwidthECG" folder in "BandwidthECG" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				BandwidthECG.xctestplan,
			);
			target = 8BC2655B2DEDD3F400F279A4 /* BandwidthECG */;
		};
```

並在 `8BC2655E2DEDD3F400F279A4 /* BandwidthECG */` 群組加 `exceptions = ( 8BD71C1F2DEE424400CEDD92 /* ... */, );`。

- [ ] **Step 2：** pbxproj 全部 `SWIFT_VERSION = 5.0;` 改 `6.0;`（PERF-16.3）。
- [ ] **Step 3：** `Config/Shared.xcconfig` 加 `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities`、`INFOPLIST_KEY_NSHumanReadableCopyright = © 2026 Bobo Chen`。
- [ ] **Step 4：App 圖示。** 用既有品牌圖 `website/public/favicon.svg`（不是改版）：`rsvg-convert -w <n> -h <n>` 產 16、32、64、128、256、512、1024 共 7 個檔，填進 `AppIcon.appiconset`，在 `Contents.json` 各項加 `filename`。
- [ ] **Step 5：`ErrorHandler` 日誌輪替（PERF-16.5）。** 寫 `ErrorHandlerLogTests.rotatesAboveOneMegabyte`：`ErrorHandler.init` 加 `logDirectory: URL = AppPaths.supportDirectory`；檔案 >1 MB 時改名 `error_log.1.txt` 再新建。實作，`logFileURL` 不再每次 `createDirectory`。
- [ ] **Step 6：** 刪空測試 `BandwidthECGFeatureTests.swift` 的 `example()`（整檔刪除，PERF-16.9）。
- [ ] **Step 7：README。** `:5` badge、`:56`、`:233` 改 macOS 14；`:57`、`:233` 改 Xcode 26；`:42` 視覺警示改為「選單列橘色／紅色並加 ▲ 標記」；`:108-111` 顯示格式改實作（下載在前，簡潔模式 `↓288.9/↑15.2 Mbps`）；資料夾結構的 entitlements 路徑改 `Config/`；popover 範例依實作；新增段落：延遲監測每 30 秒對 apple.com 送 HEAD、可在設定關閉；資料位置在 `~/Library/Containers/com.bobo52310.BandwidthECG`。`:45-46`、`:253` 的 CPU／記憶體留給 Stage 15。
- [ ] **Step 8：** `AGENTS.md` 刪 services 清單的 `speed test, leaderboard`，更新 `build.sh` 用法。`CLAUDE.md` 的 Development Notes 加：Debug bundle ID、QA 副本規則、不可直接啟動 Release。`IMPLEMENTATION_PLAN.md` 開頭加一行：最低版本已改 macOS 14，文中 13.0 fallback 作廢。

**驗收：** `TEST`、`BUILD`、`RELEASE`。`ls <app>/Contents/Resources` 無 `.xctestplan`、有 `Assets.car`。`plutil -p <app>/Contents/Info.plist` 含 `LSUIElement`、`LSApplicationCategoryType`、`NSHumanReadableCopyright`。`grep -n "macOS 13\|13\.0" $R/README.md $R/CLAUDE.md $R/AGENTS.md` 無結果。

- [ ] **CHECKPOINT 12**（新檔：`ErrorHandlerLogTests.swift`、圖示檔）

---

## Stage 13：官網 i18n 防護與內容真實性

**目標：** 全站沒有不實宣稱；ja/ko 與 zh/en 同 schema、定位一致；漏翻會在檢查時失敗。

**Model／規模：** sonnet／L。**處理：** WEB-P0-1..6、WEB-P1-4、P1-5、WEB-P2-7、P2-8、P2-9、P2-11、WEB-P3-4（locale 部分）、WEB-P3-5，PERF-14（網站部分），D11、D12、D14、D16。效能數字留給 Stage 15。

**白名單：** `website/src/i18n/**`、`website/src/components/**`；新增 `website/scripts/check-i18n.mjs`。

- [ ] **Step 1：寫 `website/scripts/check-i18n.mjs` 並確認失敗（exit 1）。** `node scripts/check-i18n.mjs` 檢查：(a) 4 份 JSON 扁平 key 集合相同（含陣列索引）；(b) 所有語系值不得符合 `/\bDMG\b|GitHub|App Store|Speedtest|Ookla|エンタープライズ|엔터프라이즈|プロフェッショナル級|전문가급|Network Peak Monitor|ネットワークピークモニター|네트워크 피크 모니터|macOS 13|Ventura|免費|無料|무료|\bfree\b|v1\.0\.0/i`；(c) 不得含下載動作用語 `/Download for|Download ·|Download now|Grab the|立即下載|下載並安裝|從.*下載|今すぐダウンロード|ダウンロードして|지금 다운로드|다운로드하/`。「下載」「ダウンロード」「다운로드」當速度方向使用是允許的。加 `--dist` 時再掃 `dist/**/*.html` 的文字節點套用 (b)。現況 ja/ko 應報 75 缺、42 多。不改 `package.json`。
- [ ] **Step 2：`src/i18n/index.ts`。** `t()` 找不到 key 時 `throw new Error`，不 fallback。`export type Messages = typeof zhHant`，其餘三份以 `const ja: Messages = jaJson` 約束。移除 `Features.astro:22`、`HowItWorks.astro:20`、`FAQ.astro:13`、`DownloadCTA.astro:12` 的 `as any`。
- [ ] **Step 3：改 `zh-Hant.json`、`en.json`。** 下表為定稿。en 其餘定位句（`header.features/howItWorks/faq`、`hero.titleEn/titleZh/subtitle/eyebrow`、各節 `sectionTitle*`、`sectionSubtitle`）改成 zh-Hant 的英譯，不用 Diagnostics、Clinical Notes 等醫療隱喻（D14）；ECG 只留在品牌名與視覺標籤。

| key | zh-Hant | en | ja | ko |
|---|---|---|---|---|
| `meta.title` | 不動 | `Bandwidth ECG — A minimal macOS menu bar network monitor` | `Bandwidth ECG — macOS メニューバーのネットワーク速度モニター` | `Bandwidth ECG — macOS 메뉴 막대 네트워크 속도 모니터` |
| `meta.description` | 不動 | `A minimal network speed monitor that lives in your menu bar. Track bandwidth peaks and daily usage, and let real data tell you whether you need a faster plan.` | `メニューバーに常駐するシンプルな通信速度モニター。帯域のピークと日々の使用量を記録し、回線プランのアップグレードが本当に必要かをデータで判断できます。` | `메뉴 막대에 상주하는 간단한 네트워크 속도 모니터. 대역폭 피크와 일일 사용량을 기록해 요금제 업그레이드가 정말 필요한지 데이터로 판단하세요.` |
| `header.subtitle` | 不動 | `MENU BAR UTILITY` | `メニューバーユーティリティ` | `메뉴 막대 유틸리티` |
| `header.download`、`hero.ctaDownload` | `即將推出` | `Coming soon` | `近日公開` | `출시 예정` |
| `hero.live` | `DEMO` | `DEMO` | `DEMO` | `DEMO` |
| `common.sampleData`（新） | `示意數據` | `SAMPLE DATA` | `サンプルデータ` | `샘플 데이터` |
| `howItWorks.steps[0].label` | `GET THE APP` | `GET THE APP` | `GET THE APP` | `GET THE APP` |
| `howItWorks.steps[0].title` | `取得 App` | `Get the app` | `アプリを入手` | `앱 받기` |
| `howItWorks.steps[0].description` | `取得 App 並開啟，它會常駐在選單列，不佔用 Dock。` | `Get the app and open it. It lives in the menu bar — no Dock clutter.` | `アプリを入手して起動するだけ。メニューバーに常駐し、Dock は使いません。` | `앱을 받아 실행하면 메뉴 막대에 상주하며 Dock을 차지하지 않습니다.` |
| `faq.items[0].question` | `需要付費嗎？` | `How much does it cost?` | `料金はかかりますか？` | `요금이 있나요?` |
| `faq.items[0].answer` | `價格與取得方式將在發行時公布。無論如何，App 不含廣告，也不需要註冊帳號。` | `Pricing and availability will be announced at launch. Either way: no ads, no account required.` | `価格と入手方法は公開時にお知らせします。いずれの場合も、広告はなく、アカウント登録も不要です。` | `가격과 배포 방식은 출시 때 안내해 드립니다. 어느 쪽이든 광고는 없으며 계정 등록도 필요하지 않습니다.` |
| `faq.items[1].answer` | `不會。所有監控數據只儲存在你的 Mac 本機，這不是雲端服務。為了量測網路延遲，App 預設每 30 秒向 apple.com 送出一次 HEAD 請求（可在設定關閉），請求中不含任何監控數據。` | `No. Readings are stored only on your Mac — this is not a cloud service. To measure latency, the app sends a HEAD request to apple.com every 30 seconds by default (you can turn this off in Settings). It contains none of your readings.` | `いいえ。監視データはすべてお使いの Mac のローカルにのみ保存され、クラウドサービスではありません。遅延を測るため、既定で 30 秒ごとに apple.com へ HEAD リクエストを送信します（設定でオフにできます）。監視データは含まれません。` | `아니요. 모든 모니터링 데이터는 사용자의 Mac에만 저장되며 클라우드 서비스가 아닙니다. 지연 시간을 측정하기 위해 기본적으로 30초마다 apple.com으로 HEAD 요청을 보내며(설정에서 끌 수 있음), 여기에는 모니터링 데이터가 포함되지 않습니다.` |
| `faq.items[2].answer` | `支援 macOS 14.0 (Sonoma) 及以上版本，Apple Silicon 與 Intel 皆原生支援。` | `macOS 14.0 (Sonoma) and later. Apple Silicon and Intel are both native.` | `macOS 14.0 (Sonoma) 以降をサポートしています。Apple Silicon と Intel の両方にネイティブ対応しています。` | `macOS 14.0 (Sonoma) 이상을 지원합니다. Apple Silicon과 Intel을 모두 네이티브로 지원합니다.` |
| `faq.items[4].answer` | `只需將應用程式移至垃圾桶即可。若想一併清除所有紀錄，請再刪除 ~/Library/Containers/com.bobo52310.BandwidthECG 資料夾。` | `Drop the app in the Trash. To clear all recorded readings too, also remove ~/Library/Containers/com.bobo52310.BandwidthECG.` | `アプリをゴミ箱に移動するだけです。記録もすべて削除するには、~/Library/Containers/com.bobo52310.BandwidthECG フォルダも削除してください。` | `앱을 휴지통으로 이동하면 됩니다. 기록까지 모두 삭제하려면 ~/Library/Containers/com.bobo52310.BandwidthECG 폴더도 삭제하세요.` |
| `download.sectionSubtitle` | `本機運作、極致輕量。讓數據成為你判斷網路方案的依據。` | `Local and lightweight. Decide with data, not gut feel.` | `ローカルで動作し、とても軽量。回線プランを見直す判断を、データで支えます。` | `로컬에서 동작하고 매우 가볍습니다. 요금제를 바꿀지 판단하는 일을 데이터로 돕습니다.` |
| `download.requirements` | `需要 macOS 14.0 或以上 · Apple Silicon 與 Intel` | `Requires macOS 14.0+ · Apple Silicon & Intel` | `macOS 14.0 以降が必要 · Apple Silicon / Intel` | `macOS 14.0 이상 필요 · Apple Silicon / Intel` |
| `download.badge`（新，取代寫死字串） | `即將推出 · macOS 14+` | `Coming soon · macOS 14+` | `近日公開 · macOS 14+` | `출시 예정 · macOS 14+` |
| `download.dosage`（新） | `常駐選單列 · 本機運作` | `Always on · Runs locally` | `常駐 · ローカル動作` | `상주 · 로컬 동작` |
| `download.features[0]` | `無廣告・免註冊` | `No ads · No account` | `広告なし・登録不要` | `광고 없음 · 가입 불필요` |
| `download.features[1]` | `不收集使用資料` | `100% local — no data uploaded` | `使用データを収集しません` | `사용 데이터를 수집하지 않습니다` |
| `footer.disclaimer` | `非醫療器材，僅用於網路狀態觀察。` | 不動 | `医療機器ではありません。ネットワークの状態確認のみを目的としています。` | `의료기기가 아닙니다. 네트워크 상태 확인용입니다.` |

  其他：zh 第五項功能把「無需連線雲端」改「不上傳至任何雲端」；en 第五項 subtitle 改 `No cloud storage`、description 改 `Every reading stays on your Mac. No accounts, no analytics, no uploads.`；en 第三項 description 改 `Nine time windows, from 1 minute to 24 hours, to see both micro-spikes and long-term shape.`、tag 改 `9 STRIPS`。CPU／RAM 句子與 `download.features[2]` 本 stage 不動，ja/ko 照 zh 翻，Stage 15 統一處理。刪 key：`header.github`、`download.ctaDownload`、`download.ctaGithub`、`howItWorks.steps[].runtime`、`howItWorks.steps[].no`，以及 WEB-P3-4 列的 14 個未使用 key。

- [ ] **Step 4：改元件。** `Hero.astro:135` 改 14；`DownloadCTA.astro:52` 改 `t('download.badge')`；`:75` 改 `t('download.dosage')`；`:31,99` 刪日期列；`HowItWorks.astro:35-38`（`~ 90 SECONDS`）與 `:53-56`（RUNTIME）整段刪；`Footer.astro:47,56` 走 i18n；`:77-80` 的 `SYSTEMS NOMINAL` 與 `v1.0.0` 改成單一 `PRE-RELEASE` 標籤；`LanguageSwitcher.astro:19` 走 `header.switchLanguage`；`ChartDemo.astro:121,124` 走 i18n，`14:41` 改 `14:29`，Y 軸刻度與 `PLAN CEILING` 線對齊，尖峰不超過天花板。Hero 監視器與 ChartDemo 標頭加 `{t('common.sampleData')}`。風格標籤（RECORDING、LEAD I、CALIBRATION）維持英文（D16）。
- [ ] **Step 5：重建 `ja.json`、`ko.json`。** 以 zh-Hant.json 為結構與語意來源，逐 key 翻譯；刪舊 schema 的 42 個 key（含 `speedTest`、第 7 張 feature）。定位用「メニューバーのシンプルなツール」「간단한 메뉴 막대 도구」，不用エンタープライズ、プロフェッショナル級、엔터프라이즈、전문가급。`features.items[].no` 等數字與風格標籤照 zh。
- [ ] **Step 6：** `node scripts/check-i18n.mjs` 應 exit 0。`WEB`。`node scripts/check-i18n.mjs --dist` 應 exit 0。

**驗收：** 上述三個指令；`node $S/audit/web/scripts/keys.mjs $R/website/src/i18n/locales` 顯示 4 語系 key 相同。人工讀一次 ja、ko 成品（agent 讀）：無中英日混雜句。`git -C $R diff --stat -- website/package.json website/astro.config.mjs website/package-lock.json` 與 `stage-0-baseline.patch` 內容一致。

- [ ] **CHECKPOINT 13**（新檔：`website/scripts/check-i18n.mjs`）

---

## Stage 14：官網互動、無障礙、SEO、標頭

**目標：** 手機可導覽與切語言，假按鈕消失，Lighthouse 扣分項歸零，安全標頭補齊。

**Model／規模：** sonnet／M。**處理：** WEB-P1-1、P1-2、P2-1、P2-2、P2-3、P2-4、P2-6、P2-10，WEB-P3-1、P3-2、P3-3、P3-4（其餘）、P3-6、P3-7。**Consumes：** Stage 13。

**白名單：** `website/src/layouts/Layout.astro`、`website/src/components/**`、`website/src/pages/**`、`website/src/styles/global.css`、`website/src/i18n/**`、`website/public/_headers`、`website/public/site.webmanifest`、`website/README.md`；新增 `website/.node-version`。

- [ ] **Step 1：`Header.astro`（WEB-P1-1）。** `<LanguageSwitcher />` 移出 `hidden lg:flex`，所有寬度可見。漢堡鈕加 `aria-expanded`、`aria-controls="mobile-nav"`，約 10 行 script 切換 `#mobile-nav`（4 個錨點連結），點連結後收起。
- [ ] **Step 2：`ChartDemo.astro:75-80`（WEB-P1-2）。** 六個 `<button>` 改 `<span>`，拿掉 hover 與 tab stop，`15m` 維持高亮樣式。
- [ ] **Step 3：`Layout.astro`（WEB-P2-1）。** `hreflang` 與 x-default 改 `new URL(href, Astro.site).href`；x-default 維持指向 `/`（D17）。Layout 加 `noindex` prop：`404.astro` 傳入，輸出 `robots noindex`、不輸出 canonical 與 hreflang。
- [ ] **Step 4：`global.css`，依序。** 先做對比：`--color-ink-3` 改 `#64748B`，加 `--color-red-text: #DC2626`、`--color-amber-text: #B45309`，文字用途改用它們，9/10px 小字上調到 11px；確認後才把 `.eyebrow`、`.mono-label`、`.readout`、`.btn-*`、`.stamp` 包進 `@layer components`（WEB-P2-3 順序要求）。`Footer.astro:43,52` 的 `<h4>` 改 `<p class="mono-label">`（WEB-P2-2）。加 reduced-motion：`html { scroll-behavior: auto }`（WEB-P3-6）。
- [ ] **Step 5：語言切換（WEB-P2-4、P3-1）。** 加 `aria-expanded`、`aria-haspopup`；Escape 關閉並還焦點；`<a>` 加 `lang`、`hreflang`；`<nav aria-label>`；click 時保留 `location.hash`。
- [ ] **Step 6：`public/_headers`（WEB-P2-6）。** 加 web.md P2-6 的 HSTS（不含 `includeSubDomains`、`preload`）、COOP、CSP 三行。字型維持 Google Fonts（D15），所以 CSP 保留兩個 Google 網域。
- [ ] **Step 7：雜項。** `website/.node-version` 內容 `22.23.4`（WEB-P2-10）。`site.webmanifest` 色票統一 `#FFFFFF`、description 同步 en meta、`display: browser`；OG 補 `og:image:alt/width/height`、`og:locale:alternate`（WEB-P3-3）。`404.astro` 依 `Astro.url.pathname` 判斷語系連回首頁（WEB-P3-2）。刪 `Button.astro`；`SpeedTest.astro` 改名 `CalibrationStrip.astro` 並改 4 個頁面 import；`Layout.astro:13` 預設 description 改 zh 現行文案；`website/README.md` 改成本站說明（WEB-P3-4）。加 skip link、`<main id="main">`、svg `aria-hidden`；ja/ko title 分隔符統一 ` — `（WEB-P3-7）。Hero 的 h1 維持品牌設計，不改。

**驗收：**

- [ ] `WEB`、`node scripts/check-i18n.mjs --dist` exit 0。
- [ ] `cp -R $S/audit/web/lh-out $S/audit/web/lh-out-baseline`，啟動 `cd $R/website && PATH=$S/node-22.23.4/bin:$PATH npx astro preview --port 4399`，跑 `zsh $S/audit/web/scripts/run-lh.sh` 與 `node $S/audit/web/scripts/interact.mjs`。預期：`hreflang`、`color-contrast`、`heading-order` 三個 audit 全過；320、390、768 寬度語言切換可見、漢堡鈕可開合；Escape 可關語言選單；16 組無橫向捲動；CLS 無惡化。結束後關 preview。
- [ ] 以 Playwright 注入 `_headers` 的 CSP 到 4 語系頁面，0 violation（方法同 web.md P2-6）。
- [ ] `grep -n "compressHTML\|cssTarget" $R/website/astro.config.mjs` 兩項仍在。

CF Pages 的 `NODE_VERSION` 列入人工驗證（需看 dashboard）。

- [ ] **CHECKPOINT 14**（新檔：`website/.node-version`、`website/src/components/sections/CalibrationStrip.astro`）

---

## Stage 15：整體驗收與效能數字定案

**目標：** 用獨立驗收證明全案成立，依實測定案官網數字，回報未解事項。施工者不得驗收自己的 stage；本 stage 由 fresh agent 執行，對抗式審查用與施工不同的 agent。

**Model／規模：** opus／M。**Consumes：** 全部。

**白名單（只有 Step 3 能動）：** `website/src/i18n/locales/*.json`、`website/src/components/sections/Hero.astro`、`website/public/og-default.png`、`README.md`。scratch：`$S/final/`、`$S/tools/seed-history.py`。

- [ ] **Step 1：全測試與建置。**
  - `TEST`，`xcodebuild test`（同 Stage 1），`BUILD`，`RELEASE`，貼末 20 行與測試總數。
  - `xcodebuild archive -workspace $R/BandwidthECG.xcworkspace -scheme BandwidthECG -configuration Release -destination 'generic/platform=macOS' -archivePath $S/final/BandwidthECG.xcarchive > $S/logs/archive.log 2>&1`。檢查：`lipo -archs` 為 `x86_64 arm64`、`llvm_profile` 0、entitlements 為 sandbox＋`network.client`＋`user-selected.read-write`、CFBundleIdentifier 為真實 ID、`LSUIElement` true。不啟動。
  - `heap <QA pid> | grep NetworkMonitorViewModel` 只有 1 個實例；`leaks <QA pid>` 無自家模型洩漏。

- [ ] **Step 2：重新量測（D13）。** 用 `RELEASE` 產物的 QA 副本（保留 sandbox，footprint 才接近真實）。寫 `$S/tools/seed-history.py N`：把 N 點寫到 `~/Library/Containers/com.bobo52310.BandwidthECG.qa/Data/Library/Application Support/BandwidthECG/history-10s.json`，格式 `{"schemaVersion":1,"points":[...]}`，時間平均分布於最近 24 小時（舊 `seed.py` 寫 UserDefaults，已不適用）。`hasCompletedOnboarding` 要先設好。sampler：`python3 -I $S/audit/perf/sampler.py <pid> <秒> 1 <csv>`，彙總 `summarize.py`。popover 開關用 Stage 5 的方法並用 winlist 確認狀態。

| 情境 | 樣本 | 基準（修前） | 通過線 |
|---|---|---|---|
| a. 從未開 popover，閒置 | 300 秒 | 0.79% / 18.9 MB | CPU mean <1%、footprint <50 MB |
| b. N=360 開過再關 | 90 秒 | 4.81% / 88.4 MB | CPU mean <1%、footprint <50 MB |
| c. N=8640 開過再關 | 90 秒 | 54.45% / 300.9 MB | CPU mean <1%、footprint <50 MB |
| d. N=8640 popover 開著 | 45 秒 | 81.6% / 281 MB | CPU mean <15%、footprint <150 MB |

  指標一律 phys footprint（Activity Monitor「記憶體」），不用 RSS。記錄機型、macOS 版本、load average、日期。結果寫 `$S/final/perf-results.md`（給下一步用）。d 未過要回報為 bug，不是調整通過線。

- [ ] **Step 3：依 D13 定案官網數字。**
  - **a、b、c 全過：** 保留條件式宣稱。zh `閒置時 CPU 低於 1%、記憶體低於 50 MB（<機型>，macOS <版本>，<日期> 量測）`，其餘語系同義。
  - **任一未過：** 移除數字（R15 預期此情況機率高）。Hero 三格改 `1 Hz`、`1m–24h`、`macOS 14+`；相關句改 zh `原生輕量設計，常駐選單列`／en `Native and lightweight, lives in the menu bar`／ja `ネイティブで軽量、メニューバーに常駐`／ko `네이티브 경량 설계, 메뉴 막대 상주`。
  - 位置：`Hero.astro:126-132`；各語系 `features.items[5]`、`faq.items[3]`、`download.features[2]`；README `:45-46,253`。`CLAUDE.md` 的 Target performance 是目標，不動。
  - `og-default.png`：`macOS 13+` 一定要改。用 `magick` 覆蓋底部一行後重寫為 `macOS MENU BAR · macOS 14+`（數字依上方結果決定是否保留），字型 Menlo，顏色 `#94A3B8`，尺寸維持 1200×630，並目視確認。
  - 改完跑 `WEB`、`node scripts/check-i18n.mjs --dist`。

- [ ] **Step 4：反向比對覆蓋表。** 對下方覆蓋表逐列找證據（測試名、`檔案:行號` 或指令輸出），找不到列為未完成。`grep -rn "isDateInToday\|if_data64\|try? csv.write" $R/BandwidthECGPackage/Sources` 無結果。

- [ ] **Step 5：對抗式審查。** 派 fresh opus agent，只給 diff（`git -C $R diff`）與「定案決策」「Global Constraints」，不給施工過程。重點：資料遺失路徑、Swift 6 隔離、DST 與時區、遷移順序、sandbox 下檔案路徑。發現的問題回到對應 stage 修，修完重跑 Step 1。

- [ ] **Step 6：宣傳片宣稱核對（`docs/design/promo-intro-v2-zh-tw`，只回報不修改）。**

| 片中宣稱 | 核對方式 |
|---|---|
| 每秒聽一次 | `NetworkMonitor` timer 1 Hz |
| 每天的尖峰，都留下時間和數字 | 今日與歷史峰值有時間。`DailyRecord` 只存數字，過去日子沒有時間，預期需回報為「部分成立」 |
| 方案 1000 Mbps、最高 284.6、使用率 28%、可考慮降級方案 | `RecommendationTests.promoScenario_downgrade`；上傳 96.2/600 = 16%；片中 30 天 ≥14 天 |
| 選單列 `↓ 182.4 ↑ 14.8 Mbps` | `.both` 格式未變 |
| 尖峰 284.6 不變色 | 28% 低於警示門檻，D18 不觸發 |
| 資料只留在你的 Mac | 僅 HEAD 探測對外，不含資料 |
| 即將推出 · bandwidth-ecg.bobochen.dev | 與 D12 一致 |
| `DESIGN.md` 引用 `L10n.swift:328`、`MonthlyReportView.swift:189`、`NetworkMonitorViewModel.swift:172` | 行號可能已移動，字串與語意要相同 |

- [ ] **Step 7：環境與範圍。** 真實容器 plist mtime 與 Stage 1 記錄一致（若使用者自己開過 app 需註明）。`git -C $R status --short` 與 `stage-0-status.txt` 比對：`TODO.md`、`docs/design/`、`docs/promo/`、`BUSINESS_STRATEGY.md`、`website/package.json`、`website/package-lock.json`、`website/astro.config.mjs` 內容與 baseline 相同。repo 根目錄無 `default.profraw`。沒有 commit、沒有 push、沒有部署。

- [ ] **Step 8：回報 team-lead。** 內容：測試總數、四情境數字與 D13 結果、未完成項目、人工驗證清單、宣傳片核對結果。另列使用者記憶需更新（施工者不改）：`MEMORY.md` 的 App Support 路徑實際在容器內、`ErrorHandler` 遷移 helper 已刪、Debug bundle ID 已改。

- [ ] **CHECKPOINT 15**（新檔：無，或 Step 3 產生者）

---

## 人工驗證清單

自動化做不到的項目。Stage 15 回報時逐項標「待人工」。

| 項目 | 為何自動化做不到 | 替代驗證（已做） | 人工步驟 |
|---|---|---|---|
| 選單列橘／紅色與 ▲ 外觀 | 本機選單列已滿，status item 看不到 | `MenuBarAlertTests`；AX 讀 `attributedTitle` | 收掉其他選單列項目，用 iperf 或大檔下載逼近方案 |
| 選單列寬度穩定 | 同上 | `NSFont` 量測、`sample` 無 setTitle | 目視 |
| 真實 status item 點擊、右鍵選單 | 同上 | `System Events` click；`applicationShouldHandleReopen` | 收掉其他項目後左右鍵各點一次 |
| 方案欄位輸入 0、負值、空白 | 輸入法（唯音）吞 CGEvent 數字鍵 | `PlanSpeedTests`；AX 設值 | 切英文輸入法後實際輸入 |
| 通知橫幅、權限拒絕提示 | ad-hoc 簽章被系統拒絕（`UNErrorDomain Code=1`） | `NotificationServiceTests` | Developer 簽章版實測 |
| 匯出 SavePanel 實際寫檔 | SavePanel 在系統程序，ad-hoc 下行為未知 | CSV 單元測試、entitlements 檢查 | Developer 簽章版匯出兩種格式與月報 |
| 登入時開啟 | 需重開機；`SMAppService` 在 ad-hoc 下可能失敗 | `FakeLoginItems` 測試 | 放到 `/Applications`，開啟、重開機、看系統設定 |
| 真實斷線、ISP 斷線、睡眠喚醒 | 需要實際環境；NWPath 行為未驗證（CORE-23） | `FakePathSource` 測試 | 拔網路線、拔路由器 WAN、闔蓋 |
| 淺色模式對比 | 本機為深色 | 色值計算 | 切淺色模式目視 |
| 多螢幕面板位置 | 需外接螢幕 | `PanelFrameValidatorTests` | 拔外接螢幕重開 |
| 24 小時實跑 | 時間成本 | 種子 8640 點 | QA 副本連跑 24 小時看 footprint 與檔案寫入 |
| CF Pages `NODE_VERSION` | 需看 dashboard | `.node-version` | push 前確認 Production 與 Preview ≥22.23.4 |
| Safari 的 `<summary>` 箭頭 | 本機只測 Chrome | 無 | Safari 開 FAQ 目視 |

## 不做

| 項目 | 理由 |
|---|---|
| PERF-13 公證、hardened runtime、Team | D6 |
| WEB-P2-5 移除 Noto Sans TC、自架 Inter | D15 |
| CORE-14「忽略超過方案 N 倍樣本」 | D3 只加註。CORE-14 其餘已處理 |
| CI（PERF §7、UI-P1-6、WEB-P2-11 的建議） | D6。改用 `L10nCatalogTests`、`check-i18n.mjs` 本機防護 |
| UI-P2-5「重置前自動匯出」 | sandbox 下匯出必走存檔面板，改為確認框提示先備份 |
| UI-P3-12「僅圖示模式」 | 新功能；改提供右鍵選單與 reopen 面板 |
| UI-P3-7 統計卡改真按鈕 | 圖例按鈕已提供同功能（D19 最少變動） |
| WEB-P3-7 zh 頁 h1 改中文 | 品牌設計 |
| WEB-P2-1 x-default 改 en | D17 |
| CORE-23(c) 區分手動關 Wi-Fi | 無可靠訊號，維持計入 |
| 新增 JSON-LD（WEB §4.3） | 發行前不加，避免填價格與下載網址 |
| 重寫 `oneHourData` 命名 | 無 finding 要求，純改名 |

## 覆蓋表

共 125 項：CORE 32、UI 40、PERF 24、WEB 29。Stage 15 Step 4 依此表反向比對。「合併」表示同一問題，修法與測試在被合併項。

| ID | Stage | 處置 |
|---|---|---|
| CORE-01 | 4 | 修。刪影子 VM，加 `.commands`（R3） |
| CORE-02 | 4 | 修。`DailyRecordStore`，月報即時推導 |
| CORE-03 | 3 | 修。per-interface 差值、讀取失敗保留基準、上限防呆（D5） |
| CORE-04 | 4 | 修。D2 規則、事件計數 |
| CORE-05 | 2 | 修。方案驗證與 `Int` clamp |
| CORE-06 | 3 | 修。跨日清 key，載入逐方向判斷 |
| CORE-07 | 4 | 修。summary 即時推導，月報加月份切換 |
| CORE-08 | 4 | 修。延遲進當日累積，失敗另計 |
| CORE-09 | 6 | 修。月報影響於 Stage 4 消失；小時彙總隨功能刪除 |
| CORE-10 | 7 | 修。連線狀態改由 tracker 與 probe 驅動 |
| CORE-11 | 9 | 修。與 CORE-12 同 stage |
| CORE-12 | 9 | 修。entitlements、全走 SavePanel、錯誤回報（R7） |
| CORE-13 | 4 | 修。schema version、`decodeIfPresent`、隔離備份；舊 key 唯讀。Stage 6 同型處理歷史檔 |
| CORE-14 | 4 | 部分。月報加註（D3）；N 倍過濾不做 |
| CORE-15 | 8 | 修。`SMAppService`，狀態以系統為準 |
| CORE-16 | 3 | 修。per-interface `&-`，不用 `if_data64`（R1） |
| CORE-17 | 5 | 修。10 秒窗 avg＋max |
| CORE-18 | 6 | 修。載入保留 24 小時 |
| CORE-19 | 6 | 修。Application Support 檔案，每 60 秒寫 |
| CORE-20 | 3 | 修。timer 加入 `.common` |
| CORE-21 | 7 | 修。暖機樣本、門檻校準，維持 HEAD（R11） |
| CORE-22 | 7 | 修。持續條件加連線交叉確認 |
| CORE-23 | 7 | 修 (a)(b)；(d) 於 Stage 4 `recordDisconnect` 切分；(c) 不做 |
| CORE-24 | 8 | 修 |
| CORE-25 | 4 | 修。併入 D2，雙向判定 |
| CORE-26 | 4 | 修。日紀錄保存當日方案 |
| CORE-27 | 4 | 修。`monthKey` 字串 |
| CORE-28 | 3 | 修。最小 dt 0.5 秒，跳過並累積 |
| CORE-29 | 9 | 修。月報月份於 Stage 4 改字串；CSV 用 POSIX formatter |
| CORE-30 | 7 | 修 |
| CORE-31 | 7 | 修。保留上一個已知介面 |
| CORE-32 | 6 | 修。全數刪除 |
| UI-P1-1 | 8 | 合併 CORE-15 |
| UI-P1-2 | 8 | 合併 CORE-24 |
| UI-P1-3 | 9 | 合併 CORE-12 |
| UI-P1-4 | 9 | 合併 CORE-11 |
| UI-P1-5 | 4 | 合併 CORE-02；加收集中提示 |
| UI-P1-6 | 11 | 修。`L10nCatalogTests` 防護（R2） |
| UI-P2-1 | 10 | 修 |
| UI-P2-2 | 10 | 修 |
| UI-P2-3 | 8 | 修 |
| UI-P2-4 | 10 | 修 |
| UI-P2-5 | 8 | 部分。確認框；不自動匯出 |
| UI-P2-6 | 9 | 修。合併為「最近 24 小時」，SavePanel，不搶焦點 |
| UI-P2-7 | 8 | 修。重啟提示 |
| UI-P2-8 | 6 | 合併 PERF-09（D9） |
| UI-P2-9 | 8 | 修。model 於 Stage 2，欄位於 Stage 8 |
| UI-P2-10 | 10 | 修（D18） |
| UI-P2-11 | 10 | 修 |
| UI-P2-12 | 10 | 修。README 於 Stage 12 |
| UI-P2-13 | 10 | 修（R12） |
| UI-P2-14 | 5 | 修。逐秒環形緩衝 |
| UI-P2-15 | 7 | 修 |
| UI-P2-16 | 7 | 修 |
| UI-P2-17 | 4 | 合併 CORE-01 |
| UI-P3-1 | 8 | 修 |
| UI-P3-2 | 8 | 修 |
| UI-P3-3 | 8 | 修 |
| UI-P3-4 | 8 | 修 |
| UI-P3-5 | 10 | 修 |
| UI-P3-6 | 10 | 修 |
| UI-P3-7 | 10 | 部分。補 label 與 value；統計卡不改 |
| UI-P3-8 | 10 | 修 |
| UI-P3-9 | 8 | 修。狀態歸零由 D10 解 |
| UI-P3-10 | 8 | 修 |
| UI-P3-11 | 5 | 修 |
| UI-P3-12 | 10 | 部分。右鍵選單與 reopen；僅圖示模式不做 |
| UI-P3-13 | 10 | 修 |
| UI-P3-14 | 8 | 修 |
| UI-P3-15 | 6 | 修。圖表死碼 Stage 5、其餘 Stage 6、`description` Stage 10 |
| UI-P3-16 | 7 | 合併 D11 |
| UI-P3-17 | 12 | 修。系列名於 Stage 11，App 圖示於 Stage 12 |
| PERF-01 | 5 | 修（R4） |
| PERF-02 | 9 | 合併 CORE-12 |
| PERF-03 | 5 | 修（D10） |
| PERF-04 | 8 | 合併 CORE-15 |
| PERF-05 | 4 | 合併 CORE-01 |
| PERF-06 | 6 | 合併 CORE-09 |
| PERF-07 | 3 | 合併 CORE-16 |
| PERF-08 | 6 | 合併 CORE-19 |
| PERF-09 | 6 | 修（D9） |
| PERF-10 | 8 | 合併 CORE-24；另加 `LSUIElement` |
| PERF-11 | 4 | 合併 CORE-02 |
| PERF-12 | 1 | 修（R6） |
| PERF-13 | 不做 | D6 |
| PERF-14 | 12 | 修。網站部分於 Stage 13，archive 於 Stage 15 重驗 |
| PERF-15 | 1 | 修（R5） |
| PERF-16.1 | 3 | 修。tolerance Stage 3，標題重設 Stage 10 |
| PERF-16.2 | 9 | 修 |
| PERF-16.3 | 12 | 修 |
| PERF-16.4 | 12 | 修 |
| PERF-16.5 | 12 | 修 |
| PERF-16.6 | 10 | 修 |
| PERF-16.7 | 11 | 合併 UI-P1-6 |
| PERF-16.8 | 10 | 修 |
| PERF-16.9 | 12 | 修。bundle ID 於 Stage 1 |
| WEB-P0-1 | 13 | 修 |
| WEB-P0-2 | 13 | 修（R10） |
| WEB-P0-3 | 13 | 修（D12） |
| WEB-P0-4 | 13 | 修（D12） |
| WEB-P0-5 | 13 | 修（D8、R8）。OG 圖於 Stage 15 |
| WEB-P0-6 | 13 | 修（R9） |
| WEB-P1-1 | 14 | 修 |
| WEB-P1-2 | 14 | 修 |
| WEB-P1-3 | 15 | 依 D13 實測定案 |
| WEB-P1-4 | 13 | 修（D12） |
| WEB-P1-5 | 13 | 修（D11） |
| WEB-P2-1 | 14 | 修；x-default 不變（D17） |
| WEB-P2-2 | 14 | 修 |
| WEB-P2-3 | 14 | 修 |
| WEB-P2-4 | 14 | 修 |
| WEB-P2-5 | 不做 | D15 |
| WEB-P2-6 | 14 | 修 |
| WEB-P2-7 | 13 | 修（D16） |
| WEB-P2-8 | 13 | 修（D16） |
| WEB-P2-9 | 13 | 修 |
| WEB-P2-10 | 14 | 修。CF dashboard 列人工驗證 |
| WEB-P2-11 | 13 | 修。`check-i18n.mjs`、`t()` throw，不接 CI |
| WEB-P3-1 | 14 | 修 |
| WEB-P3-2 | 14 | 修 |
| WEB-P3-3 | 14 | 修 |
| WEB-P3-4 | 14 | 修。locale 部分於 Stage 13 |
| WEB-P3-5 | 13 | 修 |
| WEB-P3-6 | 14 | 修 |
| WEB-P3-7 | 14 | 部分。h1 不改 |
