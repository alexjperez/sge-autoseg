#!/bin/bash

#$ -S /bin/bash
#$ -cwd
#$ -V

declare file_mrc
declare file_mod
declare path_ehs
declare path_out
declare dimx
declare dimy

# Make output directories
if [[ ! -d "${path_out}" ]]; then
    mkdir "${path_out}"
fi
mkdir "${path_out}"/images
mkdir "${path_out}"/labels
mkdir "${path_out}"/tmp

# Get the box "radii" as 1/2 dimx and 1/2 dimy
radx="$(echo "${dimx} / 2" | bc)"
rady="$(echo "${dimy} / 2" | bc)"

# Get the y dimension of the full image
mrc_dims="$(header -size "${file_mrc}")"
mrc_dims=($mrc_dims)
img_y=${mrc_dims[1]}

# Parse the ASCII IMOD model file line-by-line and extract the scattered point
# seed coordinates of object 1.
i=0
obj=0
cont_toggle=false
while read -r line; do
    case "${line}" in
        *object*)
            # Increment the object counter when a new object is encountered.
            # Break the loop when the second object containing the contours
            # is encountered.
            if [[ "${obj}" -lt 2 ]]; then
                ((obj++))
            else
                break
            fi
            ;;
        *contour*)
            # Set the contour toggle to true when a new contour is found.
            if [[ "${obj}" == 1 ]]; then 
                cont_toggle=true
            fi
            ;;
        *)
            # If the contour toggle is true, store the point coordinates to
            # an array and set the toggle to false.
            if "${cont_toggle}"; then
                seed_points[((i++))]="${line}"
                cont_toggle=false
            fi
    esac
done < <(imodinfo -a "${file_mod}")

# Get the number of seed points as the number of elements of the array
n_seeds=${#seed_points[@]}

# Loop over each seed point
for ((i=0;i<=$((n_seeds-1));i++)); do
 
    # Define output file basename as i with leading zeros
    fname_i="$(printf "%03d" $((i+1)))"

    # Get coordinates of i-th seed point
    coord_i=(${seed_points[i]})
    xi=${coord_i[0]}
    yi=${coord_i[1]}
    zi=${coord_i[2]}

    # Determine the i-th bounding box
    xmin=$((xi - radx))
    xmax=$((xi + radx - 1))
    ymin=$((yi - rady))
    ymax=$((yi + rady - 1))

    # Trim the i-th bounding box from the input mrc stack and store to a temp
    # MRC file.
    trimvol -x "${xmin}","${xmax}" \
        -y "${ymin}","${ymax}" \
        -z $((zi + 1)),$((zi + 1)) \
        "${file_mrc}" \
        "${path_out}"/tmp/"${fname_i}".mrc 

    # Generate training label by masking the temp MRC file by the provided
    # contours.
    imodmop -mask 1 -objects 2 \
        "${file_mod}" \
        "${path_out}"/tmp/"${fname_i}".mrc \
        "${path_out}"/tmp/"${fname_i}".mrc

    # Convert MRC to PNG. Remove the temp MRC file.
    mrc2tif -p \
        "${path_out}"/tmp/"${fname_i}".mrc \
        "${path_out}"/labels/"${fname_i}".png
    rm -rf "${path_out}"/tmp/"${fname_i}".mrc

    # Determine the PNG file to crop from for training images.
    img_i="$(find "${path_ehs}" -maxdepth 1 -name "*.png" \
        | sort \
        | sed -n ''$((zi+1))'p')"

    # Crop the image using ImageMagick convert.
    /home/aperez/usr/local/bin/convert \
        "${img_i}" \
        -crop "${dimx}"x"${dimx}"+"${xmin}"+$((img_y - ymax)) \
        "${path_out}"/images/"${fname_i}".png
done

# Remove temporary directory
rm -rf "${path_out}"/tmp
