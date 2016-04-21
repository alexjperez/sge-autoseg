#! /bin/bash

# Wrapper script that submits and SGE job for converting an MRC stack to a
# series of PNGs using the IMOD program mrc2tif and the -p  flag.
#
# Written by Alex Perez - alexjperez@gmail.com

function usage () {
cat <<-END
Usage: $0 [options] file.mrc path_out

Required Arguments:
------------------
file.mrc
    MRC stack to convert to individual PNG image slices.

path_out
    Output path to store PNG images to.

Optional Arguments:
------------------
-h | --help
    Display this help

-m | --mailto
    Email address to send job logs to.
    DEFAULT = None.

-j | --jobname
    Job name to submit with.
    DEFAULT = 'mrc2png'
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

# Read optional arguments
while :; do
    case $1 in
        -h|--help)
            usage 0
            shift 1
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
if [[ "$#" -ne 2 ]]; then
    print_err "Incorrect number of arguments."
fi
file_mrc=${1}
path_out=${2}

# Set defaults, if necessary
jobname="${jobname:-mrc2png}"

# Check validity of mrc file
check_mrc "${file_mrc}"

# Create path_out if necessary
if [[ ! -d "${path_out}" ]]; then
    mkdir "${path_out}" "${path_out}"/log "${path_out}"/err
fi

# Get number of slices in file_mrc
IFS=' '
read -ra mrcdims < <(header -size "${file_mrc}")

# Build qsub submit string
qstr="-N ${jobname} "
qstr+="-t 1-${mrcdims[2]} "
qstr+="-v file_mrc=${file_mrc} "
qstr+="-v path_out=${path_out} "
qstr+="-v nslices=${mrcdims[2]} "
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
qsub "${qstr}" mrcstack2png.q
