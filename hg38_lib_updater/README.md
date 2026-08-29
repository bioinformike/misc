# hg38_lib_update

This project contains one main bash script 'hg38_lib_update' and then additional bash scripts that can be used to test the main script's functionality. It was written to aid in the effort to update an internal library to hg38 and will handle the downloading of fastq files and running of the ENCODE pipeline when given a GSM ID and the corresponding SRRs. It can now also handle different genomes even though hg38 is in the project name you can specify things like mm10 as well!


# Main script

```
hg38_lib_update v1.4.1
This script can be used to download FASTQ files and run the ENCODE pipeline on
them. It was developed to handle the migration of an internal library to hg38.
You can choose to download FASTQ files from ENA or GEO. GEO is the default
due to slow download speeds from ENA, but ENA publishes MD5 checksums.
        -g [--gsm] (req):    Specify the GSM ID for this experiment
        -s [--srrs] (req):   Specify SRR files to download as comma separated list
        -n [--genome] (opt):   Specify the genome you want to use, e.g. mm10 [Default: hg38]
        -d [--down] (opt):   Specify download source, 'GEO' or 'ENA' [Default: GEO]
        -o [--out] (opt):    Output directory to create our GSM directory within.
                                [Default: /data/scratch/hg38_lib_update/working]
        -m [--max] (opt):    Maximum number of times to attempt downloading FASTQ from source [Default: 5]
        -t [--timeout] (opt): Maximum number of seconds wget should wait if not receiving data, only applicable to ENA [Default: 120]
        -b [--usebsub] (opt): Set flag to submit a new LSF job for the ENCODE pipeline
        -p [--priority] (opt): LSF priority to run ENCODE pipeline with, only applicable with --usebsub flag [Default: LSF default]
        -i [--leaveprox] (opt): Set flag to not alter proxy variables, setting this can break ENA downloading
        -z [--nodown] (opt): Set flag to skip downloading, used for testing.
        -y [--noencode] (opt): Set flag to skip ENCODE pipeline, used for testing.
        -x [--noclean] (opt): Set flag to skip cleaning up, used for testing.
        -l [--nolog] (opt):  Set flag to skip logging.
        -f [--fastq] (opt):  [DANGEROUS - disk usage] Set flag to not remove FASTQ files after run
        -V [--version] (opt): Show version of script

        Report bugs at https://XXXX.com/s/hg38-lib-update-issues

```
The script has grown quite complex but in the end you can simply run it giving it a GSM ID with ```-g/--gsm``` and a single SRR ID or a comma-separated list of SRR IDs if there are multiple using the ```-s/--srrs```. The final line of the log file generated, GSM*_hg38_prep.log will indicate the cumulative status of the script specifying either, "Final Status: SUCCESS" or "Final Status: FAILURE". The log file can be examined further to identify where things went wrong.

<details><summary>Script Arguments</summary>

A lot of the script's complexity grew out of trying to make it more robust and having specific options to enable further testing, but I'll try to document all of those options here, just in case they are not clear from the usage message above.

- ```-g/--gsm```: Specify the GSM ID you want to run through the ENCODE pipeline

- ```-s/--srrs```: Specify a single SRR ID or a comma-separated list of SRR IDs that correspond to the specified GSM ID


- ```-n/--genome```: Specify the genome you want to use, e.g. mm10. By default we use hg38 and the script assume your genome build TSV file required by the ENCODE pipeline is located in /data/databank/genome/ENCODE in a directory structure such that hg38 would be /data/databank/genome/ENCODE/hg38/hg38.tsv.


- ```-d/--down```: Specify where to download the required FASTQ files from, GEO or ENA. 
  - By default the script uses NCBI GEO to download FASTQ files for analyses because the downloads are much faster than from ENA. 
  - If downloading fails from the specified source, the script will automatically attempt to download from the other source, i.e. if you specify GEO but that fails the script will also try ENA.
  - ENA however has the advantage of publishing MD5 sums so we can be sure we have the full and uncorrupted file. The script will automatically check MD5s and if they don't match it will remove the file and try downloading again.
  - However, fasterq-dump, the tool that handles GEO downloads may do some sort of file verification, I have never seen a definitive straightforward answer.
  - Another advantage of ENA is that it sometimes has FASTQ files that for one reason or another are no longer available from GEO. So it's a good backup source.

