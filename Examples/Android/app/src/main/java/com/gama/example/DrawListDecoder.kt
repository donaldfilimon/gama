package com.gama.example

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Minimal defensive reader for Gama DrawList binary format version 1. */
object DrawListDecoder {
    sealed interface Command
    data class Fill(val x: Int, val y: Int, val width: Int, val height: Int, val color: Int) : Command
    data class Text(val x: Int, val y: Int, val value: String, val foreground: Int) : Command
    data class Frame(val columns: Int, val rows: Int, val commands: List<Command>)

    fun decode(bytes: ByteArray): Frame {
        require(bytes.size >= 20) { "truncated Gama frame" }
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(input.int == 0x414D4147) { "invalid Gama magic" }
        require(input.int == 1) { "unsupported Gama frame version" }
        val columns = input.int
        val rows = input.int
        val commandCount = input.int.toUInt().toLong()
        require(columns >= 0 && rows >= 0) { "negative frame dimensions" }
        require(commandCount <= (bytes.size - 20L) / 17L) { "impossible command count" }
        val commands = ArrayList<Command>(commandCount.toInt())
        repeat(commandCount.toInt()) {
            when (input.get().toInt()) {
                0 -> {
                    val x = input.int; val y = input.int
                    val width = input.int; val height = input.int
                    require(width >= 0 && height >= 0) { "negative fill bounds" }
                    commands += Fill(x, y, width, height, readColor(input))
                }
                1 -> {
                    val x = input.int; val y = input.int
                    val foreground = readColor(input)
                    readColor(input) // background is carried but Canvas demo clears once per frame
                    input.short // text attributes
                    val length = input.int
                    require(length >= 0 && length <= input.remaining()) { "invalid UTF-8 length" }
                    val utf8 = ByteArray(length)
                    input.get(utf8)
                    commands += Text(x, y, utf8.toString(Charsets.UTF_8), foreground)
                }
                else -> error("unknown Gama command")
            }
        }
        require(!input.hasRemaining()) { "trailing Gama frame bytes" }
        return Frame(columns, rows, commands)
    }

    private fun readColor(input: ByteBuffer): Int {
        val red = input.get().toInt() and 0xff
        val green = input.get().toInt() and 0xff
        val blue = input.get().toInt() and 0xff
        val isDefault = input.get().toInt() and 1
        return if (isDefault == 1) android.graphics.Color.WHITE
        else android.graphics.Color.rgb(red, green, blue)
    }
}
