//
//  ContentView.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI
import UIKit

private enum AppPalette {
    static let overlayTop = Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.78)
    static let overlayMiddle = Color(red: 0.05, green: 0.1, blue: 0.18).opacity(0.24)
    static let overlayBottom = Color(red: 0.03, green: 0.05, blue: 0.1).opacity(0.92)
    static let glassTint = Color(red: 0.09, green: 0.13, blue: 0.23).opacity(0.62)
    static let glassTintStrong = Color(red: 0.08, green: 0.12, blue: 0.2).opacity(0.74)
    static let surfaceBorder = Color.white.opacity(0.18)
    static let primary = Color(red: 0.24, green: 0.68, blue: 1.0)
    static let primaryText = Color.black
    static let live = Color(red: 0.16, green: 0.82, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.58, blue: 0.12)
    static let danger = Color(red: 1.0, green: 0.18, blue: 0.18)
    static let passiveButton = Color.white.opacity(0.1)
    static let blueGlow = Color(red: 0.07, green: 0.42, blue: 1.0)
}

private enum CameraMode: String, CaseIterable {
    case liveAnalyzing = "실시간"
    case textDescription = "문자 읽기"

    var icon: String {
        switch self {
        case .liveAnalyzing:
            return "eye.fill"
        case .textDescription:
            return "text.viewfinder"
        }
    }

    var title: String {
        switch self {
        case .liveAnalyzing:
            return "보행 안내"
        case .textDescription:
            return "문자 읽기"
        }
    }

    var processingMode: CameraManager.ProcessingMode {
        switch self {
        case .liveAnalyzing:
            return .liveAnalyzing
        case .textDescription:
            return .textDescription
        }
    }
}

private enum GuidanceSeverity {
    case calm
    case warning
    case danger

    var tint: Color {
        switch self {
        case .calm:
            return AppPalette.primary
        case .warning:
            return AppPalette.warning
        case .danger:
            return AppPalette.danger
        }
    }

    var icon: String {
        switch self {
        case .calm:
            return "speaker.wave.2.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .danger:
            return "exclamationmark.octagon.fill"
        }
    }
}

private enum GuidanceDirection: String, CaseIterable {
    case left = "왼쪽"
    case center = "정면"
    case right = "오른쪽"
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedMode: CameraMode = .liveAnalyzing

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)

            LinearGradient(
                colors: [AppPalette.overlayTop, AppPalette.overlayMiddle, AppPalette.overlayBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [AppPalette.blueGlow.opacity(0.38), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 18) {
                ModeHeader(mode: selectedMode, isProcessing: cameraManager.isProcessing)
                    .padding(.top, 18)

                Spacer(minLength: 20)

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

                BottomModeSelector(selectedMode: $selectedMode) { mode in
                    cameraManager.setMode(mode.processingMode)
                }
                .padding(.bottom, 22)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            cameraManager.setMode(selectedMode.processingMode)
        }
    }

    private var displayGuidance: String {
        if selectedMode == .textDescription && !cameraManager.isProcessing && cameraManager.latestDetectedText == nil {
            return cameraManager.liveOCRStatus.rawValue
        }

        return cameraManager.latestGuide
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

private struct ModeHeader: View {
    let mode: CameraMode
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(mode == .liveAnalyzing ? AppPalette.live : AppPalette.primary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .background(Circle().fill(AppPalette.glassTintStrong))

            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .tint(AppPalette.primary)
                    .scaleEffect(1.25)
                    .accessibilityLabel("처리 중")
            }
        }
        .frame(minHeight: 62)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if isProcessing {
            return "처리 중"
        }

        switch mode {
        case .liveAnalyzing:
            return "주변 확인 중"
        case .textDescription:
            return "준비됨"
        }
    }
}

private struct VoiceGuidanceCard: View {
    let message: String
    let severity: GuidanceSeverity
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: severity.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(severity.tint)
                    .frame(width: 34)

                Text("안내")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(severity.tint)

                Spacer()
            }

            Text(message)
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(3)
                .lineSpacing(4)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26, tint: AppPalette.glassTintStrong)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.42), severity.tint.opacity(isProcessing ? 0.9 : 0.58), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("음성 안내")
        .accessibilityValue(message)
    }
}

private struct LiveOCRPanel: View {
    let status: LiveOCRStatus
    let text: String
    let isProcessing: Bool
    let hasResult: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppPalette.primary)
                    .frame(width: 36, height: 36)

                Text(status.rawValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()

                if isProcessing {
                    ProgressView()
                        .tint(AppPalette.primary)
                        .scaleEffect(1.2)
                        .accessibilityLabel("문자 읽는 중")
                }
            }

            if hasResult {
                ScrollView {
                    Text(text)
                        .font(.system(size: 28, weight: .semibold))
                        .lineSpacing(8)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 96, maxHeight: 220)
                .accessibilityLabel("인식된 문자")
                .accessibilityValue(text)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24, tint: AppPalette.glassTintStrong)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            AppPalette.primary.opacity(isProcessing || hasResult ? 0.82 : 0.5),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.accessibilityLabel)
    }

    private var statusIcon: String {
        switch status {
        case .searching:
            return "viewfinder"
        case .detected:
            return "text.viewfinder"
        case .stabilizing:
            return "scope"
        case .reading:
            return "speaker.wave.2.fill"
        case .coolingDown:
            return "ear"
        case .unavailable:
            return "camera.fill"
        }
    }
}

private struct BottomModeSelector: View {
    @Binding var selectedMode: CameraMode
    let onModeChanged: (CameraMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CameraMode.allCases, id: \.self) { mode in
                modeButton(for: mode)
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 26, tint: AppPalette.glassTint)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppPalette.surfaceBorder, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
    }

    private func modeButton(for mode: CameraMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            selectedMode = mode
            onModeChanged(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .bold))
                Text(mode.rawValue)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(isActive ? AppPalette.primaryText : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
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
