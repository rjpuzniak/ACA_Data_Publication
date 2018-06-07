#!/bin/bash

## add option to just perform motion correction

## define number of threads to use
NCORE=12 #8

## raw inputs

ANAT=`jq -r '.anat' config.json`

DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`

DIFF2=`jq -r '.diff2' config.json`
BVAL2=`jq -r '.bval2' config.json`
BVEC2=`jq -r '.bvec2' config.json`

PAIRS=`jq -r '.pairs' config.json`

## acquisition phase-encoding design: none (no reversed PE), pair (single pair of images with reversed PE direction, typically b0), all (whole series acquired with two PE directions), header (PE information is stored in header and this will be the information to be used) 
RPE=`jq -r '.rpe' config.json`

## acquisition direction: RL, PA, IS
ACQD=`jq -r '.acqd' config.json`

## switches for potentially optional steps
DO_DENOISE=`jq -r '.denoise' config.json`
DO_DEGIBBS=`jq -r '.degibbs' config.json`
DO_EDDY=`jq -r '.eddy' config.json`
DO_BIAS=`jq -r '.bias' config.json`
DO_NORM=`jq -r '.norm' config.json`
DO_ACPC=`jq -r '.acpc' config.json`
NEW_RES=`jq -r '.reslice' config.json`

if [ -z $NEW_RES ]; then
    DO_RESLICE="false"
else
    DO_RESLICE="true"
fi

echo NEW_RES: $NEW_RES
echo DO_RESLICE: $DO_RESLICE

## assign output space of final data if acpc not called
out=proc

## diffusion file that changes name based on steps performed
difm=dwi
mask=b0_dwi_brain_mask

## create local copy of anat
cp $ANAT ./t1_acpc.nii.gz
ANAT=t1_acpc

## create temp folders explicitly
mkdir ./tmp

echo "Converting input files to mrtrix format..."

## convert input diffusion data into mrtrix format
mrconvert -fslgrad $BVEC $BVAL $DIFF raw.mif --export_grad_mrtrix raw.b -nthreads $NCORE -quiet

echo "Creating dwi space b0 reference images..."

## create b0 and mask image in dwi space
dwiextract raw.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0_dwi.mif -axis 3 -nthreads $NCORE -quiet
dwi2mask raw.mif ${mask}.mif -force -nthreads $NCORE -quiet

## convert to nifti for alignment
mrconvert b0_dwi.mif -stride 1,2,3,4 b0_dwi.nii.gz -nthreads $NCORE -quiet
mrconvert ${mask}.mif -stride 1,2,3,4 ${mask}.nii.gz -nthreads $NCORE -quiet

## apply mask to image
fslmaths b0_dwi.nii.gz -mas ${mask}.nii.gz b0_dwi_brain.nii.gz

echo "Creating processing mask..."

## create mask
dwi2mask raw.mif ${mask}.mif -force -nthreads $NCORE -quiet

##################################################################################################################### HERE APPLY PREEDDY FUNCTION TO ALL POSSIBLE EDDY INPUT

source mrtrix_preeddy.sh raw.mif

${difm}
${rpe_pair}
${difm} $all



echo "Identifying correct gradient orientation..."

## check and correct gradient orientation
dwigradcheck raw.mif -grad raw.b -mask ${mask}.mif -export_grad_mrtrix corr.b -force -tempdir ./tmp -nthreads $NCORE -quiet

## create corrected image
mrconvert raw.mif -grad corr.b ${difm}.mif -nthreads $NCORE -quiet

## perform PCA denoising
if [ $DO_DENOISE == "true" ]; then

    echo "Performing PCA denoising..."
    dwidenoise ${difm}.mif ${difm}_denoise.mif -nthreads $NCORE -quiet
    difm=${difm}_denoise
    
fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performing Gibbs ringing correction..."
    mrdegibbs ${difm}.mif ${difm}_degibbs.mif -nthreads $NCORE -quiet
    difm=${difm}_degibbs
    
fi
   
## perform eddy correction with FSL
if [ $DO_EDDY == "true" ]; then

	if [ $RPE == "none" ]; then
	    
	      echo "Performing FSL eddy correction..."
	      dwipreproc -rpe_none -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -cuda -tempdir ./tmp -nthreads $NCORE -quiet
	      difm=${difm}_eddy
	
    	fi

	if [ $RPE == "pairs" ]; then
	    
	      echo "Performing FSL eddy correction providing pair(s) of images with dual PE directions in order to correct DW series with single PE direction..."
	      dwipreproc -rpe_pair ${rpe_pair}.mif -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -cuda -tempdir ./tmp -nthreads $NCORE -quiet
	      difm=${difm}_eddy
	
	fi

    	if [ $RPE == "all" ]; then
    
		echo "Performing FSL eddy correction for combined series of DW images with dual PE directions..."
		dwipreproc -rpe_all -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -cuda -tempdir ./tmp -nthreads $NCORE -quiet
		difm=${difm}_eddy
	
    	fi

    
    	if [ $RPE == "header" ]; then
    
		echo "Performing FSL eddy correction for combined series of DW images with dual PE directions..."
		dwipreproc -rpe_header ${difm}.mif ${difm}_eddy.mif -cuda -tempdir ./tmp -nthreads $NCORE -quiet
		difm=${difm}_eddy
	
    	fi

fi

## recreate mask after potential motion corrections
dwi2mask ${difm}.mif ${mask}.mif -force -nthreads $NCORE -quiet

## compute bias correction with ANTs on dwi data
if [ $DO_BIAS == "true" ]; then
    
    echo "Performing bias correction with ANTs..."
    dwibiascorrect -mask ${mask}.mif -ants ${difm}.mif ${difm}_bias.mif -tempdir ./tmp -nthreads $NCORE -quiet
    difm=${difm}_bias
    
fi

## perform intensity normalization of dwi data
if [ $DO_NORM == "true" ]; then

    echo "Performing intensity normalization..."

    ## create fa wm mask of input subject
    dwi2tensor -mask ${mask}.mif -nthreads $NCORE -quiet ${difm}.mif - | tensor2metric -nthreads $NCORE -quiet - -fa - | mrthreshold -nthreads $NCORE -quiet -abs 0.5 - wm.mif 

    ## dilate / erode fa wm mask for smoother volume
    #maskfilter -npass 3 wm_raw.mif dilate - | maskfilter -connectivity - connect - | maskfilter -npass 3 - erode wm.mif
    ## this looks far too blocky to be useful
    
    ## normalize intensity of generous FA white matter mask to 1000
    dwinormalise -intensity 1000 ${difm}.mif wm.mif ${difm}_norm.mif -nthreads $NCORE -quiet
    difm=${difm}_norm
    
fi

if [ $DO_ACPC == "true" ]; then

    echo "Running brain extraction on anatomy..."

    ## create t1 mask
    bet ${ANAT}.nii.gz ${ANAT}_brain -R -B -m

    echo "Aligning dwi data with AC-PC anatomy..."

    ## compute BBR registration corrected diffusion data to AC-PC anatomy
    epi_reg --epi=b0_dwi_brain.nii.gz --t1=${ANAT}.nii.gz --t1brain=${ANAT}_brain.nii.gz --out=dwi2acpc

    ## apply the transform w/in mrtrix, correcting gradients
    mrtransform -linear dwi2acpc.mat ${difm}.mif ${difm}_acpc.mif -nthreads $NCORE -quiet
    difm=${difm}_acpc

    ## assign output space label
    out=acpc
    
fi

if [ $DO_RESLICE == "true" ]; then

    echo "Reslicing diffusion data to requested isotropic voxel size..."

    ## sed to turn possible decimal into p
    VAL=`echo $NEW_RES | sed s/\\\./p/g`

    mrresize ${difm}.mif -voxel $NEW_RES ${difm}_${VAL}mm.mif -nthreads $NCORE -quiet
    difm=${difm}_${VAL}mm

else

    ## append voxel size in mm to the end of file, rename
    VAL=`mrinfo -vox dwi.mif | awk {'print $1'} | sed s/\\\./p/g`
    echo VAL: $VAL
    mv ${difm}.mif ${difm}_${VAL}mm.mif
    difm=${difm}_${VAL}mm
    
fi

echo "Creating $out space b0 reference images..."

if [ -e ${difm}.mif ]; then
    echo ${difm}.mif FOUND
fi

## create final b0 / mask
dwiextract ${difm}.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0_${out}.mif -axis 3 -nthreads $NCORE -quiet
dwi2mask ${difm}.mif b0_${out}_brain_mask.mif -nthreads $NCORE -quiet

## create output space b0s
mrconvert b0_${out}.mif -stride 1,2,3,4 b0_${out}.nii.gz -nthreads $NCORE -quiet
mrconvert b0_${out}_brain_mask.mif -stride 1,2,3,4 b0_${out}_brain_mask.nii.gz -nthreads $NCORE -quiet
fslmaths b0_${out}.nii.gz -mas b0_${out}_brain_mask.nii.gz b0_${out}_brain.nii.gz

echo "Creating preprocessed dwi files in $out space..."

## convert to nifti / fsl output for storage
mrconvert ${difm}.mif -stride 1,2,3,4 ${difm}.nii.gz -export_grad_fsl ${difm}.bvecs ${difm}.bvals -export_grad_mrtrix ${difm}.b -json_export ${difm}.json -nthreads $NCORE -quiet

##
## export a lightly structured text file (json?) of shell count / lmax
##

echo "Writing text file of basic sequence information..."

## parse single or multishell counts
nshell=`mrinfo -shells ${difm}.mif | wc -w`
shell=$(($nshell-1))

if [ $shell -gt 1 ]; then
    echo multi-shell: $shell total shells >> summary.txt
else
    echo single-shell: $shell total shell >> summary.txt
fi

## compute # of b0s
b0s=`mrinfo -shellcounts ${difm}.mif | awk '{print $1}'`
echo Number of b0s: $b0s >> summary.txt 

echo >> summary.txt
echo shell / count / lmax >> summary.txt

## echo basic shell count summaries
mrinfo -shells ${difm}.mif >> summary.txt
mrinfo -shellcounts ${difm}.mif >> summary.txt

## echo max lmax per shell
lmaxs=`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
echo $lmaxs >> summary.txt

## print into log
cat summary.txt

echo "Cleaning up working directory..."

## link output files to simple output names
mkdir out

## link final preprocessed files
ln -s ${difm}.nii.gz out/dwi.nii.gz
ln -s ${difm}.bvals out/dwi.bvals
ln -s ${difm}.bvecs out/dwi.bvecs

## link raw diffusion space b0 / mask
ln -s b0_dwi.nii.gz out/
ln -s b0_dwi_brain.nii.gz out/
ln -s b0_dwi_brain_mask.nii.gz out/

## link final preprocessed b0 / mask
ln -s b0_${out}.nii.gz out/
ln -s b0_${out}_brain.nii.gz out/
ln -s b0_${out}_brain_mask.nii.gz out/

## link masked anatomy
ln -s anat_acpc.nii.gz out/
ln -s anat_acpc_brain.nii.gz out/
ln -s anat_acpc_brain_mask.nii.gz out/

## cleanup
rm -f *.mif
rm -f raw.b
rm -f corr.b
rm -f *fast*.nii.gz
rm -f *init.mat
rm -f dwi2acpc.nii.gz
rm -rf ./tmp

