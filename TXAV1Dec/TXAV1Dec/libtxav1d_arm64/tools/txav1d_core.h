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
 * txav1d_lanuch() 的失败返回码。
 *
 * 成功时返回输入流的总帧数（>= 0），失败时返回该负值。
 * 使用负数而不是 EXIT_FAILURE(1)，是为了与“只有 1 帧的码流”区分开，
 * 调用方用 `< 0` 判断失败即可。
 */
#define TXAV1D_LANUCH_ERROR (-1)

/**
 * 启动一次 txav1d 解码，参数与 txav1d 命令行一致。
 *
 * @param argc 参数个数
 * @param argv 参数数组，与命令行语义相同
 * @return 输入流报告的帧总数；出错时返回 TXAV1D_LANUCH_ERROR
 */
int txav1d_lanuch(const int argc, char *const *const argv);

#ifdef __cplusplus
}
#endif

#endif /* TXAV1D_CORE_H */
