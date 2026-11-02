/*
 * Copyright © 2018-2021, VideoLAN and dav1d authors
 * Copyright © 2018, Two Orioles, LLC
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef AV1D_H
#define AV1D_H

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdarg.h>

#include "common.h"
#include "picture.h"
#include "data.h"
#include "version.h"

typedef struct Av1dContext Av1dContext;
typedef struct Av1dRef Av1dRef;

#define AV1D_MAX_THREADS 256
#define AV1D_MAX_FRAME_DELAY 256

typedef struct Av1dLogger {
    void *cookie; ///< Custom data to pass to the callback.
    /**
     * Logger callback. May be NULL to disable logging.
     *
     * @param cookie Custom pointer passed to all calls.
     * @param format The vprintf compatible format string.
     * @param     ap List of arguments referenced by the format string.
     */
    void (*callback)(void *cookie, const char *format, va_list ap);
} Av1dLogger;

typedef struct Av1dSettings {
    int n_threads;
    int max_frame_delay; ///< internally clipped to $n_threads. Set to 1 for low-latency decoding.
    int use_wpp;
    int apply_grain;
    int operating_point; ///< select an operating point for scalable AV1 bitstreams (0 - 31)
    int all_layers; ///< output all spatial layers of a scalable AV1 biststream
    unsigned frame_size_limit; ///< maximum frame size, in pixels (0 = unlimited)
    Av1dPicAllocator allocator; ///< Picture allocator callback.
    Av1dLogger logger; ///< Logger callback.
    uint8_t reserved[32]; ///< reserved for future use
} Av1dSettings;

/**
 * Get library version.
 */
AV1D_API const char *av1d_version(void);

/**
 * Initialize settings to default values.
 *
 * @param s Input settings context.
 */
AV1D_API void av1d_default_settings(Av1dSettings *s);

/**
 * Allocate and open a decoder instance.
 *
 * @param c_out The decoder instance to open. *c_out will be set to the
 *              allocated context.
 * @param     s Input settings context.
 *
 * @note The context must be freed using av1d_close() when decoding is
 *       finished.
 *
 * @return 0 on success, or < 0 (a negative AV1D_ERR code) on error.
 */
AV1D_API int av1d_open(Av1dContext **c_out, const Av1dSettings *s);

/**
 * Parse a Sequence Header OBU from bitstream data.
 *
 * @param out Output Sequence Header.
 * @param buf The data to be parser.
 * @param sz  Size of the data.
 *
 * @return
 *                  0: Success, and out is filled with the parsed Sequence Header
 *                     OBU parameters.
 *  AV1D_ERR(ENOENT): No Sequence Header OBUs were found in the buffer.
 *  other negative AV1D_ERR codes: Invalid data in the buffer, invalid passed-in
 *                                  arguments, and other errors during parsing.
 *
 * @note It is safe to feed this function data containing other OBUs than a
 *       Sequence Header, as they will simply be ignored. If there is more than
 *       one Sequence Header OBU present, only the last will be returned.
 */
AV1D_API int av1d_parse_sequence_header(Av1dSequenceHeader *out,
                                          const uint8_t *buf, const size_t sz);

/**
 * Feed bitstream data to the decoder.
 *
 * @param   c Input decoder instance.
 * @param  in Input bitstream data. On success, ownership of the reference is
 *            passed to the library.
 *
 * @return
 *         0: Success, and the data was consumed.
 *  AV1D_ERR(EAGAIN): The data can't be consumed. av1d_get_picture() should
 *                     be called to get one or more frames before the function
 *                     can consume new data.
 *  other negative AV1D_ERR codes: Error during decoding or because of invalid
 *                                  passed-in arguments.
 */
AV1D_API int av1d_send_data(Av1dContext *c, Av1dData *in);

/**
 * Return a decoded picture.
 *
 * @param   c Input decoder instance.
 * @param out Output frame. The caller assumes ownership of the returned
 *            reference.
 *
 * @return
 *         0: Success, and a frame is returned.
 *  AV1D_ERR(EAGAIN): Not enough data to output a frame. av1d_send_data()
 *                     should be called with new input.
 *  other negative AV1D_ERR codes: Error during decoding or because of invalid
 *                                  passed-in arguments.
 *
 * @note To drain buffered frames from the decoder (i.e. on end of stream),
 *       call this function until it returns AV1D_ERR(EAGAIN).
 *
 * @code{.c}
 *  Av1dData data = { 0 };
 *  Av1dPicture p = { 0 };
 *  int res;
 *
 *  read_data(&data);
 *  do {
 *      res = av1d_send_data(c, &data);
 *      // Keep going even if the function can't consume the current data
 *         packet. It eventually will after one or more frames have been
 *         returned in this loop.
 *      if (res < 0 && res != AV1D_ERR(EAGAIN))
 *          free_and_abort();
 *      res = av1d_get_picture(c, &p);
 *      if (res < 0) {
 *          if (res != AV1D_ERR(EAGAIN))
 *              free_and_abort();
 *      } else
 *          output_and_unref_picture(&p);
 *  // Stay in the loop as long as there's data to consume.
 *  } while (data.sz || read_data(&data) == SUCCESS);
 *
 *  // Handle EOS by draining all buffered frames.
 *  do {
 *      res = av1d_get_picture(c, &p);
 *      if (res < 0) {
 *          if (res != AV1D_ERR(EAGAIN))
 *              free_and_abort();
 *      } else
 *          output_and_unref_picture(&p);
 *  } while (res == 0);
 * @endcode
 */
AV1D_API int av1d_get_picture(Av1dContext *c, Av1dPicture *out);

/**
 * Close a decoder instance and free all associated memory.
 *
 * @param c_out The decoder instance to close. *c_out will be set to NULL.
 */
AV1D_API void av1d_close(Av1dContext **c_out);

/**
 * Flush all delayed frames in decoder and clear internal decoder state,
 * to be used when seeking.
 *
 * @param c Input decoder instance.
 *
 * @note Decoding will start only after a valid sequence header OBU is
 *       delivered to av1d_send_data().
 *
 */
AV1D_API void av1d_flush(Av1dContext *c);

enum Av1dEventFlags {
    /**
     * The last returned picture contains a reference to a new Sequence Header,
     * either because it's the start of a new coded sequence, or the decoder was
     * flushed before it was generated.
     */
    AV1D_EVENT_FLAG_NEW_SEQUENCE =       1 << 0,
    /**
     * The last returned picture contains a reference to a Sequence Header with
     * new operating parameters information for the current coded sequence.
     */
    AV1D_EVENT_FLAG_NEW_OP_PARAMS_INFO = 1 << 1,
};

/**
 * Fetch a combination of AV1D_EVENT_FLAG_* event flags generated by the decoding
 * process.
 *
 * @param c Input decoder instance.
 * @param flags Where to write the flags.
 *
 * @return 0 on success, or < 0 (a negative AV1D_ERR code) on error.
 *
 * @note Calling this function will clear all the event flags currently stored in
 *       the decoder.
 *
 */
AV1D_API int av1d_get_event_flags(Av1dContext *c, enum Av1dEventFlags *flags);

# ifdef __cplusplus
}
# endif

#endif /* AV1D_H */
