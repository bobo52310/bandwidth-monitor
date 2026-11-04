import Foundation

/// Localization helper for all user-facing strings
public enum L10n {
    // MARK: - App General
    public static let appTitle = String(localized: "app.title", defaultValue: "Bandwidth ECG")

    // MARK: - Buttons
    public static let buttonPin = String(localized: "button.pin", defaultValue: "Pin")
    public static let buttonSettings = String(localized: "button.settings", defaultValue: "Settings")
    public static let buttonBack = String(localized: "button.back", defaultValue: "返回")
    public static let buttonClose = String(localized: "button.close", defaultValue: "關閉")
    public static let buttonOK = String(localized: "button.ok", defaultValue: "OK")
    public static let buttonPrevious = String(localized: "button.previous", defaultValue: "上一步")
    public static let buttonNext = String(localized: "button.next", defaultValue: "下一步")
    public static let buttonGetStarted = String(localized: "button.getStarted", defaultValue: "開始使用")
    public static let buttonCancel = String(localized: "button.cancel", defaultValue: "取消")

    // MARK: - Tooltips
    public static let tooltipPinWindow = String(localized: "tooltip.pinWindow", defaultValue: "固定視窗")
    public static let tooltipBackToMain = String(localized: "tooltip.backToMain", defaultValue: "返回主頁面")

    // MARK: - Settings
    public static let settingsTitle = String(localized: "settings.title", defaultValue: "設定")

    // MARK: - Settings - Network Section
    public static let settingsNetworkSection = String(localized: "settings.network.section", defaultValue: "網路設定")
    public static let settingsNetworkPlan = String(localized: "settings.network.plan", defaultValue: "網路方案設定")
    public static let settingsDownloadLimit = String(localized: "settings.download.limit", defaultValue: "下載速度上限:")
    public static let settingsUploadLimit = String(localized: "settings.upload.limit", defaultValue: "上傳速度上限:")
    public static let settingsEnableAnomalyDetection = String(localized: "settings.anomaly.enable", defaultValue: "啟用異常偵測")
    public static let settingsAnomalyDetectionHelp = String(localized: "settings.anomaly.help", defaultValue: "自動偵測網路中斷、速度驟降等異常狀況")
    public static let settingsAnomalyHistory = String(localized: "settings.anomaly.history", defaultValue: "異常記錄:")
    public static let settingsClearHistory = String(localized: "settings.clear.history", defaultValue: "清除歷史")
    public static let settingsEnableLatency = String(localized: "settings.latency.enable", defaultValue: "啟用延遲監測")
    public static let settingsLatencyHelp = String(localized: "settings.latency.help", defaultValue: "每 30 秒向 apple.com 送出一次 HEAD 請求以量測延遲，不含你的監控資料。關閉後不再送出。")

    // MARK: - Settings - Display & Notification Section
    public static let settingsDisplayNotificationSection = String(localized: "settings.displayNotification.section", defaultValue: "顯示與通知")
    public static let settingsDisplaySettings = String(localized: "settings.display.settings", defaultValue: "顯示設定")
    public static let settingsDisplayUnit = String(localized: "settings.display.unit", defaultValue: "顯示單位:")
    public static let settingsUnitLabel = String(localized: "settings.unit.label", defaultValue: "單位")
    public static let settingsMenuBarMode = String(localized: "settings.menubar.mode", defaultValue: "選單列顯示模式:")
    public static let settingsDisplayMode = String(localized: "settings.display.mode", defaultValue: "顯示模式")
    public static let settingsPreview = String(localized: "settings.preview", defaultValue: "預覽:")
    public static let settingsNotificationSettings = String(localized: "settings.notification.settings", defaultValue: "通知設定")
    public static let settingsEnablePeakNotification = String(localized: "settings.notification.enable", defaultValue: "啟用峰值通知")
    public static let settingsPeakNotificationHelp = String(localized: "settings.notification.help", defaultValue: "當網路速度接近方案上限時發送通知")
    public static let settingsNotificationThreshold = String(localized: "settings.notification.threshold", defaultValue: "通知閾值:")
    public static let settingsThreshold = String(localized: "settings.threshold", defaultValue: "閾值")
    public static let settingsThresholdHelp = String(localized: "settings.threshold.help", defaultValue: "當速度超過此百分比時觸發通知")
    public static let settingsSendTestNotification = String(localized: "settings.notification.test", defaultValue: "發送測試通知")
    public static let settingsTestNotificationHelp = String(localized: "settings.notification.test.help", defaultValue: "測試通知功能是否正常")
    public static let settingsNotificationDenied = String(localized: "settings.notification.denied", defaultValue: "通知權限未開啟，請到「系統設定 > 通知」允許 Bandwidth ECG。")
    public static func settingsNotificationDeliveryFailed(_ reason: String) -> String {
        String(format: String(localized: "settings.notification.failed", defaultValue: "通知送出失敗：%@"), reason)
    }

