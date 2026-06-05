//
//  ContentView.swift
//  Glass — redesigned UI
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

// MARK: - Enums (unchanged — keep existing logic intact)
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

private enum Dir: String, CaseIterable {
    case left   = "왼쪽"
    case center = "정면"
    case right  = "오른쪽"
    var arrow: String {
        switch self {
        case .left:   return "arrow.left"
        case .center: return "arrow.up"
        case .right:  return "arrow.right"
        }
    }
}

// MARK: - Root View
struct ContentView: View {
    @StateObject private var cam = CameraManager()
    @State private var mode: AppMode = .live

    var body: some View {
        ZStack {
            // Camera
            CameraPreview(session: cam.session)
                .ignoresSafeArea()

            // Vignette + fog
            VignetteLayer()

            // UI
            VStack(spacing: 0) {
                StatusBar()
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                ModePill(mode: mode, processing: cam.isProcessing)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                Spacer()

                Group {
                    if mode == .live {
                        LivePanel(
                            message:   liveMessage,
                            severity:  severity,
                            direction: activeDir
                        )
                        .padding(.horizontal, 16)
                    } else {
                        OcrPanel(
                            status:      cam.liveOCRStatus.rawValue,
                            result:      cam.latestDetectedText,
                            processing:  cam.isProcessing
                        )
                        .padding(.horizontal, 16)
                    }
                }

                ModeBar(selected: $mode) { m in
                    cam.setMode(m.processingMode)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .onAppear { cam.setMode(mode.processingMode) }
    }

    // MARK: computed
    private var liveMessage: String { cam.latestGuide }

    private var severity: Severity {
        if cam.latestLiveRiskScore >= 85 { return .danger }
        if cam.latestLiveRiskScore >= 55 { return .warning }
        return .calm
    }

    private var activeDir: Dir {
        switch cam.latestLiveDirection {
        case "left":  return .left
        case "right": return .right
        default:      return .center
        }
    }
}

// MARK: - Vignette
private struct VignetteLayer: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red:0.02, green:0.03, blue:0.08).opacity(0.88),
                    .clear,
                    Color(red:0.02, green:0.03, blue:0.08).opacity(0.96)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Status Bar
private struct StatusBar: View {
    var body: some View {
        HStack {
            Text(currentTime)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i == 2 ? 0.25 : 0.55))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
    private var currentTime: String {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f.string(from: Date())
    }
}

// MARK: - Mode Pill (header)
private struct ModePill: View {
    let mode: AppMode
    let processing: Bool

    var body: some View {
        HStack(spacing: 0) {
            // status dot
            Circle()
                .fill(mode == .live ? P.live : P.primary)
                .frame(width: 7, height: 7)
                .padding(.leading, 12)

            Text(mode == .live ? "보행 안내" : "문자 읽기")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 7)

            if processing {
                ProgressView()
                    .tint(P.primary)
                    .scaleEffect(0.65)
                    .padding(.leading, 8)
            }

            Spacer()
        }
        .frame(height: 36)
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
        VStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(severity.color)
                    .frame(width: 3, height: 14)
                    .clipShape(.rect(cornerRadius: 2))
                Text(severity.label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(severity.color)
            }

            Text(message)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .minimumScaleFactor(0.75)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(P.glass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(severity.color.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Direction Strip
private struct DirStrip: View {
    let active: Dir
    let severity: Severity

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Dir.allCases, id: \.self) { d in
                DirCell(dir: d, isActive: d == active, color: severity.color)
            }
        }
        .frame(height: 54)
    }
}

private struct DirCell: View {
    let dir: Dir
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: dir.arrow)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? color : .white.opacity(0.35))
            Text(dir.rawValue)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(isActive ? color.opacity(0.9) : .white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            isActive
                ? color.opacity(0.14)
                : P.pill
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? color.opacity(0.45) : P.glassStroke, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - OCR Panel
private struct OcrPanel: View {
    let status: String
    let result: String?
    let processing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(P.primary.opacity(0.14))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(P.primary)
                    )

                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(P.dimText)

                Spacer()

                if processing {
                    ProgressView()
                        .tint(P.primary)
                        .scaleEffect(0.75)
                }
            }

            if let text = result, !text.isEmpty {
                Divider()
                    .background(.white.opacity(0.08))
                    .padding(.vertical, 14)

                Text(text)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.glass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(P.primary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Mode Bar (bottom)
private struct ModeBar: View {
    @Binding var selected: AppMode
    let onChange: (AppMode) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AppMode.allCases, id: \.self) { m in
                ModeBtn(mode: m, active: selected == m) {
                    selected = m
                    onChange(m)
                }
            }
        }
        .padding(6)
        .background(P.glass, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
            HStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .bold))
                Text(mode.rawValue)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(active ? Color(red:0.02, green:0.06, blue:0.14) : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                active
                    ? P.primary
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
