//
//  ContentView.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI
import UIKit

private enum AppPalette {
    static let overlayTop = Color.black.opacity(0.72)
    static let overlayMiddle = Color.black.opacity(0.2)
    static let overlayBottom = Color.black.opacity(0.88)
    static let surface = Color.black.opacity(0.86)
    static let surfaceStrong = Color.black.opacity(0.94)
    static let surfaceBorder = Color.white.opacity(0.22)
    static let primary = Color(red: 1.0, green: 0.84, blue: 0.12)
    static let primaryStrong = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let primaryText = Color.black
    static let live = Color(red: 0.16, green: 0.82, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.58, blue: 0.12)
    static let danger = Color(red: 1.0, green: 0.18, blue: 0.18)
    static let passiveButton = Color(red: 0.18, green: 0.18, blue: 0.2)
}

private enum CameraMode: String, CaseIterable {
    case liveAnalyzing = "Live"
    case textDescription = "OCR"

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
            return "Live Guidance"
        case .textDescription:
            return "OCR Mode"
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
    case left = "Left"
    case center = "Center"
    case right = "Right"
}

private struct LiveGuidanceState {
    let severity: GuidanceSeverity
    let direction: GuidanceDirection
    let message: String
    let isApproaching: Bool

    static let standby = LiveGuidanceState(
        severity: .calm,
        direction: .center,
        message: "Monitoring forward scene",
        isApproaching: false
    )
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

            VStack(spacing: 18) {
                ModeHeader(mode: selectedMode, isProcessing: cameraManager.isProcessing)
                    .padding(.top, 18)

                Spacer(minLength: 20)

                VoiceGuidanceCard(
                    message: displayGuidance,
                    severity: .calm,
                    isProcessing: cameraManager.isProcessing
                )

                if selectedMode == .liveAnalyzing {
                    LiveGuidancePreview(state: LiveGuidanceState.standby)
                }

                if selectedMode == .textDescription {
                    OCRResultArea(
                        text: textCaptureDisplayText,
                        captureImage: cameraManager.textCaptureImage,
                        isProcessing: cameraManager.isProcessing,
                        hasResult: hasOCRResult
                    )
                }

                PrimaryActionButton(
                    title: selectedMode == .textDescription ? "Scan Text" : "Listening",
                    systemImage: selectedMode == .textDescription ? "text.magnifyingglass" : "waveform.path.ecg",
                    isEnabled: selectedMode == .textDescription && !cameraManager.isProcessing,
                    isProminent: selectedMode == .textDescription,
                    action: primaryAction
                )

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
            return "Ready to read nearby text"
        }

        return cameraManager.latestGuide
    }

    private var hasOCRResult: Bool {
        guard let detectedText = cameraManager.latestDetectedText else { return false }
        return !detectedText.isEmpty
    }

    private var textCaptureDisplayText: String {
        if cameraManager.isProcessing {
            return "Reading text..."
        }

        if let detectedText = cameraManager.latestDetectedText,
           !detectedText.isEmpty {
            return detectedText
        }

        if cameraManager.textCaptureImage != nil {
            return "No readable text found."
        }

        return "Scanned text will appear here."
    }

    private func primaryAction() {
        guard selectedMode == .textDescription else { return }
        cameraManager.triggerTextCapture()
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
                .background(Circle().fill(AppPalette.surfaceStrong))

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
                    .accessibilityLabel("Processing")
            }
        }
        .frame(minHeight: 62)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if isProcessing {
            return "Working"
        }

        switch mode {
        case .liveAnalyzing:
            return "Scene monitoring"
        case .textDescription:
            return "Ready"
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

                Text("Guidance")
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(severity.tint.opacity(isProcessing ? 1.0 : 0.8), lineWidth: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice guidance")
        .accessibilityValue(message)
    }
}

private struct OCRResultArea: View {
    let text: String
    let captureImage: UIImage?
    let isProcessing: Bool
    let hasResult: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captured Text")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppPalette.primary)

                Spacer()

                if isProcessing {
                    Text("Reading")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppPalette.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(AppPalette.primary))
                }
            }

            if captureImage != nil && !hasResult && !isProcessing {
                Text("Try moving closer or holding the camera steady.")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 28, weight: .semibold))
                    .lineSpacing(8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, maxHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.85), lineWidth: 2)
            )
            .accessibilityLabel("Recognized text")
            .accessibilityValue(text)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.surface)
        )
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))

                Text(title)
                    .font(.title3.weight(.bold))

                Spacer()
            }
            .foregroundStyle(isProminent ? AppPalette.primaryText : .white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isProminent ? AppPalette.primary : AppPalette.passiveButton)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isProminent ? AppPalette.primaryStrong : AppPalette.surfaceBorder, lineWidth: 2)
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled || !isProminent ? 1.0 : 0.72)
        .accessibilityLabel(title)
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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
            )
        }
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct LiveGuidancePreview: View {
    let state: LiveGuidanceState

    var body: some View {
        VStack(spacing: 12) {
            DangerWarningBanner(severity: state.severity, message: state.message, isApproaching: state.isApproaching)
            DirectionGuidanceStrip(activeDirection: state.direction, severity: state.severity)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DangerWarningBanner: View {
    let severity: GuidanceSeverity
    let message: String
    let isApproaching: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isApproaching ? "arrow.down.forward.and.arrow.up.backward" : severity.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(severity.tint)
                .frame(width: 32)

            Text(message)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(severity.tint.opacity(0.75), lineWidth: 2)
        )
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
        .frame(height: 58)
    }
}

private struct DirectionSegment: View {
    let direction: GuidanceDirection
    let isActive: Bool
    let severity: GuidanceSeverity

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .bold))
            Text(direction.rawValue)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isActive ? AppPalette.primaryText : .white.opacity(0.72))
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? severity.tint : AppPalette.passiveButton)
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