    // MARK: - Settings - System & Maintenance Section
    public static let settingsSystemMaintenanceSection = String(localized: "settings.systemMaintenance.section", defaultValue: "系統與維護")
    public static let settingsSystemSettings = String(localized: "settings.system.settings", defaultValue: "系統設定")
    public static let settingsLaunchAtLogin = String(localized: "settings.launch.login", defaultValue: "登入時開啟")
    public static let settingsLaunchAtLoginMoveHint = String(localized: "settings.launch.login.moveHint", defaultValue: "請先把 App 移到「應用程式」資料夾，才能設定登入時開啟。")
    public static let settingsLaunchAtLoginNeedsApproval = String(localized: "settings.launch.login.needsApproval", defaultValue: "請在「系統設定 > 一般 > 登入項目」中允許 Bandwidth ECG。")
    public static func settingsLaunchAtLoginFailed(_ reason: String) -> String {
        String(format: String(localized: "settings.launch.login.failed", defaultValue: "無法變更登入時開啟：%@"), reason)
    }
    public static let settingsShowInDock = String(localized: "settings.show.dock", defaultValue: "顯示在 Dock")
    public static let settingsShowInDockHelp = String(localized: "settings.show.dock.help", defaultValue: "關閉後僅在選單列顯示")
    public static let settingsShowOnboarding = String(localized: "settings.show.onboarding", defaultValue: "重新顯示新手引導")
    public static let settingsShowOnboardingHelp = String(localized: "settings.show.onboarding.help", defaultValue: "再次查看應用程式功能介紹")
    public static let settingsErrorLog = String(localized: "settings.error.log", defaultValue: "錯誤日誌")
    public static let settingsEnableLogging = String(localized: "settings.logging.enable", defaultValue: "啟用錯誤記錄")
    public static let settingsLoggingHelp = String(localized: "settings.logging.help", defaultValue: "記錄錯誤和應用程式活動以協助診斷問題")
    public static let settingsLogSize = String(localized: "settings.log.size", defaultValue: "日誌大小:")
    public static let settingsManage = String(localized: "settings.manage", defaultValue: "管理")
    public static let settingsClearErrors = String(localized: "settings.clear.errors", defaultValue: "清除錯誤")
    public static let settingsClearLogs = String(localized: "settings.clear.logs", defaultValue: "清除日誌")
    public static let settingsExportLogs = String(localized: "settings.export.logs", defaultValue: "導出日誌")
    public static let settingsResetAllPeaks = String(localized: "settings.reset.peaks", defaultValue: "重置所有峰值記錄")

    // MARK: - Settings - Language
    public static let settingsLanguage = String(localized: "settings.language", defaultValue: "語言")
    public static let settingsLanguageRestartTitle = String(localized: "settings.language.restart.title", defaultValue: "需要重新啟動才會套用新語言")
    public static let settingsLanguageRestartMessage = String(localized: "settings.language.restart.message", defaultValue: "選擇「稍後」的話，下次開啟 Bandwidth ECG 時會改用新語言。")
    public static let settingsLanguageRestartNow = String(localized: "settings.language.restart.now", defaultValue: "立即重新啟動")
    public static let settingsLanguageRestartLater = String(localized: "settings.language.restart.later", defaultValue: "稍後")
    public static let languageSystem = String(localized: "language.system", defaultValue: "系統預設")
    public static let languageEnglish = String(localized: "language.english", defaultValue: "English")
    public static let languageTraditionalChinese = String(localized: "language.traditionalChinese", defaultValue: "繁體中文")
    public static let languageJapanese = String(localized: "language.japanese", defaultValue: "日本語")
    public static let languageKorean = String(localized: "language.korean", defaultValue: "한국어")

