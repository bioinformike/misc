#!/bin/bash
# 
# Name: hg38_lib_update.sh
# 
# Description:
# This script can be used to download FASTQ files and run the ENCODE pipeline on
# them. It was developed to handle the migration of an internal library to hg38
# and designed to be run on an LSF HPC cluster.
# You can choose to download FASTQ files from ENA or GEO. GEO is the default
# due to slow download speeds from ENA, but ENA publishes MD5 checksums.
#
# Source: /XXXX/gitlab/mike/hg38_lib_update
# Author: Mike Lape
# Email: Lapema@mail.uc.edu
# Date: 02-22-2024

# set TRACE=1 in the environment to enable execution tracing
(( TRACE )) && set -x


VERSION='1.4.1'
ME=$(basename "$0")
ISSUETRACKER='https://XXXX.com/s/hg38-lib-update-issues'


# I tend to do this to prevent errors but you can disable if you'd 
# prefer.
module purge

# Required for fasterq-dump
module load sratoolkit/3.0.0

# ENCODE pipeline
module load encode-chip/2.0.0

# Set as "ENA" or "GEO" to either use the ENA API and wget to download
# fastq files from ENA or to use fasterq-dump to download from NCBI GEO.
# Switching to GEO as default because ENA was downloading slow.
FASTQ_SRC="GEO"

# Where we should make the GSM directory to do all of our work
WORKING_DIR="/data/scratch/hg38_lib_update/working"

# Base URL for ENA API
ENA_BASE_URL="https://www.ebi.ac.uk/ena/portal/api/filereport?accession="

# Fields that we want from ENA: Accession ID, FTP address for fastq and md5 for fastq
ENA_FIDS="&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,read_count"

# Maximum time to try downloading the fastq file before giving up.
MAX_DL_RETRIES=5

# WGET timeout, number of seconds with no data being download before killing connection
# Default 2 minutes should allow for a hiccup
WGET_TIMEOUT=120

# Placeholder for path to generated JSON file.
JSON_PATH=""

# Boolean if we should skip downloading
SKIP_DOWN=false

# Boolean if we should skip ENCODE pipeline stuff
SKIP_ENCODE=false

# Boolean if we should not generate log file
NO_LOG=false

# Boolean if we should not clean up after script.
SKIP_CLEAN=false

# Boolean if we should leave any environmental proxy settings untouched.
# otherwise we will unset all proxy environmental vars so ENA isn't confused.
LEAVE_PROXY=false

# Boolean if we should keep the fastq (DANGEROUS)
LEAVE_FASTQ=false

# Priority to run LSF with, by default empty string, but user can change
priority_str=""

# Boolean saying whether we should submit a separate job for the ENCODE 
# pipeline or just run it within this script.
USE_BSUB=false

# Start and end of the peak file we want to unzip and move
BASE_PEAK_FN="unique_qfiltered-0.01_sorted_"
END_PEAK_FN=".srt.nodup.pval0.01.500K.bfilt.narrowPeak.gz"

# Directory where the final GSM directory and GSM peak file should be stored
# for RELI
FINAL_DESTINATION_STUB="/data/databank/bed"

# Location of genome files
GENOME_HOME="/data/databank/genome/ENCODE"

# Genome the user wants to use (defaults to hg38)
GENOME_BUILD="hg38"



##########################################
#                                        #
#          Utility Functions             #
#                                        #
##########################################

# Usage function
function usage() {   

        printf "\n%s\n" "${ME} v${VERSION}"
        printf "%s\n" "This script can be used to download FASTQ files and run the ENCODE pipeline on"
        printf "%s\n" "them. It was developed to handle the migration of an internal library to hg38."
        printf "%s\n" "You can choose to download FASTQ files from ENA or GEO. GEO is the default "
        printf "%s\n" "due to slow download speeds from ENA, but ENA publishes MD5 checksums."
        printf "\t%-20s %-60s\n" "-g [--gsm] (req):"  "Specify the GSM ID for this experiment"
        printf "\t%-20s %-60s\n" "-s [--srrs] (req):" "Specify SRR files to download as comma separated list"
        printf "\t%-20s %-60s\n" "-n [--genome] (opt):" "Specify the genome you want to use, e.g. mm10 [Default: hg38]"
        printf "\t%-20s %-60s\n" "-d [--down] (opt):" "Specify download source, 'GEO' or 'ENA' [Default: GEO]"
        printf "\t%-20s %-60s\n" "-o [--out] (opt):" "Output directory to create our GSM directory within."
        printf "\t\t\t\t%-60s\n" "[Default: /data/scratch/hg38_lib_update/working]"
        printf "\t%-20s %-60s\n" "-m [--max] (opt):" "Maximum number of times to attempt downloading FASTQ from source [Default: 5]"
        printf "\t%-20s %-60s\n" "-t [--timeout] (opt):" "Maximum number of seconds wget should wait if not receiving data, only applicable to ENA [Default: 120]"
        printf "\t%-20s %-60s\n" "-b [--usebsub] (opt):" "Set flag to submit a new LSF job for the ENCODE pipeline"
        printf "\t%-20s %-60s\n" "-p [--priority] (opt):" "LSF priority to run ENCODE pipeline with, only applicable with --usebsub flag [Default: LSF default]"
        printf "\t%-20s %-60s\n" "-i [--leaveprox] (opt):" "Set flag to not alter proxy variables, setting this can break ENA downloading"
        printf "\t%-20s %-60s\n" "-z [--nodown] (opt):" "Set flag to skip downloading, used for testing."
        printf "\t%-20s %-60s\n" "-y [--noencode] (opt):" "Set flag to skip ENCODE pipeline, used for testing."
        printf "\t%-20s %-60s\n" "-x [--noclean] (opt):" "Set flag to skip cleaning up, used for testing."
        printf "\t%-20s %-60s\n" "-l [--nolog] (opt):" "Set flag to skip logging."
        printf "\t%-20s %-60s\n" "-f [--fastq] (opt):" "[DANGEROUS - disk usage] Set flag to not remove FASTQ files after run"
        printf "\t%-20s %-60s\n" "-h [--help] (opt):" "Shows this help message"
        printf "\t%-20s %-60s\n" "-V [--version] (opt):" "Show version of script"
        printf "\n\t%s\n" "Report bugs at ${ISSUETRACKER}"
}

