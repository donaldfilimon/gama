#include <jni.h>
#include <cstdint>
#include "GamaEmbed.h"

// Supplied by AndroidDemoBootstrap.swift so the sample, not the framework,
// chooses the concrete application associated with a context.
extern "C" GamaEmbedContext gama_android_demo_v1_create(void);

extern "C" JNIEXPORT jlong JNICALL
Java_com_gama_example_GamaNative_nativeCreate(JNIEnv *, jobject) {
    return reinterpret_cast<jlong>(gama_android_demo_v1_create());
}

extern "C" JNIEXPORT void JNICALL
Java_com_gama_example_GamaNative_nativeDestroy(JNIEnv *, jobject, jlong context) {
    gama_embed_v1_context_destroy(reinterpret_cast<GamaEmbedContext>(context));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_gama_example_GamaNative_nativeResize(JNIEnv *, jobject, jlong context, jint columns, jint rows) {
    return gama_embed_v1_resize(reinterpret_cast<GamaEmbedContext>(context), columns, rows);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_gama_example_GamaNative_nativeKey(
    JNIEnv *, jobject, jlong context, jint code, jint scalar, jboolean shift, jboolean control) {
    return gama_embed_v1_key(reinterpret_cast<GamaEmbedContext>(context), code, scalar, shift, control);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_gama_example_GamaNative_nativePointer(
    JNIEnv *, jobject, jlong context, jint column, jint row, jboolean pressed) {
    return gama_embed_v1_pointer(reinterpret_cast<GamaEmbedContext>(context), column, row, pressed);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_gama_example_GamaNative_nativeNeedsFrame(JNIEnv *, jobject, jlong context) {
    return gama_embed_v1_needs_frame(reinterpret_cast<GamaEmbedContext>(context));
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_gama_example_GamaNative_nativeFrame(JNIEnv *env, jobject, jlong context) {
    std::int32_t length = 0;
    const auto *bytes = gama_embed_v1_frame(reinterpret_cast<GamaEmbedContext>(context), &length);
    if (bytes == nullptr || length <= 0) return nullptr;
    jbyteArray output = env->NewByteArray(length);
    if (output == nullptr) return nullptr;
    env->SetByteArrayRegion(output, 0, length, reinterpret_cast<const jbyte *>(bytes));
    return output;
}
