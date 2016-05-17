#! /bin/bash

function show_help () {
cat <<-END
contourgen.sh
Usage:
------
    -i | --input (Directory name)
        Path to series of TIF files to be processed
    
    -o | --output (Directory name)
        Path to store output model file to

    -m | --mrc (MRC stack)
        Name of MRC stack to match to

    -d | --del (Integer,Integer,Integer)
        Pixel size of MRC stack to match to (X,Y,Z)

    -r | --org (Integer,Integer,Integer)
        Origin of MRC stack to match to (X,Y,Z)    

    -R | --point
        Tolerance for point shaving during model generation.
        R = [0,...,1]. Default value = 0.

    -k | --sigma
        Smooth the data during model generation with a kernal filter
        whose Gaussian sigma is given by this value. Defaule value = 0.

    -h | --help
        Display this help
END
}

while :; do
    case $1 in
        -h|--help)
            show_help
            exit
            ;;
        -i|--input)
            path_in=$2
            shift 2
            continue
            ;;
        -o|--output)
            path_out=$2
            shift 2
            continue
            ;;
        -m|--mrc)
            mrc_stack=$2
            shift 2
            continue
            ;;
        -d|--del)
            del=$2
            shift 2
            continue
            ;;
        -r|--org)
            org=$2
            shift 2
            continue
            ;;
        -R|--point)
            pointred=$2
            shift 2
            continue
            ;;
        -k|--sigma)
            sigma=$2
            shift 2
            continue
            ;;
        *)
            break
    esac
    shift
done

#Check for problems with input. Print help and exit if not correct
if [[ ! $path_in ]] || [[ ! $path_out ]]; then
    printf 'ERROR: options -i and -o must be specified\n\n' >&2
    show_help
    exit 1
fi

if [[ -n $mrc_stack ]] && [[ -n $del ]]; then
    printf 'ERROR: Use either the -m option OR the -d and -r options\n\n' >&2
    show_help
    exit 1
elif [[ -n $mrc_stack ]] && [[ -n $org ]]; then
    printf 'ERROR: Use either the -m option OR the -d and -r options\n\n' >&2
    show_help
    exit 1
elif [[ ! $mrc_stack ]] && [[ ! $del ]] && [[ -n $org ]]; then
    printf 'ERROR: options -d and -r must both be specified\n\n' >&2
    show_help
    exit 1
elif [[ ! $mrc_stack ]] && [[ -n $del ]] && [[ ! $org ]]; then
    printf 'ERROR: options -d and -r must both be specified\n\n' >&2
    show_help
    exit 1
fi

source /home/aperez/.bashrc #Source IMOD

#Make output directory if necessary and make temporary subdirectories
if [[ ! -d $path_out ]]; then mkdir ${path_out}; fi
mkdir ${path_out}/log ${path_out}/mod ${path_out}/ncont ${path_out}/txt

Nslices=`ls ${path_in}/*.tif | wc -l` #Determine number of images

#If the original mrc stack is supplied, extract the pixel spacing and origin information
#from the header of that file. If not, use the user-supplied values. These values are 
#critical to ensure the output model file aligns properly with the original mrc stack.
if [[ -n $mrc_stack ]]; then
    del=`${IMOD_DIR}/bin/header -pixel $mrc_stack | tr -s ' '` 
    org=`${IMOD_DIR}/bin/header -origin $mrc_stack | tr -s ' '`
else
    del=`echo $del | tr ',' ' '` #Replace commas with spaces
    org=`echo $org | tr ',' ' '`
fi

#Turn off point reduction and smoothing (i.e., set their values to zero) if they are not specified
if [[ ! $pointred ]]; then pointred=0; fi
if [[ ! $sigma ]]; then sigma=0; fi

#(1) Submit tif2mod2D.q as an array job to convert TIFS to model files. 
qsub -t 1-${Nslices} -v path_in=${path_in},path_out=${path_out},del="${del}",org="${org}",pointred=${pointred},sigma=${sigma} -o ${path_out}/log tif2mod2D.q

#(2) Submit mod2point2D.q as an array job to convert model files to text files containing point listings.
qsub -hold_jid tif2mod -t 1-${Nslices} -v path_mod=${path_out}/mod,path_txt=${path_out}/ncont,path_out=${path_out}/txt -o ${path_out}/log mod2point2D.q

#(3) Submit point2mod3D.q to append all point listings to a single text file, and then generate a model from this using point2model.
qsub -hold_jid mod2point -v path_out=${path_out},del="${del}",org="${org}" -o ${path_out}/log point2mod3D.q
