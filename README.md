# misc

A collection of smaller standalone scripts and utilities that do not fit naturally into one of my other repositories or are not large enough to warrant a dedicated repository of their own.

Each utility is kept in its own directory along with a project-specific README containing additional documentation and usage information.

## Repository structure

```text
misc/
├── hg38_lib_updater/
│   ├── README.md
│   └── hg38_lib_update.sh
├── random_audio_checker/
│   ├── README.md
│   └── random_audio_check.sh
└── README.md
```

## Included scripts

### `hg38_lib_updater/hg38_lib_update.sh`

A Bash utility originally developed to help migrate an internal sequencing library to the hg38 genome build. Given a GSM accession and one or more corresponding SRR accessions, the script can download FASTQ files from GEO or ENA and run them through the ENCODE pipeline.

Although originally written for hg38, it can also work with other configured genome builds such as mm10. The script includes options for retrying downloads, ENA checksum validation, logging, cleanup behavior, LSF job submission, and testing workflows.

See [`hg38_lib_updater/README.md`](hg38_lib_updater/README.md) for full documentation and usage.

### `random_audio_checker/random_audio_check.sh`

A Bash utility that uses `ffmpeg` to quickly check whether a video file contains audible audio. Instead of processing the entire video, it samples several short sections from randomly selected locations and measures their audio levels.

The number of samples and sample duration can be configured, making it useful for quickly checking long video files without scanning the entire file.

See [`random_audio_checker/README.md`](random_audio_checker/README.md) for usage information.
