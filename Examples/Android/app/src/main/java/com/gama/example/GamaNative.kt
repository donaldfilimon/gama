package com.gama.example

/** Minimal lifecycle-safe JNI owner for the versioned Gama embedding ABI. */
class GamaNative : AutoCloseable {
    private var context: Long = nativeCreate()

    fun resize(columns: Int, rows: Int): Int = nativeResize(context, columns, rows)
    fun key(code: Int, scalar: Int = 0, shift: Boolean = false, control: Boolean = false): Int =
        nativeKey(context, code, scalar, shift, control)
    fun pointer(column: Int, row: Int, pressed: Boolean): Int =
        nativePointer(context, column, row, pressed)
    fun needsFrame(): Boolean = nativeNeedsFrame(context) == 1
    fun frame(): ByteArray? = nativeFrame(context)

    override fun close() {
        if (context != 0L) {
            nativeDestroy(context)
            context = 0
        }
    }

    private external fun nativeCreate(): Long
    private external fun nativeDestroy(context: Long)
    private external fun nativeResize(context: Long, columns: Int, rows: Int): Int
    private external fun nativeKey(
        context: Long, code: Int, scalar: Int, shift: Boolean, control: Boolean
    ): Int
    private external fun nativePointer(context: Long, column: Int, row: Int, pressed: Boolean): Int
    private external fun nativeNeedsFrame(context: Long): Int
    private external fun nativeFrame(context: Long): ByteArray?

    companion object {
        init { System.loadLibrary("gama_android") }
    }
}
