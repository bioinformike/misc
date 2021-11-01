This is my repo where I keep all the scripts and programs that don't seem to fit into any of my other repos.

Contents:
random_audio_check.sh: A shell script that uses ffmpeg to check a video file for audio using random sampling of short duration clips, rather than processing the entire clip.

    Usage:
      random_audio_check.sh v0.3.0 [-v] [-f input file] [-n # samples] [-s sample lenght]
        -n   Number of video samples to measure volume    [Default: 5]
        -d   Video sample duration in seconds             [Default: 10]
        -f   Input video file
        -v   Increase verbosity
