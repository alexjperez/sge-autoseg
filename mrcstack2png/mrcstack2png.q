#! /bin/bash

#$ -S /bin/bash
#$ -cwd
#$ -V

declare nslices
declare file_mrc
declare path_out

# Get basename of the mrc file
bname=$(basename "${file_mrc}")
bname="${bname%.*}"

# Set slice number for current array job
N="$((SGE_TASK_ID-1))"

# Run mrc2tif for the current slice
mrc2tif -p -z "${N}","${N}" "${file_mrc}" "${path_out}"/"${bname}"

# The slice numbers output by mrc2tif need to be re-made so they properly list
# in order.
lenslices="${#nslices}"
lenslices=$((lenslices+1))
fnamein="${bname}"."${N}".png
fnameout="${bname}".$(printf "%0"${lenslices}"d" "${N}").png

# Change the filename accordingly
mv "${path_out}"/"${fnamein}" "${path_out}"/"${fnameout}"
