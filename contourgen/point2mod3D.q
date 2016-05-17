#! /bin/bash

# point2mod3D.q
#    Takes a directory of text files containing point listings for each 2D slice, appends
#    them to one single file, and generates contours using this file as input to the IMOD
#    program point2model.
#
#    INPUT
#    --------------------
#    path_out    Output path
#    del         Pixel spacing of the original mrc file, delimited by spaces,  in the format "X Y Z"
#    org         Origin of the original mrc file, delimited by spaces,  in the format "X Y Z"
#

#$ -S /bin/bash
#$ -N point2mod
#$ -j yes
#$ -m eas
#$ -M alexjperez@outlook.com
#$ -l h_vmem=5G
#$ -cwd
#$ -V

source /home/aperez/.bashrc #Source IMOD

del=`echo $del | tr -s ' ' ','` #Replace space delimiter with commas
org=`echo $org | tr -s ' ' ','`

rm -rf ${path_out}/mod ${path_out}/ncont #Remove intermediates

for file in ${path_out}/txt/*.txt; do #Append individual point listing files to one file
    cat $file >> ${path_out}/out.txt
done

#Generate a model file from the complete point listing
point2model -pixel ${del} -origin ${org} ${path_out}/out.txt ${path_out}/out.mod

rm -rf ${path_out}/out.txt ${path_out}/txt

