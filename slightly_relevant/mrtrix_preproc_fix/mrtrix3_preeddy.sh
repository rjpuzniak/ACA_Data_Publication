#!/bin/bash

## Performs preprocessing steps, as recommended by MRtrix developers, up to eddy current correction step (but without it - this is handled by another script)
## Input: 	raw dwi image in mrtrix format (.mif)
## Output: 	separate dwi images ready to be fed to eddy + name of output dwi images

preeddy_preproc () {

## function input
local raw=${1::-4} 
local __resultvar=${2}

## switches for potentially optional steps
DO_DENOISE=$(jq -r '.denoise' ../config.json)
DO_DEGIBBS=$(jq -r '.degibbs' ../config.json)

NCORE=12

## diffusion file that changes name based on steps performed
difm=dwi
mask=dwi_mask

## create temp folders explicitly
mkdir ./tmp

## name of the output

local output_name

## extract gradient table
mrconvert ${raw}.mif -export_grad_mrtrix tmp/${raw}.b tmp/${raw}.mif

## create mask
dwi2mask ${raw}.mif tmp/${mask}.mif -force -nthreads $NCORE -quiet

echo "Identifying correct gradient orientation..."

## check and correct gradient orientation
dwigradcheck ${raw}.mif -grad tmp/${raw}.b -mask tmp/${mask}.mif -export_grad_mrtrix tmp/corr.b -force -tempdir ./tmp -nthreads $NCORE -quiet

## create corrected image
mrconvert ${raw}.mif -grad tmp/corr.b tmp/${difm}.mif -nthreads $NCORE -quiet

## perform PCA denoising
if [ $DO_DENOISE == "true" ]; then

    echo "Performing PCA denoising..."
    dwidenoise tmp/${difm}.mif tmp/${difm}_denoise.mif -nthreads $NCORE -quiet
    difm=${difm}_denoise
    
fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performing Gibbs ringing correction..."
    mrdegibbs tmp/${difm}.mif tmp/${difm}_degibbs.mif -nthreads $NCORE -quiet
    difm=${difm}_degibbs
    
fi

## setting output name
output_name="${difm}"
eval $__resultvar="'$myresult'"
printf -v "$__resultvar" '%s' "$output_name"

## removing unnecessary files
cp tmp/${difm}.mif ${difm}.mif
rm tmp -r

}

preeddy_preproc ce04_raw.mif result ; echo ${result}