    // MARK: - Menu Bar Display Modes
    public static let menuBarModeBoth = String(localized: "menubar.mode.both", defaultValue: "顯示兩者")
    public static let menuBarModeDownloadOnly = String(localized: "menubar.mode.downloadOnly", defaultValue: "僅顯示下載")
    public static let menuBarModeUploadOnly = String(localized: "menubar.mode.uploadOnly", defaultValue: "僅顯示上傳")
    public static let menuBarModeCompact = String(localized: "menubar.mode.compact", defaultValue: "簡潔模式")

    // MARK: - Menu Bar Alert
    /// What VoiceOver adds to the menu bar button when the title carries a warning prefix.
    public static let menuBarAlertWarning = String(localized: "menubar.alert.warning", defaultValue: "接近方案上限")
    public static let menuBarAlertCritical = String(localized: "menubar.alert.critical", defaultValue: "已達方案上限")
    public static let menuBarMenuOpen = String(localized: "menubar.menu.open", defaultValue: "開啟 Bandwidth ECG")
    public static let menuBarMenuQuit = String(localized: "menubar.menu.quit", defaultValue: "結束")

    // MARK: - Accessibility
    /// The value of a toggle button whose state is otherwise shown by colour only.
    public static let accessibilityStateOn = String(localized: "accessibility.state.on", defaultValue: "開啟")
    public static let accessibilityStateOff = String(localized: "accessibility.state.off", defaultValue: "關閉")

    // MARK: - Chart Y-Axis Modes
    public static let chartYAxisModeAuto = String(localized: "chart.yaxis.auto", defaultValue: "自動縮放")
    public static let chartYAxisModeFixed = String(localized: "chart.yaxis.fixed", defaultValue: "固定上限")

    // MARK: - Peak Approach Section
    /// Each direction against its own plan. The key is new: the old one took one number.
    public static func approachingSpeedLimit(_ download: Int, _ upload: Int) -> String {
        String(format: String(localized: "peak.approaching.limit.pair", defaultValue: "接近速率上限 (↓%d / ↑%d Mbps)"), download, upload)
    }
    /// What counts as one time. The numbers come from `ReportRules`, so the text cannot drift
    /// from the rule it describes.
    public static func approachingHelp(seconds: Int, percent: Int) -> String {
        String(format: String(localized: "peak.approaching.help", defaultValue: "持續 %1$d 秒達方案 %2$d%% 算一次"), seconds, percent)
    }
    public static var approachingHelpCurrent: String {
        approachingHelp(
            seconds: Int(ReportRules.approachSustainSeconds),
            percent: Int((ReportRules.approachRatio * 100).rounded())
        )
    }
    public static let peakTimesUnit = String(localized: "peak.times.unit", defaultValue: "次")
    public static let peakTriggerTime = String(localized: "peak.trigger.time", defaultValue: "觸發時間")
    public static let peakNoApproachToday = String(localized: "peak.no.approach.today", defaultValue: "今日尚未接近速率上限")

    // MARK: - Statistics
    public static let statsDownload = String(localized: "stats.download", defaultValue: "下載統計 (Download Stats)")
    public static let statsUpload = String(localized: "stats.upload", defaultValue: "上傳統計 (Upload Stats)")
    public static let statsTodayPeak = String(localized: "stats.today.peak", defaultValue: "今日峰值")
    public static let statsAllTimePeak = String(localized: "stats.alltime.peak", defaultValue: "歷史總峰值")
    public static let statsHourlyPeak = String(localized: "stats.hourly.peak", defaultValue: "1小時峰值")

    // MARK: - Network Status
    public static let networkStatus = String(localized: "network.status", defaultValue: "網路狀態")
    public static let networkStable = String(localized: "network.stable", defaultValue: "穩定")
    public static let networkAbnormal = String(localized: "network.abnormal", defaultValue: "異常")
    public static func networkInterruptions(_ count: Int) -> String {
        String(format: String(localized: "network.interruptions", defaultValue: "%d 次中斷"), count)
    }
    public static func networkSpeedDrops(_ count: Int) -> String {
        String(format: String(localized: "network.speed.drops", defaultValue: "%d 次驟降"), count)
    }
    public static let networkNoAnomaliesRecently = String(localized: "network.no.anomalies", defaultValue: "近1小時無異常記錄")

