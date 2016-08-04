#! /bin/bash

#$ -S /bin/bash
#$ -N mask
#$ -m eas
#$ -cwd
#$ -V

declare file_mrc
declare path_mod
declare path_seg
declare path_out

# Set basename for current cell
bname=$(printf "cell_%03d" "${SGE_TASK_ID}")
path_cell="${path_out}"/"${bname}"

# Make output directory for current cell
if [[ ! -d "${path_cell}" ]]; then
    mkdir "${path_cell}"
fi

# Get the cell file name
file_mod=$(ls "${path_mod}"/*.mod | sed -n ''"${SGE_TASK_ID}"'p')

# Print job specific details
echo "Host: " "${SGE_O_HOST}"
echo "Node: " "${HOSTNAME}"
echo "Job ID: " "${JOB_ID}"
echo "Task ID: " "${SGE_TASK_ID}"

printf "Masking with file %s\n\n" "${file_mod}"

# If on megashark, use the Python version installed in /opt to import numpy
# and scipy, which are not installed for /usr/bin/python
#if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
if [[ "$SGE_O_HOST" == "megashark.crbs.ucsd.edu" ]]; then
    echo "Running on megashark. Updating Python path."
    export PYTHONPATH="/opt/python/bin/python":"$PYTHONPATH"
    export PATH="/opt/python/bin":"$PATH"
fi

which python

./maskWholeCell.py \
    --output "${path_cell}" \
    --color '0,1,0' \
    --filterByNContours 3 \
    --imodautor 0.5 \
    --mergeAll \
    --name 'Mitochondria' \
    --runImodfillin \
    --runPostprocessing \
    "${file_mrc}" \
    "${file_mod}" \
    "${path_seg}"
