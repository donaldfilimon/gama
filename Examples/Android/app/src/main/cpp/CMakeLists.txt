cmake_minimum_required(VERSION 3.22.1)
project(gama_android LANGUAGES CXX)

if(NOT DEFINED GAMA_ROOT)
  message(FATAL_ERROR "GAMA_ROOT must point to the Gama checkout")
endif()

add_library(gama_swift SHARED IMPORTED)
set_target_properties(gama_swift PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libGamaAndroidDemo.so")

add_library(gama_android SHARED gama_jni.cpp)
target_compile_features(gama_android PRIVATE cxx_std_23)
target_include_directories(gama_android PRIVATE "${GAMA_ROOT}/Sources/GamaEmbedABI/include")
target_link_libraries(gama_android PRIVATE gama_swift log)