    // MARK: - Time Ago
    public static let timeJustNow = String(localized: "time.just.now", defaultValue: "剛剛")
    public static func timeMinutesAgo(_ minutes: Int) -> String {
        String(format: String(localized: "time.minutes.ago", defaultValue: "%d分鐘前"), minutes)
    }
    public static func timeHoursAgo(_ hours: Int) -> String {
        String(format: String(localized: "time.hours.ago", defaultValue: "%d小時前"), hours)
    }
    public static func timeDaysAgo(_ days: Int) -> String {
        String(format: String(localized: "time.days.ago", defaultValue: "%d天前"), days)
    }
    public static func timeDaysHoursAgo(_ days: Int, _ hours: Int) -> String {
        String(format: String(localized: "time.days.hours.ago", defaultValue: "%d天%d小時前"), days, hours)
    }

    // MARK: - Export
    public static let exportData = String(localized: "export.data", defaultValue: "導出數據")
    public static let exportRecent24Hours = String(localized: "export.recent.24h", defaultValue: "導出最近 24 小時數據")
    public static let exportPeakHistory = String(localized: "export.peak.history", defaultValue: "導出峰值記錄")
    public static let exportDataHelp = String(localized: "export.data.help", defaultValue: "導出網路數據為 CSV 檔案")
    public static let exportSuccessTitle = String(localized: "export.success.title", defaultValue: "已成功導出")
    public static func exportSuccessDetail(_ fileName: String) -> String {
        String(format: String(localized: "export.success.detail", defaultValue: "已儲存為「%@」"), fileName)
    }
    public static let exportRevealInFinder = String(localized: "export.reveal.in.finder", defaultValue: "在 Finder 中顯示")
    public static let exportFailure = String(localized: "export.failure", defaultValue: "導出失敗")
    public static func exportFailureDetail(_ reason: String) -> String {
        String(format: String(localized: "export.failure.detail", defaultValue: "無法寫入檔案：%@"), reason)
    }

    // Save panel
    public static let exportPanelTitle = String(localized: "export.panel.title", defaultValue: "導出網路數據")
    public static let exportPanelMessage = String(localized: "export.panel.message", defaultValue: "選擇儲存位置")
    public static let exportPanelPrompt = String(localized: "export.panel.prompt", defaultValue: "導出")

    // CSV column headers and row labels. The unit is part of the header, so a spreadsheet reader
    // never has to guess whether a number is Mbps or MB/s.
    public static let exportColumnTime = String(localized: "export.column.time", defaultValue: "時間")
    public static func exportColumnAvgDownload(_ unit: String) -> String {
        String(format: String(localized: "export.column.avg.download", defaultValue: "平均下載 (%@)"), unit)
    }
    public static func exportColumnMaxDownload(_ unit: String) -> String {
        String(format: String(localized: "export.column.max.download", defaultValue: "峰值下載 (%@)"), unit)
    }
    public static func exportColumnAvgUpload(_ unit: String) -> String {
        String(format: String(localized: "export.column.avg.upload", defaultValue: "平均上傳 (%@)"), unit)
    }
    public static func exportColumnMaxUpload(_ unit: String) -> String {
        String(format: String(localized: "export.column.max.upload", defaultValue: "峰值上傳 (%@)"), unit)
    }
    public static let exportColumnType = String(localized: "export.column.type", defaultValue: "類型")
    public static func exportColumnPeakSpeed(_ unit: String) -> String {
        String(format: String(localized: "export.column.peak.speed", defaultValue: "峰值速度 (%@)"), unit)
    }
    public static let exportColumnPeakTime = String(localized: "export.column.peak.time", defaultValue: "發生時間")
    public static let exportRowTodayDownload = String(localized: "export.row.today.download", defaultValue: "今日下載峰值")
    public static let exportRowTodayUpload = String(localized: "export.row.today.upload", defaultValue: "今日上傳峰值")
    public static let exportRowAllTimeDownload = String(localized: "export.row.alltime.download", defaultValue: "歷史下載峰值")
    public static let exportRowAllTimeUpload = String(localized: "export.row.alltime.upload", defaultValue: "歷史上傳峰值")
    public static let exportRowHourDownload = String(localized: "export.row.hour.download", defaultValue: "1小時下載峰值")
    public static let exportRowHourUpload = String(localized: "export.row.hour.upload", defaultValue: "1小時上傳峰值")

    // MARK: - Actions
    public static let actionResetPeaks = String(localized: "action.reset.peaks", defaultValue: "重置峰值記錄")
    public static let resetConfirmTitle = String(localized: "reset.confirm.title", defaultValue: "重置所有峰值記錄？")
    public static let resetConfirmMessage = String(localized: "reset.confirm.message", defaultValue: "將清除所有峰值與圖表歷史，月度報告不受影響。此動作無法復原，可先用「導出數據」備份。")

