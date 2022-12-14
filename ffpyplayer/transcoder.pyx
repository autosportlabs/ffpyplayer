cdef class Transcoder(object):
    
    cdef (AVStream *, AVCodec *, AVCodecContext *) _find_decoder(self, AVFormatContext *ifmt_ctx, int i):
        cdef AVStream *stream = ifmt_ctx.streams[i]
        # cdef const AVCodec *dec = avcodec_find_decoder(stream.codecpar.codec_id)
        cdef AVCodec *dec = avcodec_find_decoder(stream.codecpar.codec_id)
        cdef AVCodecContext *codec_ctx = NULL

        return stream, dec, codec_ctx

    cdef int open_input_file(self, const char *filename) nogil except 1:
        cdef int ret
        cdef unsigned int i

        self.ifmt_ctx = NULL

        ret = avformat_open_input(&self.ifmt_ctx, filename, NULL, NULL)
        if ret < 0:
            with gil:
                print("Unable to open the file")
            return ret
        
        ret = avformat_find_stream_info(self.ifmt_ctx, NULL)
        if ret < 0:
            with gil:
                print("Unable to find the stream information")
            return ret
        
        self.stream_ctx = <StreamContext *>av_calloc(self.ifmt_ctx.nb_streams, sizeof(StreamContext))
        if not self.stream_ctx:
            return AVERROR(ENOMEM)
        
        for i in range(self.ifmt_ctx.nb_streams):
            with gil:
                decoder = self._find_decoder(self.ifmt_ctx, i)
            stream = decoder[0]
            dec = decoder[1]
            codec_ctx = decoder[2]

            if not dec:
                with gil:
                    print("Failed to find decoder for stream", i)

            codec_ctx = avcodec_alloc_context3(dec)
            if not codec_ctx:
                with gil:
                    print("Failed to allocate the decoder context for stream", i)
                return AVERROR(ENOMEM)
            
            ret = avcodec_parameters_to_context(codec_ctx, stream.codecpar)
            if ret < 0:
                with gil:
                    print("Failed to copy decoder parameters to input decoder context for stream", i)
                return ret

            
            if (codec_ctx.codec_type == AVMEDIA_TYPE_VIDEO or codec_ctx.codec_type == AVMEDIA_TYPE_AUDIO):

                if codec_ctx.codec_type == AVMEDIA_TYPE_VIDEO:
                    codec_ctx.framerate = av_guess_frame_rate(self.ifmt_ctx, stream, NULL)


                ret = avcodec_open2(codec_ctx, dec, NULL)
                if ret < 0:
                    with gil:
                        print("Failed to open decoder for stream", i)
                    return ret

            self.stream_ctx[i].dec_ctx = codec_ctx

            self.stream_ctx[i].dec_frame = av_frame_alloc()
            if not self.stream_ctx[i].dec_frame:
                return AVERROR(ENOMEM)

        av_dump_format(self.ifmt_ctx, 0, filename, 0)
        return 0

    # cdef int open_output_file(self, const char *filename) nogil except 1:
    #     cdef AVStream *out_stream
    #     cdef AVStream *in_stream
    #     cdef AVCodecContext *dec_ctx, *enc_ctx
    #     cdef const AVCodec *encoder
    #     cdef int ret
    #     cdef unsigned int i

    #     self.ofmt_ctx = NULL
    #     avformat_alloc_output_context2(&self.ofmt_ctx, NULL, NULL, filename)
    #     if not self.ofmt_ctx:
    #         with gil:
    #             print("Could not create output context")
    #         return AVERROR_UNKNOWN

    #     for i in range(self.ifmt_ctx.nb_streams):
    #         out_stream = avformat_new_stream(self.ofmt_ctx, NULL)
    #         if not out_stream:
    #             with gil:
    #                 print("Failed allocating output stream")
    #             return AVERROR_UNKNOWN

    #         in_stream = self.ifmt_ctx.streams[i]
    #         dec_ctx = self.stream_ctx[i].dec_ctx

    #         if dec_ctx.codec_type == AVMEDIA_TYPE_VIDEO or dec_ctx.codec_type == AVMEDIA_TYPE_AUDIO:
                
    #             # transcoding to same codec
    #             encoder = avcodec_find_encoder(dec_ctx.codec_id)
    #             if not encoder:
    #                 with gil:
    #                     print("Necessary encoder not found")
    #                 return AVERROR_INVALIDDATA
                
    #             enc_ctx = avcodec_alloc_context3(encoder)
    #             if not enc_ctx:
    #                 with gil:
    #                     print("Failed to allocate the encoder context")
    #                 return AVERROR(ENOMEM)

    #             # Transcoding to same properties (picture size, sample rate etc.)
    #             # These properties can be changed for output streams easily using filters
    #             if dec_ctx.codec_type == AVMEDIA_TYPE_VIDEO:
    #                 enc_ctx.height = dec_ctx.height
    #                 enc_ctx.width = dec_ctx.width
    #                 enc_ctx.sample_aspect_ratio = dec_ctx.sample_aspect_ratio
                    
    #                 # take first format from list of supported formats
    #                 if encoder.pix_fmts:
    #                     enc_ctx.pix_fmt = encoder.pix_fmts[0]
    #                 else:
    #                     enc_ctx.pix_fmt = dec_ctx.pix_fmt
                    
    #                 # video time_base can be set to whatever is handy and supported by encoder
    #                 enc_ctx.time_base = av_inv_q(dec_ctx.framerate)
    #             else:
    #                 enc_ctx.sample_rate = dec_ctx.sample_rate
    #                 enc_ctx.channel_layout = dec_ctx.channel_layout
    #                 enc_ctx.channels = av_get_channel_layout_nb_channels(enc_ctx.channel_layout)
                    
    #                 # take first format from list of supported formats
    #                 enc_ctx.sample_fmt = encoder.sample_fmts[0]
    #                 enc_ctx.time_base.num = 1
    #                 enc_ctx.time_base.den = enc_ctx.sample_rate

    #             if self.ofmt_ctx.oformat.flags and AVFMT_GLOBALHEADER:
    #                 enc_ctx.flags = enc_ctx.flags | AV_CODEC_FLAG_GLOBAL_HEADER

    #                 # Third parameter can be used to pass settings to encoder
    #                 ret = avcodec_open2(enc_ctx, encoder, NULL)
    #                 if ret < 0:
    #                     with gil:
    #                         print("Cannot open video encoder for stream #%u", i)
    #                     return ret
    #                 ret = avcodec_parameters_from_context(out_stream.codecpar, enc_ctx)
    #                 if ret < 0:
    #                     with gil:
    #                         print("Failed to copy encoder parameters to output stream #%u", i)
    #                     return ret

    #                 out_stream.time_base = enc_ctx.time_base
    #                 self.stream_ctx[i].enc_ctx = enc_ctx

    #             elif dec_ctx.codec_type == AVMEDIA_TYPE_UNKNOWN:
    #                 with gil:
    #                     print("Elementary stream is of unknown type, cannot proceed #%u", i)
    #                 return AVERROR_INVALIDDATA
    #             else:
    #                 ret = avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar)
    #                 if ret < 0:
    #                     with gil:
    #                         print("Copying parameters for stream #%u failed", i)
    #                     return ret
    #                 out_stream.time_base = in_stream.time_base

    #             return 0
        
    #     av_dump_format(self.ofmt_ctx, 0, filename, 1)

    #     if not (self.ofmt_ctx.oformat.flags and AVFMT_NOFILE):
    #         ret = avio_open(&self.ofmt_ctx.pb, filename, AVIO_FLAG_WRITE)
    #         if ret < 0:
    #             with gil:
    #                 print("Could not open output file '%s'", filename)
    #             return ret

    #     ret = avformat_write_header(self.ofmt_ctx, NULL)
    #     if ret < 0:
    #         with gil:
    #             print("Error occurred when opening output file")
    #         return ret
    #     return 0


    cdef int open_output_file(self, const char *filename) nogil except 1:
        cdef AVStream *out_stream
        cdef AVStream *in_stream
        cdef AVCodecContext *dec_ctx, *enc_ctx
        cdef const AVCodec *encoder
        cdef int ret
        cdef unsigned int i
        

        self.ofmt_ctx = NULL
        avformat_alloc_output_context2(&self.ofmt_ctx, NULL, NULL, filename)

        if not self.ofmt_ctx:
            with gil:
                print("Could not create output context")
            return AVERROR_UNKNOWN

        # cdef unsigned int i
        for i in range(self.ifmt_ctx.nb_streams):
            out_stream = avformat_new_stream(self.ofmt_ctx, NULL)
            if not out_stream:
                with gil:
                    print("Failed allocating output stream")
                return AVERROR_UNKNOWN

            in_stream = self.ifmt_ctx.streams[i]
            dec_ctx = self.stream_ctx[i].dec_ctx


            if (dec_ctx.codec_type == AVMEDIA_TYPE_VIDEO or dec_ctx.codec_type == AVMEDIA_TYPE_AUDIO):
                encoder = avcodec_find_encoder(dec_ctx.codec_id)
                if not encoder:
                    with gil:
                        print("Necessary encoder not found")
                    return AVERROR_INVALIDDATA
                
                enc_ctx = avcodec_alloc_context3(encoder)
                
                if not enc_ctx:
                    with gil:
                        print("Failed to allocate the encoder context")
                    return AVERROR(ENOMEM)

                if dec_ctx.codec_type == AVMEDIA_TYPE_VIDEO:
                    enc_ctx.height = dec_ctx.height
                    enc_ctx.width = dec_ctx.width
                    enc_ctx.sample_aspect_ratio = dec_ctx.sample_aspect_ratio
                    
                    if encoder.pix_fmts:
                        enc_ctx.pix_fmt = encoder.pix_fmts[0]
                    else:
                        enc_ctx.pix_fmt = dec_ctx.pix_fmt

                    enc_ctx.time_base = av_inv_q(dec_ctx.framerate)

                else:
                    enc_ctx.sample_rate = dec_ctx.sample_rate
                    enc_ctx.channel_layout = dec_ctx.channel_layout
                    enc_ctx.channels = av_get_channel_layout_nb_channels(enc_ctx.channel_layout)
                    
                    # take first format from list of supported formats
                    enc_ctx.sample_fmt = encoder.sample_fmts[0]
                    enc_ctx.time_base.num = 1
                    enc_ctx.time_base.den = enc_ctx.sample_rate

                if self.ofmt_ctx.oformat.flags & AVFMT_GLOBALHEADER:
                    enc_ctx.flags |= AV_CODEC_FLAG_GLOBAL_HEADER

                ret = avcodec_open2(enc_ctx, encoder, NULL)
                
                if ret < 0:
                    with gil:
                        print("Cannot open video encoder for stream", i)
                    return ret
                
                ret = avcodec_parameters_from_context(out_stream.codecpar, enc_ctx)
                if ret < 0:
                    with gil:
                        print("Failed to copy encoder parameters to output stream", i)
                    return ret

                out_stream.time_base = enc_ctx.time_base
                self.stream_ctx[i].enc_ctx = enc_ctx

            elif dec_ctx.codec_type == AVMEDIA_TYPE_UNKNOWN:
                with gil:
                    print("Elementary stream #%d is of unknown type, cannot proceed", i)
                return AVERROR_INVALIDDATA
            else:
                ret = avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar)
                if ret < 0:
                    with gil:
                        print("Copying parameters for stream failed", i)
                    return ret
                out_stream.time_base = in_stream.time_base

        av_dump_format(self.ofmt_ctx, 0, filename, 1)

        if not (self.ofmt_ctx.oformat.flags & AVFMT_NOFILE):
            ret = avio_open(&self.ofmt_ctx.pb, filename, AVIO_FLAG_WRITE)
            if ret < 0:
                with gil:
                    print("Could not open output file", filename)
                return ret

        ret = avformat_write_header(self.ofmt_ctx, NULL)
        if ret < 0:
            with gil:
                print("Error occurred when opening output file")
            return ret

        
        return 0

    cdef int _free_filters(self, int ret, AVFilterInOut *inputs, AVFilterInOut *outputs) nogil except 1:
        avfilter_inout_free(&inputs)
        avfilter_inout_free(&outputs)
        return ret

    cdef int init_filter(self, FilteringContext* fctx, AVCodecContext *dec_ctx, AVCodecContext *enc_ctx, const char *filter_spec) nogil except 1:
        cdef char args[512]
        cdef int ret = 0
        cdef const AVFilter *buffersrc = NULL
        cdef const AVFilter *buffersink = NULL
        cdef AVFilterContext *buffersrc_ctx = NULL
        cdef AVFilterContext *buffersink_ctx = NULL
        cdef AVFilterInOut *outputs = avfilter_inout_alloc()
        cdef AVFilterInOut *inputs  = avfilter_inout_alloc()
        cdef AVFilterGraph *filter_graph = avfilter_graph_alloc()


        if not outputs or not inputs or not filter_graph:
            ret = AVERROR(ENOMEM)
            self._free_filters(ret, inputs, outputs)

        if dec_ctx.codec_type == AVMEDIA_TYPE_VIDEO:
            buffersrc = avfilter_get_by_name("buffer")
            buffersink = avfilter_get_by_name("buffersink")
            
            if not buffersrc or not buffersink:
                with gil:
                    print("filtering source or sink element not found")
                ret = AVERROR_UNKNOWN
                self._free_filters(ret, inputs, outputs)

            snprintf(args, sizeof(args),
                    "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                    dec_ctx.width, dec_ctx.height, dec_ctx.pix_fmt,
                    dec_ctx.time_base.num, dec_ctx.time_base.den,
                    dec_ctx.sample_aspect_ratio.num,
                    dec_ctx.sample_aspect_ratio.den)

            ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in", args, NULL, filter_graph)
            if ret < 0:
                with gil:
                    print("Cannot create buffer source")
                self._free_filters(ret, inputs, outputs)

            ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out", NULL, NULL, filter_graph)
            if ret < 0:
                with gil:
                    print("Cannot create buffer sink")
                self._free_filters(ret, inputs, outputs)

            ret = av_opt_set_bin(buffersink_ctx, "pix_fmts", <uint8_t*>&enc_ctx.pix_fmt, sizeof(enc_ctx.pix_fmt), AV_OPT_SEARCH_CHILDREN)
            if ret < 0:
                with gil:
                    print("Cannot set output pixel format")
                self._free_filters(ret, inputs, outputs)

        elif dec_ctx.codec_type == AVMEDIA_TYPE_AUDIO:
            buffersrc = avfilter_get_by_name("abuffer")
            buffersink = avfilter_get_by_name("abuffersink")
            if not buffersrc or not buffersink:
                with gil:
                    print("filtering source or sink element not found")
                ret = AVERROR_UNKNOWN
                self._free_filters(ret, inputs, outputs)

            if not dec_ctx.channel_layout:
                dec_ctx.channel_layout = av_get_default_channel_layout(dec_ctx.channels)
                
            snprintf(args, sizeof(args),
                "time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=0x%lx",
                dec_ctx.time_base.num, dec_ctx.time_base.den, dec_ctx.sample_rate,
                av_get_sample_fmt_name(dec_ctx.sample_fmt),
                dec_ctx.channel_layout)
            
            
            ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in", args, NULL, filter_graph)
            if ret < 0:
                with gil:
                    print("Cannot create audio buffer source")
                self._free_filters(ret, inputs, outputs)

            ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out", NULL, NULL, filter_graph)
            if ret < 0:
                with gil:
                    print("Cannot create audio buffer sink")
                self._free_filters(ret, inputs, outputs)

            ret = av_opt_set_bin(buffersink_ctx, "sample_fmts", <uint8_t*>&enc_ctx.sample_fmt, sizeof(enc_ctx.sample_fmt), AV_OPT_SEARCH_CHILDREN)
            if ret < 0:
                with gil:
                    print("Cannot set output sample format")
                self._free_filters(ret, inputs, outputs)

            ret = av_opt_set_bin(buffersink_ctx, "channel_layouts", <uint8_t*>&enc_ctx.channel_layout, sizeof(enc_ctx.channel_layout), AV_OPT_SEARCH_CHILDREN)
            if ret < 0:
                with gil:
                    print("Cannot set output channel layout")
                self._free_filters(ret, inputs, outputs)

            ret = av_opt_set_bin(buffersink_ctx, "sample_rates", <uint8_t*>&enc_ctx.sample_rate, sizeof(enc_ctx.sample_rate), AV_OPT_SEARCH_CHILDREN)
            if ret < 0:
                with gil:
                    print("Cannot set output sample rate")
                self._free_filters(ret, inputs, outputs)

        else:
            ret = AVERROR_UNKNOWN
            self._free_filters(ret, inputs, outputs)

        # /* Endpoints for the filter graph. */
        outputs.name = av_strdup("in")
        outputs.filter_ctx = buffersrc_ctx
        outputs.pad_idx = 0
        outputs.next = NULL

        inputs.name  = av_strdup("out")
        inputs.filter_ctx = buffersink_ctx
        inputs.pad_idx = 0
        inputs.next = NULL

        if not outputs.name or not inputs.name:
            ret = AVERROR(ENOMEM)
            self._free_filters(ret, inputs, outputs)

        ret = avfilter_graph_parse_ptr(filter_graph, filter_spec, &inputs, &outputs, NULL)
        if ret < 0:
            self._free_filters(ret, inputs, outputs)

        ret = avfilter_graph_config(filter_graph, NULL)
        if ret < 0:
            self._free_filters(ret, inputs, outputs)

        # Fill FilteringContext
        fctx.buffersrc_ctx = buffersrc_ctx
        fctx.buffersink_ctx = buffersink_ctx
        fctx.filter_graph = filter_graph

        self._free_filters(ret, inputs, outputs)

    cdef int encode_write_frame(self, unsigned int stream_index, int flush) nogil except 1:
        cdef StreamContext *stream = &self.stream_ctx[stream_index]
        cdef FilteringContext *filter = &self.filter_ctx[stream_index]
        cdef AVPacket *enc_pkt = filter.enc_pkt
        cdef int ret

        cdef AVFrame *filt_frame
        if flush:
            filt_frame = NULL
        else:
            filt_frame = filter.filtered_frame

        with gil:
            print("Encoding frame")

        # encode filtered frame
        av_packet_unref(enc_pkt)
        
        ret = avcodec_send_frame(stream.enc_ctx, filt_frame)
        
        if ret < 0:
            return ret
        
        while ret >= 0:
            ret = avcodec_receive_packet(stream.enc_ctx, enc_pkt)
            
            if ret == AVERROR(EAGAIN) or ret == AVERROR_EOF:
                return 0
            
            # prepare packet for muxing
            enc_pkt.stream_index = stream_index
            av_packet_rescale_ts(enc_pkt,
                                stream.enc_ctx.time_base,
                                self.ofmt_ctx.streams[stream_index].time_base)
            
            with gil:
                print("Muxing frame")
            # mux encoded frame
            ret = av_interleaved_write_frame(self.ofmt_ctx, enc_pkt)
        
        return ret
    

    cdef int filter_encode_write_frame(self, AVFrame *frame, unsigned int stream_index) nogil except 1:
        cdef FilteringContext *filter = &self.filter_ctx[stream_index]
        cdef int ret
        
        with gil:
            print("Pushing decoded frame to filters")
        
        # push the decoded frame into the filtergraph
        ret = av_buffersrc_add_frame_flags(filter.buffersrc_ctx, frame, 0)
        if ret < 0:
            with gil:
                print("Error while feeding the filtergraph")
            return ret
        
        # pull filtered frames from the filtergraph
        while True:
            with gil:
                print("Pulling filtered frame from filters")
            ret = av_buffersink_get_frame(filter.buffersink_ctx, filter.filtered_frame)
            if ret < 0:

                # if no more frames for output - returns AVERROR(EAGAIN)
                # if flushed and no more frames for output - returns AVERROR_EOF
                # rewrite retcode to 0 to show it as normal procedure completion
                if ret == AVERROR(EAGAIN) or ret == AVERROR_EOF:
                    ret = 0
                break
            
            filter.filtered_frame.pict_type = AV_PICTURE_TYPE_NONE
            ret = self.encode_write_frame(stream_index, 0)
            av_frame_unref(filter.filtered_frame)
            if ret < 0:
                break
        
        return ret


    cdef int init_filters(self) nogil except 1:
        cdef const char *filter_spec
        cdef unsigned int i
        cdef int ret
        self.filter_ctx = <FilteringContext *>av_malloc_array(self.ifmt_ctx.nb_streams, sizeof(self.filter_ctx))

        if not self.filter_ctx:
            return AVERROR(ENOMEM)

        for i in range(self.ifmt_ctx.nb_streams):
            self.filter_ctx[i].buffersrc_ctx  = NULL
            self.filter_ctx[i].buffersink_ctx = NULL
            self.filter_ctx[i].filter_graph   = NULL
            if not (self.ifmt_ctx.streams[i].codecpar.codec_type == AVMEDIA_TYPE_AUDIO
                    or self.ifmt_ctx.streams[i].codecpar.codec_type == AVMEDIA_TYPE_VIDEO):
                continue

            if self.ifmt_ctx.streams[i].codecpar.codec_type == AVMEDIA_TYPE_VIDEO:
                filter_spec = "null" # passthrough (dummy) filter for video
            else:
                filter_spec = "anull" # passthrough (dummy) filter for audio
            ret = self.init_filter(&self.filter_ctx[i], self.stream_ctx[i].dec_ctx, self.stream_ctx[i].enc_ctx, filter_spec)
            if ret:
                return ret

            self.filter_ctx[i].enc_pkt = av_packet_alloc()
            if not self.filter_ctx[i].enc_pkt:
                return AVERROR(ENOMEM)

            self.filter_ctx[i].filtered_frame = av_frame_alloc()
            if not self.filter_ctx[i].filtered_frame:
                return AVERROR(ENOMEM)
        return 0


    cdef int flush_encoder(self, unsigned int stream_index) nogil except 1:
        if not (self.stream_ctx[stream_index].enc_ctx.codec.capabilities & AV_CODEC_CAP_DELAY):
            return 0
        
        with gil:
            print("Flushing stream encoder", stream_index)
        return self.encode_write_frame(stream_index, 1)

    cdef int start_transcoding(self, const char *input_file, const char *output_file) nogil except 1:
        cdef int ret
        cdef AVPacket *packet = NULL
        cdef unsigned int stream_index
        cdef unsigned int i

        cdef StreamContext *stream

        ret = self.open_input_file(input_file)
        if ret < 0:
            self._end(ret, packet)

        ret = self.open_output_file(output_file)
        if ret < 0:
            self._end(ret, packet)

        ret = self.init_filters()
        if ret < 0:
            self._end(ret, packet)
        
        packet = av_packet_alloc()
        if not packet:
            self._end(ret, packet)
        
        while True:
            ret = av_read_frame(self.ifmt_ctx, packet)
            if ret < 0:
                break

            stream_index = packet.stream_index
            with gil:
                print("Demuxer gave frame of stream_index", stream_index)

            if self.filter_ctx[stream_index].filter_graph:
                # StreamContext *stream = &self.stream_ctx[stream_index]
                stream = &self.stream_ctx[stream_index]

                with gil:
                    print("Going to reencode&filter the frame")

                av_packet_rescale_ts(packet, self.ifmt_ctx.streams[stream_index].time_base, stream.dec_ctx.time_base)
                ret = avcodec_send_packet(stream.dec_ctx, packet)

                if ret < 0:
                    with gil:
                        print("Decoding failed")
                    break

                while ret >= 0:
                    ret = avcodec_receive_frame(stream.dec_ctx, stream.dec_frame)
                    if ret == AVERROR_EOF or ret == AVERROR(EAGAIN):
                        break
                    elif ret < 0:
                        self._end(ret, packet)

                    stream.dec_frame.pts = stream.dec_frame.best_effort_timestamp

                    ret = self.filter_encode_write_frame(stream.dec_frame, stream_index)
                    if ret < 0:
                        self._end(ret, packet)
            else:
                av_packet_rescale_ts(packet,
                                    self.ifmt_ctx.streams[stream_index].time_base,
                                    self.ofmt_ctx.streams[stream_index].time_base)

                ret = av_interleaved_write_frame(self.ofmt_ctx, packet)
                if ret < 0:
                    self._end(ret, packet)
            av_packet_unref(packet)

        for i in range(self.ifmt_ctx.nb_streams):
            if not self.filter_ctx[i].filter_graph:
                continue
            
            ret = self.filter_encode_write_frame(NULL, i)
            if ret < 0:
                with gil:
                    print("Flushing filter failed")
                self._end(ret, packet)

            ret = self.flush_encoder(i)
            if ret < 0:
                with gil:
                    print("Flushing encoder failed")
                self._end(ret, packet)

        av_write_trailer(self.ofmt_ctx)


    cdef int _end(self, int ret, AVPacket * packet) nogil except 1:
        pass
        av_packet_free(&packet)

        for i in range(self.ifmt_ctx.nb_streams):

            avcodec_free_context(&self.stream_ctx[i].dec_ctx)
            if self.ofmt_ctx and self.ofmt_ctx.nb_streams > i and self.ofmt_ctx.streams[i] and self.stream_ctx[i].enc_ctx:
                avcodec_free_context(&self.stream_ctx[i].enc_ctx)

            if self.filter_ctx[i].filter_graph:
                avfilter_graph_free(&self.filter_ctx[i].filter_graph)

            av_frame_free(&self.filter_ctx[i].filtered_frame)
            av_packet_free(&self.filter_ctx[i].enc_pkt)

        av_free(self.filter_ctx)
        avformat_close_input(&self.ifmt_ctx)
        
        if self.ofmt_ctx and not (self.ofmt_ctx.oformat.flags and AVFMT_NOFILE):
            avio_closep(&self.ofmt_ctx.pb)
        avformat_free_context(self.ofmt_ctx)

        if ret:
            with gil:
                print("Error occurred")
            return 1

        return 0


def transcode(input_file="", output_file=""):
    if not input_file or not output_file:
        raise ValueError("Input file and/or output file not specified")
    
    transcoder = Transcoder()
    transcoder.start_transcoding(input_file.encode('utf-8'), output_file.encode('utf-8'))
