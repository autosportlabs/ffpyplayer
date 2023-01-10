include 'includes/ffmpeg.pxi'


ctypedef struct FilteringContext:
    AVFilterContext *buffersink_ctx
    AVFilterContext *buffersrc_ctx
    AVFilterGraph *filter_graph
    AVPacket *enc_pkt
    AVFrame *filtered_frame


ctypedef struct StreamContext:
    AVCodecContext *dec_ctx
    AVCodecContext *enc_ctx
    AVFrame *dec_frame


cdef extern from "inttypes.h" nogil:
    const char *PRId64
    const char *PRIx64


cdef extern from "stdio.h" nogil:
    int snprintf(char *, size_t, const char *, ... )
    

cdef extern from "errno.h" nogil:
    int ENOENT
    int EAGAIN


cdef extern from "errno.h" nogil:
    int ENOMEM

cdef extern from "libavutil/error.h":
    char* av_err2str(int errnum)


cdef class Transcoder(object):

    cdef AVFormatContext *ifmt_ctx
    cdef AVFormatContext *ofmt_ctx
    cdef StreamContext *stream_ctx
    cdef FilteringContext *filter_ctx

    cdef int _end(self, int ret, AVPacket * packet) nogil except 1
    cdef int _free_filters(self, int ret, AVFilterInOut *inputs, AVFilterInOut *outputs) nogil except 1

    cdef int open_input_file(self, const char *filename) nogil except 1
    cdef int open_output_file(self, const char *filename, int output_width, int output_bitrate) nogil except 1
    cdef int init_filter(self, FilteringContext* fctx, AVCodecContext *dec_ctx,
        AVCodecContext *enc_ctx, const char *filter_spec) nogil except 1
    cdef int init_filters(self, const char *video_filters) nogil except 1
    cdef int encode_write_frame(self, unsigned int stream_index, int flush) nogil except 1
    cdef int filter_encode_write_frame(self, AVFrame *frame, unsigned int stream_index) nogil except 1
    cdef int flush_encoder(self, unsigned int stream_index) nogil except 1

    cdef int start_transcoding(self, const char *input_file, const char *output_file, const char *video_filters, int output_width, int output_bitrate) nogil except 1