    // MARK: - Clearing One Peak
    public static let peakDirectionDownload = String(localized: "peak.direction.download", defaultValue: "下載")
    public static let peakDirectionUpload = String(localized: "peak.direction.upload", defaultValue: "上傳")
    public static let peakClearHelp = String(localized: "peak.clear.help", defaultValue: "清除這個歷史峰值")
    public static let peakClearButton = String(localized: "peak.clear.button", defaultValue: "清除峰值")
    public static func peakClearAccessibility(_ direction: String) -> String {
        String(format: String(localized: "peak.clear.accessibility", defaultValue: "清除歷史%@峰值"), direction)
    }
    public static func peakClearConfirmTitle(_ direction: String) -> String {
        String(format: String(localized: "peak.clear.confirm.title", defaultValue: "清除歷史%@峰值？"), direction)
    }
    public static let peakClearConfirmMessage = String(localized: "peak.clear.confirm.message", defaultValue: "將清除這筆歷史最高紀錄，若今日峰值來自同一次測量也會一併清除。月度報告不受影響。此動作無法復原。")
    public static let actionQuitApp = String(localized: "action.quit.app", defaultValue: "退出應用程式")

    // MARK: - Onboarding
    public static let onboardingWelcomeTitle = String(localized: "onboarding.welcome.title", defaultValue: "歡迎使用 Bandwidth ECG")
    public static let onboardingWelcomeDescription = String(localized: "onboarding.welcome.description", defaultValue: "即時監控您的網路速度，追蹤峰值記錄，確保您的網路效能符合預期。")
    public static let onboardingFeature1 = String(localized: "onboarding.feature.1", defaultValue: "即時顯示上傳/下載速度")
    public static let onboardingFeature2 = String(localized: "onboarding.feature.2", defaultValue: "自動記錄今日、1小時和歷史峰值")
    public static let onboardingFeature3 = String(localized: "onboarding.feature.3", defaultValue: "互動式圖表視覺化網路流量")

    public static let onboardingNotificationTitle = String(localized: "onboarding.notification.title", defaultValue: "智慧通知提醒")
    public static let onboardingNotificationDescription = String(localized: "onboarding.notification.description", defaultValue: "當網路速度接近您的方案上限時，我們會及時通知您。")
    public static let onboardingNotificationFeature1 = String(localized: "onboarding.notification.feature.1", defaultValue: "可自訂通知閾值 (90%, 95%, 98%)")
    public static let onboardingNotificationFeature2 = String(localized: "onboarding.notification.feature.2", defaultValue: "避免過度使用頻寬")
    public static let onboardingNotificationFeature3 = String(localized: "onboarding.notification.feature.3", defaultValue: "1小時冷卻時間，避免通知干擾")

    public static let onboardingExportTitle = String(localized: "onboarding.export.title", defaultValue: "數據導出與分析")
    public static let onboardingExportDescription = String(localized: "onboarding.export.description", defaultValue: "輕鬆導出您的網路數據，進行深度分析。")
    public static let onboardingExportFeature1 = String(localized: "onboarding.export.feature.recent", defaultValue: "導出最近 24 小時數據")
    public static let onboardingExportFeature2 = String(localized: "onboarding.export.feature.2", defaultValue: "導出峰值記錄")
    public static let onboardingExportFeature3 = String(localized: "onboarding.export.feature.monthly", defaultValue: "導出每月報告")
    public static let onboardingExportFeature4 = String(localized: "onboarding.export.feature.4", defaultValue: "CSV 格式，方便使用 Excel 分析")

    public static let onboardingSetupTitle = String(localized: "onboarding.setup.title", defaultValue: "開始設定")
    public static let onboardingSetupDescription = String(localized: "onboarding.setup.description", defaultValue: "請設定您的網路方案速度上限，以便我們提供更準確的監控。")
    public static let onboardingPlanHint = String(localized: "onboarding.plan.hint", defaultValue: "預設 300 Mbps，請改成你的方案速度")

    public static let onboardingWindowTitle = String(localized: "onboarding.window.title", defaultValue: "歡迎使用 Bandwidth ECG")

