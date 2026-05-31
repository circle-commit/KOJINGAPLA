package com.kojingapla.glass

import android.graphics.Bitmap
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class OcrService(private val serverUrl: String) {
    fun analyze(image: Bitmap, mode: ProcessingMode): AnalysisResponse {
        val url = try {
            URL(serverUrl)
        } catch (_: Exception) {
            return error(mode, "분석을 시작하려면 앱 설정에 백엔드 서버 주소를 입력해 주세요.")
        }

        val imageBytes = ByteArrayOutputStream().use { stream ->
            if (!image.compress(Bitmap.CompressFormat.JPEG, 85, stream)) {
                return error(mode, "카메라 이미지를 업로드할 수 있도록 준비하지 못했습니다.")
            }
            stream.toByteArray()
        }

        return try {
            val boundary = "Boundary-${UUID.randomUUID()}"
            val connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 18_000
                doOutput = true
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }

            connection.outputStream.use { output ->
                output.write("--$boundary\r\n".toByteArray())
                output.write("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".toByteArray())
                output.write("${mode.wireName}\r\n".toByteArray())
                output.write("--$boundary\r\n".toByteArray())
                output.write("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n".toByteArray())
                output.write("Content-Type: image/jpeg\r\n\r\n".toByteArray())
                output.write(imageBytes)
                output.write("\r\n--$boundary--\r\n".toByteArray())
            }

            val responseCode = connection.responseCode
            val responseText = if (responseCode in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }

            if (responseCode !in 200..299) {
                return error(mode, "서버가 HTTP $responseCode 응답을 반환했습니다.")
            }

            parseResponse(JSONObject(responseText), mode)
        } catch (exception: Exception) {
            error(mode, "서버 연결에 실패했습니다: ${exception.localizedMessage ?: "알 수 없는 오류"}")
        }
    }

    private fun parseResponse(json: JSONObject, mode: ProcessingMode): AnalysisResponse {
        val detectionsJson = json.optJSONArray("detections")
        val detections = detectionsJson?.let { array ->
            buildList {
                for (index in 0 until array.length()) {
                    add(parseDetection(array.getJSONObject(index)))
                }
            }
        }

        val warningsJson = json.optJSONArray("warnings")
        val warnings = warningsJson?.toStringList()

        return AnalysisResponse(
            status = json.optString("status", "ok"),
            mode = json.optString("mode", mode.wireName),
            detectedText = json.optStringOrNull("detected_text"),
            voiceGuide = json.optString("voice_guide", ""),
            warnings = warnings,
            detections = detections
        )
    }

    private fun parseDetection(json: JSONObject): DetectionResponse =
        DetectionResponse(
            label = json.optString("label"),
            koreanLabel = json.optStringOrNull("korean_label"),
            confidence = json.optNullableDouble("confidence"),
            position = json.optStringOrNull("position"),
            bboxXyxy = json.optJSONArray("bbox_xyxy")?.toDoubleList(),
            areaRatio = json.optNullableDouble("area_ratio"),
            approaching = if (json.has("approaching") && !json.isNull("approaching")) json.optBoolean("approaching") else null,
            riskScore = if (json.has("risk_score") && !json.isNull("risk_score")) json.optInt("risk_score") else null
        )

    private fun error(mode: ProcessingMode, message: String): AnalysisResponse =
        AnalysisResponse(
            status = "error",
            mode = mode.wireName,
            detectedText = null,
            voiceGuide = message,
            warnings = null,
            detections = null
        )
}

private fun JSONObject.optStringOrNull(name: String): String? =
    if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotBlank() } else null

private fun JSONObject.optNullableDouble(name: String): Double? =
    if (has(name) && !isNull(name)) optDouble(name) else null

private fun JSONArray.toStringList(): List<String> =
    buildList {
        for (index in 0 until length()) add(optString(index))
    }

private fun JSONArray.toDoubleList(): List<Double> =
    buildList {
        for (index in 0 until length()) add(optDouble(index))
    }