function show_vers() {
    printf "\n%s\n\n" "${ME} v${VERSION}"
}

# define timestamp function ds
function ds() {
	date +"[%F %T]"
}

# Function to count reads in fastq or fastq.gz files.
# $1: FASTQ file to count lines in
function read_count() {

  input_fn=$1
  fn=$(realpath "${input_fn}")

  if grep -qs ".gz" "${fn}"; then
  
    read_num=$(zcat "${fn}" | wc -l | awk '{print $1/4}')
    read_str=$(printf "%'d" "${read_num}")

  else
    read_num=$(wc -l "${fn}"  | awk '{print $1/4}')
    read_str=$(printf "%'d" "${read_num}")    
  fi

  echo "${read_str}"

}

# Function to count reads peaks in bed or gzipped bed file
# $1: Peak file to count lines in
function peak_count() {

  input_fn=$1
  fn=$(realpath "${input_fn}")

  if grep -qs ".gz" "${fn}"; then
  
    peak_num=$(zcat "${fn}" | wc -l | awk '{print $1}')
    peak_str=$(printf "%'d" "${peak_num}")

  else
    peak_num=$(wc -l "${fn}"  | awk '{print $1}')
    peak_str=$(printf "%'d" "${peak_num}")    
  fi

  echo "${peak_str}"

}


# Function handling downloading an SRR from GEO
function geo_dl_file () {
	SECONDS=0

  curr_path=$1
  input_srr=$2

	log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download of: "
	log_func "${NO_LOG}" "${LOG}"  "\t\t\t${input_srr}"

	# Keep track of the number of times that fasterq-dump fails
	fail_cnt=0
	fastq_ret=1

	while [[ "${fastq_ret}" -gt 0 && "${fail_cnt}" -lt "${MAX_DL_RETRIES}" ]] ; do

    log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download attempt $((fail_cnt + 1)) of max ${MAX_DL_RETRIES}" 

		# Now download the fastq
		# Can add -p option to show progress if desired
		fast_out=$(fasterq-dump "${input_srr}" -p -t "${curr_path}" 2>&1 )
    fast_ret=$?

		# Capture return of fasterq-dump
		if echo "${fast_out}" | grep -qs 'err' ; then
			
      if echo "${fast_out}" | grep -qs 'rcExists' ; then
        log_func "${NO_LOG}" "${LOG}"  "$(ds) SRR file already exists, if you want to re-download please delete it and re-run."
			  log_func "${NO_LOG}" "${LOG}"  "\t\t\tContinuing to process the existing FASTQ file."
        fastq_ret=0       
      
      else
        fastq_ret=1
      fi
    
    elif [[ "${fast_ret}" -ne 0 ]]; then
      fastq_ret=1
    else
			fastq_ret=0
		fi
		# No matter if it failed or succeeded that was an attempt, so update cnt
		fail_cnt=$((fail_cnt+1))
  done

	# Now we can see based on fastq_ret whether we failed to dl and should quit
	if [[ "${fastq_ret}" -gt 0 ]]; then
	  log_func "${NO_LOG}" "${LOG}"  "$(ds) GEO download failed.\n\t\t${fast_out}" >&2
	  return 1
	else
		duration=$SECONDS
		dur_str="$((duration / 60))m $((duration % 60))s"

    num_files=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" | wc -l)

    if [[ "${num_files}" -gt 1 ]]; then
      log_func "${NO_LOG}" "${LOG}"  "$(ds) Found multiple FASTQ files for this SRR!"
      
      fs_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" | grep '_1.f'  | xargs du -h  | awk '{print $1}')
      fn_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" | grep '_1.f'  | xargs du -h  | awk '{print $2}')
      fn_1=$(basename "${fn_1}")
      
      full_fn_1=$(realpath "${fn_1}")
      read_1_str=$(read_count "${full_fn_1}")

      fs_2=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" | grep '_2.f' | xargs du -h  |  awk '{print $1}')
      fn_2=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" | grep '_2.f'  | xargs du -h  | awk '{print $2}')
      fn_2=$(basename "${fn_2}")
      full_fn_2=$(realpath "${fn_2}")
      read_2_str=$(read_count "${full_fn_2}")

 
      log_func "${NO_LOG}" "${LOG}"  "$(ds) ${fn_1} [${fs_1}, n reads: ${read_1_str}] and ${fn_2} [${fs_2}, n reads: ${read_2_str}] successfully downloaded from GEO in ${dur_str}."
      

    else

      fs_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}.fastq*" | xargs du -h  | awk '{print $1}')
      fn_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}.fastq*" | xargs du -h  | awk '{print $2}')
      fn_1=$(basename "${fn_1}")

      full_fn_1=$(realpath "${fn_1}")
      read_1_str=$(read_count "${full_fn_1}")

      log_func "${NO_LOG}" "${LOG}"  "$(ds) ${fn_1} [${fs_1}, n reads: ${read_1_str}] successfully downloaded from GEO in ${dur_str}."
    
    
    fi
    return 0
	fi
}

