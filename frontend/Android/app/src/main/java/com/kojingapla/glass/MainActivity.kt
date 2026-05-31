package com.kojingapla.glass

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.concurrent.thread
import kotlin.math.abs

class MainActivity : ComponentActivity(), TextToSpeech.OnInitListener {
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val ocrService = OcrService(SERVER_URL)
    private val stabilityTracker = TextStabilityTracker()
    private val duplicateSuppressor = DuplicateTextSuppressor()

    private lateinit var previewView: PreviewView
    private lateinit var titleText: TextView
    private lateinit var statusText: TextView
    private lateinit var guidanceCard: LinearLayout
    private lateinit var guidanceLabel: TextView
    private lateinit var guidanceText: TextView
    private lateinit var ocrPanel: LinearLayout
    private lateinit var ocrStatusText: TextView
    private lateinit var ocrResultText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var liveButton: Button
    private lateinit var textButton: Button
    private lateinit var directionButtons: List<TextView>

    private var textToSpeech: TextToSpeech? = null
    private var vibrator: Vibrator? = null
    private var currentMode = ProcessingMode.LIVE
    private var isProcessing = false
    private var latestGuide = "실시간 안내 모드가 준비되었습니다."
    private var latestDetectedText: String? = null
    private var liveOcrStatus = LiveOcrStatus.SEARCHING
    private var latestLiveDirection = "center"
    private var latestLiveRiskScore = 0
    private var lastLiveRequestMs = 0L
    private var lastFullOcrRequestMs = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
        textToSpeech = TextToSpeech(this, this)
        buildUi()

