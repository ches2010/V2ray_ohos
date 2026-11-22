cmake_minimum_required(VERSION 3.5.0)
project(v2rayng_harmony)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED napi_init.cpp)

# libxray_ohos.so 由 ohos-go 从 2dust/AndroidLibXrayLite 编译产出，
# 运行期通过 dlopen 加载（见 napi_init.cpp），此处无需链接。
target_link_libraries(entry PUBLIC libhilog_ndk.z.so libnapi_ndk.z.so libdl.so)
