package com.kojingapla.glass

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RoundRectShape
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.camera.core.*
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

    // ── 비즈니스 로직 (변경 없음) ─────────────────────────────
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val ocrService     = OcrService(SERVER_URL)
    private val stabilityTracker   = TextStabilityTracker()
    private val duplicateSuppressor = DuplicateTextSuppressor()

    private lateinit var previewView: PreviewView
    private var textToSpeech: TextToSpeech? = null
    private var vibrator: Vibrator? = null
    private var currentMode        = ProcessingMode.LIVE
    private var isProcessing       = false
    private var latestGuide        = "실시간 안내 모드가 준비되었습니다."
    private var latestDetectedText: String? = null
    private var liveOcrStatus      = LiveOcrStatus.SEARCHING
    private var latestLiveDirection = "center"
    private var latestLiveRiskScore = 0
    private var lastLiveRequestMs  = 0L
    private var lastFullOcrRequestMs = 0L

    // ── UI refs ───────────────────────────────────────────────
    private lateinit var statusDot:       View
    private lateinit var statusLabel:     TextView
    private lateinit var spinnerRef:      ProgressBar
    private lateinit var guidanceTag:     TextView
    private lateinit var guidanceMsg:     TextView
    private lateinit var guidanceCard:    LinearLayout
    private lateinit var ocrCard:         LinearLayout
    private lateinit var ocrStatusLbl:    TextView
    private lateinit var ocrDivider:      View
    private lateinit var ocrResultLbl:    TextView
    private lateinit var dirButtons:      List<LinearLayout>
    private lateinit var btnLive:         LinearLayout
    private lateinit var btnOcr:          LinearLayout

    // ── Lifecycle ─────────────────────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vibrator    = getSystemService(VIBRATOR_SERVICE) as Vibrator
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

    // ── UI Build ──────────────────────────────────────────────
    private fun buildUi() {
        previewView = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }

        val root = FrameLayout(this)
        root.addView(previewView, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(makeScrim(), FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        val overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(52), dp(16), dp(28))
        }
        root.addView(overlay, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        overlay.addView(makeModePill())
        overlay.addView(spacer())
        overlay.addView(buildGuidanceCard())
        overlay.addView(buildOcrCard())
        overlay.addView(buildDirStrip())
        overlay.addView(buildModeBar())

        setContentView(root)
        renderState()
    }

    // scrim: top dark → clear → bottom dark
    private fun makeScrim(): View = View(this).apply {
        background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0xE1050810.toInt(), 0x00000000, 0xF5040610.toInt())
        )
    }

    // ── Mode Pill (header) ────────────────────────────────────
    private fun makeModePill(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
            setPadding(dp(12), 0, dp(14), 0)
            background  = pillBg()
        }

        statusDot = View(this).apply {
            background = circle(C_LIVE)
        }
        row.addView(statusDot, dp(8), dp(8))

        statusLabel = TextView(this).apply {
            text      = "보행 안내"
            textSize  = 13f
            typeface  = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setPadding(dp(8), 0, 0, 0)
        }
        row.addView(statusLabel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        spinnerRef = ProgressBar(this).apply {
            isIndeterminate = true
            visibility      = View.GONE
            scaleX = 0.65f; scaleY = 0.65f
        }
        row.addView(spinnerRef, dp(24), dp(24))

        val wrap = FrameLayout(this)
        wrap.addView(row, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(38)))
        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(38))
        lp.bottomMargin = dp(14)
        wrap.layoutParams = lp
        return wrap
    }

    // ── Guidance Card ─────────────────────────────────────────
    private fun buildGuidanceCard(): LinearLayout {
        guidanceCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(18))
            background  = glassCard(C_PRIMARY, dp(20))
            elevation   = dp(12).toFloat()
        }

        // tag row: accent bar + label
        val tagRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
        }
        val accentBar = View(this).apply {
            background = rounded(C_PRIMARY, dp(2))
        }
        tagRow.addView(accentBar, dp(3), dp(14))
        guidanceTag = TextView(this).apply {
            text      = "안내"
            textSize  = 10f
            typeface  = Typeface.DEFAULT_BOLD
            letterSpacing = 0.12f
            setTextColor(C_PRIMARY)
            setPadding(dp(7), 0, 0, 0)
        }
        tagRow.addView(guidanceTag)
        guidanceCard.addView(tagRow)

        guidanceMsg = TextView(this).apply {
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setLineSpacing(dp(3).toFloat(), 1f)
            maxLines = 3
            setPadding(0, dp(10), 0, 0)
            setAutoSizeTextTypeUniformWithConfiguration(16, 22, 1, TypedValue.COMPLEX_UNIT_SP)
        }
        guidanceCard.addView(guidanceMsg, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.bottomMargin = dp(8)
        guidanceCard.layoutParams = lp
        return guidanceCard
    }

    // ── OCR Card ──────────────────────────────────────────────
    private fun buildOcrCard(): LinearLayout {
        ocrCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(18))
            background  = glassCard(C_PRIMARY, dp(20))
            elevation   = dp(12).toFloat()
        }

        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
        }

        // small icon badge
        val iconBadge = TextView(this).apply {
            text      = "OCR"
            textSize  = 9f
            typeface  = Typeface.DEFAULT_BOLD
            gravity   = Gravity.CENTER
            setTextColor(C_PRIMARY)
            background = rounded(0x261AADFF.toInt(), dp(7))
            setPadding(dp(6), dp(4), dp(6), dp(4))
        }
        topRow.addView(iconBadge)

        ocrStatusLbl = TextView(this).apply {
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0x78FFFFFF.toInt())
            setPadding(dp(10), 0, 0, 0)
        }
        topRow.addView(ocrStatusLbl, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val spin2 = ProgressBar(this).apply { isIndeterminate = true; scaleX = 0.65f; scaleY = 0.65f }
        topRow.addView(spin2, dp(24), dp(24))
        ocrCard.addView(topRow)

        ocrDivider = View(this).apply { background = GradientDrawable().apply { setColor(0x14FFFFFF) } }
        val divLp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1))
        divLp.topMargin = dp(14); divLp.bottomMargin = dp(14)
        ocrCard.addView(ocrDivider, divLp)

        ocrResultLbl = TextView(this).apply {
            textSize = 26f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setLineSpacing(dp(4).toFloat(), 1f)
            setAutoSizeTextTypeUniformWithConfiguration(18, 26, 1, TypedValue.COMPLEX_UNIT_SP)
        }
        ocrCard.addView(ocrResultLbl, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.bottomMargin = dp(8)
        ocrCard.layoutParams = lp
        return ocrCard
    }

    // ── Direction Strip ───────────────────────────────────────
    private fun buildDirStrip(): View {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val labels = listOf("왼쪽", "정면", "오른쪽")
        dirButtons = labels.map { lbl ->
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity     = Gravity.CENTER
                background  = glassCard(0x00000000, dp(14))
                elevation   = dp(4).toFloat()

                val arrow = TextView(this@MainActivity).apply {
                    text      = when (lbl) { "왼쪽" -> "←"; "오른쪽" -> "→"; else -> "↑" }
                    textSize  = 15f
                    typeface  = Typeface.DEFAULT_BOLD
                    gravity   = Gravity.CENTER
                    setTextColor(0x59FFFFFF.toInt())
                }
                val label = TextView(this@MainActivity).apply {
                    text      = lbl
                    textSize  = 9f
                    typeface  = Typeface.DEFAULT_BOLD
                    gravity   = Gravity.CENTER
                    letterSpacing = 0.05f
                    setTextColor(0x4CFFFFFF.toInt())
                    setPadding(0, dp(2), 0, 0)
                }
                addView(arrow)
                addView(label)

                val lp = LinearLayout.LayoutParams(0, dp(54), 1f)
                lp.marginEnd = if (lbl != "오른쪽") dp(7) else 0
                layoutParams = lp
            }.also { row.addView(it) }
        }
        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54))
        lp.bottomMargin = dp(8)
        row.layoutParams = lp
        return row
    }

    // ── Mode Bar (bottom) ─────────────────────────────────────
    private fun buildModeBar(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background  = glassCard(0x00000000, dp(22))
            elevation   = dp(12).toFloat()
        }

        btnLive = modeBtn("실시간")  { setMode(ProcessingMode.LIVE) }
        btnOcr  = modeBtn("문자 읽기") { setMode(ProcessingMode.TEXT) }

        row.addView(btnLive, LinearLayout.LayoutParams(0, dp(48), 1f))
        val ocrlp = LinearLayout.LayoutParams(0, dp(48), 1f)
        ocrlp.marginStart = dp(7)
        row.addView(btnOcr, ocrlp)
        return row
    }

    private fun modeBtn(label: String, onClick: () -> Unit): LinearLayout {
        val tv = TextView(this).apply {
            text     = label
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity  = Gravity.CENTER
            isAllCaps = false
            setTextColor(0x99FFFFFF.toInt())
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER
            background  = rounded(0x00000000, dp(16))
            setOnClickListener { onClick() }
            addView(tv, ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            tag = tv
        }
    }

    // ── Render ────────────────────────────────────────────────
    private fun renderState() {
        val isOcr = currentMode == ProcessingMode.TEXT

        statusLabel.text = if (isOcr) "문자 읽기" else "보행 안내"
        (statusDot.background as? GradientDrawable)?.setColor(if (isOcr) C_PRIMARY else C_LIVE)
        spinnerRef.visibility = if (isProcessing) View.VISIBLE else View.GONE

        guidanceCard.visibility = if (isOcr) View.GONE else View.VISIBLE
        ocrCard.visibility      = if (isOcr) View.VISIBLE else View.GONE

        // guidance card
        val sev = severityColor()
        guidanceMsg.text = latestGuide
        guidanceTag.setTextColor(sev)
        guidanceTag.text = when {
            latestLiveRiskScore >= 85 -> "위험"
            latestLiveRiskScore >= 55 -> "주의"
            else -> "안내"
        }
        guidanceCard.background = glassCard(sev and 0x00FFFFFF or 0x24000000, dp(20))
        // stroke tint via border
        (guidanceCard.background as? GradientDrawable)?.setStroke(dp(1), sev and 0x00FFFFFF or 0x47000000)

        // ocr card
        ocrStatusLbl.text = liveOcrStatus.message
        val hasResult = !latestDetectedText.isNullOrBlank()
        ocrDivider.visibility   = if (hasResult) View.VISIBLE else View.GONE
        ocrResultLbl.visibility = if (hasResult) View.VISIBLE else View.GONE
        ocrResultLbl.text       = latestDetectedText.orEmpty()

        // dir strip
        dirButtons.forEachIndexed { i, cell ->
            val dir = when (i) { 0 -> "left"; 2 -> "right"; else -> "center" }
            val active = !isOcr && latestLiveDirection == dir
            cell.visibility = if (isOcr) View.GONE else View.VISIBLE
            cell.background = if (active)
                glassCard(sev and 0x00FFFFFF or 0x24000000, dp(14)).also {
                    it.setStroke(dp(1), sev and 0x00FFFFFF or 0x73000000)
                }
            else glassCard(0x00000000, dp(14))
            val arrow = cell.getChildAt(0) as? TextView
            val label = cell.getChildAt(1) as? TextView
            val tc = if (active) sev else 0x47FFFFFF.toInt()
            arrow?.setTextColor(tc); label?.setTextColor(tc)
        }

        // mode bar
        listOf(btnLive to (currentMode == ProcessingMode.LIVE),
               btnOcr  to (currentMode == ProcessingMode.TEXT))
            .forEach { (btn, on) ->
                btn.background = if (on) rounded(C_PRIMARY, dp(16)) else rounded(0x00000000, dp(16))
                (btn.tag as? TextView)?.setTextColor(
                    if (on) Color.parseColor("#020F24") else 0x66FFFFFF.toInt()
                )
                btn.elevation = if (on) dp(6).toFloat() else 0f
            }
    }

    // ── setMode (unchanged logic) ─────────────────────────────
    private fun setMode(mode: ProcessingMode) {
        currentMode = mode
        stabilityTracker.reset()
        latestDetectedText = null
        liveOcrStatus      = LiveOcrStatus.SEARCHING
        latestLiveDirection = "center"
        latestLiveRiskScore = 0

        latestGuide = if (mode == ProcessingMode.LIVE) {
            pulse(35); "실시간 보행 안내를 시작할게요."
        } else {
            pulse(65); "문자 읽기 모드예요. 카메라를 가까운 문자에 맞춰 주세요."
        }
        renderState()
        if (mode == ProcessingMode.LIVE) speak(latestGuide)
    }

    // ── Camera / Processing (unchanged) ──────────────────────
    private fun startCamera() {
        val fut = ProcessCameraProvider.getInstance(this)
        fut.addListener({
            val cp = fut.get()
            val preview  = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
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

    private fun updateResponse(r: AnalysisResponse) {
        latestGuide = r.voiceGuide.ifBlank { latestGuide }
        latestDetectedText = r.detectedText
        if (r.mode == ProcessingMode.LIVE.wireName && r.status != "error") {
            val p = r.detections?.firstOrNull()
            latestLiveDirection = p?.position ?: "center"
            latestLiveRiskScore = p?.riskScore ?: 0
        } else if (r.mode == ProcessingMode.LIVE.wireName) {
            latestLiveDirection = "center"; latestLiveRiskScore = 0
        }
    }

    private fun updateLiveOcrStatus(s: LiveOcrStatus) {
        if (currentMode != ProcessingMode.TEXT || (isProcessing && s != LiveOcrStatus.READING)) return
        liveOcrStatus = s
        if (latestDetectedText.isNullOrBlank()) latestGuide = s.message
        runOnUiThread { renderState() }
    }

    private fun speak(msg: String) {
        if (msg.isBlank()) return
        runOnUiThread { textToSpeech?.speak(msg, TextToSpeech.QUEUE_FLUSH, null, "g-${System.currentTimeMillis()}") }
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

    // ── Draw helpers ──────────────────────────────────────────
    private fun rounded(color: Int, r: Int) = GradientDrawable().apply { setColor(color); cornerRadius = r.toFloat() }
    private fun circle(color: Int)          = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color) }
    private fun pillBg() = GradientDrawable().apply {
        setColor(0x12FFFFFF); cornerRadius = dp(18).toFloat()
        setStroke(dp(1), 0x1AFFFFFF)
    }
    private fun glassCard(stroke: Int, r: Int) = GradientDrawable().apply {
        setColor(0xBA060A18.toInt()); cornerRadius = r.toFloat()
        setStroke(dp(1), stroke or 0x1A000000)
    }
    private fun spacer() = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, 0, 1f)
    }
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    // ── FrameAnalyzer (unchanged) ─────────────────────────────
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
            processImage(bmp, ProcessingMode.LIVE, true)
        }

        @OptIn(ExperimentalGetImage::class)
        private fun text(proxy: ImageProxy) {
            val now = System.currentTimeMillis()
            val img = proxy.image
            if (img == null || isAnalyzing || now - lastAnalysisMs < 160L) { proxy.close(); return }
            isAnalyzing = true; lastAnalysisMs = now
            val sample = ImageProxyBitmapConverter.lumaSample(proxy)
            val blur   = blurScore(sample)
            val move   = moveScore(sample)
            prevLuma   = sample
            val input  = InputImage.fromMediaImage(img, proxy.imageInfo.rotationDegrees)
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
                android.graphics.Rect(minOf(a.left,b.left),minOf(a.top,b.top),maxOf(a.right,b.right),maxOf(a.bottom,b.bottom))
            }?.let { RectRatio(it.left.toFloat()/w,it.top.toFloat()/h,it.right.toFloat()/w,it.bottom.toFloat()/h) }
            return OcrFrameAnalysis(region, if(boxes.isEmpty()) 0f else 0.8f, blur, move, System.currentTimeMillis())
        }

        private fun blurScore(s: List<Double>): Double {
            if (s.isEmpty()) return 0.0; val c=24; var e=0.0; var n=0
            s.indices.forEach { i ->
                if (i%c!=c-1){e+=abs(s[i]-s[i+1]);n++}
                val j=i+c; if(j<s.size){e+=abs(s[i]-s[j]);n++}
            }
            return if(n==0) 0.0 else e/n
        }
        private fun moveScore(cur: List<Double>): Double {
            val p=prevLuma; return if(p==null||p.size!=cur.size) 0.0
            else p.zip(cur).sumOf{abs(it.first-it.second)}/cur.size
        }
    }

    companion object {
        private const val SERVER_URL = "http://100.64.174.44:8000/analyze"
        private val C_PRIMARY = 0xFF46BFFF.toInt()
        private val C_LIVE    = 0xFF29D18F.toInt()
        private val C_WARNING = 0xFFFF941F.toInt()
        private val C_DANGER  = 0xFFFF2E2E.toInt()
    }

    private fun severityColor() = when {
        latestLiveRiskScore >= 85 -> C_DANGER
        latestLiveRiskScore >= 55 -> C_WARNING
        else -> C_PRIMARY
    }
}
