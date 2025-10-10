import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Color {
    /// Adaptive colors for dark mode support
    struct Adaptive {
        // MARK: - Background Colors

        /// Primary background color (adapts to appearance)
        static var background: Color {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }

        /// Secondary background color for cards and sections
        static var secondaryBackground: Color {
            #if os(macOS)
            Color(NSColor.controlBackgroundColor)
            #else
            Color(UIColor.secondarySystemBackground)
            #endif
        }

        /// Tertiary background for subtle contrast
        static var tertiaryBackground: Color {
            #if os(macOS)
            Color(NSColor.underPageBackgroundColor)
            #else
            Color(UIColor.tertiarySystemBackground)
            #endif
        }

        // MARK: - Text Colors

        /// Primary text color
        static var text: Color {
            #if os(macOS)
            Color(NSColor.labelColor)
            #else
            Color(UIColor.label)
            #endif
        }

        /// Secondary text color (less prominent)
        static var secondaryText: Color {
            #if os(macOS)
            Color(NSColor.secondaryLabelColor)
            #else
            Color(UIColor.secondaryLabel)
            #endif
        }

        /// Tertiary text color (least prominent)
        static var tertiaryText: Color {
            #if os(macOS)
            Color(NSColor.tertiaryLabelColor)
            #else
            Color(UIColor.tertiaryLabel)
            #endif
        }

        // MARK: - Separator Colors

        /// Standard separator/divider color
        static var separator: Color {
            #if os(macOS)
            Color(NSColor.separatorColor)
            #else
            Color(UIColor.separator)
            #endif
        }

        // MARK: - Chart Colors

        /// Download/Blue colors that adapt to dark mode
        static var downloadPrimary: Color {
            .blue
        }

        static var downloadSecondary: Color {
            .blue.opacity(0.3)
        }

        /// Upload/Green colors that adapt to dark mode
        static var uploadPrimary: Color {
            .green
        }

        static var uploadSecondary: Color {
            .green.opacity(0.3)
        }

        /// Warning/Orange color for concerning peaks
        static var warning: Color {
            .orange
        }

        /// Error/Red color for critical alerts
        static var error: Color {
            .red
        }

        // MARK: - Card Colors

        /// Card background with subtle distinction
        static var cardBackground: Color {
            Color.Adaptive.secondaryBackground.opacity(0.5)
        }

        /// Hovered card background
        static var cardBackgroundHover: Color {
            Color.Adaptive.secondaryBackground.opacity(0.8)
        }

        // MARK: - Chart Specific

        /// Grid line color for charts
        static var chartGridLine: Color {
            Color.gray.opacity(0.2)
        }

        /// Chart axis color
        static var chartAxis: Color {
            Color.Adaptive.secondaryText
        }

        /// Tooltip background
        static var tooltipBackground: Color {
            #if os(macOS)
            Color(NSColor.controlBackgroundColor).opacity(0.95)
            #else
            Color(UIColor.secondarySystemBackground).opacity(0.95)
            #endif
        }

        /// Tooltip border
        static var tooltipBorder: Color {
            Color.gray.opacity(0.3)
        }
    }
}

// MARK: - Shadow Extension for Dark Mode

extension View {
    /// Applies adaptive shadow that works well in both light and dark modes
    func adaptiveShadow(radius: CGFloat = 4, x: CGFloat = 0, y: CGFloat = 2) -> some View {
        self.shadow(
            color: Color.black.opacity(0.1),
            radius: radius,
            x: x,
            y: y
        )
    }

    /// Applies adaptive card styling
    func adaptiveCardStyle() -> some View {
        self
            .background(Color.Adaptive.cardBackground)
            .cornerRadius(8)
            .adaptiveShadow()
    }
}
