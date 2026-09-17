plugins {
    id("com.android.application")
}

layout.buildDirectory.set(
    file(
        providers.gradleProperty("gamaAndroidBuildDir")
            .orElse("${System.getProperty("java.io.tmpdir")}/gama-android-gradle-build")
            .get()
    )
)

android {
    namespace = "com.gama.example"
    compileSdk = 36
    ndkVersion = "30.0.15729638"

    defaultConfig {
        applicationId = "com.gama.example"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += setOf("x86_64", "arm64-v8a") }
        externalNativeBuild {
            cmake {
                arguments += "-DGAMA_ROOT=${rootProject.projectDir.parentFile.parentFile.absolutePath}"
                cppFlags += "-std=c++23"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
            buildStagingDirectory = file(
                providers.gradleProperty("gamaAndroidCxxBuildDir")
                    .orElse("${System.getProperty("java.io.tmpdir")}/gama-android-cxx-build")
                    .get()
            )
        }
    }

    sourceSets["main"].jniLibs.srcDir("src/main/jniLibs")
}
