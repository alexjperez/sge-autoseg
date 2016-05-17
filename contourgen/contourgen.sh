#! /bin/bash

# Wrapper script that submits an SGE job for generating a model file with IMOD
# contours about a stack of segmented TIF images. This is essentialy a 
# parallelization of imodauto that can run on SGE clusters.
#
# Written by Alex Perez - alexjperez@gmail.com


function usage () {
cat <<-END
Usage: $0 [options] path_seg

Required Arguments:
------------------
path_images Path that contains the stack of segmented TIF images.

Optional Arguments:
------------------
--mrc (MRC stack)
    Name of MRC stack to match the out put model to. If no value is supplied
    for --mrc, then both --del and --org must be supplied.

--del (Integer,Integer,Integer)
    Pixel size of MRC stack to match the output model to, in comma-separated
    form for X,Y,Z (e.g. 70,70,600). Pixel size is typically in Angstroms.

--org (Integer,Integer,Integer)
    Origin of MRC stack to match the output model to, in comma-separated form
    for X,Y,Z (e.g. 0,0,0).

--output (path)
    Output path to store temporary files and final model file to.

--point
    Tolerance for point shaving during model generation.
    R = [0,...,1]. Default value = 0.

--sigma
    Smooth the data during model generation with a kernal filter
    whose Gaussian sigma is given by this value. Defaule value = 0.

--mailto
    Email address to send job logs to.
    DEFAULT: None.

--jobname
    Job name to submit with.
    DEFAULT: 'contourgen'

-h | --help
    Display this help
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
            usage 0
            exit
            ;;
        --output)
            path_out=$2
            shift 2
            continue
            ;;
        --mrc)
            file_mrc=$2
            shift 2
            continue
            ;;
        --del)
            del=$2
            shift 2
            continue
            ;;
        --org)
            org=$2
            shift 2
            continue
            ;;
        --point)
            pointred=$2
            shift 2
            continue
            ;;
        --sigma)
            sigma=$2
            shift 2
            continue
            ;;
        --mailto)
            mailto=$2
            shift 2
            continue
            ;;
        --jobname)
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
if [[ "$#" -ne 1 ]]; then
    print_err "Incorrect number of arguments."
fi
path_seg=${1}

# Set defaults, if necessary
path_out="${path_out:-output}"
jobname="${jobname:-contourgen}"
pointred="${pointred:-0}"
sigma="${sigma:-0}"

# Check that valid MRC file information has been supplied. If an MRC stack has
# been input using the --mrc flag, check that the MRC stack is valid and if so,
# extract its del and org data. If no MRC stack has been input using the --mrc
# flag, make sure that both the --del and --org flags have been supplied with 
# data. If not, throw an error.
if [[ ! -z "${file_mrc+x}" ]]; then
    IFS=' '
    check_mrc "${file_mrc}"
    read -ra del < <(header -pixel "${file_mrc}")
    read -ra org < <(header -origin "${file_mrc}")
else
    if [[ -z "${del+x}" ]] || [[ -z "${org+x}" ]]; then
        print_err "If --mrc is not given, both --del and --org must be used."
    fi
    IFS=','
    read -ra del < <(echo "${del}")
    read -ra org < <(echo "${org}")
fi

# Check that del and org both have 3 values for X, Y, Z
if [[ "${#del[@]}" -ne 3 ]]; then
    print_err "Incorrect number of values supplied to --del."
fi

if [[ "${#org[@]}" -ne 3 ]]; then
    print_err "Incorrect number of values supplied to --org."
fi

# Check that path_seg exists
if [[ ! -d "${path_seg}" ]]; then
    print_err "The path given by path_images does not exist."
fi

# Get the number of TIF files in path_seg. 
nseg=$(ls "${path_seg}"/*.tif 2>/dev/null | wc -l)

# Print run metadata
echo "MRC pixel size (A): ${del[0]},${del[1]},${del[2]}"
echo "MRC origin: ${org[0]},${org[1]},${org[2]}"
echo "# of segmented images: ${nseg}"
echo "Point reduction: ${pointred}"
echo "Gaussian sigma: ${sigma}"

# Make output directory, if necessary
if [[ ! -d "${path_out}" ]]; then
    mkdir "${path_out}" "${path_out}"/log "${path_out}"/err 
    mkdir "${path_out}"/mod "${path_out}"/ncont "${path_out}"/txt
fi

# Build qsub submit string for step 1 (tif2mod2D)
qstr1="-N ${jobname}-1 "
qstr1+="-t 1-${nseg} "
qstr1+="-v path_seg=${path_seg} "
qstr1+="-v path_out=${path_out} "
qstr1+="-v del1=${del[0]} "
qstr1+="-v del2=${del[1]} "
qstr1+="-v del3=${del[2]} "
qstr1+="-v org1=${org[0]} "
qstr1+="-v org2=${org[1]} "
qstr1+="-v org3=${org[2]} "
qstr1+="-v pointred=${pointred} "
qstr1+="-v sigma=${sigma} "
qstr1+="-o ${path_out}/log "
qstr1+="-e ${path_out}/err "
if [[ ! -z "${mailto+x}" ]]; then
    qstr1+="-m eas -M ${mailto} "
fi
if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
    qstr1+="-q default.q "
fi

# Build qsub submit string for step 2 (tif2mod)
qstr2="-hold_jid"
qstr2+="-N ${jobname}-2 "
qstr2+="-t 1-${nseg} "
qstr2+="-v path_mod=${path_out}/mod "
qstr2+="-v path_txt=${path_out}/ncont "
qstr2+="-v path_out=${path_out}/txt "
qstr2+="-o ${path_out}/log "
qstr2+="-e ${path_out}/err "
if [[ ! -z "${mailto+x}" ]]; then
    qstr2+="-m eas -M ${mailto} "
fi
if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
    qstr2+="-q default.q "
fi

# Build qsub submit string for step 3 (mod2point)
qstr3="-hold_jid"
qstr3+="-N ${jobname}-3 "
qstr3+="-v path_out=${path_out} "
qstr3+="-v del1=${del[0]} "
qstr3+="-v del2=${del[1]} "
qstr3+="-v del3=${del[2]} "
qstr3+="-v org1=${org[0]} "
qstr3+="-v org2=${org[1]} "
qstr3+="-v org3=${org[2]} "
qstr3+="-o ${path_out}/log "
qstr3+="-e ${path_out}/err "
if [[ ! -z "${mailto+x}" ]]; then
    qstr3+="-m eas -M ${mailto} "
fi
if [[ "$HOSTNAME" == "megashark.crbs.ucsd.edu" ]]; then
    qstr3+="-q default.q "
fi

# Submit jobs
#qsub ${qstr1} tif2mod2D.q
#qsub ${qstr2} mod2point2D.q
#qsub ${qstr3} point2mod3D.q