# Hand this function the working directory and the SRR ID and it'll download
# from ENA
function ena_dl_file () {
	
  SECONDS=0


  curr_path=$1
  input_srr=$2
  log_func "${NO_LOG}" "${LOG}"  "$(ds) Searching ENA for the provided SRR ${input_srr}"


  # Search ENA for the SRR
  query_str="${ENA_BASE_URL}${input_srr}${ENA_FIDS}"

  # Run the actual query to get the FTP and MD5 checksum for this SRR FASTQ.

  ret=$(wget -qO- "${query_str}" --read-timeout ${WGET_TIMEOUT})

  # Extract the FTP path
  ftp_path=$(echo -e "${ret}" | awk '{print $2}' | grep -v 'fastq_ftp')

  # Grab MD5, use the ftp address as anchor and look 1 line past it (usually the last line)
  md5=$(echo -e "${ret}" | awk '{print $3}' | grep -v 'fastq_md5')

  read_count=$(echo -e "${ret}" | awk '{print $4}' | grep -v 'read_count')

  # If there is no FTP path for this SRR query in ENA. Log the issue and try to run geo_dl_file
  # Handling switching to GEO mode in main function not here
  if [[ $ftp_path == "" ]]; then
    
    log_func "${NO_LOG}" "${LOG}"  "$(ds) SRR file ${input_srr} not found in ENA!"
    return 2

  fi

  # sometimes we have PE data and thus get 2 SRRs back separated by ;'s'
  if echo "${ftp_path}" | grep -qs ';' ; then
    
    # Break up the multiple ftp paths into an arr
    ftp_arr=($(echo "${ftp_path}" | tr ";" "\n"))
    md5_arr=($(echo "${md5}" | tr ";" "\n"))
    read_count_arr=($(echo "${read_count}" | tr ";" "\n"))
    
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Found multiple FASTQ files for this SRR!"
    
    # Echo out the Fastq files available for SRR
    for curr_ftp in "${ftp_arr[@]}"; do
      base_fn=$(basename "${curr_ftp}")
      log_func "${NO_LOG}" "${LOG}"  "\t\t\t${base_fn}"
    done

    # Set these outside the loop
    # Keep track of the number of times that wget fails
    fail_cnt=0
    fastq_ret=(1 1)
    
    ftp_count=0
    # Now loop through each of our FTP addresses
    for curr_ftp in "${ftp_arr[@]}"; do
      
      # If we got here we have a file and an MD5
      # Specify fastq file name
      base_fn=$(basename "${curr_ftp}")
      full_fn="${curr_path}/${base_fn}"

      # Get the md5 sum for this ftp file
      curr_md5=${md5_arr["${ftp_count}"]}

      # See if we have multiple read counts, if so pick the right one,
      # otherwise just use the 1 value you have
      if [[ ${#read_count_arr[@]} -gt 1 ]] ; then
        curr_count=${read_count_arr["${ftp_count}"]}
        curr_count_str=$(printf "%'d" "${curr_count}")
      else
        curr_count=${read_count_arr[0]}
        curr_count_str=$(printf "%'d" "${curr_count}")
      fi

      log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download of: "
      log_func "${NO_LOG}" "${LOG}"  "\t\t\tFTP:    ${curr_ftp}"
      log_func "${NO_LOG}" "${LOG}"  "\t\t\tFile:   ${base_fn}"
      log_func "${NO_LOG}" "${LOG}"  "\t\t\tMD5:    ${curr_md5}"
      log_func "${NO_LOG}" "${LOG}"  "\t\t\tReads:  ${curr_count_str}"

      fail_cnt=0
      while [[ ${fastq_ret[ftp_count]} -gt 0 && "${fail_cnt}" -lt "${MAX_DL_RETRIES}" ]] ; do

        log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download attempt $((fail_cnt + 1)) of max ${MAX_DL_RETRIES}" 

        # Now download the fastq
        # Can add -p option to show progress if desired
        fast_out=$(wget  --progress=bar:force -c "${curr_ftp}" -O "${full_fn}"  --read-timeout ${WGET_TIMEOUT} 2>&1  | tee /dev/tty)
        #fast_out=$(wget -c "${curr_ftp}" -O "${full_fn}" 2>&1 )

        # If wget failed
        if [ $? -ne 0 ]; then

          # Check if the error is that the file is already downloaded
          if echo "${fast_out}" | grep -qs "The file is already fully retrieved"; then

            # Apparently the file is already there so let's check the md5 if it succeeded
            # https://unix.stackexchange.com/a/254875/485324
            if echo "${curr_md5}  ${base_fn}" | md5sum --status -c - ; then
              fastq_ret[ftp_count]=0
              log_func "${NO_LOG}" "${LOG}"  "$(ds) File already existed and checksums matched!" 

            # We have a downloaded file but MD5 doesn't match so delete what
            # we have and retry
            else
              log_func "${NO_LOG}" "${LOG}"  "$(ds) FASTQ file already exists but checksums do not match, re-downloading"
              rm -v "${full_fn}"
              fastq_ret[ftp_count]=1
            
            fi
          # Some other error
          else
            fastq_ret[ftp_count]=1
            log_func "${NO_LOG}" "${LOG}"  "$(ds) Download $((fail_cnt + 1)) failed!" 
          fi
        else

          # Check the md5 if it succeeded
          # https://unix.stackexchange.com/a/254875/485324
          if echo "${curr_md5}  ${base_fn}" | md5sum --status -c - ; then
            fastq_ret[ftp_count]=0
            log_func "${NO_LOG}" "${LOG}"  "$(ds) Download was successful and checksums matched!" 

          # We have a downloaded file but MD5 doesn't match so delete what
          # we have and retry
          else
            log_func "${NO_LOG}" "${LOG}"  "$(ds) ENA download finished, but checksums do not match, re-downloading"
            rm -v "${full_fn}"
            fastq_ret[ftp_count]=1
          
          fi
        fi

        # No matter if it failed or succeeded that was an attempt, so update cnt
        fail_cnt=$((fail_cnt+1))
      done
      ftp_count=$((ftp_count+1))
    done
  
  else
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Found the SRR in ENA!"

    # If we got here we have a file and an MD5
    # Specify fastq file name
    base_fn=$(basename "${ftp_path}")
    full_fn="${curr_path}/${base_fn}"

    curr_count=${read_count}
    curr_count_str=$(printf "%'d" "${curr_count}")

    log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download of: "
    log_func "${NO_LOG}" "${LOG}"  "\t\t\tFTP:    ${ftp_path}"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\tFile:   ${base_fn}"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\tMD5:    ${md5}"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\tReads:  ${curr_count_str}"

    # Keep track of the number of times that wget fails
    fail_cnt=0
    fastq_ret=(1)

    # This number won't change for SE, but doing this for consistency
    ftp_count=0
    fast_out_str=""
    while [[ ${fastq_ret[ftp_count]} -gt 0 && "${fail_cnt}" -lt "${MAX_DL_RETRIES}" ]] ; do

      log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting download attempt $((fail_cnt + 1)) of max ${MAX_DL_RETRIES}" 

      # Now download the fastq
      # Can add -p option to show progress if desired
      fast_out=$(wget --progress=bar:force -c "${ftp_path}" -O "${full_fn}" --read-timeout ${WGET_TIMEOUT} 2>&1)

      # If wget failed
      if [ $? -ne 0 ]; then
        fastq_ret[ftp_count]=1
        fast_out_str="${fast_out_str}\n${fast_out}"
        log_func "${NO_LOG}" "${LOG}"  "$(ds) Download $((fail_cnt + 1)) failed!" 

      else

        # Check the md5 if it succeeded
        # https://unix.stackexchange.com/a/254875/485324
        if echo "${md5}  ${base_fn}" | md5sum --status -c - ; then
          fastq_ret[ftp_count]=0
          log_func "${NO_LOG}" "${LOG}"  "$(ds) Download was successful and checksums matched!" 

        # We have a downloaded file but MD5 doesn't match so delete what
        # we have and retry
        else
          log_func "${NO_LOG}" "${LOG}"  "$(ds) ENA download finished, but checksums do not match, re-downloading"
          rm -v "${full_fn}"
          fastq_ret[ftp_count]=1
        
        fi
      fi

      # No matter if it failed or succeeded that was an attempt, so update cnt
      fail_cnt=$((fail_cnt+1))
    done
  fi

  fastq_ret_sum=0
  for curr_val in "${fastq_ret[@]}"; do
    fastq_ret_sum+="${curr_val}"
  done

  # Now we can see based on fastq_ret whether we failed to dl and should quit
  if [[ "${fastq_ret_sum}" -gt 0 ]]; then
    
    # Stripping out the word ERROR from message so we can use ERROR/SUCCESS at very bottom
    log_func "${NO_LOG}" "${LOG}"  "$(ds) ENA download failed to download the file with error:\n\t${fast_out_str}" 
    return 1
  else
    duration=$SECONDS
    dur_str="$((duration / 60))m $((duration % 60))s"

    # PE
    if [[ "${ftp_count}" -gt 0 ]]; then
    
      fs_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" |  grep '_1.f'  | xargs du -h  | awk '{print $1}')
      fn_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" |  grep '_1.f'  | xargs du -h | awk '{print $2}')
      fn_1=$(basename "${fn_1}")

      full_fn_1=$(realpath "${fn_1}")
      read_1_str=$(read_count "${full_fn_1}")


      fs_2=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" |  grep '_2.f'  | xargs du -h  | awk '{print $1}')
      fn_2=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*" |  grep '_2.f'  | xargs du -h | awk '{print $2}')
      fn_2=$(basename "${fn_2}")

      full_fn_2=$(realpath "${fn_2}")
      read_2_str=$(read_count "${full_fn_2}")


      log_func "${NO_LOG}" "${LOG}"  "$(ds) ${fn_1} [${fs_1}, n reads: ${read_1_str}] and ${fn_2} [${fs_2}, n reads: ${read_2_str}] successfully downloaded from ENA in ${dur_str}."
      return 0
    else
    
      fs_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*"  | xargs du -h  | awk '{print $1}')
      fn_1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${input_srr}*.fastq*"  | xargs du -h | awk '{print $2}')
      fn_1=$(basename "${fn_1}")

      full_fn_1=$(realpath "${fn_1}")
      read_1_str=$(read_count "${full_fn_1}")

      log_func "${NO_LOG}" "${LOG}"  "$(ds) ${fn_1} [${fs_1}, n reads: ${read_1_str}] successfully downloaded from ENA in ${dur_str}."
      return 0
    fi

  fi

}		  

# Write out the input JSON file for ENCODE Pipeline
# $1: Full GSM directory path
# $2: Comma separated list of SRR IDs we downloaded (raw user input)
# $3: The GSM ID, which we will need for the JSON file name. We could probably just parse the 
#     curr_path, but this works too.
function generate_json () {


  curr_path=$1
  input_srr_list=$2
  input_gsm_id=$3

  input_srr_array=($(echo "${input_srr_list}" | tr "," "\n"))

  json_file="${curr_path}/${input_gsm_id}.json"

  log_func "${NO_LOG}" "${LOG}"  "$(ds) Generating ENCODE input JSON file: "
  log_func "${NO_LOG}" "${LOG}"  "\t\t\t${json_file}"

  # If JSON file already exists
  if [[ -f "${json_file}" ]]; then
    log_func "${NO_LOG}" "${LOG}"  "$(ds) JSON file already exists! Moving existing file to:\n\t\t\t${json_file}.old"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\tNow writing our new JSON file to:\n\t\t\t${json_file}"

    mv "${json_file}" "${json_file}.old"

  # File doesn't exist, touch it.
  else

    touch "${json_file}"  

  fi

  # Before starting to push data into json file, we will put together rep1_R1 
  # and possibly rep1_R2 strings
  rep1_R1=""
  rep1_R2=""
  
  # Count number of SRRs we need to loop through.
  num_srrs=${#input_srr_array[@]}
  MODE="SE"
  # Now loop through each of our SRRs processing it.
  for curr_srr in "${input_srr_array[@]}"; do
    

    # Somewhat more reliable way to count number of files that find command found
    # https://stackoverflow.com/a/15663760/12689788
    num_files=$(find "${curr_path}" -maxdepth 1 -type f -iname "${curr_srr}*.fastq*" | wc -l)
    curr_srr_path=$(find "${curr_path}" -maxdepth 1 -type f -iname "${curr_srr}*.fastq*" -exec realpath {} \;)

    # Should be paired end
    if [[ "${num_files}" -gt 1 ]]; then 
      MODE="PE"
      if [[ "${SKIP_DOWN}" == false ]]; then 
        log_func "${NO_LOG}" "${LOG}"  "$(ds) ${curr_srr} is PE!"
      fi
      curr_r1=$(find "${curr_path}" -maxdepth 1 -type f -iname "${curr_srr}*.fastq*" -exec realpath {} \; | grep '_1.f')
      curr_r1="\"${curr_r1}\""

      curr_r2=$(find "${curr_path}" -maxdepth 1 -type f -iname "${curr_srr}*.fastq*" -exec realpath {} \; | grep '_2.f')
      curr_r2="\"${curr_r2}\""

      # Is this the last SRR? If so, not trailing comma.
      if [[ "${num_srrs}" -eq 1 ]]; then

        # Is this the first SRR?
        if [[ "${rep1_R1}" == "" ]]; then

          rep1_R1="${curr_r1}"
        else
          rep1_R1="${rep1_R1} ${curr_r1}"
        fi

        if [[ "${rep1_R2}" == "" ]]; then

          rep1_R2="${curr_r2}"
        else
          rep1_R2="${rep1_R2} ${curr_r2}"
        fi
        
      else       
        # Is this the first SRR?
        if [[ "${rep1_R1}" == "" ]]; then
          rep1_R1="${curr_r1}, "
        else
          rep1_R1="${rep1_R1} ${curr_r1},"
        fi

        if [[ "${rep1_R2}" == "" ]]; then
          rep1_R2="${curr_r2},"
        else
          rep1_R2="${rep1_R2} ${curr_r2},"
        fi
      fi
    else
      if [[ "${SKIP_DOWN}" == false ]]; then 
        log_func "${NO_LOG}" "${LOG}"  "$(ds) ${curr_srr} is SE!"
      fi
      curr_srr_path="\"${curr_srr_path}\""

      # Is this the last SRR? If so, not trailing comma.
      if [[ "${num_srrs}" -eq 1 ]]; then
        # Is this the first SRR?
        if [[ "${rep1_R1}" == "" ]]; then
          rep1_R1="${curr_srr_path}"
        else
          rep1_R1="${rep1_R1} ${curr_srr_path}"
        fi
      # Not the last SRR, add comma
      else
        # Is this the first SRR?
        if [[ "${rep1_R1}" == "" ]]; then
          rep1_R1="${curr_srr_path},"
        else
          rep1_R1="${rep1_R1} ${curr_srr_path},"
        fi
      fi
    fi
    num_srrs=$((num_srrs - 1))
  done
  
  # We are going to overwrite any current file now.
  echo -e '{' > "${json_file}"
  echo -e '  "chip.pipeline_type": "tf",' >> "${json_file}"
  echo -e "  \"chip.genome_tsv\": \"${GENOME_FILE}\", " >> "${json_file}"
  
  # Use -n here because apparently JSON doesn't like multiline arrays??
  echo -e "  \"chip.fastqs_rep1_R1\": [ ${rep1_R1} ], " >> "${json_file}"
  
  # If we have a PE R2 string
  if [[ "${rep1_R2}" != "" ]]; then
    echo -e "  \"chip.fastqs_rep1_R2\": [ ${rep1_R2} ], " >> "${json_file}"
  fi
  
  echo -e '  "chip.pseudoreplication_random_seed": 12345, ' >> "${json_file}"

  # IF PE set option to true, otherwise false
  if [[ "${MODE}" == "PE" ]]; then

    echo -e '  "chip.paired_end": true,' >> "${json_file}"
  else
    echo -e '  "chip.paired_end": false,' >> "${json_file}"
  fi

  echo -e '  "chip.peak_caller" : "macs2",' >> "${json_file}"
  echo -e "  \"chip.title\": \"${input_gsm_id}\"," >> "${json_file}"
  echo -e "  \"chip.description\" : \"${input_gsm_id}\"" >> "${json_file}"
  echo -e '}' >> "${json_file}"

  log_func "${NO_LOG}" "${LOG}"  "$(ds) Finished generating the input JSON file."


  # Now lettuce return the json file path
  #echo "${json_file}"
  JSON_PATH="${json_file}"

}

# This function handles all output to stdout and to a log file
# User can specify command line argument to tell program to not create log, 
# but by default we create a log file.
# $1: Boolean indicating if we should (NO_LOG = false) or should not (NO_LOG = true)
#     log to a file
# $2: Log file full path
# $3: String to either push to stdout and log or just push to stdout.
function log_func () {

  no_log=$1
  log=$2
  our_str=$3

  # We want to log
  if [[ "${no_log}" == false ]]; then
    echo -e "${our_str}" |  tee -a "${log}"

  # No log
  else
    echo -e "${our_str}" 
  fi
}

# This function will clean up only the FASTQ and FASTQ.gz files in a directory
# $1: Full GSM directory path
# $2: Comma separated list of SRR IDs we downloaded (raw user input)
function clean_fastq () {

  if [[ "${LEAVE_FASTQ}" == true ]]; then
    log_func "${NO_LOG}" "${LOG}" '\n\n\t\t\t!DANGER!   Leaving FASTQ files [-f/--fastq is true]   !DANGER!\n\n'

  else
      
    # Now remove the FASTQ files
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Removing FASTQ files"

    srr_arr=($(echo "${SRR_LIST}" | tr "," "\n"))
    
    # Now loop through each of our SRRs processing it.
    for curr_srr in "${srr_arr[@]}"; do
      find "${GSM_DIR}" -maxdepth 1 -type f -iname "${curr_srr}*fastq*" -exec rm -v {} \;
    done

  fi
}

# This function will clean up the working directory when all done with work
# or when the code fails
# $1: Full GSM directory path
# $2: Comma separated list of SRR IDs we downloaded (raw user input)
function clean_up () {
  
  if [[ "${SKIP_CLEAN}" == true ]]; then
    log_func "${NO_LOG}" "${LOG}" "Skipping cleaning [-x/--noclean is true]"

  else
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Starting to clean up."

    # If we actually did ENCODE, move the peaks to the peaks dir
    if [[ "${SKIP_ENCODE}" = false ]]; then

      peak_dir_path="${GSM_DIR}/peaks"
      log_func "${NO_LOG}" "${LOG}"  "$(ds) Moving peak files into peaks directory:\n\t\t\t${peak_dir_path}"
      
      # Make the dir
      mkdir -p "${peak_dir_path}"

      # Now move the files
      find "${GSM_DIR}" -maxdepth 1  -type f -iname "*.narrowPeak.gz" -exec mv {} "${peak_dir_path}/" \;

      # Clean up any annoying fasterq-dump tmp dirs
      find "${GSM_DIR}" -type d -name 'fasterq.tmp.*' -exec rm -rf {} \; > /dev/null 2>&1
    fi
    
    # Run special function removing FASTQ files
    clean_fastq $1 $2
  fi
}

# This function will handle the actual exiting of the program, makes it easier
# to manage all the 'exit' calls in one place
# $1: indicator of failure or success
function bail () {
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  dur_str="$((duration / 60))m $((duration % 60))s"
  
  # It looks like flock should work with a file on an NFS mount nowadays so 
  # using that as >> is supposedly subject to race conditions.
  # https://man7.org/linux/man-pages/man2/flock.2.html

  # Define what the lock file's name is
  # Following this site for help with the flock stuff
  # https://jdimpson.livejournal.com/5685.html
  lock_file="/tmp/${ME}.lock"

  # Return code of 0 indicates success so output
  if [[ "${1}" -eq 0 ]]; then
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Total runtime: ${dur_str}"
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Final Status: SUCCESS"
    
    # Wait up to 30 seconds for lock (it should never actually take this long)
    # but waiting up to 30s is worth it to get this final status in the log file.

    # Last part assigns file handle (FH) to our lock file
    (
      # Tell flock to get an exclusive lock on the file that FH points to, and 
      # wait up to 30 seconds for that lock.
      flock --exclusive --wait 30 200

      # Remove old version from MAIN_LOG if present
      grep -v "${GSM_ID}" "${MAIN_LOG}" | sponge "${MAIN_LOG}"

      # Now do our write
      echo -e "$(ds) ${GSM_ID} Final Status: SUCCESS" >> "${MAIN_LOG}"

    ) 200>"${lock_file}"

    # Now exit
    exit 0

  else
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Total runtime: ${dur_str}"
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Final Status: FAILURE"
    (
      flock --exclusive --wait 30 200
      grep -v "${GSM_ID}" "${MAIN_LOG}" | sponge "${MAIN_LOG}"
      echo -e "$(ds) ${GSM_ID} Final Status: FAILURE" >> "${MAIN_LOG}"

    ) 200>"${lock_file}"
    exit 1
  fi
}

##########################################
#                                        #
#                 Main                   #
#                                        #
##########################################

# grab user command
# https://stackoverflow.com/a/36625791/12689788
script=$(basename $0)
in_cmd=$( (($#)) && printf ' %q' "$@")
in_cmd="${script} ${in_cmd}"

start_time=$(date +%s)

# Using this as an example: http://linuxcommand.org/lc3_wss0120.php
# and this: https://stackoverflow.com/a/14203146
if [[ $# -eq 0 ]]; then
        usage >&2
        exit 1
fi

# Parse command line args
while (( $# )); do

    case $1 in
        -g | --gsm )        shift; GSM_ID=$1 ;;
        -s | --srrs )       shift; SRR_LIST=$1 ;;
        -n | --genome )     shift; GENOME_BUILD=$1 ;;
        -d | --down )       shift; FASTQ_SRC=$1 ;;
        -o | --out )        shift; WORKING_DIR=$1 ;;
        -m | --max )        shift; MAX_DL_RETRIES=$1 ;;
        -t |--timeout )     shift; WGET_TIMEOUT=$1 ;;
        -b | --usebsub )    USE_BSUB=true;;
        -p | --priority )   shift; priority_str=$1 ;;
        -i | --leaveprox )  LEAVE_PROXY=true ;;
        -z | --nodown )     SKIP_DOWN=true ;;
        -y | --noencode )   SKIP_ENCODE=true ;;
        -x | --noclean )    SKIP_CLEAN=true ;;
        -l | --nolog )      NO_LOG=true ;;
        -f | --fastq )      LEAVE_FASTQ=true ;;
        -V | --version )    show_vers; exit ;;
        -h | --help )       usage; exit ;;
        * )                 echo "Invalid option: '${1}'"; usage >&2; exit 1 ;;
    esac

    shift
