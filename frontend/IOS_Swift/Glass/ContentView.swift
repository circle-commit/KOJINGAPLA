//
//  ContentView.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI

struct ContentView: View {
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
                colors: [.black.opacity(0.45), .clear, .black.opacity(0.72)],
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
                .font(.headline.weight(.semibold))
            Text(selectedMode.subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Voice Guidance", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                if cameraManager.isProcessing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                }
            }
            
            Text(cameraManager.latestGuide)
                .font(.body)
                .foregroundStyle(.white.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
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
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(selectedMode == .liveAnalyzing ? .white.opacity(0.78) : .black)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selectedMode == .liveAnalyzing ? Color.white.opacity(0.12) : Color.white)
            )
        }
        .disabled(selectedMode == .liveAnalyzing || cameraManager.isProcessing)
        .opacity(selectedMode == .liveAnalyzing ? 0.9 : 1.0)
    }
    
    private var bottomModeSwitcher: some View {
        HStack(spacing: 12) {
            modeButton(for: .liveAnalyzing)
            modeButton(for: .textDescription)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
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
                    .font(.system(size: 17, weight: .semibold))
                Text(mode.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isActive ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isActive ? Color.white : Color.white.opacity(0.08))
            )
        }
    }
    
    private func primaryAction() {
        guard selectedMode == .textDescription else { return }
        cameraManager.triggerTextCapture()
    }
}