- ```-o/--out```: Specify the directory where the script should create the GSM output folder. 
  - By default this is the scratch hg38 library update directory, /data/scratch/hg38_lib_update/working

- ```-m/--max```: Specify the maximum number of times to attempt downloading the FASTQ file from the source before declaring a failure.
  - The default value is 5.

- ```-t/--timeout```: The maximum number of time for wget to wait for a file before timing out.
  - The default value is 120
  - This only applies to ENA downloading, since GEO uses fasterq-dump not wget to download files.


- ```-b/--usebsub```: Flag to tell the script to submit the ENCODE pipeline to LSF as a separate job.
  - By default this is off and the ENCODE pipeline will be run within the process running this script.
  - However, you have the option to use this script as a manager that will download the file and then kick off a separate job for the ENCODE pipeline.
  - If you set this option you can run this script with few resources, e.g. 1 core, since all it will be doing is downloading files and submitting jobs. But it is off by default because in the end it will waste resources.
  - Either way the script should detect when the pipeline is finished running and will capture its status.

- ```-p/--priority```: Specify the LSF priority to run the ENCODE pipeline job with.
  - Only applicable when using the -b/--usebsub option.

- ```-i/--leaveprox```: Flag to tell the script not to remove any proxy variables.
  - By default this is off and should really only affect ENA downloads.
  - Both NCBI GEO and ENA are whitelisted on the proxy, so they run best when no proxy variables are set, as unauthenticated proxy variables can cause errors reaching ENA.
  - By default the following commands are run to remove all proxy variables from the environment
  ```bash
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
    ```


- ```-z/--nodown```: Flag to skip the download step.
  - If this option is used the script will attempt to run the ENCODE pipeline assuming the required FASTQ files are present. 
  - If the files are not present the script will fail.

- ```-y/--noencode```: Flag to skip running the ENCODE pipeline, so just downloading the FASTQ files and generating the ENCODE input JSON file.

- ```x/--noclean```: Flag to skip cleaning up after a run, basically leaving all peak files in the main GSM directory.
  - This is off by default and all output peak files are put in the ```peaks``` subdirectory.
  - Even with this option set the FASTQ files are still deleted! You can change this with the ```-f/--fastq``` option.

- ```-l/--nolog```: Flag to not write out the GSM*_hg38_prep.log file. 
  - All logging information will still be displayed to stdout.
  - This is off by default, because logging is good!

- ```-f/--fastq```: Flag to leave the downloaded FASTQ files behind. [!DANGEROUS!]
  - By default the FASTQ files are deleted upon the script exiting, either in a success or failure state.
  - This option is marked as danergous because if used FASTQ files can pile up quickly leading to disk space issues.

- ```-h/--help```: Shows the script usage message.

- ```-V/--version```: Shows the script version
</details>

<details><summary>Sample run</summary>
Again the simplest run is to just specify the GSM ID and the SRR ID(s).

