//
//  ContentView.swift
//  Glass — redesigned UI (large text for low vision)
//

import SwiftUI

// MARK: - Palette
private enum P {
    static let bg          = Color(red:0.027, green:0.031, blue:0.055)
    static let primary     = Color(red:0.27,  green:0.72,  blue:1.0)
    static let live        = Color(red:0.16,  green:0.87,  blue:0.56)
    static let warning     = Color(red:1.0,   green:0.58,  blue:0.12)
    static let danger      = Color(red:1.0,   green:0.23,  blue:0.23)
    static let glass       = Color(red:0.09,  green:0.13,  blue:0.22).opacity(0.72)
    static let glassStroke = Color.white.opacity(0.10)
    static let dimText     = Color.white.opacity(0.45)
    static let pill        = Color.white.opacity(0.07)
}

// MARK: - Enums
private enum AppMode: String, CaseIterable {
    case live = "실시간"
    case ocr  = "문자 읽기"
    var icon: String {
        self == .live ? "eye.fill" : "text.viewfinder"
    }
    var processingMode: CameraManager.ProcessingMode {
        self == .live ? .liveAnalyzing : .textDescription
    }
}

private enum Severity {
    case calm, warning, danger
    var color: Color {
        switch self {
        case .calm:    return P.primary
        case .warning: return P.warning
        case .danger:  return P.danger
        }
    }
    var label: String {
        switch self {
        case .calm:    return "안내"
        case .warning: return "주의"
        case .danger:  return "위험"
        }
    }
}

private enum GuidanceDirection: String, CaseIterable {
    case left = "왼쪽"
    case center = "정면"
    case right = "오른쪽"
}

// MARK: - Root View
struct ContentView: View {
    @StateObject private var cam = CameraManager()
    @State private var mode: AppMode = .live

    var body: some View {
        ZStack {
            CameraPreview(session: cam.session)
                .ignoresSafeArea()

            VignetteLayer()

            VStack(spacing: 0) {
                StatusBar()
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                ModePill(mode: mode, processing: cam.isProcessing)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                if selectedMode == .liveAnalyzing {
                    VoiceGuidanceCard(
                        message: displayGuidance,
                        severity: liveGuidanceSeverity,
                        isProcessing: cameraManager.isProcessing
                    )

                    DirectionGuidanceStrip(
                        activeDirection: liveGuidanceDirection,
                        severity: liveGuidanceSeverity
                    )
                }

                if selectedMode == .textDescription {
                    LiveOCRPanel(
                        status: cameraManager.liveOCRStatus,
                        text: textCaptureDisplayText,
                        isProcessing: cameraManager.isProcessing,
                        hasResult: hasOCRResult
                    )
                }

                ModeBar(selected: $mode) { m in
                    cam.setMode(m.processingMode)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .onAppear { cam.setMode(mode.processingMode) }
    }

    private var liveMessage: String { cam.latestGuide }

    private var severity: Severity {
        if cam.latestLiveRiskScore >= 85 { return .danger }
        if cam.latestLiveRiskScore >= 55 { return .warning }
        return .calm
    }

    private var hasOCRResult: Bool {
        guard let detectedText = cameraManager.latestDetectedText else { return false }
        return !detectedText.isEmpty
    }

    private var textCaptureDisplayText: String {
        if let detectedText = cameraManager.latestDetectedText,
           !detectedText.isEmpty {
            return detectedText
        }

        return cameraManager.liveOCRStatus.rawValue
    }

    private var liveGuidanceDirection: GuidanceDirection {
        switch cameraManager.latestLiveDirection {
        case "left":
            return .left
        case "right":
            return .right
        default:
            return .center
        }
    }

    private var liveGuidanceSeverity: GuidanceSeverity {
        if cameraManager.latestLiveRiskScore >= 85 {
            return .danger
        }

        if cameraManager.latestLiveRiskScore >= 55 {
            return .warning
        }

        return .calm
    }
}

// MARK: - Mode Pill
private struct ModePill: View {
    let mode: AppMode
    let processing: Bool

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(mode == .live ? P.live : P.primary)
                .frame(width: 10, height: 10)  // 7→10
                .padding(.leading, 14)

            Text(mode == .live ? "보행 안내" : "문자 읽기")
                .font(.system(size: 17, weight: .bold))  // 13→17
                .foregroundStyle(.white)
                .padding(.leading, 9)

            if processing {
                ProgressView()
                    .tint(P.primary)
                    .scaleEffect(0.75)
                    .padding(.leading, 10)
            }

            Spacer()
        }
        .frame(height: 46)  // 36→46
        .background(P.pill, in: Capsule())
        .overlay(Capsule().stroke(P.glassStroke, lineWidth: 1))
    }
}

// MARK: - Live Panel
private struct LivePanel: View {
    let message: String
    let severity: Severity
    let direction: Dir

