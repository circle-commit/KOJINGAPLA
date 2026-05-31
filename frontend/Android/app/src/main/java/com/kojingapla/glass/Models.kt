package com.kojingapla.glass

enum class ProcessingMode(val wireName: String) {
    LIVE("live"),
    TEXT("text")
}

enum class LiveOcrStatus(val message: String) {
    SEARCHING("문자를 찾는 중..."),
    DETECTED("문자를 감지했습니다"),
    STABILIZING("화면을 안정화하는 중..."),
    READING("문자를 읽는 중..."),
    COOLING_DOWN("새 문자를 기다리는 중..."),
    UNAVAILABLE("카메라를 사용할 수 없습니다")
}

data class DetectionResponse(
    val label: String,
    val koreanLabel: String?,
    val confidence: Double?,
    val position: String?,
    val bboxXyxy: List<Double>?,
    val areaRatio: Double?,
    val approaching: Boolean?,
    val riskScore: Int?
)

data class AnalysisResponse(
    val status: String,
    val mode: String,
    val detectedText: String?,
    val voiceGuide: String,
    val warnings: List<String>?,
    val detections: List<DetectionResponse>?
)

data class OcrFrameAnalysis(
    val textRegion: RectRatio?,
    val confidence: Float,
    val blurScore: Double,
    val movementScore: Double,
    val timestampMs: Long
)

data class RectRatio(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val centerX: Float get() = (left + right) / 2f
    val centerY: Float get() = (top + bottom) / 2f
}

data class TextStabilityDecision(
    val status: LiveOcrStatus,
    val shouldRunFullOcr: Boolean
)
