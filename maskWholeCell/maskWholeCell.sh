#! /bin/bash

# Wrapper script that submits an SGE job for masking a full stack segmentation
# into regions specified by a trace from an IMOD model file. These regions are
# typically cells (e.g., masking segmented mitochondria into a particular cell
# that was manually traced.
#
# Written by Alex Perez - alexjperez@gmail.com

function usage () {
cat <<-END
Usage: $0 [options] file.mrc path_mod path_seg

Required Arguments:
------------------
file.mrc
    Original MRC the segmentation was built on.

path_mod
    Path to a directory containing model files, where each model file
    corresponds to one cell or structure to be masked. Model files must
    have a .mod extension.

path_seg
    Path to a stack of segmented images, stored as TIFs.

Optional Arguments:
------------------
-o | --output
    Path to save output masked model files to.
    DEFAULT: ./output

-m | --mailto
    Email address to send job logs to.
    DEFAULT: None.

-j | --jobname
    Job name to submit with.
    DEFAULT: 'mask'

-h | --help
    Display this help.
END
exit "$1"
}

function print_err () {
    # Prints specified error message and exits with a status of 1.
    printf "ERROR: %s\n\\n" "${1}" >&2
    usage 1
}

function check_mrc () {
    # Checks the validity of an input MRC file in two ways. First, checks to
    # see if the file exists. If so, the IMOD program header will be run on 
    # the MRC file. If the exit status is 1, the MRC file is not valid.
    if [[ ! -f "$1" ]]; then
        print_err "The specified MRC file does not exist."
    fi
    
    header "$1" > /dev/null
    if [[ "$?" == 1 ]]; then
        print_err "The specified MRC file is not in the valid MRC format."
    fi
}

# Parse optional arguments
while :; do
    case $1 in
        -h|--help)
            usage
            exit
            ;;
        -o|--output)
            path_out=$2
            shift 2
            continue
            ;;
        -m|--mailto)
            mailto=$2
            shift 2
            continue
            ;;
        -j|--jobname)
            jobname=$2
            shift 2
            continue
            ;;
        *)
            break
    esac
    shift
done

# Read required arguments
if [[ "$#" -ne 3 ]]; then
    print_err "Incorrect number of arguments."
fi
file_mrc=${1}
path_mod=${2}
path_seg=${3}

# Set defaults, if necessary
path_out="${path_out:-output}"
jobname="${jobname:-mask}"

# Check validity of file_mrc
check_mrc "${file_mrc}"

# Get size of mrc file
IFS=' '
read -ra mrcdims < <(header -size "${file_mrc}")

# Check that path_mod exists
if [[ ! -d "${path_mod}" ]]; then
    print_err "The model file path specified by path_mod does not exist."
fi

# Check that path_seg exists
if [[ ! -d "${path_seg}" ]]; then
    print_err "The seg file path specified by seg_mod does not exist."
fi

# Get the number of TIF files in path_seg. Check that the number of TIF files
# is the same as the Z dimension of the MRC stack.
nseg=$(ls "${path_seg}"/*.tif 2>/dev/null | wc -l)
if [[ "${nseg}" -ne "${mrcdims[2]}" ]]; then
    print_err "Number of seg images does not match the MRC stack size."
fi

# Get the number of mask model files in path_mod. Exit with an error if no
# files exist.
nmod=$(ls "${path_mod}"/*.mod 2>/dev/null | wc -l)
if [[ "${nmod}" == 0 ]]; then
    print_err "No model files are present in path_mod."
fi

# Check the validity of each individual mask model file. First, check that it
# contains at least one object. Second, check that the dimensions specified in
# the model file are the same as the max dimensions of the mrc file.
for file in "${path_mod}"/*.mod; do
    while read -r line; do
        case "${line}" in
           imod*)
               read -ra nobj <<< "${line}"
               if [[ "${nobj[1]}" == 0 ]]; then
                   strerr=$(printf "The model file %s is not valid." "${file}")
                   print_err "${strerr}"
               fi
               ;;
            max*)
                read -ra moddims <<< "${line}"
                unset moddims[0]
                moddims=( "${moddims[@]}" )
                for i in 0 1 2; do
                    if [[ "${moddims["$i"]}" -ne "${mrcdims["$i"]}" ]]; then
                        strerr=$(printf "The model file %s does not match the mrc file." "${file}")
                        print_err "${strerr}"
                    fi
                done
                break
                ;;
        esac
    done < <(imodinfo -a "${file}" 2> /dev/null)
done

# Create output directory, if necessary
if [[ ! -d "${path_out}" ]]; then 
    mkdir "${path_out}" "${path_out}"/log "${path_out}"/err
fi

# Build qsub submit string
qstr="-N ${jobname} "
qstr+="-t 1-${nmod} "
qstr+="-v file_mrc=${file_mrc} "
qstr+="-v path_seg=${path_seg} "
qstr+="-v path_mod=${path_mod} "
qstr+="-v path_out=${path_out} "
qstr+="-o ${path_out}/log "
qstr+="-e ${path_out}/err "

if [[ ! -z "${mailto+x}" ]]; then
    qstr+="-m eas -M ${mailto} "
fi

# Specify certain queues to submit to, depending on the cluster
if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
    qstr+="-q default.q "
fi

# Submit job
qsub ${qstr} maskWholeCell.q
