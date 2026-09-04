package com.gama.example

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View

private const val ACCEPTANCE_EXTRA = "com.gama.example.ACCEPTANCE"

class MainActivity : Activity() {
    private lateinit var host: GamaView

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        host = GamaView(intent.getBooleanExtra(ACCEPTANCE_EXTRA, false))
        setContentView(host)
    }

    override fun onDestroy() {
        host.close()
        super.onDestroy()
    }

    private inner class GamaView(acceptanceMode: Boolean) : View(this@MainActivity), AutoCloseable {
        private val native = GamaNative()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            textSize = 24f
        }
        private var frame = DrawListDecoder.Frame(0, 0, emptyList())

        init {
            check(native.resize(40, 12) == 0)
            val before = requireNotNull(native.frame())
            val beforeFrame = DrawListDecoder.decode(before)
            frame = beforeFrame
            if (acceptanceMode) {
                check(beforeFrame.columns == 40)
                val beforeTapLabels = tapLabels(beforeFrame)
                check(beforeTapLabels == listOf("Tapped 0")) {
                    "initial tap labels were $beforeTapLabels, expected [Tapped 0]"
                }
                check(native.pointer(1, 2, true) == 0)
                val after = requireNotNull(native.frame())
                frame = DrawListDecoder.decode(after)
                check(!before.contentEquals(after)) { "pointer action did not mutate the rendered frame" }
                val afterTapLabels = tapLabels(frame)
                check(afterTapLabels == listOf("Tapped 1")) {
                    "post-input tap labels were $afterTapLabels, expected [Tapped 1]"
                }
                contentDescription = "GAMA_OK ${frame.columns} ${frame.rows} TAPPED_0_TO_1"
                Log.i("GamaAcceptance", contentDescription.toString())
            } else {
                contentDescription = "Gama Android"
            }
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        private fun tapLabels(candidate: DrawListDecoder.Frame): List<String> = candidate.commands
            .filterIsInstance<DrawListDecoder.Text>()
            .map { it.value }
            .filter { it.startsWith("Tapped ") }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cellWidth = width.toFloat() / maxOf(1, frame.columns)
            val cellHeight = height.toFloat() / maxOf(1, frame.rows)
            frame.commands.forEach { command ->
                when (command) {
                    is DrawListDecoder.Fill -> {
                        paint.color = command.color
                        canvas.drawRect(
                            command.x * cellWidth, command.y * cellHeight,
                            (command.x + command.width) * cellWidth,
                            (command.y + command.height) * cellHeight, paint
                        )
                    }
                    is DrawListDecoder.Text -> {
                        paint.color = command.foreground
                        canvas.drawText(command.value, command.x * cellWidth, (command.y + 1) * cellHeight, paint)
                    }
                }
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val column = (event.x / (width.toFloat() / maxOf(1, frame.columns))).toInt()
            val row = (event.y / (height.toFloat() / maxOf(1, frame.rows))).toInt()
            native.pointer(column, row, event.action != MotionEvent.ACTION_UP)
            native.frame()?.let { frame = DrawListDecoder.decode(it) }
            invalidate()
            return true
        }

        override fun close() = native.close()
    }
}
