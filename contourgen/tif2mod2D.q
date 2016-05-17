#! /bin/bash

#$ -S /bin/bash
#$ -cwd
#$ -V

declare path_seg
declare path_out
declare del1
declare del2
declare del3
declare org1
declare org2
declare org3
declare pointred
declare sigma

# Determine which image to process
file_in=$(find ${path_seg} -name "*.tif" -type f | sort | sed -n ''${SGE_TASK_ID}'p')

# Get basename
base=$(basename $file_in)
base=${base%.*}

#STEP (1)
tif2mrc "${file_in}" "${path_out}"/mod/"${base}".mrc

#STEP (2)
del="${del1} ${del2} ${del3}"
org="${org1} ${org2} ${org3}"
echo -e "${path_out}/mod/${base}.mrc\ndel\n${del}\norg\n${org}\ndone\n" | alterheader

#STEP (3)
# Generate an imodauto string, iastr, with the desired optional arguments.
iastr="-h 1 "
if [[ "${pointred}" > 0 ]]; then
    iastr+="-R ${pointred} "
fi
if [[ "${sigma}" > 0 ]]; then
    iastr+="-k ${sigma} "
fi
iastr+="${path_out}/mod/${base}.mrc "
iastr+="${path_out}/mod/${base}.mod "
eval imodauto "${iastr}"

#STEP (4)
imodtrans -tz $((SGE_TASK_ID-1)) ${path_out}/mod/${base}.mod ${path_out}/mod/${base}.mod

#STEP (5)
imodinfo -a ${path_out}/mod/${base}.mod | grep -m 1 'object 0*' | cut -d ' ' -f3 >> ${path_out}/ncont/${base}.txt

#STEP (6)
rm -rf ${path_out}/mod/${base}.mrc ${path_out}/mod/${base}.mod~