```bash
# Assuming the main script, hg38_lib_update is in your path.
hg38_lib_update.sh --gsm GSM1294876 -s SRR1055336,SRR1055335

# This script does the following:
# Creates an output directory in the default directory, since --out was not specified:
# /data/scratch/hg38_lib_update/working/GSM1294876
# Attempts to download the FASTQ files corresponding to the specified SRR IDs from GEO with a max number of attempts of 5
# Generates an input JSON file for the ENCODE pipeline
# Runs the ENCODE pipeline within this same process (--usebsub not specified)
# Generate a 'peaks' directory and move all generated peak files there (--noclean not specified).
# Remove the downloaded FASTQ files and add a final status to the log file, GSM1294876_hg38_prep.log

# The output directory looks as such:

GSM1294876
├── cromwell.out
├── cromwell-workflow-logs
├── encode_pipeline_run-GSM1294876.log
├── GSM1294876_hg38_prep.log
├── GSM1294876.json
├── metadata-GSM1294876.json
├── peaks/
├── qc2tsv_results.tsv
├── qc.html
└── qc.json

# Within the peaks directory:
peaks/
├── sorted_idr.conservative_peak.narrowPeak.gz
├── sorted_idr.optimal_peak.narrowPeak.gz
├── sorted_overlap.conservative_peak.narrowPeak.gz
├── sorted_overlap.optimal_peak.narrowPeak.gz
├── sorted_rep1-pr1_vs_rep1-pr2.idr0.05.bfilt.narrowPeak.gz
├── sorted_rep1-pr1_vs_rep1-pr2.overlap.bfilt.narrowPeak.gz
├── sorted_SRR1055336.merged.srt.nodup.pr1.pval0.01.500K.bfilt.narrowPeak.gz
├── sorted_SRR1055336.merged.srt.nodup.pr2.pval0.01.500K.bfilt.narrowPeak.gz
├── sorted_SRR1055336.merged.srt.nodup.pval0.01.500K.bfilt.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_idr.conservative_peak.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_idr.optimal_peak.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_overlap.conservative_peak.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_overlap.optimal_peak.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_rep1-pr1_vs_rep1-pr2.idr0.05.bfilt.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_rep1-pr1_vs_rep1-pr2.overlap.bfilt.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_SRR1055336.merged.srt.nodup.pr1.pval0.01.500K.bfilt.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_SRR1055336.merged.srt.nodup.pr2.pval0.01.500K.bfilt.narrowPeak.gz
├── unique_qfiltered-0.01_sorted_SRR1055336.merged.srt.nodup.pval0.01.500K.bfilt.narrowPeak.gz
├── unique_sorted_idr.conservative_peak.narrowPeak.gz
├── unique_sorted_idr.optimal_peak.narrowPeak.gz
├── unique_sorted_overlap.conservative_peak.narrowPeak.gz
├── unique_sorted_overlap.optimal_peak.narrowPeak.gz
├── unique_sorted_rep1-pr1_vs_rep1-pr2.idr0.05.bfilt.narrowPeak.gz
├── unique_sorted_rep1-pr1_vs_rep1-pr2.overlap.bfilt.narrowPeak.gz
├── unique_sorted_SRR1055336.merged.srt.nodup.pr1.pval0.01.500K.bfilt.narrowPeak.gz
├── unique_sorted_SRR1055336.merged.srt.nodup.pr2.pval0.01.500K.bfilt.narrowPeak.gz
└── unique_sorted_SRR1055336.merged.srt.nodup.pval0.01.500K.bfilt.narrowPeak.gz

# The final log:
[2022-02-21 10:23:40] Your command:
                        hg38_lib_update  --gsm GSM1294876 -s SRR1055336\,SRR1055335
[2022-02-21 10:23:40] Processing input:
                        GSM ID:                GSM1294876
                        SRR(s):                SRR1055336,SRR1055335
                        Download Source:       GEO
                        Max Download Attempts: 5
                        Wget Timeout [s]:      120
                        Preserve Proxy Vars:   false
                        Skip Logging:          false
                        Skip Download:         false
                        Skip ENCODE:           false
                        Skip Cleaning:         false
                        Leave FASTQs:          false
                        Use BSUB:              false

                        Output Directory:  /data/scratch/hg38_lib_update/working/GSM1294876
                        ENCODE log file:   /data/scratch/hg38_lib_update/working/GSM1294876/encode_pipeline_run-GSM1294876.log
                        Log file:          /data/scratch/hg38_lib_update/working/GSM1294876/GSM1294876_hg38_prep.log

[2022-02-21 10:23:40] Input processed, starting to do some work.
[2022-02-21 10:23:40] Creating working directory:
                        /data/scratch/hg38_lib_update/working/GSM1294876
[2022-02-21 10:23:40] Moving into working directory.
[2022-02-21 10:23:40] Starting to process the 2 SRR(s).
[2022-02-21 10:23:40] Processing SRR1055336.
[2022-02-21 10:23:40] Switching to GEO download mode.
[2022-02-21 10:23:40] Starting download of:
                        SRR1055336
[2022-02-21 10:23:41] Starting download attempt 1 of max 5
[2022-02-21 10:23:42] Starting download attempt 2 of max 5
[2022-02-21 10:24:42] SRR1055336.fastq [6.7G, n reads: 31,530,186] successfully downloaded from GEO in 0m 44s.
[2022-02-21 10:24:42] Processing SRR1055335.
[2022-02-21 10:24:42] Switching to GEO download mode.
[2022-02-21 10:24:42] Starting download of:
                        SRR1055335
[2022-02-21 10:24:42] Starting download attempt 1 of max 5
[2022-02-21 10:25:38] SRR1055335.fastq [6.7G, n reads: 31,612,626] successfully downloaded from GEO in 0m 39s.
[2022-02-21 10:25:38] Generating ENCODE input JSON file:
                        /data/scratch/hg38_lib_update/working/GSM1294876/GSM1294876.json
[2022-02-21 10:25:38] JSON file already exists! Moving existing file to:
                        /data/scratch/hg38_lib_update/working/GSM1294876/GSM1294876.json.old
                        Now writing our new JSON file to:
                        /data/scratch/hg38_lib_update/working/GSM1294876/GSM1294876.json
[2022-02-21 10:25:38] SRR1055336 is SE!
[2022-02-21 10:25:38] SRR1055335 is SE!
[2022-02-21 10:25:38] Finished generating the input JSON file.
[2022-02-21 10:25:38] Running ENCODE pipeline with command:
                        encode-chipgeo-pipeline run  --cleanup /data/scratch/hg38_lib_update/working/GSM1294876/GSM1294876.json
[2022-02-21 12:17:44] ENCODE pipeline finished SUCCESSfully, starting post-processing!
[2022-02-21 12:17:44] Starting to clean up.
[2022-02-21 12:17:44] Moving peak files into peaks directory:
/data/scratch/hg38_lib_update/working/GSM1294876/peaks
[2022-02-21 12:17:45] Removing FASTQ files
[2022-02-21 12:17:46] Finished with all work, script ending.
[2022-02-21 12:17:46] Final Status: SUCCESS



```
</details>


