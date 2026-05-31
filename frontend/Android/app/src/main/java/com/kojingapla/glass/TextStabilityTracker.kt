package com.kojingapla.glass

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class TextStabilityTracker {
    private var detectedStartMs: Long? = null
    private var stableStartMs: Long? = null
    private var smoothedRegion: RectRatio? = null

    private val requiredStableDurationMs = 750L
    private val persistentTextFallbackDurationMs = 1_500L
    private val minimumRegionArea = 0.035f
    private val maximumCenterDistance = 0.28f
    private val minimumBlurScore = 5.0
    private val maximumMovementScore = 13.0

    fun reset() {
        detectedStartMs = null
        stableStartMs = null
        smoothedRegion = null
    }

    fun update(analysis: OcrFrameAnalysis): TextStabilityDecision {
        val region = analysis.textRegion ?: run {
            reset()
            return TextStabilityDecision(LiveOcrStatus.SEARCHING, false)
        }

        if (detectedStartMs == null) {
            detectedStartMs = analysis.timestampMs
        }

        val readableCandidate = isLargeEnough(region) &&
            isCentered(region) &&
            analysis.blurScore >= minimumBlurScore &&
            analysis.movementScore <= maximumMovementScore &&
            analysis.confidence >= 0.45f

        if (!readableCandidate) {
            stableStartMs = null
            smoothedRegion = smooth(region, smoothedRegion)

            val detectedDuration = analysis.timestampMs - (detectedStartMs ?: analysis.timestampMs)
            if (detectedDuration >= persistentTextFallbackDurationMs) {
                detectedStartMs = null
                return TextStabilityDecision(LiveOcrStatus.READING, true)
            }

            return TextStabilityDecision(LiveOcrStatus.DETECTED, false)
        }

        val sameTarget = smoothedRegion?.let { intersectionOverUnion(it, region) >= 0.55f } ?: true
        smoothedRegion = smooth(region, if (sameTarget) smoothedRegion else null)

        if (!sameTarget || stableStartMs == null) {
            stableStartMs = analysis.timestampMs
        }

        val stableDuration = analysis.timestampMs - (stableStartMs ?: analysis.timestampMs)
        if (stableDuration >= requiredStableDurationMs) {
            detectedStartMs = null
            stableStartMs = null
            return TextStabilityDecision(LiveOcrStatus.READING, true)
        }

        return TextStabilityDecision(LiveOcrStatus.STABILIZING, false)
    }

    private fun isLargeEnough(region: RectRatio): Boolean = region.width * region.height >= minimumRegionArea

    private fun isCentered(region: RectRatio): Boolean {
        val dx = region.centerX - 0.5f
        val dy = region.centerY - 0.5f
        return sqrt(dx * dx + dy * dy) <= maximumCenterDistance
    }

    private fun smooth(region: RectRatio, previous: RectRatio?): RectRatio {
        previous ?: return region
        val weight = 0.65f
        return RectRatio(
            left = previous.left * weight + region.left * (1 - weight),
            top = previous.top * weight + region.top * (1 - weight),
            right = previous.right * weight + region.right * (1 - weight),
            bottom = previous.bottom * weight + region.bottom * (1 - weight)
        )
    }

    private fun intersectionOverUnion(first: RectRatio, second: RectRatio): Float {
        val left = max(first.left, second.left)
        val top = max(first.top, second.top)
        val right = min(first.right, second.right)
        val bottom = min(first.bottom, second.bottom)
        if (right <= left || bottom <= top) return 0f

        val intersection = (right - left) * (bottom - top)
        val union = first.width * first.height + second.width * second.height - intersection
        return if (union <= 0f) 0f else intersection / union
    }
}
