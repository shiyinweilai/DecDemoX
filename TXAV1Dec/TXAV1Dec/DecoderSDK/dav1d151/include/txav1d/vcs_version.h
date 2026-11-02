//
//  txav1d/vcs_version.h —— dav1d 兼容层
//
//  共用源码里 txav1d_bench.c 只是 include 这个头，并没有真的引用宏值；
//  真正用到 TXAV1D_VERSION 的是 txav1d_core.c，而那条路径不参与 dylib 构建。
//  这里仍然定义一个正确的值，避免将来有人加引用时拿到空字符串。
//

#ifndef TXAV1D_SHIM_DAV1D_VCS_VERSION_H
#define TXAV1D_SHIM_DAV1D_VCS_VERSION_H

/** 本快照对应的上游 dav1d 版本 */
#define TXAV1D_VERSION "1.5.1"

#endif /* TXAV1D_SHIM_DAV1D_VCS_VERSION_H */
