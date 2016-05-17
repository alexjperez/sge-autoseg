#! /bin/bash

# mod2point2D.q
#    SGE script to submit array jobs converting 2D model files to point listings compatible 
#    with the IMOD program point2model. Conversion is done using MATLAB, and is dependent on 
#    the MatTomo package of MATLAB scripts from IMOD.
#
#    INPUT
#    --------------------
#    path_mod    Path containing the model files to process
#    path_txt    Path containing the contour listings output from tif2mod2D.q
#    path_out    Output path to write point listing text files to
#

#$ -S /bin/bash
#$ -N mod2point
#$ -j yes
#$ -m eas
#$ -M alexjperez@outlook.com
#$ -l h_vmem=5G
#$ -cwd
#$ -V

matlab -nodisplay -nosplash -r "mod2point2D('"${path_mod}"','"${path_txt}"','"${path_out}"',${SGE_TASK_ID})";