# Testing

## JSON Generation
The script ```gen_json_testing.sh``` can be used to verify that the main script is generating accurate and valid JSON files. Edit the ```SCRIPT``` and ```BASE``` variables within the ```gen_json_testing.sh``` script to specify where the main script lives and where the test environment should be setup, respectively.

The testing script will setup a synthetic environment with 3 SE GSMs and 3 PE GSMs, after which it will run the main script on each with the ```--nodown``` and ```--noencode``` options to limit the work to JSON generation.

The main script will clean up everything and generate a separate JSON file for each GSM, which can then be examined to make sure paths are being generated correctly as well as all options. Finally, the JSON contents can be pasted into a site like https://jsonlint.com to verify that the generated file is valid JSON.
<details><summary>Test environment generated</summary>

```bash
BASE
├── GSM_PE_1_SRR
│   ├── SRR1_1.fastq.gz
│   └── SRR1_2.fastq.gz
├── GSM_PE_2_SRR
│   ├── SRR1_1.fastq.gz
│   ├── SRR1_2.fastq.gz
│   ├── SRR2_1.fastq.gz
│   └── SRR2_2.fastq.gz
├── GSM_PE_3_SRR
│   ├── SRR1_1.fastq.gz
│   ├── SRR1_2.fastq.gz
│   ├── SRR2_1.fastq.gz
│   ├── SRR2_2.fastq.gz
│   ├── SRR3_1.fastq.gz
│   └── SRR3_2.fastq.gz
├── GSM_SE_1_SRR
│   └── SRR1.fastq.gz
├── GSM_SE_2_SRR
│   ├── SRR1.fastq.gz
│   └── SRR2.fastq.gz
└── GSM_SE_3_SRR
    ├── SRR1.fastq.gz
    ├── SRR2.fastq.gz
    └── SRR3.fastq.gz
```
</details>



<details><summary>Results</summary>

- Example of synthetic GSM containing 1 SE SRR file.

