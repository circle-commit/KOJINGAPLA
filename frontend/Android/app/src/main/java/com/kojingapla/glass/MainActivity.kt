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
import android.speech.tts.Voice
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.concurrent.thread
import kotlin.math.abs

/**
 * Native Android port of the iOS `Glass` UI (ContentView.swift).
 *
 * Layout, palette, typography and component structure mirror SwiftUI 1:1:
 * a GLASS status bar, a mode pill, a bounding-box overlay over the live preview,
 * a guidance card (live) / OCR panel (text), and a bottom mode bar. The camera,
 * backend, TTS and stability-tracking logic are unchanged from before.
 */
class MainActivity : ComponentActivity(), TextToSpeech.OnInitListener {

    // ── Business logic ────────────────────────────────────────
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val ocrService = OcrService(SERVER_URL)
    private val stabilityTracker = TextStabilityTracker()
    private val duplicateSuppressor = DuplicateTextSuppressor()

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

    // Bounding-box state (mirrors iOS liveBoxes / liveImageSize).
    private var liveBoxes: List<LiveGuidanceBox> = emptyList()
    private var liveImageW = 0f
    private var liveImageH = 0f
    @Volatile private var latestFrameW = 0f
    @Volatile private var latestFrameH = 0f

    // ── UI refs ───────────────────────────────────────────────
    private lateinit var previewView: PreviewView
    private lateinit var boxOverlay: BoundingBoxOverlayView
    private lateinit var statusDot: View
    private lateinit var modeLabel: TextView
    private lateinit var modeSpinner: ProgressBar
    private lateinit var guidanceCard: LinearLayout
    private lateinit var guidanceAccent: View
    private lateinit var guidanceTag: TextView
    private lateinit var guidanceMsg: TextView
    private lateinit var ocrCard: LinearLayout
    private lateinit var ocrStatusLbl: TextView
    private lateinit var ocrSpinner: ProgressBar
    private lateinit var ocrDivider: View
    private lateinit var ocrResultLbl: TextView
    private lateinit var btnLive: LinearLayout
    private lateinit var btnLiveIcon: IconView
    private lateinit var btnLiveLabel: TextView
    private lateinit var btnOcr: LinearLayout
    private lateinit var btnOcrIcon: IconView
    private lateinit var btnOcrLabel: TextView

    private val density get() = resources.displayMetrics.density