done

# Check input
# Directory is required
if [[ -z ${GSM_ID+x} ]]; then
    echo -e  "A GSM ID (-g or --gsm) argument is required!"
    echo -e  "Exiting."
    exit 1
fi

if [[ -z ${SRR_LIST+x} ]]; then
    echo -e  "A SRR or a comma separated list of SRRs (-s or --srrs) are required!"
    echo -e  "Exiting."
    exit 1
fi

GENOME_FILE="${GENOME_HOME}/${GENOME_BUILD}/${GENOME_BUILD}.tsv"
if [ ! -f "${GENOME_FILE}" ] ; then
    echo -e  "Could not find the genome build specified. Please fix this and re-run."
    echo -e  "Genome home: ${GENOME_HOME}"
    echo -e  "Input genome build: ${GENOME_BUILD}"
    echo -e  "Expected file: ${GENOME_FILE}"
    exit 1
fi


if [ ! -d "${WORKING_DIR}" ] ; then
    echo -e  "Specified output directory does not exist! Please fix this and re-run."
    echo -e  "Input directory: ${WORKING_DIR}"
    exit 1
fi

# Generate our GSM directory and move into it.
GSM_DIR="${WORKING_DIR}/${GSM_ID}"

# I like mkdir to tell you what it did for logging purposes.
mkdir -pv "${GSM_DIR}"


