/*
 * 命令行工具的编译配置。
 *
 * HAVE_XXHASH_H 为 0 时不编译 xxh3 封装，output.c 中也不会引用 xxh3_muxer。
 */

#ifndef TXAV1D_CONFIG_IOS_CLI_CONFIG_H
#define TXAV1D_CONFIG_IOS_CLI_CONFIG_H

#define HAVE_XXHASH_H 0

#endif /* TXAV1D_CONFIG_IOS_CLI_CONFIG_H */
