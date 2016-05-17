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
#    path_in     Path containing the segmented TIF images to process
#    path_out    Output path to write model files to
#    del         Pixel spacing of the original mrc file, delimited by spaces,  in the format "X Y Z"
#    org         Origin of the original mrc file, delimited by spaces,  in the format "X Y Z"
#    pointred    Value for point reduction during contour generation
#    sigma       Value for Gaussian smoothing during contour generation
#

#$ -S /bin/bash
#$ -N tif2mod
#$ -j yes
#$ -m eas
#$ -M alexjperez@outlook.com
#$ -l h_vmem=1G
#$ -cwd
#$ -V

source /home/aperez/.bashrc #Source IMOD

file_in=`ls ${path_in}/*.tif | sed -n ''${SGE_TASK_ID}'p'` #Determine which image to work with
base=`basename $file_in`
base=${base%.*}

#STEP (1)
${IMOD_DIR}/bin/tif2mrc $file_in ${path_out}/mod/${base}.mrc

#STEP (2)
echo -e "${path_out}/mod/${base}.mrc\ndel\n${del}\norg\n${org}\ndone\n" | ${IMOD_DIR}/bin/alterheader

#STEP (3)
${IMOD_DIR}/bin/imodauto -h 1 -R $pointred -k $sigma ${path_out}/mod/${base}.mrc ${path_out}/mod/${base}.mod

#STEP (4)
${IMOD_DIR}/bin/imodtrans -tz $((SGE_TASK_ID-1)) ${path_out}/mod/${base}.mod ${path_out}/mod/${base}.mod

#STEP (5)
${IMOD_DIR}/bin/imodinfo -a ${path_out}/mod/${base}.mod | grep -m 1 'object 0*' | cut -d ' ' -f3 >> ${path_out}/ncont/${base}.txt

#STEP (6)
rm -rf ${path_out}/mod/${base}.mrc ${path_out}/mod/${base}.mod~
