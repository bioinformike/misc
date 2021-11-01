#!/bin/bash
VERSION="0.2.0"

# Number of samples to extractDefault number of samples to take from input file
NUM_SAMPLES=5

# Duration of each sample to play video to capture audio
SAMPLE_DURATION=10

# Verbosity flag
verbose=false


print_usage() {
	printf
    printf "%s" "usage: ${0}v${VERSION} [-ndv] [-f input file]"
    printf "%-5s%s\n" "-n" "Number of video samples to measure volume [Default: 5]"
    printf "%-5s%s\n" "-d" "Video sample duration in seconds [Default: 10]"
    printf "%-5s%s\n" "-f" "Input video file"
    printf "%-5s%s\n" "-v" "Increase verbosity"
    exit 1
}

while getopts 'n:d:f:v' flag; do
  case "${flag}" in
    n) NUM_SAMPLES="${OPTARG}" ;;
    d) SAMPLE_DURATION="${OPTARG}" ;;
    f) input_video="${OPTARG}" ;;
    v) verbose=true ;;
    *) print_usage
       exit 1 ;;
  esac
done

       
# Get the duration of file and truncate to int
# https://unix.stackexchange.com/q/89712
file_probe=$(ffprobe -i "${input_video}" -show_format 2>&1)

if echo "$file_probe" | grep -q "Invalid data found when processing input"; then
  printf "%s\n"  "Input file, ${input_video}, is not a supported video file"
  exit 1
fi

video_duration_raw=$(echo "${file_probe}" | sed -n 's/duration=//p')
video_duration=$(printf "%.0f" "${video_duration_raw}")

if [ "${verbose}" = true ]; then 
  printf "%-30s %s\n"  "Number of samples" "${NUM_SAMPLES}"
  printf "%-30s %s\n"  "Sample duration" "${SAMPLE_DURATION}"
  printf "%-30s %s\n"  "Input file" "${input_video}"
  printf "%-30s %s\n"  "Video duration raw" "${video_duration_raw}"
  printf "%-30s %s\n"  "Video duration" "${video_duration}"
fi

# Inspired by the following to generate the random numbers
# https://stackoverflow.com/a/21651047
video_clip_times=($(shuf -i 0-"${video_duration}" -n "${NUM_SAMPLES}"))

declare -a errors=()
cumulative_mean_volume=0

for x in "${!video_clip_times[@]}"; do 
  iter_str=$((x + 1))

	curr_seek_seconds=${video_clip_times[x]}
	end_seek_seconds=$((curr_seek_seconds + SAMPLE_DURATION))

	# Nifty way of converting seconds to hours:minutes:seconds
	seek_str=$(date -d@"${curr_seek_seconds}" -u +%H:%M:%S)
  end_str=$(date -d@"${end_seek_seconds}" -u +%H:%M:%S)
  
  if [ "${verbose}" = true ]; then 	
	  printf "%s\n" "Sample ${iter_str} of ${NUM_SAMPLES}: ${seek_str} - ${end_str}"
  fi

	ff_out=$(ffmpeg -hide_banner -ss "${seek_str}" -t "${SAMPLE_DURATION}" \
          -i "${input_video}" -filter:a volumedetect -f null /dev/null 2>&1)


	if echo "$ff_out" | grep -q "Invalid"; then
		errors+=("${ff_out}")
	elif echo "$ff_out" | grep -q "mean_volume"; then
		mean_volume=$(echo "$ff_out" | grep "mean_volume" | awk '{print $5}')
		cumulative_mean_volume=$(echo "scale=2 ; $cumulative_mean_volume + $mean_volume" | bc)
	else
		errors+=("${ff_out}")

	fi

done

mean_of_mean_volume=$(echo "scale=2 ; $cumulative_mean_volume / $NUM_SAMPLES" | bc)

n_errors="${#errors[@]}"

if [ "${n_errors}" == "${NUM_SAMPLES}" ]; then 

  printf "%s\n" "All samples failed with errors!"

  for x in "${!errors[@]}"; do 
	  printf "%s\n\t%s\n" "Sample ${x} of ${NUM_SAMPLES}: ${seek_str}" "Error: ${x}"
  done

elif [ "${n_errors}" -gt 0 ]; then
  printf "%s\n" "Warning: ${n_errors} of ${NUM_SAMPLES} samples gave error!"

fi


if [ "${verbose}" = true ]; then 
  printf "%s\n" "Mean volume across ${NUM_SAMPLES} ${SAMPLE_DURATION}-second samples of input file ${input_video}: ${mean_of_mean_volume}"
else
  printf "%s\n" "${mean_of_mean_volume}"
fi