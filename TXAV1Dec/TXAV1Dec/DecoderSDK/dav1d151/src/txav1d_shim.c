//
//  txav1d_shim.c —— dav1d 兼容层的实现
//
//  只有两个函数需要真实实现：设置结构体的类型与 dav1d 不同，必须逐字段搬运。
//  其余 API 都在头文件里用宏改成了 dav1d_* 原名，不需要中转。
//

#include "txav1d/txav1d.h"

void txav1d_default_settings(Txav1dSettings *const settings) {
    if (!settings) return;

    Dav1dSettings d;
    dav1d_default_settings(&d);

    // 逐字段搬运而不是 memcpy：上游以后往结构体中间插字段时，
    // memcpy 会把错位的数据悄悄带进来（表现为「某个参数莫名不生效」），
    // 而逐字段写会在编译期报错，是更容易发现的失败方式。
    settings->n_threads = d.n_threads;
    settings->max_frame_delay = d.max_frame_delay;
    settings->apply_grain = d.apply_grain;
    settings->operating_point = d.operating_point;
    settings->all_layers = d.all_layers;
    settings->frame_size_limit = d.frame_size_limit;
    settings->allocator = d.allocator;
    settings->logger = d.logger;
    settings->strict_std_compliance = d.strict_std_compliance;
    settings->output_invisible_frames = d.output_invisible_frames;
    settings->inloop_filters = d.inloop_filters;
    settings->decode_frame_type = d.decode_frame_type;

    // dav1d 没有 WPP 开关（上游始终启用），这里固定填 -1。
    // 填 0 会让共用源码以为「已关闭 WPP」，报告里就会写下一个与实际不符的配置。
    settings->use_wpp = -1;

    memset(settings->reserved, 0, sizeof(settings->reserved));
}

int txav1d_open(Txav1dContext **const c_out, const Txav1dSettings *const settings) {
    if (!c_out || !settings) return DAV1D_ERR(EINVAL);

    Dav1dSettings d;
    dav1d_default_settings(&d);

    d.n_threads = settings->n_threads;
    d.max_frame_delay = settings->max_frame_delay;
    d.apply_grain = settings->apply_grain;
    d.operating_point = settings->operating_point;
    d.all_layers = settings->all_layers;
    d.frame_size_limit = settings->frame_size_limit;
    d.allocator = settings->allocator;
    d.logger = settings->logger;
    d.strict_std_compliance = settings->strict_std_compliance;
    d.output_invisible_frames = settings->output_invisible_frames;
    d.inloop_filters = settings->inloop_filters;
    d.decode_frame_type = settings->decode_frame_type;

    // settings->use_wpp 有意不参与：dav1d 没有这个开关。

    return dav1d_open(c_out, &d);
}

const char *txav1d_version(void) {
    return dav1d_version();
}
