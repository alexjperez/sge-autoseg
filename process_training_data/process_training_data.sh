#!/bin/bash

# Wrapper script that submits an SGE job to extract training data from a
# given model file and series of PNG images
#
# Written by: Alex Perez - alexjperez@gmail.com

function usage () {
cat << END
Usage: $0 [options] file.mrc training_data.mod path_ehs dimx,dimy

Required Arguments:
------------------
file.mrc
    Original MRC file the training contours were traced on.

training_data.mod
    Model file containing two objects. The first object consists of 
    scattered seed points marking the center of each training image. The 
    second object consists of closed contours representing manual traces
    of the object of interest.

path_ehs
    Path containing a series of individual PNGs (i.e. those produced by
    EHS histogram equalization.

dimx,dimy
    Desired dimensions of training images and labels, in pixels in X (dimx)
    and pixels in Y (dimy).

Optional Arguments:
------------------
-o | --output
    Path to save training images and labels to. 
    DEFAULT: ./training_data

-h | --help
        Display this help
END
exit "$1"
}

function print_err () {
    printf "ERROR: %s\n\n" "${1}" >&2
    usage 1
}

# Parse optional arguments
while :; do
    case ${1} in
        -h|--help)
            usage 0
            ;;
        -o|--output)
	    path_out=${2}
	    shift 2
	    continue
	    ;;
        *)
            break
    esac
    shift
done

# Read required arguments
if [[ "$#" -ne 4 ]]; then
    print_err "Incorrect number of arguments."
fi
file_mrc=${1}
file_mod=${2}
path_ehs=${3}
dim=${4}

# Set default path if necessary
if [[ ! "${path_out}" ]]; then
    path_out="./training_data"
fi

# Source IMOD
source /home/aperez/.bashrc

# Check validity of file_mrc
if [[ ! -f "${file_mrc}" ]]; then
    print_err "The specified MRC file does not exist."
fi

header "${file_mrc}" > /dev/null
if [[ "$?" == 1 ]]; then
    print_err "The specified MRC file is not a valid MRC file."
fi

# Check validity of file_mod
if [[ ! -f "${file_mod}" ]]; then
    print_err "The specified model file does not exist."
fi

imodinfo "${file_mod}" > /dev/null
if [[ "$?" == 1 ]]; then
    print_err "The specified model file is not a valid IMOD model file."
fi 

# Check that file_mod has exactly two objects, and that the first object is of
# type scattered and the second object is of type closed. This is done by 
# parsing the ASCII model file output from imodinfo.
obj=0
obj_type[1]=0
obj_type[2]=0
while read -r line; do
    case "${line}" in
        imod*)
            # Check that the model file has exactly two objects.
            imod_obj=($line)
            if [[ ${imod_obj[1]} -ne 2 ]]; then
                print_err "The model file must contain two objects."
            fi
            ;;
        object*)
            # Increment the object counter when a new object is found.
            ((obj++))
            ;;
        scattered)
            # Store object type scattered if necessary.
            obj_type[${obj}]=1
            ;;
        open)
            # Store object type open if necessary.
            obj_type[${obj}]=2
            ;;
    esac
done < <(imodinfo -a "${file_mod}")

if [[ ${obj_type[1]} -ne 1 ]]; then
    print_err "The model file must have scattered contours for Object 1."
fi

if [[ ${obj_type[2]} -ne 0 ]]; then
    print_err "The model file must have closed contours for Object 2."
fi

# Check that path_ehs exists
if [[ ! -d "${path_ehs}" ]]; then
    print_err "The directory given by path_ehs does not exist."
fi

# Check that path_ehs contains PNG files
n_png_ehs="$(find "${path_ehs}" -maxdepth 1 -name "*.png" 2> /dev/null | wc -l)"
if [[ ${n_png_ehs} == 0 ]]; then
    print_err "The directory given by path_ehs does not contain PNGs."
fi

# Check that the number of slices in the file_mrc is equal to the number of
# PNG files in path_ehs.
dims_mrc="$(header -size "${file_mrc}")"
dims_mrc=($dims_mrc)

if [[ ${n_png_ehs} -ne ${dims_mrc[2]} ]]; then
    print_err "Mismatch between slices in the MRC and the number of PNG files."
fi

# Check that the lateral dimensions of file_mrc are equal to the lateral 
# dimensions of the first PNG file in path_ehs.
file_png_test="$(find "${path_ehs}" -maxdepth 1 -name "*.png" | sort | head -1)"
dims_png="$(identify -ping -format "%w %h" "${file_png_test}")"
dims_png=($dims_png)
if [[ ${dims_mrc[0]} -ne ${dims_png[0]} ]] || \
    [[ ${dims_mrc[1]} -ne ${dims_png[1]} ]]; then
    print_err "Mismatch between size of the MRC and the PNG files."
fi  

# Check validity of the dim string
n_commas="$(grep -o "," <<< "${dim}" | wc -l)"
if [[ ${n_commas} -ne 1 ]]; then
    print_err "Incorrect format of training data dimensions string."
fi

# Extract dimx and dimy from the input 'dim' comma-delimited string
IFS=","
read -ra train_dims <<< "${dim}"

qsub \
    -v file_mrc="${file_mrc}" \
    -v file_mod="${file_mod}" \
    -v path_ehs="${path_ehs}" \
    -v path_out="${path_out}" \
    -v dimx="${train_dims[0]}" \
    -v dimy="${train_dims[1]}" \
    process_training_data.q