    // MARK: - Notifications
    public static let notificationTestTitle = String(localized: "notification.test.title", defaultValue: "測試通知")
    public static let notificationTestBody = String(localized: "notification.test.body", defaultValue: "這是一個測試通知，用來確認通知功能正常運作。")
    public static func notificationApproachingLimit(_ speed: Int) -> String {
        String(format: String(localized: "notification.approaching.limit", defaultValue: "接近速率上限(%dMbps)"), speed)
    }
    public static func notificationDownloadReached(_ percentage: Int, _ speed: String) -> String {
        String(format: String(localized: "notification.download.reached", defaultValue: "下載速度已達到方案上限的 %d%% (%@ Mbps)"), percentage, speed)
    }
    public static func notificationUploadReached(_ percentage: Int, _ speed: String) -> String {
        String(format: String(localized: "notification.upload.reached", defaultValue: "上傳速度已達到方案上限的 %d%% (%@ Mbps)"), percentage, speed)
    }

    // MARK: - Anomaly Types
    public static let anomalyDownload = String(localized: "anomaly.download", defaultValue: "下載")
    public static let anomalyUpload = String(localized: "anomaly.upload", defaultValue: "上傳")
    public static func anomalyConnectionDrop(_ duration: String) -> String {
        String(format: String(localized: "anomaly.connection.drop", defaultValue: "連線中斷 %@ 秒"), duration)
    }
    public static func anomalySpeedDrop(_ direction: String, _ percentage: String, _ from: String, _ to: String) -> String {
        String(format: String(localized: "anomaly.speed.drop", defaultValue: "%@速度驟降 %@%% (從 %@ 降至 %@ Mbps)"), direction, percentage, from, to)
    }
    public static let anomalyZeroSpeed = String(localized: "anomaly.zero.speed", defaultValue: "網路速度為零")

    // MARK: - Chart Time Ranges
    public static let chartTimeRangeOneMinute = String(localized: "chart.timeRange.oneMinute", defaultValue: "1 分鐘")
    public static let chartTimeRangeFiveMinutes = String(localized: "chart.timeRange.fiveMinutes", defaultValue: "5 分鐘")
    public static let chartTimeRangeFifteenMinutes = String(localized: "chart.timeRange.fifteenMinutes", defaultValue: "15 分鐘")
    public static let chartTimeRangeThirtyMinutes = String(localized: "chart.timeRange.thirtyMinutes", defaultValue: "30 分鐘")
    public static let chartTimeRangeOneHour = String(localized: "chart.timeRange.oneHour", defaultValue: "1 小時")
    public static let chartTimeRangeThreeHours = String(localized: "chart.timeRange.threeHours", defaultValue: "3 小時")
    public static let chartTimeRangeSixHours = String(localized: "chart.timeRange.sixHours", defaultValue: "6 小時")
    public static let chartTimeRangeTwelveHours = String(localized: "chart.timeRange.twelveHours", defaultValue: "12 小時")
    public static let chartTimeRangeTwentyFourHours = String(localized: "chart.timeRange.twentyFourHours", defaultValue: "24 小時")

    // MARK: - Chart Y-Axis Labels & Tooltips
    /// `speed` is the plan with its unit, as shown on the axis ("300 Mbps", "37.5 MB/s"). The key
    /// is new: the old one took an `Int` and no unit.
    public static func chartYAxisFixedLabel(_ speed: String) -> String {
        String(format: String(localized: "chart.yaxis.fixedLabel.value", defaultValue: "固定 %@"), speed)
    }
    public static let chartYAxisAccessibility = String(localized: "chart.yaxis.accessibility", defaultValue: "Y 軸範圍")
    /// A plan line that does not fit the axis has no line; the legend says where it is.
    public static func chartPlanOffscale(_ plan: String) -> String {
        String(format: String(localized: "chart.plan.offscale", defaultValue: "方案 %@（超出範圍）"), plan)
    }
    public static let chartYAxisTooltipAuto = String(localized: "chart.yaxis.tooltip.auto", defaultValue: "當前為自動縮放模式，根據實際使用範圍智能調整 Y 軸。點擊切換為固定上限模式。")
    public static let chartYAxisTooltipFixed = String(localized: "chart.yaxis.tooltip.fixed", defaultValue: "當前為固定上限模式，Y 軸固定顯示方案速度上限。點擊切換為自動縮放模式。")

    // MARK: - Chart Help Tooltips
    public static let chartHelpExtendedRanges = String(localized: "chart.help.extendedRanges", defaultValue: "更長時間範圍")
    public static func chartHelpToggleData(_ dataType: String) -> String {
        String(format: String(localized: "chart.help.toggleData", defaultValue: "點擊切換 %@ 資料顯示"), dataType)
    }
    public static let chartHelpDismissBanner = String(localized: "chart.help.dismissBanner", defaultValue: "關閉提示")

