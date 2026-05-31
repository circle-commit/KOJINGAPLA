package com.kojingapla.glass

class DuplicateTextSuppressor {
    private var lastNormalizedText = ""
    private var lastSpokenMs = 0L
    private val cooldownMs = 8_000L

    fun shouldSpeak(text: String, nowMs: Long = System.currentTimeMillis()): Boolean {
        val normalized = normalize(text)
        if (normalized.isEmpty()) return false

        if (isDuplicate(normalized, lastNormalizedText)) return false

        if (nowMs - lastSpokenMs < cooldownMs) {
            val previousWords = lastNormalizedText.split(" ").filter { it.isNotEmpty() }.toSet()
            val newWords = normalized.split(" ").filter { it.isNotEmpty() }.toSet()
            if (previousWords.intersect(newWords).isNotEmpty()) return false
        }

        lastNormalizedText = normalized
        lastSpokenMs = nowMs
        return true
    }

    private fun normalize(text: String): String =
        text.lowercase()
            .replace(Regex("[^\\p{IsAlphabetic}\\p{IsDigit}]+"), " ")
            .trim()
            .replace(Regex("\\s+"), " ")

    private fun isDuplicate(first: String, second: String): Boolean {
        if (first.isEmpty() || second.isEmpty()) return false
        if (first == second || first.contains(second) || second.contains(first)) return true

        val firstWords = first.split(" ").toSet()
        val secondWords = second.split(" ").toSet()
        val overlap = firstWords.intersect(secondWords).size
        val union = firstWords.union(secondWords).size
        return union > 0 && overlap.toDouble() / union.toDouble() >= 0.84
    }
}