#  Generate the FINAL_DESTINATION and MAIN_LOG variables using the possibly input genome build
FINAL_DESTINATION="${FINAL_DESTINATION_STUB}/${GENOME_BUILD}/chip_geo"
mkdir -pv "${FINAL_DESTINATION}"
MAIN_LOG="${FINAL_DESTINATION}/run_status.log"


# Make the destination directory and final peak file name
final_dir="${FINAL_DESTINATION}/${GSM_ID}"
mkdir -pv "${final_dir}"
final_file="${final_dir}/${GSM_ID}.bed"

# Only create log file if they want a log.
LOG="${GSM_DIR}/${GSM_ID}_hg38_prep.log"
if [[ "${NO_LOG}" == false ]]; then
  touch "${LOG}"
fi

encode_log="${GSM_DIR}/encode_pipeline_run-${GSM_ID}.log"


log_func "${NO_LOG}" "${LOG}" "$(ds) Your command:\n\t\t\t${in_cmd}"
log_func "${NO_LOG}" "${LOG}" "$(ds) Processing input:"
log_func "${NO_LOG}" "${LOG}" "\t\t\tGSM ID:                ${GSM_ID}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tSRR(s):                ${SRR_LIST}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tGenome:                ${GENOME_BUILD}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tGenome file:           ${GENOME_FILE}"