    // ── Lifecycle ─────────────────────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
        textToSpeech = TextToSpeech(this, this)
        buildUi()
        if (hasCameraPermission()) startCamera()
        else ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 10)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) configureTtsVoice()
    }

    override fun onRequestPermissionsResult(req: Int, perms: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(req, perms, results)
        if (req == 10 && results.firstOrNull() == PackageManager.PERMISSION_GRANTED) startCamera()
        else { liveOcrStatus = LiveOcrStatus.UNAVAILABLE; renderState() }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        textToSpeech?.stop(); textToSpeech?.shutdown()
    }

    // ── UI build ──────────────────────────────────────────────
    private fun buildUi() {
        previewView = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
        boxOverlay = BoundingBoxOverlayView(this)

        val root = FrameLayout(this)
        root.addView(previewView, matchParent())
        root.addView(makeVignette(), matchParent())
        root.addView(boxOverlay, matchParent())

        val overlay = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(overlay, matchParent())

        // Edge-to-edge: pad the overlay by the system-bar insets so the camera bleeds
        // full-screen behind a status bar / nav bar that never overlaps the controls.
        ViewCompat.setOnApplyWindowInsetsListener(overlay) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(0, bars.top, 0, bars.bottom)
            insets
        }

        overlay.addView(makeStatusBar(), rowLp(top = 14, h = 36))
        overlay.addView(makeModePill(), rowLp(top = 16, h = 46))
        overlay.addView(View(this), LinearLayout.LayoutParams(MATCH, 0, 1f))   // Spacer
        guidanceCard = makeGuidanceCard()
        overlay.addView(guidanceCard, cardLp())
        ocrCard = makeOcrCard()
        overlay.addView(ocrCard, cardLp())
        overlay.addView(makeModeBar(), modeBarLp())

        setContentView(root)
        renderState()
    }

    // Vignette: top dark → clear → bottom dark, matching iOS VignetteLayer (bg #070810).
    private fun makeVignette(): View = View(this).apply {
        background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0xD1070810.toInt(), 0x2E070810, 0xEB070810.toInt())
        )
    }

    // ── Status bar (GLASS) ────────────────────────────────────
    private fun makeStatusBar(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = IconView(this, IconView.Type.CAMERA_VIEWFINDER).apply { setColor(C_PRIMARY) }
        row.addView(icon, LinearLayout.LayoutParams(dp(22), dp(22)))
        val title = TextView(this).apply {
            text = "GLASS"
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(dp(10), 0, 0, 0)
        }
        row.addView(title)
        return row
    }

    // ── Mode pill ─────────────────────────────────────────────
    private fun makeModePill(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = capsule(C_PILL, C_GLASS_STROKE, 23)
        }
        statusDot = View(this).apply { background = circle(C_LIVE) }
        row.addView(statusDot, LinearLayout.LayoutParams(dp(10), dp(10)).apply { marginStart = dp(14) })

        modeLabel = TextView(this).apply {
            text = "보행 안내"
            textSize = 17f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(dp(9), 0, 0, 0)
        }
        row.addView(modeLabel)

        modeSpinner = spinner(0.75f)
        row.addView(modeSpinner, LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginStart = dp(10) })

        row.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))   // trailing Spacer
        return row
    }

    // ── Guidance card (live) ──────────────────────────────────
    private fun makeGuidanceCard(): LinearLayout {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(22), dp(22), dp(22))
            background = glass(C_GLASS, withAlpha(C_PRIMARY, 0.28f), 24)
            elevation = dp(12).toFloat()
        }

        val tagRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        guidanceAccent = View(this).apply { background = rounded(C_PRIMARY, 3) }
        tagRow.addView(guidanceAccent, LinearLayout.LayoutParams(dp(5), dp(20)))
        guidanceTag = TextView(this).apply {
            text = "안내"
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.08f
            setTextColor(C_PRIMARY)
            setPadding(dp(8), 0, 0, 0)
        }
        tagRow.addView(guidanceTag)
        card.addView(tagRow)

        guidanceMsg = TextView(this).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setLineSpacing(dp(5).toFloat(), 1f)
            maxLines = 3
            // 28sp, shrinking to ~0.75× (≈21sp) to fit — mirrors iOS minimumScaleFactor(0.75).
            setAutoSizeTextTypeUniformWithConfiguration(21, 28, 1, TypedValue.COMPLEX_UNIT_SP)
        }
        card.addView(guidanceMsg, LinearLayout.LayoutParams(MATCH, WRAP).apply { topMargin = dp(12) })
        return card
    }

    // ── OCR panel (text) ──────────────────────────────────────
    private fun makeOcrCard(): LinearLayout {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(22), dp(22), dp(22))
            background = glass(C_GLASS, withAlpha(C_PRIMARY, 0.25f), 24)
            elevation = dp(18).toFloat()
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val iconBox = FrameLayout(this).apply { background = rounded(withAlpha(C_PRIMARY, 0.14f), 10) }
        val icon = IconView(this, IconView.Type.TEXT_VIEWFINDER).apply { setColor(C_PRIMARY) }
        iconBox.addView(icon, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        header.addView(iconBox, LinearLayout.LayoutParams(dp(36), dp(36)))

        ocrStatusLbl = TextView(this).apply {
            text = liveOcrStatus.message
            textSize = 17f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(C_DIM_TEXT)
            setPadding(dp(12), 0, 0, 0)
        }
        header.addView(ocrStatusLbl, LinearLayout.LayoutParams(0, WRAP, 1f))

        ocrSpinner = spinner(0.85f)
        header.addView(ocrSpinner, LinearLayout.LayoutParams(dp(26), dp(26)))
        card.addView(header)

        ocrDivider = View(this).apply { setBackgroundColor(0x14FFFFFF) }
        card.addView(ocrDivider, LinearLayout.LayoutParams(MATCH, dp(1)).apply {
            topMargin = dp(16); bottomMargin = dp(16)
        })

        ocrResultLbl = TextView(this).apply {
            textSize = 32f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setLineSpacing(dp(6).toFloat(), 1f)
        }
        card.addView(ocrResultLbl, LinearLayout.LayoutParams(MATCH, WRAP))
        return card
    }

    // ── Mode bar (bottom) ─────────────────────────────────────
    private fun makeModeBar(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(7), dp(7), dp(7), dp(7))
            background = glass(C_GLASS, C_GLASS_STROKE, 26)
            elevation = dp(12).toFloat()
        }

        val live = makeModeButton(IconView.Type.EYE, "실시간") { setMode(ProcessingMode.LIVE) }
        btnLive = live.first; btnLiveIcon = live.second; btnLiveLabel = live.third
        val ocr = makeModeButton(IconView.Type.TEXT_VIEWFINDER, "문자 읽기") { setMode(ProcessingMode.TEXT) }
        btnOcr = ocr.first; btnOcrIcon = ocr.second; btnOcrLabel = ocr.third

        row.addView(btnLive, LinearLayout.LayoutParams(0, dp(58), 1f))
        row.addView(btnOcr, LinearLayout.LayoutParams(0, dp(58), 1f).apply { marginStart = dp(8) })
        return row
    }

    private fun makeModeButton(
        iconType: IconView.Type,
        label: String,
        onClick: () -> Unit
    ): Triple<LinearLayout, IconView, TextView> {
        val icon = IconView(this, iconType)
        val text = TextView(this).apply {
            this.text = label
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dp(8), 0, 0, 0)
        }
        val btn = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = rounded(C_PILL, 16)
            isClickable = true
            isFocusable = true
            contentDescription = label
            setOnClickListener { onClick() }
            addView(icon, LinearLayout.LayoutParams(dp(22), dp(22)))
            addView(text)
        }
        return Triple(btn, icon, text)
    }

    // ── Render ────────────────────────────────────────────────
    private fun renderState() {
        val isOcr = currentMode == ProcessingMode.TEXT

        statusDot.background = circle(if (isOcr) C_PRIMARY else C_LIVE)
        modeLabel.text = if (isOcr) "문자 읽기" else "보행 안내"
        modeSpinner.visibility = if (isProcessing) View.VISIBLE else View.GONE

        guidanceCard.visibility = if (isOcr) View.GONE else View.VISIBLE
        ocrCard.visibility = if (isOcr) View.VISIBLE else View.GONE

        boxOverlay.visibility = if (isOcr) View.GONE else View.VISIBLE
        if (isOcr) boxOverlay.clear() else boxOverlay.update(liveBoxes, liveImageW, liveImageH)

        // Guidance card
        val sev = severityColor()
        guidanceTag.text = when {
            latestLiveRiskScore >= 85 -> "위험"
            latestLiveRiskScore >= 55 -> "주의"
            else -> "안내"
        }
        guidanceTag.setTextColor(sev)
        guidanceAccent.background = rounded(sev, 3)
        guidanceMsg.text = latestGuide
        guidanceCard.background = glass(C_GLASS, withAlpha(sev, 0.28f), 24)

        // OCR panel
        ocrStatusLbl.text = liveOcrStatus.message
        ocrSpinner.visibility = if (isProcessing) View.VISIBLE else View.GONE
        val hasResult = !latestDetectedText.isNullOrBlank()
        ocrDivider.visibility = if (hasResult) View.VISIBLE else View.GONE
        ocrResultLbl.visibility = if (hasResult) View.VISIBLE else View.GONE
        ocrResultLbl.text = latestDetectedText.orEmpty()

        // Mode bar
        styleModeButton(btnLive, btnLiveIcon, btnLiveLabel, active = !isOcr)
        styleModeButton(btnOcr, btnOcrIcon, btnOcrLabel, active = isOcr)
    }

    private fun styleModeButton(btn: LinearLayout, icon: IconView, label: TextView, active: Boolean) {
        btn.background = rounded(if (active) C_PRIMARY else C_PILL, 16)
        btn.elevation = if (active) dp(7).toFloat() else 0f
        val tint = if (active) C_DARK else 0x99FFFFFF.toInt()
        icon.setColor(tint)
        label.setTextColor(tint)
    }

    private fun severityColor(): Int = when {
        latestLiveRiskScore >= 85 -> C_DANGER
        latestLiveRiskScore >= 55 -> C_WARNING
        else -> C_PRIMARY
    }

    // ── Mode switching ────────────────────────────────────────
    private fun setMode(mode: ProcessingMode) {
        currentMode = mode
        stabilityTracker.reset()
        latestDetectedText = null
        liveOcrStatus = LiveOcrStatus.SEARCHING
        latestLiveDirection = "center"
        latestLiveRiskScore = 0
        liveBoxes = emptyList()

        latestGuide = if (mode == ProcessingMode.LIVE) {
            pulse(35); "실시간 보행 안내를 시작할게요."
        } else {
            pulse(65); "문자 읽기 모드예요. 카메라를 가까운 문자에 맞춰 주세요."
        }
        renderState()
        if (mode == ProcessingMode.LIVE) speak(latestGuide)
    }

    // ── Camera / processing ───────────────────────────────────
    private fun startCamera() {
        val fut = ProcessCameraProvider.getInstance(this)
        fut.addListener({
            val cp = fut.get()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build().also { it.setAnalyzer(cameraExecutor, FrameAnalyzer()) }
            cp.unbindAll()
            cp.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            setMode(currentMode)
        }, ContextCompat.getMainExecutor(this))
    }

    private fun processImage(bmp: android.graphics.Bitmap, mode: ProcessingMode, allowDup: Boolean) {
        if (isProcessing) return
        isProcessing = true
        runOnUiThread { renderState() }
        thread(name = "backend") {
            val resp = ocrService.analyze(bmp, mode)
            if (currentMode != mode) { isProcessing = false; runOnUiThread { renderState() }; return@thread }
            val speak = shouldSpeak(resp, mode, allowDup)
            if (speak && mode == ProcessingMode.TEXT) pulse(90)
            runOnUiThread {
                updateResponse(resp)
                isProcessing = false
                if (mode == ProcessingMode.TEXT) {
                    liveOcrStatus = if (resp.status == "error") LiveOcrStatus.SEARCHING else LiveOcrStatus.COOLING_DOWN
                    if (resp.status == "error") pulse(35) else if (!speak) pulse(45)
                }
                renderState()
            }
            if (speak) speak(resp.voiceGuide)
        }
    }

    private fun shouldSpeak(r: AnalysisResponse, m: ProcessingMode, allowDup: Boolean): Boolean {
        if (m == ProcessingMode.LIVE) return true
        if (r.status == "error") return true
        val t = r.detectedText
        return if (t.isNullOrBlank()) allowDup else allowDup || duplicateSuppressor.shouldSpeak(t)
    }

    private fun updateResponse(response: AnalysisResponse) {
        latestGuide = response.voiceGuide.ifBlank { latestGuide }
        latestDetectedText = response.detectedText

        if (response.mode == ProcessingMode.LIVE.wireName && response.status != "error") {
            val primaryDetection = response.detections?.firstOrNull()
            latestLiveDirection = primaryDetection?.position ?: "center"
            latestLiveRiskScore = primaryDetection?.riskScore ?: 0
            liveImageW = latestFrameW
            liveImageH = latestFrameH
            liveBoxes = makeLiveBoxes(response.detections, latestFrameW, latestFrameH)
        } else if (response.mode == ProcessingMode.LIVE.wireName) {
            latestLiveDirection = "center"
            latestLiveRiskScore = 0
            liveBoxes = emptyList()
        }
    }

    /// Builds bounding boxes for the highest-risk detections (mirrors iOS makeLiveBoxes):
    /// keep objects with a valid 4-value bbox, sort by risk desc, take the top 2.
    private fun makeLiveBoxes(detections: List<DetectionResponse>?, w: Float, h: Float): List<LiveGuidanceBox> {
        if (detections == null || w <= 0f || h <= 0f) return emptyList()
        return detections
            .filter { (it.riskScore ?: 0) >= LIVE_BOX_MIN_RISK && (it.bboxXyxy?.size ?: 0) == 4 }
            .sortedByDescending { it.riskScore ?: 0 }
            .take(LIVE_BOX_MAX_COUNT)
            .mapNotNull { d ->
                val bb = d.bboxXyxy ?: return@mapNotNull null
                if (bb.size != 4) return@mapNotNull null
                val x1 = minOf(bb[0], bb[2]); val y1 = minOf(bb[1], bb[3])
                val x2 = maxOf(bb[0], bb[2]); val y2 = maxOf(bb[1], bb[3])
                LiveGuidanceBox(
                    rect = RectRatio((x1 / w).toFloat(), (y1 / h).toFloat(), (x2 / w).toFloat(), (y2 / h).toFloat()),
                    riskScore = d.riskScore ?: 0,
                    label = d.koreanLabel ?: d.label
                )
            }
    }

    private fun updateLiveOcrStatus(s: LiveOcrStatus) {
        if (currentMode != ProcessingMode.TEXT || (isProcessing && s != LiveOcrStatus.READING)) return
        liveOcrStatus = s
        if (latestDetectedText.isNullOrBlank()) latestGuide = s.message
        runOnUiThread { renderState() }
    }

    private fun speak(message: String) {
        if (message.isBlank()) return
        runOnUiThread {
            textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "guide-${System.currentTimeMillis()}")
        }
    }

    private fun configureTtsVoice() {
        textToSpeech?.apply {
            language = Locale.KOREAN
            setSpeechRate(0.92f); setPitch(1.04f)
            voices?.filter { it.locale.language == Locale.KOREAN.language }
                ?.filterNot { it.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) == true }
                ?.sortedWith(compareByDescending<Voice> { it.quality }.thenBy { it.latency })
                ?.firstOrNull()?.let { voice = it }
        }
    }

    private fun pulse(ms: Long) {
        vibrator?.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    private fun hasCameraPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    // ── Layout / drawable helpers ─────────────────────────────
    private fun dp(v: Int) = (v * density).toInt()

    private fun matchParent() = FrameLayout.LayoutParams(MATCH, MATCH)

    private fun rowLp(top: Int, h: Int) = LinearLayout.LayoutParams(MATCH, dp(h)).apply {
        topMargin = dp(top); marginStart = dp(24); marginEnd = dp(24)
    }

    private fun cardLp() = LinearLayout.LayoutParams(MATCH, WRAP).apply {
        marginStart = dp(24); marginEnd = dp(24)
    }

    private fun modeBarLp() = LinearLayout.LayoutParams(MATCH, WRAP).apply {
        topMargin = dp(12); bottomMargin = dp(30); marginStart = dp(18); marginEnd = dp(18)
    }

    private fun rounded(color: Int, r: Int) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(r).toFloat()
    }

    private fun circle(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL; setColor(color)
    }

    private fun capsule(fill: Int, stroke: Int, r: Int) = GradientDrawable().apply {
        setColor(fill); cornerRadius = dp(r).toFloat(); setStroke(dpStroke(1f), stroke)
    }

    private fun glass(fill: Int, stroke: Int, r: Int) = GradientDrawable().apply {
        setColor(fill); cornerRadius = dp(r).toFloat(); setStroke(dpStroke(1.5f), stroke)
    }

    private fun dpStroke(v: Float) = (v * density).toInt().coerceAtLeast(1)

    private fun spinner(scale: Float) = ProgressBar(this).apply {
        isIndeterminate = true
        visibility = View.GONE
        scaleX = scale; scaleY = scale
        indeterminateTintList = android.content.res.ColorStateList.valueOf(C_PRIMARY)
    }

    private fun withAlpha(color: Int, fraction: Float): Int {
        val a = (fraction.coerceIn(0f, 1f) * 255).toInt()
        return (color and 0x00FFFFFF) or (a shl 24)
    }

    // ── FrameAnalyzer (unchanged logic) ───────────────────────
    private inner class FrameAnalyzer : ImageAnalysis.Analyzer {
        private val recognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        private var isAnalyzing = false
        private var lastAnalysisMs = 0L
        private var prevLuma: List<Double>? = null

        @OptIn(ExperimentalGetImage::class)
        override fun analyze(proxy: ImageProxy) {
            when (currentMode) { ProcessingMode.LIVE -> live(proxy); ProcessingMode.TEXT -> text(proxy) }
        }

        private fun live(proxy: ImageProxy) {
            val now = System.currentTimeMillis()
            if (isProcessing || now - lastLiveRequestMs < 2_000L) { proxy.close(); return }
            val bmp = ImageProxyBitmapConverter.toBitmap(proxy); proxy.close()
            if (bmp == null) return
            lastLiveRequestMs = now
            latestFrameW = bmp.width.toFloat()
            latestFrameH = bmp.height.toFloat()
            processImage(bmp, ProcessingMode.LIVE, true)
        }

        @OptIn(ExperimentalGetImage::class)
        private fun text(proxy: ImageProxy) {
            val now = System.currentTimeMillis()
            val img = proxy.image
            if (img == null || isAnalyzing || now - lastAnalysisMs < 160L) { proxy.close(); return }
            isAnalyzing = true; lastAnalysisMs = now
            val sample = ImageProxyBitmapConverter.lumaSample(proxy)
            val blur = blurScore(sample)
            val move = moveScore(sample)
            prevLuma = sample
            val input = InputImage.fromMediaImage(img, proxy.imageInfo.rotationDegrees)
            recognizer.process(input)
                .addOnSuccessListener { res ->
                    val analysis = frameAnalysis(res, proxy.width, proxy.height, blur, move)
                    val decision = stabilityTracker.update(analysis)
                    updateLiveOcrStatus(decision.status)
                    if (decision.shouldRunFullOcr && currentMode == ProcessingMode.TEXT && !isProcessing) {
                        if (now - lastFullOcrRequestMs >= 3_000L) {
                            val bmp = ImageProxyBitmapConverter.toBitmap(proxy)
                            lastFullOcrRequestMs = now
                            if (bmp != null) { liveOcrStatus = LiveOcrStatus.READING; processImage(bmp, ProcessingMode.TEXT, false) }
                        } else updateLiveOcrStatus(LiveOcrStatus.COOLING_DOWN)
                    }
                }
                .addOnCompleteListener { isAnalyzing = false; proxy.close() }
        }

        private fun frameAnalysis(t: Text, w: Int, h: Int, blur: Double, move: Double): OcrFrameAnalysis {
            val boxes = t.textBlocks.mapNotNull { it.boundingBox }
            val region = boxes.reduceOrNull { a, b ->
                android.graphics.Rect(minOf(a.left, b.left), minOf(a.top, b.top), maxOf(a.right, b.right), maxOf(a.bottom, b.bottom))
            }?.let { RectRatio(it.left.toFloat() / w, it.top.toFloat() / h, it.right.toFloat() / w, it.bottom.toFloat() / h) }
            return OcrFrameAnalysis(region, if (boxes.isEmpty()) 0f else 0.8f, blur, move, System.currentTimeMillis())
        }

        private fun blurScore(s: List<Double>): Double {
            if (s.isEmpty()) return 0.0; val c = 24; var e = 0.0; var n = 0
            s.indices.forEach { i ->
                if (i % c != c - 1) { e += abs(s[i] - s[i + 1]); n++ }
                val j = i + c; if (j < s.size) { e += abs(s[i] - s[j]); n++ }
            }
            return if (n == 0) 0.0 else e / n
        }

        private fun moveScore(cur: List<Double>): Double {
            val p = prevLuma; return if (p == null || p.size != cur.size) 0.0
            else p.zip(cur).sumOf { abs(it.first - it.second) } / cur.size
        }
    }

    companion object {
        private const val SERVER_URL = "http://100.64.174.44:8000/analyze"
        private const val LIVE_BOX_MIN_RISK = 0
        private const val LIVE_BOX_MAX_COUNT = 2

        // Palette (mirrors iOS `P`).
        private val C_PRIMARY = 0xFF45B8FF.toInt()
        private val C_LIVE = 0xFF29DE8F.toInt()
        private val C_WARNING = 0xFFFF941F.toInt()
        private val C_DANGER = 0xFFFF3B3B.toInt()
        private val C_GLASS = 0xB8172138.toInt()
        private val C_GLASS_STROKE = 0x1AFFFFFF
        private val C_DIM_TEXT = 0x73FFFFFF
        private val C_PILL = 0x12FFFFFF
        private val C_DARK = 0xFF050F24.toInt()

        private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
    }
}
