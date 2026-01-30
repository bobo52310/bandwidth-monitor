import Foundation

/// Localization helper for all user-facing strings
public enum L10n {
    // MARK: - App General
    public static let appTitle = String(localized: "app.title", defaultValue: "Network Peak Monitor")

    // MARK: - Buttons
    public static let buttonPin = String(localized: "button.pin", defaultValue: "Pin")
    public static let buttonSettings = String(localized: "button.settings", defaultValue: "Settings")
    public static let buttonBack = String(localized: "button.back", defaultValue: "返回")
    public static let buttonClose = String(localized: "button.close", defaultValue: "關閉")
    public static let buttonOK = String(localized: "button.ok", defaultValue: "OK")
    public static let buttonPrevious = String(localized: "button.previous", defaultValue: "上一步")
    public static let buttonNext = String(localized: "button.next", defaultValue: "下一步")
    public static let buttonGetStarted = String(localized: "button.getStarted", defaultValue: "開始使用")

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

    // MARK: - Settings - System & Maintenance Section
    public static let settingsSystemMaintenanceSection = String(localized: "settings.systemMaintenance.section", defaultValue: "系統與維護")
    public static let settingsSystemSettings = String(localized: "settings.system.settings", defaultValue: "系統設定")
    public static let settingsLaunchAtLogin = String(localized: "settings.launch.login", defaultValue: "登入時開啟")
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
    public static let settingsMemoryManagement = String(localized: "settings.memory.management", defaultValue: "記憶體管理")
    public static let settingsMemoryUsage = String(localized: "settings.memory.usage", defaultValue: "使用量:")
    public static let settingsOptimizeMemory = String(localized: "settings.memory.optimize", defaultValue: "優化記憶體")
    public static let settingsOptimizeMemoryHelp = String(localized: "settings.memory.optimize.help", defaultValue: "清理過期數據以減少記憶體使用")
    public static let settingsResetAllPeaks = String(localized: "settings.reset.peaks", defaultValue: "重置所有峰值記錄")

    // MARK: - Settings - Language
    public static let settingsLanguageSection = String(localized: "settings.language.section", defaultValue: "語言設定")
    public static let settingsLanguage = String(localized: "settings.language", defaultValue: "語言")
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

    // MARK: - Chart Y-Axis Modes
    public static let chartYAxisModeAuto = String(localized: "chart.yaxis.auto", defaultValue: "自動縮放")
    public static let chartYAxisModeFixed = String(localized: "chart.yaxis.fixed", defaultValue: "固定上限")

    // MARK: - Popover View
    public static let chartRequiresMacOS13 = String(localized: "chart.requires.macos13", defaultValue: "圖表功能需要 macOS 13.0 或更新版本")

    // MARK: - Peak Approach Section
    public static func approachingSpeedLimit(_ speed: Int) -> String {
        String(format: String(localized: "peak.approaching.limit", defaultValue: "接近速率上限(%dMbps)"), speed)
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

    // MARK: - Export
    public static let exportData = String(localized: "export.data", defaultValue: "導出數據")
    public static let exportTodayData = String(localized: "export.today.data", defaultValue: "導出今日數據")
    public static let exportPeakHistory = String(localized: "export.peak.history", defaultValue: "導出峰值記錄")
    public static let exportFullHistory = String(localized: "export.full.history", defaultValue: "導出完整歷史")
    public static let exportDataHelp = String(localized: "export.data.help", defaultValue: "導出網路數據為 CSV 檔案")
    public static let exportSuccess = String(localized: "export.success", defaultValue: "導出成功")
    public static let exportSuccessMessage = String(localized: "export.success.message", defaultValue: "數據已成功導出至下載資料夾")
    public static let exportFailure = String(localized: "export.failure", defaultValue: "導出失敗")
    public static let exportFailureMessage = String(localized: "export.failure.message", defaultValue: "無法導出數據，請稍後再試")

    // MARK: - Actions
    public static let actionResetPeaks = String(localized: "action.reset.peaks", defaultValue: "重置峰值記錄")
    public static let actionQuitApp = String(localized: "action.quit.app", defaultValue: "退出應用程式")

    // MARK: - Onboarding
    public static let onboardingWelcomeTitle = String(localized: "onboarding.welcome.title", defaultValue: "歡迎使用 Network Peak Monitor")
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
    public static let onboardingExportFeature1 = String(localized: "onboarding.export.feature.1", defaultValue: "導出今日數據 (過去24小時)")
    public static let onboardingExportFeature2 = String(localized: "onboarding.export.feature.2", defaultValue: "導出峰值記錄")
    public static let onboardingExportFeature3 = String(localized: "onboarding.export.feature.3", defaultValue: "導出完整歷史記錄")
    public static let onboardingExportFeature4 = String(localized: "onboarding.export.feature.4", defaultValue: "CSV 格式，方便使用 Excel 分析")

    public static let onboardingSetupTitle = String(localized: "onboarding.setup.title", defaultValue: "開始設定")
    public static let onboardingSetupDescription = String(localized: "onboarding.setup.description", defaultValue: "請設定您的網路方案速度上限，以便我們提供更準確的監控。")

    public static let onboardingWindowTitle = String(localized: "onboarding.window.title", defaultValue: "歡迎使用 Network Peak Monitor")

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
    public static let notificationPeaksReset = String(localized: "notification.peaks.reset", defaultValue: "峰值已重置")
    public static let notificationPeaksResetBody = String(localized: "notification.peaks.reset.body", defaultValue: "所有峰值記錄已清除")
    public static let notificationExportSuccessBody = String(localized: "notification.export.success.body", defaultValue: "數據已成功導出")
    public static let notificationMemoryOptimized = String(localized: "notification.memory.optimized", defaultValue: "記憶體已優化")
    public static let notificationMemoryOptimizedBody = String(localized: "notification.memory.optimized.body", defaultValue: "過期數據已清除")

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
    public static func chartYAxisFixedLabel(_ speed: Int) -> String {
        String(format: String(localized: "chart.yaxis.fixedLabel", defaultValue: "固定 %d"), speed)
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
}
