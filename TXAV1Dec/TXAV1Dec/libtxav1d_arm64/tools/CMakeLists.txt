##
## Copyright(C) 2018 - 2020 Tencent.
##
## All Rights Reserved.
##

# executable
set(AV1D_APP_NAME av1d)
add_executable(${AV1D_APP_NAME} "")
if (NOT WIN32)
  add_definitions(-std=c99)
endif()
set_property(DIRECTORY PROPERTY VS_STARTUP_PROJECT "av1d")
# set c++11
# add_definitions(-std=c++11)
# target_compile_features(${AV1D_APP_NAME} PRIVATE cxx_constexpr)

set(AV1D_SOURCES ${CMAKE_CURRENT_LIST_DIR}/av1d.c
    ${CMAKE_CURRENT_LIST_DIR}/av1d_cli_parse.c
    ${CMAKE_CURRENT_LIST_DIR}/input/annexb.c
    ${CMAKE_CURRENT_LIST_DIR}/input/input.c
    ${CMAKE_CURRENT_LIST_DIR}/input/ivf.c
    ${CMAKE_CURRENT_LIST_DIR}/input/section5.c
    ${CMAKE_CURRENT_LIST_DIR}/output/md5.c
    ${CMAKE_CURRENT_LIST_DIR}/output/null.c
    ${CMAKE_CURRENT_LIST_DIR}/output/output.c
    ${CMAKE_CURRENT_LIST_DIR}/output/y4m2.c
    ${CMAKE_CURRENT_LIST_DIR}/output/yuv.c)
	
if (WIN32)
  set(AV1D_SOURCES ${AV1D_SOURCES} ${CMAKE_SOURCE_DIR}/tools/compat/getopt.c)
endif()

target_sources(${AV1D_APP_NAME}
  PRIVATE ${AV1D_SOURCES}
)

target_include_directories(${AV1D_APP_NAME}
  PRIVATE
  ${CMAKE_CURRENT_LIST_DIR}/inc
  ${PROJECT_SOURCE_DIR}/include

)

# compile setting
if (WIN32)
  if (CMAKE_CL_64)
    set(CMAKE_C_FLAGS "-EHsc -D_CRT_SECURE_NO_WARNINGS -DWIN32 -DARCH_X86_64=1 -DNDEBUG")
    set(CMAKE_CXX_FLAGS "-EHsc -D_CRT_SECURE_NO_WARNINGS -DWIN32 -DARCH_X86_64=1 -DNDEBUG")
  else()
    set(CMAKE_C_FLAGS "-EHsc -D_CRT_SECURE_NO_WARNINGS -DWIN32 -DARCH_X86_64=0 -DBITDEPTH=8 -DNDEBUG")
    set(CMAKE_CXX_FLAGS "-EHsc -D_CRT_SECURE_NO_WARNINGS -DWIN32 -DARCH_X86_64=0 -DBITDEPTH=8 -DNDEBUG")
  endif()
elseif (APPLE)
  include_directories(${PROJECT_SOURCE_DIR}/build/macos)
  set(CMAKE_XCODE_ATTRIBUTE_CMAKE_OSX_DEPLOYMENT_TARGET "10.8" CACHE STRING "Deployment target for osx" FORCE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "10.8" CACHE STRING "Deployment target for osx" FORCE)
  set(CMAKE_C_FLAGS "-m64 -stdlib=libc++")
  set(CMAKE_CXX_FLAGS "-m64 -stdlib=libc++")
  add_compile_definitions(ARCH_X86_64=1)
elseif (ANDROID)
  if("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "aarch64")
    include_directories(${PROJECT_SOURCE_DIR}/build/android/arm64)
    add_compile_definitions(AARCH64=1 NDEBUG)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "armv7-a")
    include_directories(${PROJECT_SOURCE_DIR}/build/android/armv7-a)
    add_compile_definitions(ARM=1 NDEBUG)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "i686")
    include_directories(${PROJECT_SOURCE_DIR}/build/android/x86)
    add_compile_definitions(NDEBUG)
  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
    include_directories(${PROJECT_SOURCE_DIR}/build/android/x86_64)
    add_compile_definitions(NDEBUG)
  endif()
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
  if (CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    add_compile_definitions(AARCH64=1 NDEBUG)
  elseif(LINUX_ARCH STREQUAL "x86_32")
    target_link_options(${AV1D_APP_NAME} PRIVATE -Wl,-melf_i386 -m32)
    target_compile_options(${AV1D_APP_NAME} PRIVATE -m32)
    add_compile_definitions(ARCH_X86_64=0 _FILE_OFFSET_BITS=64)
  else ()
    include_directories(${PROJECT_SOURCE_DIR}/build/linux)
    target_compile_options(${AV1D_APP_NAME} PRIVATE -m64 -D__STDC_FORMAT_MACROS -D_POSIX_C_SOURCE=199309L -D_GNU_SOURCE)
    add_compile_definitions(ARCH_X86_64=1)
  endif()
endif()

# link setting
if (WIN32)
  target_link_libraries(${AV1D_APP_NAME} ${AV1D_LIB_STATIC})
elseif (APPLE)
  target_link_libraries(${AV1D_APP_NAME} ${AV1D_LIB_STATIC} pthread dl m)
elseif (ANDROID)
  target_link_libraries(${AV1D_APP_NAME} ${AV1D_LIB_STATIC} dl m)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(${AV1D_APP_NAME} ${AV1D_LIB_STATIC} pthread dl m rt)
endif()
