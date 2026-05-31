package com.kojingapla.glass

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

object ImageProxyBitmapConverter {
    fun toBitmap(image: ImageProxy): Bitmap? {
        val nv21 = yuv420ToNv21(image)
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        val jpegBytes = ByteArrayOutputStream().use { stream ->
            yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 90, stream)
            stream.toByteArray()
        }
        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size) ?: return null
        val rotation = image.imageInfo.rotationDegrees
        if (rotation == 0) return bitmap

        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    fun lumaSample(image: ImageProxy, columns: Int = 24, rows: Int = 32): List<Double> {
        val plane = image.planes.firstOrNull() ?: return emptyList()
        val buffer = plane.buffer.duplicate()
        val rowStride = plane.rowStride
        val width = image.width
        val height = image.height
        val values = ArrayList<Double>(columns * rows)

        for (row in 0 until rows) {
            val y = (row * height / rows).coerceIn(0, height - 1)
            for (column in 0 until columns) {
                val x = (column * width / columns).coerceIn(0, width - 1)
                values.add(buffer.get(y * rowStride + x).unsignedInt().toDouble())
            }
        }

        return values
    }

    private fun yuv420ToNv21(image: ImageProxy): ByteArray {
        val width = image.width
        val height = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val nv21 = ByteArray(width * height * 3 / 2)

        var outputOffset = 0
        copyPlane(
            buffer = yPlane.buffer.duplicate(),
            width = width,
            height = height,
            rowStride = yPlane.rowStride,
            pixelStride = yPlane.pixelStride,
            output = nv21,
            outputOffset = outputOffset,
            outputPixelStride = 1
        )
        outputOffset += width * height

        val uBuffer = uPlane.buffer.duplicate()
        val vBuffer = vPlane.buffer.duplicate()
        val chromaWidth = width / 2
        val chromaHeight = height / 2
        for (row in 0 until chromaHeight) {
            for (column in 0 until chromaWidth) {
                val vIndex = row * vPlane.rowStride + column * vPlane.pixelStride
                val uIndex = row * uPlane.rowStride + column * uPlane.pixelStride
                nv21[outputOffset++] = vBuffer.get(vIndex)
                nv21[outputOffset++] = uBuffer.get(uIndex)
            }
        }
        return nv21
    }

    private fun copyPlane(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int,
        output: ByteArray,
        outputOffset: Int,
        outputPixelStride: Int
    ) {
        var offset = outputOffset
        for (row in 0 until height) {
            for (column in 0 until width) {
                output[offset] = buffer.get(row * rowStride + column * pixelStride)
                offset += outputPixelStride
            }
        }
    }

    private fun Byte.unsignedInt(): Int = toInt() and 0xFF
}
