//
//  ContentView.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isDetectionMode = true
    
    var body: some View {
        ZStack {
            // 1. 카메라 배경 (여기에 실제 카메라 화면을 띄울 겁니다)
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
            
            // 2. 하단 메뉴 영역
            VStack {
                Spacer()
                HStack {
                    modeButton(title: "실시간 탐지", icon: "eye.fill", active: isDetectionMode) {
                        isDetectionMode = true
                        // 여기서 TTS 안내 로직 추가
                    }
                    modeButton(title: "텍스트 읽기", icon: "text.justify.left", active: !isDetectionMode) {
                        isDetectionMode = false
                        // 여기서 TTS 안내 로직 추가
                    }
                }
                .padding(.bottom, 40)
                // .background(Color.black.opacity(0.6))
                .background(Color.clear)
            }
        }
    }
    
    func modeButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 35))
                Text(title)
                    .font(.caption)
                    .bold()
                
            }
            .foregroundColor(active ? .green : .white)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .frame(maxWidth: .infinity)
        }
    }
}