    // MARK: - Chart Legend
    public static let chartLegendDownload = String(localized: "chart.legend.download", defaultValue: "下載")
    public static let chartLegendUpload = String(localized: "chart.legend.upload", defaultValue: "上傳")
    public static let chartLegendPlanSpeed = String(localized: "chart.legend.planSpeed", defaultValue: "方案速度")

    // MARK: - Chart Tooltip
    public static func chartTooltipAverage(_ speed: String) -> String {
        String(format: String(localized: "chart.tooltip.average", defaultValue: "平均 %@"), speed)
    }
    public static func chartTooltipPeak(_ speed: String) -> String {
        String(format: String(localized: "chart.tooltip.peak", defaultValue: "峰值 %@"), speed)
    }

    // MARK: - Chart Statistics
    public static let chartStatsCollecting = String(localized: "chart.stats.collecting", defaultValue: "收集中")
    public static let chartStatsRealtime = String(localized: "chart.stats.realtime", defaultValue: "即時")
    public static let chartStatsPeak = String(localized: "chart.stats.peak", defaultValue: "峰值")
    public static let chartStatsAverage = String(localized: "chart.stats.average", defaultValue: "平均")

    // MARK: - Chart Empty State
    public static let chartEmptyCollecting = String(localized: "chart.empty.collecting", defaultValue: "正在收集網路資料")
    public static let chartEmptyPleaseWait = String(localized: "chart.empty.pleaseWait", defaultValue: "請稍候，圖表將在幾秒鐘後顯示")

    // MARK: - Chart Data Collection Banner
    public static let chartBannerCollecting = String(localized: "chart.banner.collecting", defaultValue: "資料收集中...")
    public static func chartBannerCollectingWithCoverage(_ coverage: String) -> String {
        String(format: String(localized: "chart.banner.collectingWithCoverage", defaultValue: "資料收集中：%@"), coverage)
    }
    public static func chartBannerRemainingTime(_ time: String) -> String {
        String(format: String(localized: "chart.banner.remainingTime", defaultValue: "還需 %@ 達到完整視圖"), time)
    }
    public static func chartBannerCollected(_ percentage: Int) -> String {
        String(format: String(localized: "chart.banner.collected", defaultValue: "已收集 %d%%"), percentage)
    }