```json
{
  "chip.pipeline_type": "tf",
  "chip.genome_tsv": "/data/databank/genome/ENCODE/hg38/hg38.tsv",
  "chip.fastqs_rep1_R1": [ "/data/scratch/hg38_lib_update/working/testing/test2/GSM_SE_1_SRR/SRR1.fastq.gz" ],
  "chip.pseudoreplication_random_seed": 12345,
  "chip.paired_end": false,
  "chip.peak_caller" : "macs2",
  "chip.title": "GSM_SE_1_SRR",
  "chip.description" : "GSM_SE_1_SRR"
}
```

- Example of synthetic GSM containing 1 PE SRR file.

```json
{
  "chip.pipeline_type": "tf",
  "chip.genome_tsv": "/data/databank/genome/ENCODE/hg38/hg38.tsv",
  "chip.fastqs_rep1_R1": [ "/data/scratch/hg38_lib_update/working/testing/test2/GSM_PE_1_SRR/SRR1_1.fastq.gz" ],
  "chip.fastqs_rep1_R2": [ "/data/scratch/hg38_lib_update/working/testing/test2/GSM_PE_1_SRR/SRR1_2.fastq.gz" ],
  "chip.pseudoreplication_random_seed": 12345,
  "chip.paired_end": true,
  "chip.peak_caller" : "macs2",
  "chip.title": "GSM_PE_1_SRR",
  "chip.description" : "GSM_PE_1_SRR"
}
```
</details>


## Downloading
The script ```download_testing.sh``` can be used to verify that the main script's downloading functionality is working properly, including trying to download from an alternative source when the main source fails. It does this by first attempting an ENA and a GEO download with a legitimate GSM and SRR ID. The ENA download can sometimes fail if the environmental variables include unauthenticated proxy entries, but if it fails during this the main script should recover and attempt to use GEO. To get this initial ENA test to function remove all non-authenticated proxy environmental variables.

Again edit the ```BASE``` and ```SCRIPT``` variables to point to where the main script is located and where the test environment should be setup.

<details><summary>Test environment generated</summary>

```bash
BASE
├── GSM293155447
│   ├── GSM293155447_hg38_prep.log
│   ├── GSM293155447.json
│   └── GSM293155447.json.old
└── GSM2931557
    ├── GSM2931557_hg38_prep.log
    ├── GSM2931557.json
    └── GSM2931557.json.old

```
</details>

