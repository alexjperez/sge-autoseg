#! /bin/bash

#$ -S /bin/bash
#$ -N mask
#$ -m eas
#$ -M alexjperez@outlook.com
#$ -cwd
#$ -V
#$ -q default.q

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

printf "Masking with file %s\n\n" "${file_mod}"

# If on megashark, use the Python versioninstalled in /opt to import numpy
# and scipy, which are not installed for /usr/bin/python
if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
    export PYTHONPATH="/opt/python/bin/python":"$PYTHONPATH"
    export PATH="/opt/python/bin":"$PATH"
fi

./maskWholeCell.py --output "${path_cell}" "${file_mrc}" "${file_mod}" "${path_seg}"
