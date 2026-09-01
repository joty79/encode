#PY  <- Needed to identify #

adm = Avidemux()
adm.videoCodec(
    "ffNvEncH264",
    "preset=6",
    "profile=2",
    "rc_mode=1",
    "quality=22",
    "bitrate=10000",
    "max_bitrate=20000",
    "gopsize=25",
    "refs=0",
    "bframes=0",
    "b_ref_mode=0",
    "lookahead=0",
    "aq_strength=1",
    "spatial_aq=False",
    "temporal_aq=False",
    "weighted_pred=False"
)
