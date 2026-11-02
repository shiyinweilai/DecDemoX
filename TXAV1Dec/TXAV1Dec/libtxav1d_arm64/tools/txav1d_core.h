//
//  txav1d_core.h
//  TXAV1Dec
//
//  App 侧调用 txav1d 解码入口的声明。
//

#ifndef TXAV1D_CORE_H
#define TXAV1D_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 启动一次 txav1d 解码，参数与 txav1d 命令行一致。
 *
 * @param argc 参数个数
 * @param argv 参数数组，与命令行语义相同
 * @return 输入流报告的帧总数；出错时返回 EXIT_FAILURE
 */
int txav1d_lanuch(const int argc, char *const *const argv);

#ifdef __cplusplus
}
#endif

#endif /* TXAV1D_CORE_H */
