#PY  <- Needed to identify #

adm = Avidemux()
adm.videoCodec("x264")

if not adm.videoCodecSetProfile("x264", "Encode x264 CRF 19 Fast"):
    raise("Cannot load the Encode x264 CRF 19 Fast profile")