## All parameter Testing
The Excel document in this repo, functionality_tests.xlsx contains a bunch of different tests for the hg38_lib_update script, with the expected outcome for trying out all sorts of parameters. I have converted the Excel document to a markdown table (using https://tabletomarkdown.com/convert-spreadsheet-to-markdown) and dropped it in below.

<details><summary>Good test sets</summary>
I grabbed 2 smaller SE and a PE datasets to do all the testing so hopefully the downloading step will finish much more quickly.

- Single End for Tests [215,051 reads]:
  - GSM3520051	SRX5162034	SRR8351072	
- Paired end for Tests [102,863]:
  - GSM1918472	SRX1383718	SRR2817161	
</details>
<details><summary>Some helpful test commands</summary>

```bash
  # Generate directory structure.
  for x in {1..29}; do  mkdir "test_${x}"; done

  # Swap out script version number
  sed -i 's/_1_4_0.sh/_1_4_1.sh/' se_commands.sh

  # Change path to se_tests
  sed -i 's/all_tests/se_tests/g' all_commands.sh

  # Now change GSM and SRR
  sed -i 's/GSM1918472/GSM3662770/g' all_commands.sh
  sed -i 's/SRR2817161/SRR8702365/g' all_commands.sh

  # Add more buffer between tests
  sed -i "s/echo -e  '/echo -e  '================================================\n/g" all_commands.sh

  # Kick off tests
  ./all_commands.sh  | tee all_commands.log`
```

</details>

<details><summary>Table of tests</summary>

| Test Number                                  | Output Directory                                                           | Expected Status | Parameter Tested        | Expectation Notes                                                     | Command                                                                                                                                                                                                      |
| -------------------------------------------- | -------------------------------------------------------------------------- | --------------- | ----------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/1  | Fail            | No args                 | Show usage and quit                                                   | hg38_lib_update.sh  --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/1                                                     |
| 2                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/2  | Success         | Help flag               | Show usage and quit                                                   | hg38_lib_update.sh --help --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/2                                               |
| 3                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/3  | Success         | Version flag            | Show version and quit                                                 | hg38_lib_update.sh -V --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/3                                                   |
| 4                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/4  | Fail            | No SRR                  | Need SRR                                                              | hg38_lib_update.sh -g GSM1918472 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/4                                        |
| 5                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/5  | Success         | Normal run              | Normal default run                                                    | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/5                          |
| 6                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/6  | Success         | ENA download            | Run fine downloaded from ENA                                          | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/6               |
| 7                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/7  | Success         | GEO download            | Run fine downloaded from GEO                                          | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/7               |
| 8                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/8  | Success         | ENA max retry           | Could fail, only 1 chance to download                                 | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --max 1 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/8       |
| 9                                            | /data/scratch/hg38_lib_update/working/testing/all/tests/test/9  | Success         | GEO max retry           | Could fail, only 1 chance to download                                 | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --max 1 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/9       |
| 10                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/10 | Mixed           | ENA small timeout       | Likely fail                                                           | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --timeout 1 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/10  |
| 11                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/11 | Success         | GEO small timeout       | Should not be affected by timeout param                               | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --timeout 1 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/11  |
| 12                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/12 | Success         | Use BSUB                | Should run fine, LSF job submitted to run ENCODE                      | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --usebsub --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/12               |
| 13                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/13 | Success         | Bsub priority           | Should submit LSF job for ENCODE with priority of 90                  | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --usebsub --priority 90 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/13 |
| 14                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/14 | Mixed           | ENA leave prox          | Could cause failure if unauth proxy vars set                          | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --leaveprox --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/14  |
| 15                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/15 | Success         | Geo leave proxy         | Shouldn't be affected                                                 | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --leaveprox --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/15  |
| 16                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/16 | Success         | Leave fastq             | Fine but leave fastq file                                             | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --fastq --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/16                 |
| 17                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/17 | Fail            | ENA no download         | Should fail with no fastq downloaded                                  | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --nodown --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/17     |
| 18                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/18 | Fail            | GEO no download         | Should fail with no fastq downloaded                                  | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --nodown --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/18     |
| 19                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/19 | Success         | ENA no download         | Should be fine if fastq in directory                                  | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down ENA --nodown --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/19     |
| 20                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/20 | Success         | GEO no download         | Should be fine if fastq in directory                                  | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --down GEO --nodown --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/20     |
| 21                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/21 | Success         | Leave fastq skip encode | Should be fine, just won't run ENCODE and will leave the fastq behind | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --fastq --noencode --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/21      |
| 22                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/22 | Success         | No encode               | Should just skip ENCODE                                               | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --noencode --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/22              |
| 23                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/23 | Success         | No encode use bsub      | Should just skip ENCODE even though it would run in LSF job           | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --noencode --usebsub --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/23    |
| 24                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/24 | Success         | skip clean              | Run fine but won't clean up (peaks out of peak dir)                   | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --noclean --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/24               |
| 25                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/25 | Success         | skip clean leave fastq  | Run fine without cleanup and the fastq will be left                   | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --noclean --fastq --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/25       |
| 26                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/26 | Success         | skip logging            | Run fine but won't log                                                | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --nolog --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/26                 |
| 27                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/27 | Success         | specify hg38 genome             | Runs normal, this time specifying hg38 as genome                                               | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --genome hg38 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/27                 |
| 28                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/28 | Success         | specify mm10 as genome            | Should run but tries to use mm10 as genome with human data                                               | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --genome mm10 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/28                 |
| 29                                           | /data/scratch/hg38_lib_update/working/testing/all/tests/test/29 | Success         | specify nonexistent zz25 as genome            | Should fail with error indicating the genome file could not be found.                                               | hg38_lib_update.sh -g GSM1918472 -s SRR2817161 --genome zz25 --out /data/scratch/hg38_lib_update/working/testing/all/tests/test/29                 |
|                                              |                                                                            |                 |                         |                                                                       |                                                                                                                                                                                                              |
| Base Output Directory                        | /data/scratch/hg38_lib_update/working/testing/all/tests          |                 |
| \* Needs fastq files in directory before run |                                                                            |                 |                         |                                                                       |
</details>