        if (hasCameraPermission()) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech?.language = Locale.KOREAN
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            liveOcrStatus = LiveOcrStatus.UNAVAILABLE
            latestGuide = "이 앱을 사용하려면 카메라 권한이 필요합니다."
            renderState()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
    }

    private fun buildUi() {
        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }

        val root = FrameLayout(this)
        root.addView(previewView, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(makeScrim(), FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        val overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(34), dp(20), dp(22))
        }
        root.addView(overlay, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        overlay.addView(makeHeader())
        overlay.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))

        guidanceCard = makeGuidanceCard()
        overlay.addView(guidanceCard)

        ocrPanel = makeOcrPanel()
        overlay.addView(ocrPanel)

        overlay.addView(makeDirectionStrip())
        overlay.addView(makeModeSelector())

        setContentView(root)
        renderState()
    }

    private fun makeScrim(): View =
        View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xB8000000.toInt(), 0x33000000, 0xE0000000.toInt())
            )
        }

    private fun makeHeader(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(62)
        }

        val icon = TextView(this).apply {
            text = "안내"
            gravity = Gravity.CENTER
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(PALETTE_LIVE)
            background = rounded(0xEF000000.toInt(), dp(24))
        }
        row.addView(icon, LinearLayout.LayoutParams(dp(48), dp(48)))

        val labels = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        titleText = TextView(this).apply {
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
        }
        statusText = TextView(this).apply {
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xB8FFFFFF.toInt())
        }
        labels.addView(titleText)
        labels.addView(statusText)
        row.addView(labels, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        progress = ProgressBar(this).apply {
            visibility = View.GONE
            isIndeterminate = true
        }
        row.addView(progress, LinearLayout.LayoutParams(dp(42), dp(42)))
        return row
    }

    private fun makeGuidanceCard(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(18), dp(22), dp(18))
            background = bordered(0xEF000000.toInt(), PALETTE_PRIMARY, dp(20), dp(3))

            guidanceLabel = TextView(context).apply {
                text = "안내"
                textSize = 16f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(PALETTE_PRIMARY)
            }
            guidanceText = TextView(context).apply {
                textSize = 32f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                setLineSpacing(dp(4).toFloat(), 1f)
                maxLines = 3
                setAutoSizeTextTypeUniformWithConfiguration(22, 32, 2, TypedValue.COMPLEX_UNIT_SP)
                setPadding(0, dp(12), 0, 0)
            }
            addView(guidanceLabel)
            addView(guidanceText)
        }

    private fun makeOcrPanel(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(18))
            background = bordered(0xEF000000.toInt(), PALETTE_PRIMARY, dp(18), dp(2))

            ocrStatusText = TextView(context).apply {
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
            }
            ocrResultText = TextView(context).apply {
                textSize = 26f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                setLineSpacing(dp(6).toFloat(), 1f)
                setAutoSizeTextTypeUniformWithConfiguration(18, 26, 2, TypedValue.COMPLEX_UNIT_SP)
                setPadding(0, dp(14), 0, 0)
            }
            val scroll = ScrollView(context).apply { addView(ocrResultText) }
            addView(ocrStatusText)
            addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(210)))
        }

    private fun makeDirectionStrip(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(10), 0, 0)
        }
        directionButtons = listOf("왼쪽", "정면", "오른쪽").map { label ->
            TextView(this).apply {
                text = label
                gravity = Gravity.CENTER
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
            }.also {
                val params = LinearLayout.LayoutParams(0, dp(64), 1f).apply {
                    marginEnd = dp(8)
                }
                row.addView(it, params)
            }
        }
        return row
    }

    private fun makeModeSelector(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = bordered(0xDB000000.toInt(), 0x38FFFFFF, dp(22), dp(2))
        }

        liveButton = modeButton("실시간") { setMode(ProcessingMode.LIVE) }
        textButton = modeButton("문자 읽기") { setMode(ProcessingMode.TEXT) }
        row.addView(liveButton, LinearLayout.LayoutParams(0, dp(58), 1f))
        row.addView(textButton, LinearLayout.LayoutParams(0, dp(58), 1f).apply { marginStart = dp(10) })
        return row
    }

    private fun modeButton(label: String, onClick: () -> Unit): Button =
        Button(this).apply {
            text = label
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setOnClickListener { onClick() }
        }

    private fun setMode(mode: ProcessingMode) {
        currentMode = mode
        stabilityTracker.reset()
        latestDetectedText = null
        liveOcrStatus = LiveOcrStatus.SEARCHING
        latestLiveDirection = "center"
        latestLiveRiskScore = 0

        latestGuide = if (mode == ProcessingMode.LIVE) {
            pulse(35)
            "실시간 보행 안내를 시작합니다."
        } else {
            pulse(65)
            "문자 읽기 모드입니다. 카메라를 가까운 문자에 맞춰주세요."
        }
        renderState()
        if (mode == ProcessingMode.LIVE) speak(latestGuide)
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val cameraProvider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(cameraExecutor, FrameAnalyzer()) }

            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            setMode(currentMode)
        }, ContextCompat.getMainExecutor(this))
    }

    private fun processImage(bitmap: android.graphics.Bitmap, mode: ProcessingMode, allowDuplicateSpeech: Boolean) {
        if (isProcessing) return
        isProcessing = true
        runOnUiThread { renderState() }

        thread(name = "backend-analysis") {
            val response = ocrService.analyze(bitmap, mode)
            if (currentMode != mode) {
                isProcessing = false
                runOnUiThread { renderState() }
                return@thread
            }

            val shouldSpeak = shouldSpeak(response, mode, allowDuplicateSpeech)
            if (shouldSpeak && mode == ProcessingMode.TEXT) pulse(90)

            runOnUiThread {
                updateResponse(response)
                isProcessing = false
                if (mode == ProcessingMode.TEXT) {
                    liveOcrStatus = if (response.status == "error") LiveOcrStatus.SEARCHING else LiveOcrStatus.COOLING_DOWN
                    if (response.status == "error") pulse(35) else if (!shouldSpeak) pulse(45)
                }
                renderState()
            }

            if (shouldSpeak) speak(response.voiceGuide)
        }
    }

    private fun shouldSpeak(response: AnalysisResponse, mode: ProcessingMode, allowDuplicateSpeech: Boolean): Boolean {
        if (mode == ProcessingMode.LIVE) return true
        if (response.status == "error") return true
        val detectedText = response.detectedText
        if (detectedText.isNullOrBlank()) return allowDuplicateSpeech
        return allowDuplicateSpeech || duplicateSuppressor.shouldSpeak(detectedText)
    }

    private fun updateResponse(response: AnalysisResponse) {
        latestGuide = response.voiceGuide.ifBlank { latestGuide }
        latestDetectedText = response.detectedText

        if (response.mode == ProcessingMode.LIVE.wireName && response.status != "error") {
            val primaryDetection = response.detections?.firstOrNull()
            latestLiveDirection = primaryDetection?.position ?: "center"
            latestLiveRiskScore = primaryDetection?.riskScore ?: 0
        } else if (response.mode == ProcessingMode.LIVE.wireName) {
            latestLiveDirection = "center"
            latestLiveRiskScore = 0
        }
    }

    private fun updateLiveOcrStatus(status: LiveOcrStatus) {
        if (currentMode != ProcessingMode.TEXT || (isProcessing && status != LiveOcrStatus.READING)) return
        liveOcrStatus = status
        if (latestDetectedText.isNullOrBlank()) latestGuide = status.message
        runOnUiThread { renderState() }
    }

    private fun renderState() {
        val textMode = currentMode == ProcessingMode.TEXT
        titleText.text = if (textMode) "문자 읽기" else "보행 안내"
        statusText.text = if (isProcessing) "처리 중" else if (textMode) "준비됨" else "주변 확인 중"
        progress.visibility = if (isProcessing) View.VISIBLE else View.GONE

        guidanceCard.visibility = if (textMode) View.GONE else View.VISIBLE
        ocrPanel.visibility = if (textMode) View.VISIBLE else View.GONE
        guidanceText.text = latestGuide
        ocrStatusText.text = liveOcrStatus.message
        ocrResultText.text = latestDetectedText.orEmpty()

        val severityColor = severityColor()
        guidanceLabel.setTextColor(severityColor)
        guidanceCard.background = bordered(0xEF000000.toInt(), severityColor, dp(20), dp(3))

        liveButton.background = rounded(if (!textMode) PALETTE_PRIMARY else PALETTE_PASSIVE, dp(16))
        liveButton.setTextColor(if (!textMode) Color.BLACK else Color.WHITE)
        textButton.background = rounded(if (textMode) PALETTE_PRIMARY else PALETTE_PASSIVE, dp(16))
        textButton.setTextColor(if (textMode) Color.BLACK else Color.WHITE)

        directionButtons.forEachIndexed { index, view ->
            val direction = when (index) {
                0 -> "left"
                2 -> "right"
                else -> "center"
            }
            val active = latestLiveDirection == direction
            view.background = bordered(if (active) severityColor else PALETTE_PASSIVE, 0x66FFFFFF, dp(14), dp(2))
            view.setTextColor(if (active) Color.BLACK else 0xC7FFFFFF.toInt())
            view.visibility = if (textMode) View.GONE else View.VISIBLE
        }
    }

    private fun severityColor(): Int =
        when {
            latestLiveRiskScore >= 85 -> PALETTE_DANGER
            latestLiveRiskScore >= 55 -> PALETTE_WARNING
            else -> PALETTE_PRIMARY
        }

    private fun speak(message: String) {
        if (message.isBlank()) return
        runOnUiThread {
            textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "guide-${System.currentTimeMillis()}")
        }
    }

    private fun pulse(durationMs: Long) {
        vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun rounded(color: Int, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()
        }

    private fun bordered(color: Int, strokeColor: Int, radius: Int, strokeWidth: Int): GradientDrawable =
        rounded(color, radius).apply { setStroke(strokeWidth, strokeColor) }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private inner class FrameAnalyzer : ImageAnalysis.Analyzer {
        private val recognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        private var isAnalyzingText = false
        private var lastTextAnalysisMs = 0L
        private var previousLumaSample: List<Double>? = null

        @OptIn(ExperimentalGetImage::class)
        override fun analyze(imageProxy: ImageProxy) {
            when (currentMode) {
                ProcessingMode.LIVE -> analyzeLive(imageProxy)
                ProcessingMode.TEXT -> analyzeText(imageProxy)
            }
        }

        private fun analyzeLive(imageProxy: ImageProxy) {
            val now = System.currentTimeMillis()
            if (isProcessing || now - lastLiveRequestMs < LIVE_REQUEST_INTERVAL_MS) {
                imageProxy.close()
                return
            }

            val bitmap = ImageProxyBitmapConverter.toBitmap(imageProxy)
            imageProxy.close()
            if (bitmap == null) return

            lastLiveRequestMs = now
            processImage(bitmap, ProcessingMode.LIVE, allowDuplicateSpeech = true)
        }

        @OptIn(ExperimentalGetImage::class)
        private fun analyzeText(imageProxy: ImageProxy) {
            val now = System.currentTimeMillis()
            val mediaImage = imageProxy.image
            if (mediaImage == null || isAnalyzingText || now - lastTextAnalysisMs < TEXT_FRAME_INTERVAL_MS) {
                imageProxy.close()
                return
            }

            isAnalyzingText = true
            lastTextAnalysisMs = now
            val sample = ImageProxyBitmapConverter.lumaSample(imageProxy)
            val blurScore = blurScore(sample)
            val movementScore = movementScore(sample)
            previousLumaSample = sample

            val inputImage = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            recognizer.process(inputImage)
                .addOnSuccessListener { result ->
                    val analysis = frameAnalysis(result, imageProxy.width, imageProxy.height, blurScore, movementScore)
                    val decision = stabilityTracker.update(analysis)
                    updateLiveOcrStatus(decision.status)

                    if (decision.shouldRunFullOcr && currentMode == ProcessingMode.TEXT && !isProcessing) {
                        if (now - lastFullOcrRequestMs >= FULL_OCR_COOLDOWN_MS) {
                            val bitmap = ImageProxyBitmapConverter.toBitmap(imageProxy)
                            lastFullOcrRequestMs = now
                            if (bitmap != null) {
                                liveOcrStatus = LiveOcrStatus.READING
                                processImage(bitmap, ProcessingMode.TEXT, allowDuplicateSpeech = false)
                            }
                        } else {
                            updateLiveOcrStatus(LiveOcrStatus.COOLING_DOWN)
                        }
                    }
                }
                .addOnCompleteListener {
                    isAnalyzingText = false
                    imageProxy.close()
                }
        }

        private fun frameAnalysis(
            text: Text,
            imageWidth: Int,
            imageHeight: Int,
            blurScore: Double,
            movementScore: Double
        ): OcrFrameAnalysis {
            val boxes = text.textBlocks.mapNotNull { it.boundingBox }
            val region = boxes.reduceOrNull { acc, rect ->
                android.graphics.Rect(
                    minOf(acc.left, rect.left),
                    minOf(acc.top, rect.top),
                    maxOf(acc.right, rect.right),
                    maxOf(acc.bottom, rect.bottom)
                )
            }?.let { box ->
                RectRatio(
                    left = box.left.toFloat() / imageWidth.toFloat(),
                    top = box.top.toFloat() / imageHeight.toFloat(),
                    right = box.right.toFloat() / imageWidth.toFloat(),
                    bottom = box.bottom.toFloat() / imageHeight.toFloat()
                )
            }

            return OcrFrameAnalysis(
                textRegion = region,
                confidence = if (boxes.isEmpty()) 0f else 0.8f,
                blurScore = blurScore,
                movementScore = movementScore,
                timestampMs = System.currentTimeMillis()
            )
        }

        private fun blurScore(sample: List<Double>): Double {
            if (sample.isEmpty()) return 0.0
            val columns = 24
            var edgeEnergy = 0.0
            var comparisons = 0
            sample.indices.forEach { index ->
                if (index % columns != columns - 1) {
                    edgeEnergy += abs(sample[index] - sample[index + 1])
                    comparisons += 1
                }
                val lowerIndex = index + columns
                if (lowerIndex < sample.size) {
                    edgeEnergy += abs(sample[index] - sample[lowerIndex])
                    comparisons += 1
                }
            }
            return if (comparisons == 0) 0.0 else edgeEnergy / comparisons.toDouble()
        }

        private fun movementScore(current: List<Double>): Double {
            val previous = previousLumaSample
            if (previous == null || previous.size != current.size) return 0.0
            return previous.zip(current).sumOf { abs(it.first - it.second) } / current.size.toDouble()
        }
    }

    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 10
        private const val SERVER_URL = "http://100.64.174.44:8000/analyze"
        private const val LIVE_REQUEST_INTERVAL_MS = 2_000L
        private const val FULL_OCR_COOLDOWN_MS = 3_000L
        private const val TEXT_FRAME_INTERVAL_MS = 160L

        private const val PALETTE_PRIMARY = 0xFFFFD61F.toInt()
        private const val PALETTE_LIVE = 0xFF29D18F.toInt()
        private const val PALETTE_WARNING = 0xFFFF941F.toInt()
        private const val PALETTE_DANGER = 0xFFFF2E2E.toInt()
        private const val PALETTE_PASSIVE = 0xFF2E2E33.toInt()
    }
}
