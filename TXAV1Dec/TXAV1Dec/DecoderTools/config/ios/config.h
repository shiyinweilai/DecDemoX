/*
 * iOS arm64 编译配置。
 *
 * 等价于参考仓库中 Meson 为 iOS/arm64 生成的 config.h，
 * 仅用于编译 tools/ 下的命令行源码，libtxav1d.a 本身已预编译好。
 */

#ifndef TXAV1D_CONFIG_IOS_CONFIG_H
#define TXAV1D_CONFIG_IOS_CONFIG_H

#define ARCH_AARCH64 1
#define ARCH_ARM 0
#define ARCH_LOONGARCH 0
#define ARCH_PPC64LE 0
#define ARCH_RISCV 0
#define ARCH_X86 0
#define ARCH_X86_32 0
#define ARCH_X86_64 0

#define CONFIG_LOG 1
#define ENDIANNESS_BIG 0

#define HAVE_AS_FUNC 0
#define HAVE_CLOCK_GETTIME 1
#define HAVE_IO_H 0
#define HAVE_POSIX_MEMALIGN 1
#define HAVE_UNISTD_H 1

#define TRIM_DSP_FUNCTIONS 0

#endif /* TXAV1D_CONFIG_IOS_CONFIG_H */
