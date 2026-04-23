//
//  ContentView.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI

struct ContentView: View {
    private enum Palette {
        static let surface = Color.black.opacity(0.88)
        static let surfaceBorder = Color.white.opacity(0.2)
        static let accent = Color(red: 1.0, green: 0.84, blue: 0.1)
        static let accentStrong = Color(red: 1.0, green: 0.72, blue: 0.0)
        static let accentText = Color.black
        static let secondarySurface = Color(red: 0.08, green: 0.08, blue: 0.1)
        static let passiveButton = Color(red: 0.18, green: 0.18, blue: 0.2)
        static let liveMode = Color(red: 0.18, green: 0.82, blue: 0.52)
    }
    
    private enum CameraMode: String {
        case liveAnalyzing = "Live Analyzing"
        case textDescription = "Text Description"
        
        var icon: String {
            switch self {
            case .liveAnalyzing:
                return "eye.fill"
            case .textDescription:
                return "text.viewfinder"
            }
        }
        
        var subtitle: String {
            switch self {
            case .liveAnalyzing:
                return "Detect objects and warn about danger ahead"
            case .textDescription:
                return "Capture and read nearby text with OCR"
            }
        }
        
        var actionTitle: String {
            switch self {
            case .liveAnalyzing:
                return "Monitoring forward scene"
            case .textDescription:
                return "Read Text Now"
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
    
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedMode: CameraMode = .liveAnalyzing
    
    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
            
            LinearGradient(
                colors: [.black.opacity(0.7), .black.opacity(0.18), .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 18) {
                topModeCard
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                guidanceCard
                    .padding(.horizontal, 20)
                
                if selectedMode == .textDescription,
                   let detectedText = cameraManager.latestDetectedText,
                   !detectedText.isEmpty {
                    detectedTextCard(text: detectedText)
                        .padding(.horizontal, 20)
                }
                
                actionCard
                    .padding(.horizontal, 20)
                
                bottomModeSwitcher
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            cameraManager.setMode(selectedMode.processingMode)
        }
    }
    
    private var topModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(selectedMode.rawValue, systemImage: selectedMode.icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(selectedMode == .liveAnalyzing ? Palette.liveMode : Palette.accent)
            Text(selectedMode.subtitle)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 2)
        )
    }
    
    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Voice Guidance", systemImage: "speaker.wave.2.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.accent)
                
                Spacer()
                
                if cameraManager.isProcessing {
                    ProgressView()
                        .tint(Palette.accent)
                        .scaleEffect(1.1)
                }
            }
            
            Text(cameraManager.latestGuide)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.secondarySurface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.accent.opacity(0.8), lineWidth: 2)
        )
    }
    
    private func detectedTextCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detected Text", systemImage: "text.alignleft")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.accent)
            
            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 2)
        )
    }
    
    private var actionCard: some View {
        Button(action: primaryAction) {
            HStack(spacing: 12) {
                Image(systemName: selectedMode == .liveAnalyzing ? "waveform.path.ecg" : "text.magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                Text(selectedMode.actionTitle)
                    .font(.headline.weight(.semibold))
                Spacer()
                
                if selectedMode == .textDescription {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(selectedMode == .liveAnalyzing ? .white : Palette.accentText)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selectedMode == .liveAnalyzing ? Palette.passiveButton : Palette.accent)
            )
        }
        .disabled(selectedMode == .liveAnalyzing || cameraManager.isProcessing)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selectedMode == .liveAnalyzing ? Palette.surfaceBorder : Palette.accentStrong, lineWidth: 2)
        )
        .opacity(selectedMode == .liveAnalyzing ? 0.96 : 1.0)
    }
    
    private var bottomModeSwitcher: some View {
        HStack(spacing: 12) {
            modeButton(for: .liveAnalyzing)
            modeButton(for: .textDescription)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 2)
        )
    }
    
    private func modeButton(for mode: CameraMode) -> some View {
        let isActive = selectedMode == mode
        
        return Button {
            selectedMode = mode
            cameraManager.setMode(mode.processingMode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 19, weight: .bold))
                Text(mode.rawValue)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(isActive ? Palette.accentText : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isActive ? Palette.accent : Palette.passiveButton)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isActive ? Palette.accentStrong : Palette.surfaceBorder, lineWidth: 2)
            )
        }
    }
    
    private func primaryAction() {
        guard selectedMode == .textDescription else { return }
        cameraManager.triggerTextCapture()
    }
}
