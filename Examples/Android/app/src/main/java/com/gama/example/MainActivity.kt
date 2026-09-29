package com.gama.example

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View

private const val ACCEPTANCE_EXTRA = "com.gama.example.ACCEPTANCE"

// The grid's text size in scale-independent pixels, so it follows both the
// screen density and the system font scale. The C ABI stays in cells: a
// larger font makes larger cells, and the view resizes the grid in cells.
private const val TEXT_SIZE_SP = 14f

class MainActivity : Activity() {
    private lateinit var host: GamaView

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        host = GamaView()
        if (intent.getBooleanExtra(ACCEPTANCE_EXTRA, false)) {
            host.runAcceptanceProbe()
        }
        setContentView(host)
    }

    override fun onDestroy() {
        host.close()
        super.onDestroy()
    }

    private inner class GamaView : View(this@MainActivity), AutoCloseable {
        private val native = GamaNative()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            textSize = scaledTextSize()
        }
        private var frame = DrawListDecoder.Frame(0, 0, emptyList())
        private var cellWidth = 1f
        private var cellHeight = 1f

        private fun scaledTextSize(): Float = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, TEXT_SIZE_SP, resources.displayMetrics
        )

        // One cell is the advance of "M" by the font's line spacing, measured
        // from the paint that draws the grid.
        private fun measureCell() {
            cellWidth = maxOf(1f, paint.measureText("M"))
            cellHeight = maxOf(1f, paint.fontSpacing)
        }

        // Refits the grid to the view in whole cells and redraws. A size
        // that yields the grid already in place sends nothing.
        private fun refit() {
            if (width <= 0 || height <= 0) return
            val columns = maxOf(1, (width / cellWidth).toInt())
            val rows = maxOf(1, (height / cellHeight).toInt())
            if (columns != frame.columns || rows != frame.rows) {
                check(native.resize(columns, rows) == 0)
                native.frame()?.let { frame = DrawListDecoder.decode(it) }
            }
            invalidate()
        }

        init {
            measureCell()
            // The acceptance probe runs before layout against this fixed
            // grid; the first layout then refits it to the view.
            check(native.resize(40, 12) == 0)
            frame = DrawListDecoder.decode(requireNotNull(native.frame()))
            contentDescription = "Gama Android"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        fun runAcceptanceProbe() {
            check(frame.columns == 40)
            val beforeTapLabels = tapLabels(frame)
            check(beforeTapLabels == listOf("Tapped 0")) {
                "initial tap labels were $beforeTapLabels, expected [Tapped 0]"
            }
            check(native.pointer(1, 2, true) == 0)
            val after = requireNotNull(native.frame())
            frame = DrawListDecoder.decode(after)
            val afterTapLabels = tapLabels(frame)
            check(afterTapLabels == listOf("Tapped 1")) {
                "post-input tap labels were $afterTapLabels, expected [Tapped 1]"
            }
            contentDescription = "GAMA_OK ${frame.columns} ${frame.rows} TAPPED_0_TO_1"
            Log.i("GamaAcceptance", contentDescription.toString())
        }

        private fun tapLabels(candidate: DrawListDecoder.Frame): List<String> = candidate.commands
            .filterIsInstance<DrawListDecoder.Text>()
            .map { it.value }
            .filter { it.startsWith("Tapped ") }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            refit()
        }

        // A font scale or density change re-derives the text size and the
        // cell, then refits. The manifest declares fontScale and density in
        // configChanges, so the activity keeps this view instead of being
        // recreated.
        override fun onConfigurationChanged(newConfig: Configuration) {
            super.onConfigurationChanged(newConfig)
            paint.textSize = scaledTextSize()
            measureCell()
            refit()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
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
                        canvas.drawText(
                            command.value, command.x * cellWidth,
                            command.y * cellHeight - paint.ascent(), paint
                        )
                    }
                }
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val column = (event.x / cellWidth).toInt()
            val row = (event.y / cellHeight).toInt()
            native.pointer(column, row, event.action != MotionEvent.ACTION_UP)
            native.frame()?.let { frame = DrawListDecoder.decode(it) }
            invalidate()
            return true
        }

        override fun close() = native.close()
    }
}