log_func "${NO_LOG}" "${LOG}" "\t\t\tSRR(s):                ${SRR_LIST}"

log_func "${NO_LOG}" "${LOG}" "\t\t\tDownload Source:       ${FASTQ_SRC}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tMax Download Attempts: ${MAX_DL_RETRIES}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tWget Timeout [s]:      ${WGET_TIMEOUT}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tPreserve Proxy Vars:   ${LEAVE_PROXY}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tSkip Logging:          ${NO_LOG}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tSkip Download:         ${SKIP_DOWN}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tSkip ENCODE:           ${SKIP_ENCODE}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tSkip Cleaning:         ${SKIP_CLEAN}"

if [[ "${LEAVE_FASTQ}" == true ]]; then
  log_func "${NO_LOG}" "${LOG}" "\t\t\tLeave FASTQs:          ${LEAVE_FASTQ}       [!DANGER!]"
else
  log_func "${NO_LOG}" "${LOG}" "\t\t\tLeave FASTQs:          ${LEAVE_FASTQ}"
fi


log_func "${NO_LOG}" "${LOG}" "\t\t\tUse BSUB:              ${USE_BSUB}"
if [[ "${priority_str}" != "" ]]; then
  log_func "${NO_LOG}" "${LOG}" "\t\t\tLSF Priority:          ${priority_str}"