    // MARK: - Chart Time Formatting
    public static func chartTimeHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        String(format: String(localized: "chart.time.hoursMinutes", defaultValue: "%d 小時 %d 分鐘"), hours, minutes)
    }
    public static func chartTimeHoursMinutesShort(_ hours: Int, _ minutes: Int) -> String {
        String(format: String(localized: "chart.time.hoursMinutesShort", defaultValue: "%d 小時 %d 分"), hours, minutes)
    }
    public static func chartTimeHours(_ hours: Int) -> String {
        String(format: String(localized: "chart.time.hours", defaultValue: "%d 小時"), hours)
    }
    public static func chartTimeMinutes(_ minutes: Int) -> String {
        String(format: String(localized: "chart.time.minutes", defaultValue: "%d 分鐘"), minutes)
    }
    public static let chartTimeLessThanOneMinute = String(localized: "chart.time.lessThanOneMinute", defaultValue: "< 1 分鐘")

    // MARK: - Chart Partial Data
    public static func chartPartialMessage(_ actual: String, _ required: String) -> String {
        String(format: String(localized: "chart.partial.message", defaultValue: "顯示最近 %@ 資料（完整視圖需 %@）"), actual, required)
    }

    // MARK: - Connection Quality
    public static let connectionQualityTitle = String(localized: "connection.quality.title", defaultValue: "連線品質")
    public static let connectionQualityGood = String(localized: "connection.quality.good", defaultValue: "良好")
    public static let connectionQualityFair = String(localized: "connection.quality.fair", defaultValue: "普通")
    public static let connectionQualityPoor = String(localized: "connection.quality.poor", defaultValue: "差")
    public static let connectionQualityUnknown = String(localized: "connection.quality.unknown", defaultValue: "未知")
    public static let latencyLabel = String(localized: "latency.label", defaultValue: "延遲")
    public static let jitterLabel = String(localized: "jitter.label", defaultValue: "抖動")
    public static let latencyUnit = String(localized: "latency.unit", defaultValue: "ms")
    public static let latencyDisabled = String(localized: "latency.disabled", defaultValue: "延遲監測已關閉")

    // MARK: - Disconnect Tracking
    public static let disconnectTitle = String(localized: "disconnect.title", defaultValue: "斷線記錄")
    public static let disconnectTodayCount = String(localized: "disconnect.today.count", defaultValue: "今日斷線")
    public static let disconnectTotalDowntime = String(localized: "disconnect.total.downtime", defaultValue: "總中斷時間")
    public static let disconnectNoDowntime = String(localized: "disconnect.no.downtime", defaultValue: "無中斷")
    public static let disconnectNoEventsToday = String(localized: "disconnect.no.events.today", defaultValue: "今日無斷線記錄")
    public static let disconnectSeconds = String(localized: "disconnect.seconds", defaultValue: "秒")
    public static let disconnectMinutes = String(localized: "disconnect.minutes", defaultValue: "分鐘")
    public static let disconnectHours = String(localized: "disconnect.hours", defaultValue: "小時")
    public static let disconnectInterfaceWifi = String(localized: "disconnect.interface.wifi", defaultValue: "Wi-Fi")
    public static let disconnectInterfaceEthernet = String(localized: "disconnect.interface.ethernet", defaultValue: "乙太網路")
    public static let disconnectInterfaceCellular = String(localized: "disconnect.interface.cellular", defaultValue: "行動數據")
    public static let disconnectInterfaceOther = String(localized: "disconnect.interface.other", defaultValue: "其他")
    public static func disconnectTimesUnit(_ count: Int) -> String {
        String(format: String(localized: "disconnect.times.unit", defaultValue: "%d 次"), count)
    }

    // MARK: - Monthly Report
    public static let reportTitle = String(localized: "report.title", defaultValue: "月度報告")
    public static let reportViewReport = String(localized: "report.view", defaultValue: "查看月度報告")
    public static let reportPeakDownload = String(localized: "report.peak.download", defaultValue: "下載峰值")
    public static let reportPeakUpload = String(localized: "report.peak.upload", defaultValue: "上傳峰值")
    public static let reportAvgDownload = String(localized: "report.avg.download", defaultValue: "平均下載")
    public static let reportAvgUpload = String(localized: "report.avg.upload", defaultValue: "平均上傳")
    public static let reportPlanUtilization = String(localized: "report.plan.utilization", defaultValue: "方案使用率")
    public static let reportPeakApproaches = String(localized: "report.peak.approaches", defaultValue: "接近上限次數")
    public static let reportDisconnects = String(localized: "report.disconnects", defaultValue: "斷線次數")
    public static let reportTotalDowntime = String(localized: "report.total.downtime", defaultValue: "總中斷時間")
    public static let reportAvgLatency = String(localized: "report.avg.latency", defaultValue: "平均延遲")
    public static let reportAvgJitter = String(localized: "report.avg.jitter", defaultValue: "平均抖動")
    public static let reportDaysMonitored = String(localized: "report.days.monitored", defaultValue: "監控天數")
    public static let reportRecommendation = String(localized: "report.recommendation", defaultValue: "建議")
    public static let reportRecommendUpgrade = String(localized: "report.recommend.upgrade", defaultValue: "建議升級方案")
    public static let reportRecommendFits = String(localized: "report.recommend.fits", defaultValue: "目前方案合適")
    public static let reportRecommendDowngrade = String(localized: "report.recommend.downgrade", defaultValue: "可考慮降級方案")
    public static let reportRecommendInsufficientData = String(localized: "report.recommend.insufficient", defaultValue: "資料不足")
    public static let reportNoData = String(localized: "report.no.data", defaultValue: "尚無月度報告資料")
    public static let reportExport = String(localized: "report.export", defaultValue: "匯出報告")
    public static func reportMonthLabel(_ month: String) -> String {
        String(format: String(localized: "report.month.label", defaultValue: "%@ 月度報告"), month)
    }
    public static func reportCollectingDays(_ have: Int, _ need: Int) -> String {
        String(format: String(localized: "report.collecting.days", defaultValue: "資料收集中：已監控 %1$d 天，滿 %2$d 天後提供建議"), have, need)
    }
    public static let reportScopeNote = String(localized: "report.note.scope", defaultValue: "只計算這台 Mac，包含區網傳輸")
    public static let reportSustainedNote = String(localized: "report.note.sustained", defaultValue: "峰值為持續 3 秒的速度")
}
