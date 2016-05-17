#! /bin/bash

# tif2mod2D.q
#    SGE script to convert a single binary image to a single model file. The output model file 
#    consists of a single object with individual contours drawn around each 2D connected component. 
#    The steps involved are:
#        (1) Convert the TIF file to a 2D mrc file
#        (2) Alter the header information of the 2D mrc file to match that of the original stack
#        (3) Generate contours around 2d connected components using user-specified values for
#            point reduction (-R) and Gaussian smoothing (-k).
#        (4) Translate the model file in Z so it sits in the correct depth of the stack.
#        (5) Convert the IMOD model file binary format to ASCII, and parse this output to determine
#            the number of contours on this slice. Store this value to a text file, which will be
#            used in future processing.
#        (6) Clean up intermediates.
#
#    The next script to be run in the workflow is mod2point2D.q
#
#    INPUT
#    --------------------
#    path_seg    Path containing the segmented TIF images to process
#    path_out    Output path to write model files to
#    del         Pixel spacing of the original mrc file, delimited by spaces,  in the format "X Y Z"
#    org         Origin of the original mrc file, delimited by spaces,  in the format "X Y Z"
#    pointred    Value for point reduction during contour generation
#    sigma       Value for Gaussian smoothing during contour generation
#

#$ -S /bin/bash
#$ -j yes
#$ -cwd
#$ -V

# Determine which image to process
file_in=$(ls ${path_seg}/*.tif | sed -n ''${SGE_TASK_ID}'p')

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
imodauto "${iastr}"

#STEP (4)
imodtrans -tz $((SGE_TASK_ID-1)) ${path_out}/mod/${base}.mod ${path_out}/mod/${base}.mod

#STEP (5)
imodinfo -a ${path_out}/mod/${base}.mod | grep -m 1 'object 0*' | cut -d ' ' -f3 >> ${path_out}/ncont/${base}.txt

#STEP (6)
rm -rf ${path_out}/mod/${base}.mrc ${path_out}/mod/${base}.mod~