fi

log_func "${NO_LOG}" "${LOG}" "\n\t\t\tOutput Directory:  ${GSM_DIR}"

if [[ "${SKIP_ENCODE}" == false ]]; then
  log_func "${NO_LOG}" "${LOG}" "\t\t\tENCODE Log File:   ${encode_log}"
fi

if [[ "${NO_LOG}" == false ]]; then
  log_func "${NO_LOG}" "${LOG}" "\t\t\tLog File:          ${LOG}"
fi
log_func "${NO_LOG}" "${LOG}" "\t\t\tFinal Peak File:   ${final_file}"
log_func "${NO_LOG}" "${LOG}" "\t\t\tFinal Status Log:  ${MAIN_LOG}"

log_func "${NO_LOG}" "${LOG}" "\n$(ds) Input processed, starting to do some work."

log_func "${NO_LOG}" "${LOG}" "$(ds) Creating working directory:\n\t\t\t${GSM_DIR}"
log_func "${NO_LOG}" "${LOG}" "$(ds) Moving into working directory."

cd "${GSM_DIR}"

#######################
#  Parsing Input      #
#######################

# Parse the SRR_LIST, the outer parens are required, I guess they make
# it into an array
srr_arr=($(echo "${SRR_LIST}" | tr "," "\n"))

log_func "${NO_LOG}" "${LOG}" "$(ds) Starting to process the ${#srr_arr[@]} SRR(s)."


#######################
#  Downloading Files  #
#######################
if [[ $SKIP_DOWN = false ]]; then

  # If we are OK to alter proxy environmental variables do so
  # We could probably narrow this down to exactly which proxy vars we need to, 
  # but for now it doesn't seem to matter
  if [[ $LEAVE_PROXY = false ]]; then
    unset all_proxy
    unset ALL_PROXY

    unset ftp_proxy
    unset FTP_PROXY

    unset http_proxy
    unset HTTP_PROXY

    unset https_proxy
    unset HTTPS_PROXY

    unset rsync_proxy
    unset RSYNC_PROXY

  fi

  # Now loop through each of our SRRs processing it.
  for curr_srr in "${srr_arr[@]}"; do
    
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Processing ${curr_srr}."

    # Who do we want to get this file from?
    if [[ "${FASTQ_SRC}" = "ENA" ]]; then
      log_func "${NO_LOG}" "${LOG}"  "$(ds) Switching to ENA download mode."
      ena_dl_file "${GSM_DIR}" "${curr_srr}"
      dl_ret=$?
      
      # ENA DL failed, try GEO
      if [[ "${dl_ret}" -ne 0 ]]; then        
        log_func "${NO_LOG}" "${LOG}"  "$(ds) ENA download failed! Switching to GEO download mode and trying again."

        # Remove any possible lingering fastq file (ENA seems to do this)
        clean_fastq "${GSM_DIR}" "${curr_srr}"
        geo_dl_file "${GSM_DIR}" "${curr_srr}"        
        dl_ret=$?

        # Both failed!
        if [[ "${dl_ret}" -ne 0 ]]; then        
          log_func "${NO_LOG}" "${LOG}"  "$(ds) Download from ENA and GEO both failed, exiting"
          clean_fastq "${GSM_DIR}" "${curr_srr}"
          bail 1
        fi
      fi
    elif [[ "${FASTQ_SRC}" = "GEO" ]]; then
      log_func "${NO_LOG}" "${LOG}"  "$(ds) Switching to GEO download mode."

      geo_dl_file "${GSM_DIR}" "${curr_srr}"
      dl_ret=$?
      
      # GEO DL failed, try ENA
      if [[ "${dl_ret}" -ne 0 ]]; then 
        log_func "${NO_LOG}" "${LOG}"  "$(ds) GEO download failed! Switching to ENA download mode and trying again."

        # Remove any possible lingering fastq file (ENA seems to do this)
        clean_fastq "${GSM_DIR}" "${curr_srr}"  
        ena_dl_file "${GSM_DIR}" "${curr_srr}"        
        dl_ret=$?

        # Both failed!
        if [[ "${dl_ret}" -ne 0 ]]; then        
          log_func "${NO_LOG}" "${LOG}"  "Download from GEO and ENA both failed, exiting"
          clean_fastq "${GSM_DIR}" "${curr_srr}"
          bail 1
        fi
      fi

    else
      log_func "${NO_LOG}" "${LOG}"  "Download source ${FASTQ_SRC} unavailable, please use 'ENA' or 'GEO'."
      bail 1

    fi

  done
else
  log_func "${NO_LOG}" "${LOG}" "$(ds) Skipping downloading of FASTQ files [-z/--nodown flag set]"
fi

#######################
#  Generating JSON    #
#######################
# Once all SRRs are downloaded we need to generate the json file.
generate_json "${GSM_DIR}" "${SRR_LIST}" "${GSM_ID}"

