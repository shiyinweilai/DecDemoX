/*
 * Copyright © 2018, VideoLAN and txav1d authors
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

#ifndef TXAV1D_COMMON_H
#define TXAV1D_COMMON_H

#include <errno.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef TXAV1D_API
    #if defined _WIN32
      #if defined TXAV1D_BUILDING_DLL
        #define TXAV1D_API __declspec(dllexport)
      #else
        #define TXAV1D_API
      #endif
    #else
      #if __GNUC__ >= 4
        #define TXAV1D_API __attribute__ ((visibility ("default")))
      #else
        #define TXAV1D_API
      #endif
    #endif
#endif

#if EPERM > 0
#define TXAV1D_ERR(e) (-(e)) ///< Negate POSIX error code.
#else
#define TXAV1D_ERR(e) (e)
#endif

/**
 * A reference-counted object wrapper for a user-configurable pointer.
 */
typedef struct Txav1dUserData {
    const uint8_t *data; ///< data pointer
    struct Txav1dRef *ref; ///< allocation origin
} Txav1dUserData;

/**
 * Input packet metadata which are copied from the input data used to
 * decode each image into the matching structure of the output image
 * returned back to the user. Since these are metadata fields, they
 * can be used for other purposes than the documented ones, they will
 * still be passed from input data to output picture without being
 * used internally.
 */
typedef struct Txav1dDataProps {
    int64_t timestamp; ///< container timestamp of input data, INT64_MIN if unknown (default)
    int64_t duration; ///< container duration of input data, 0 if unknown (default)
    int64_t offset; ///< stream offset of input data, -1 if unknown (default)
    size_t size; ///< packet size, default Txav1dData.sz
    struct Txav1dUserData user_data; ///< user-configurable data, default NULL members
} Txav1dDataProps;

/**
 * Release reference to a Txav1dDataProps.
 */
TXAV1D_API void txav1d_data_props_unref(Txav1dDataProps *props);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* TXAV1D_COMMON_H */
