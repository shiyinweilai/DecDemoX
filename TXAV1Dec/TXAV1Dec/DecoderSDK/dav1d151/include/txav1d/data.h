//
//  txav1d/data.h —— dav1d 兼容层转发
//
//  共用源码写的是 #include "txav1d/data.h"。dav1d 的头文件之间用相对路径
//  互相引用（data.h → common.h），所以这里只转发、不复制内容，
//  避免出现两份会被改歪的声明。
//

#ifndef TXAV1D_SHIM_DAV1D_DATA_H
#define TXAV1D_SHIM_DAV1D_DATA_H

#include "txav1d/txav1d.h"

#endif /* TXAV1D_SHIM_DAV1D_DATA_H */