clean_str=""
if [[ "${SKIP_CLEAN}" == false ]]; then
  clean_str=" --cleanup "
fi

if [[ "${priority_str}" != "" ]]; then
  priority_str=" --priority ${priority_str} "
fi

# If they want us to submit ENCODE pipeline as a new job add --lsf flag to command
if [[ "${USE_BSUB}" == true ]]; then
  encode_cmd="encode-chipgeo-pipeline run --lsf ${clean_str}${priority_str}${JSON_PATH}"
else
  encode_cmd="encode-chipgeo-pipeline run ${clean_str}${JSON_PATH}"
fi

####################
#  Run ENCODE      #
####################
if [[ "${SKIP_ENCODE}" = false ]]; then

  if [[ "${USE_BSUB}" == true ]]; then
    # OK now actually run ENCODE pipeline
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Submitting LSF job for ENCODE pipeline with command:"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\t${encode_cmd}"
    
  else
    # OK now actually run ENCODE pipeline
    log_func "${NO_LOG}" "${LOG}"  "$(ds) Running ENCODE pipeline with command:"
    log_func "${NO_LOG}" "${LOG}"  "\t\t\t${encode_cmd}"

  fi

  # Start timing ENCODE pipeline
  SECONDS=0

  # We submitted the job so we need to wait now..
  if [[ "${USE_BSUB}" == true ]]; then

    # We need to capture encode_out to grab the job code so we can wait
    encode_out=$(eval "${encode_cmd}" 2>&1)
    encode_ret="$?"
    
    # Grab the Job ID
    job_id=$(echo "${encode_out}" | tr ' ' '\n' | grep -E '<[[:digit:]]+>' | tr -d '<' | tr -d '>')

    log_func "${NO_LOG}" "${LOG}"  "$(ds) Waiting for ENCODE pipeline LSF job [${job_id}] to finish."

    # bwait allows our script to sit and wait for the LSF job to finish,
    # I'm pretty sure done does not mean succeeded necessarily, so we'll need
    # to verify the output.
    b_res=$(bwait -w "done(${job_id})")

  else
    # We need to capture encode_out to grab the job code so we can wait
    encode_out=$(eval "${encode_cmd}" 2>&1)
    encode_ret="$?"
  fi
  
  # OK we are back from ENCODE pipeline, so calculate duration and let use know.
  duration=$SECONDS
  dur_str="$((duration / 60))m $((duration % 60))s"
  
else
  log_func "${NO_LOG}" "${LOG}" "$(ds) Skipping ENCODE pipeline [-y/--noencode flag set]"
fi

#######################
#   Post-processing   #
#######################
if [[ "${SKIP_ENCODE}" = false ]]; then

  # Only do this if we used BSUB - looking at BSUB job return, otherwise just
  # look at the log file.
  if [[ "${USE_BSUB}" == true ]]; then
    # If bsub reports failure
    if grep "Wait condition is never satisfied" "${b_res}"; then
      log_func "${NO_LOG}" "${LOG}"  "$(ds) LSF reports that after ${dur_str} the ENCODE pipeline FAILED!"    
      
      # If pipeline fails don't clean up anything but FASTQ files
      clean_fastq "${GSM_DIR}" "${SRR_LIST}"    
      bail 1

    else
      log_func "${NO_LOG}" "${LOG}"  "$(ds) ENCODE pipeline LSF job finished in ${dur_str} checking log files."
    fi
  fi


  # Either bsub was good or we ran the pipeline ourselves, so look at 
  # ENCODE return code then ENCODE log

  if [[ "${encode_ret}" -ne 0 ]]; then
    log_func "${NO_LOG}" "${LOG}"  "$(ds) After ${dur_str} the ENCODE pipeline FAILED, exiting!"
  
    # If pipeline fails don't clean up anything but FASTQ files
    clean_fastq "${GSM_DIR}" "${SRR_LIST}"
    bail 1  
fi

  
  # If we get here bsub reports success, so check the ENCODE login file.
  if grep -qs "The ENCODE pipeline has finished successfully" "${encode_log}" ; then

    log_func "${NO_LOG}" "${LOG}"  "$(ds) ENCODE pipeline finished successfully in ${dur_str}, starting post-processing!"
        
    peak_file=$(find . -type f -name "${BASE_PEAK_FN}*${END_PEAK_FN}")
    num_files=$(echo -e "${peak_file}" | wc -l)

    if [[ "${num_files}" -gt 0 ]]; then

      curr_peak_cnt=$(peak_count "${peak_file}")
      log_func "${NO_LOG}" "${LOG}"  "$(ds) Number of peaks: ${curr_peak_cnt}"     

      gunzip -c "${peak_file}" > "${final_file}"
      gun_ret=$?

      if [[ "${gun_ret}" -ne 0 ]]; then
        log_func "${NO_LOG}" "${LOG}"  "Failed moving peak file!"      
        clean_fastq "${GSM_DIR}" "${SRR_LIST}"
        bail 1        
      fi

      log_func "${NO_LOG}" "${LOG}"  "$(ds) Final peak file moved:\n\t\t\t ${final_file}"  

    else
      log_func "${NO_LOG}" "${LOG}"  "ERROR: NO PEAK FILE FOUND!"      
      clean_fastq "${GSM_DIR}" "${SRR_LIST}"
      bail 1

    fi

  else
    log_func "${NO_LOG}" "${LOG}"  "$(ds) After ${dur_str} the ENCODE pipeline FAILED, exiting!"
    # If pipeline fails don't clean up anything but FASTQ files
    clean_fastq "${GSM_DIR}" "${SRR_LIST}"
    bail 1
  fi
fi


#######################
#   Cleaning up       #
#######################

# $1: Full GSM directory path
# $2: Comma separated list of SRR IDs we downloaded (raw user input)
if [[ "${SKIP_CLEAN}" == true ]]; then
  clean_fastq "${GSM_DIR}" "${SRR_LIST}"
else
  clean_up "${GSM_DIR}" "${SRR_LIST}"
fi

#####################
#   All done!       #
#####################
log_func "${NO_LOG}" "${LOG}"  "$(ds) Finished with all work, script ending."
bail 0