    var body: some View {
        VStack(spacing: 10) {
            GuidanceCard(message: message, severity: severity)
            DirStrip(active: direction, severity: severity)
        }
    }
}

// MARK: - Guidance Card
private struct GuidanceCard: View {
    let message: String
    let severity: Severity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(severity.color)
                    .frame(width: 5, height: 20)  // 3×14 → 5×20
                    .clipShape(.rect(cornerRadius: 3))
                Text(severity.label)
                    .font(.system(size: 14, weight: .bold))  // 10→14
                    .tracking(1.2)
                    .foregroundStyle(severity.color)
            }

            Text(message)
                .font(.system(size: 28, weight: .bold))  // 22→28
                .foregroundStyle(.white)
                .lineSpacing(5)
                .minimumScaleFactor(0.75)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)  // 18→22
        .background(P.glass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(severity.color.opacity(0.28), lineWidth: 1.5)
        )
    }
}

// MARK: - Direction Strip
private struct DirStrip: View {
    let active: Dir
    let severity: Severity

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Dir.allCases, id: \.self) { d in
                DirCell(dir: d, isActive: d == active, color: severity.color)
            }
        }
        .frame(height: 72)  // 54→72
    }
}

private struct DirCell: View {
    let dir: Dir
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: dir.arrow)
                .font(.system(size: 20, weight: .bold))  // 14→20
                .foregroundStyle(isActive ? color : .white.opacity(0.35))
            Text(dir.rawValue)
                .font(.system(size: 13, weight: .bold))  // 9→13
                .tracking(0.4)
                .foregroundStyle(isActive ? color.opacity(0.9) : .white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)  // 54→72
        .background(isActive ? color.opacity(0.14) : P.pill)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? color.opacity(0.45) : P.glassStroke, lineWidth: 1.5)
        )
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - OCR Panel
private struct OcrPanel: View {
    let status: String
    let result: String?
    let processing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(P.primary.opacity(0.14))
                    .frame(width: 36, height: 36)  // 30→36
                    .overlay(
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 17, weight: .semibold))  // 14→17
                            .foregroundStyle(P.primary)
                    )

                Text(status)
                    .font(.system(size: 17, weight: .semibold))  // 13→17
                    .foregroundStyle(P.dimText)

                Spacer()

                if processing {
                    ProgressView()
                        .tint(P.primary)
                        .scaleEffect(0.85)
                }
            }

            if let text = result, !text.isEmpty {
                Divider()
                    .background(.white.opacity(0.08))
                    .padding(.vertical, 16)

                Text(text)
                    .font(.system(size: 32, weight: .bold))  // 26→32
                    .foregroundStyle(.white)
                    .lineSpacing(6)
            }
        }
        .padding(22)  // 18→22
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.glass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(P.primary.opacity(0.25), lineWidth: 1.5)
        )
    }
}

// MARK: - Mode Bar
private struct ModeBar: View {
    @Binding var selected: AppMode
    let onChange: (AppMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppMode.allCases, id: \.self) { m in
                ModeBtn(mode: m, active: selected == m) {
                    selected = m
                    onChange(m)
                }
            }
        }
        .padding(7)
        .background(P.glass, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(P.glassStroke, lineWidth: 1)
        )
    }
}

private struct ModeBtn: View {
    let mode: AppMode
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .bold))  // 16→20
                Text(mode.rawValue)
                    .font(.system(size: 18, weight: .bold))  // 14→18
            }
            .foregroundStyle(active ? Color(red:0.02, green:0.06, blue:0.14) : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 58)  // 48→58
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? AppPalette.primary : AppPalette.passiveButton)
                    .shadow(color: isActive ? AppPalette.primary.opacity(0.34) : .clear, radius: 14, x: 0, y: 7)
            )
        }
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct DirectionGuidanceStrip: View {
    let activeDirection: GuidanceDirection
    let severity: GuidanceSeverity

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GuidanceDirection.allCases, id: \.self) { direction in
                DirectionSegment(
                    direction: direction,
                    isActive: direction == activeDirection,
                    severity: severity
                )
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("위험 방향")
        .accessibilityValue(activeDirection.rawValue)
    }
}

private struct DirectionSegment: View {
    let direction: GuidanceDirection
    let isActive: Bool
    let severity: GuidanceSeverity

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .bold))
            Text(direction.rawValue)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isActive ? AppPalette.primaryText : .white.opacity(0.78))
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? severity.tint : AppPalette.passiveButton)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? Color.white.opacity(0.65) : AppPalette.surfaceBorder, lineWidth: 2)
        )
    }

    private var iconName: String {
        switch direction {
        case .left:
            return "arrow.left"
        case .center:
            return "arrow.up"
        case .right:
            return "arrow.right"
        }
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .shadow(color: Color.black.opacity(0.42), radius: 28, x: 0, y: 18)
            .shadow(color: AppPalette.blueGlow.opacity(0.16), radius: 22, x: 0, y: 8)
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}
