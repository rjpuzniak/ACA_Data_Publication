#!/bin/bash

## define number of threads to use
NCORE=12

##
## parse inputs
##

## raw inputs
DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`
ANAT=`jq -r '.anat' config.json`
FIVETT=`jq -r '.fivett' config.json` # optional

## additional options
B0=`jq -r '.b0' config.json`

## parse potential ensemble / individual lmaxs
ENS_LMAX=`jq -r '.ens_lmax' config.json`
IMAXS=`jq -r '.imaxs' config.json`

## single fiber response (SFR) parameters
SFR_ALG=`jq -r '.response_algorithm' config.json`
SFR_LMAX=`jq -r '.response_lmax' config.json`

## fibre orientation distribution (FOD) parameters
FOD_ALG=`jq -r '.dwi2fod_algorithm' config.json`
FOD_LMAX=`jq -r '.dwi2fod_lmax_range' config.json`

## tracking params
CURVS=`jq -r '.curvs' config.json`
FA=`jq -r '.FAtresh' config.json`
NUM_FIBERS=`jq -r '.num_fibers' config.json`
MIN_LENGTH=`jq -r '.min_length' config.json`
MAX_LENGTH=`jq -r '.max_length' config.json`
SEED=`jq -r '.seed' config.json`
STEP=`jq -r '.step' config.json`

## perform multi-tissue intensity normalization
NORM=`jq -r '.norm' config.json`

## tracking types
DO_PRB2=`jq -r '.do_prb2' config.json`

# ROIs
START_ROIs=`jq -r '.start_ROIs' config.json`
END_ROIs=`jq -r '.end_ROIs' config.json`
INCL_ROIs=`jq -r '.incl_ROIs' config.json`
EXCL_ROIs=`jq -r '.excl_ROIs' config.json`

##
## begin execution
##

## working directory labels
mkdir ./tmp
difm=dwi
mask=mask
anat=t1

## convert input diffusion data into mrtrix format
echo "Converting raw data into MRTrix3 format..."
mrconvert -fslgrad $BVEC $BVAL $DIFF ${difm}.mif --export_grad_mrtrix ${difm}.b -nthreads $NCORE -quiet

## create mask of dwi data
dwi2mask ${difm}.mif ${mask}.mif -nthreads $NCORE -quiet

## convert anatomy
mrconvert $ANAT ${anat}.mif -nthreads $NCORE -quiet

## create b0 - accepting non-zero b0 if provided by user
if [ $B0 -eq 0 ]; then
	dwiextract ${difm}.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0.mif -axis 3 -nthreads $NCORE -quiet
else
	dwiextract ${difm}.mif -shell 0,$B0 -nthreads $NCORE -quiet | mrmath - mean b0.mif -axis -nthreads $NCORE -quiet
fi

## check if b0 volume successfully created
if [ ! -f b0.mif ]; then
    echo "No b-zero volumes present."
    NSHELL=`mrinfo -shells ${difm}.mif | wc -w`
    NB0s=0
    EB0=''
else
    ISHELL=`mrinfo -shells ${difm}.mif | wc -w`
    NSHELL=$(($ISHELL-1))
    NB0s=`mrinfo -shellcounts ${difm}.mif | awk '{print $1}'`
    EB0="0,"
fi

## determine single shell or multishell fit
if [ $NSHELL -gt 1 ]; then
    MS=1
    echo "Multi-shell data: $NSHELL total shells"
else
    MS=0
    echo "Single-shell data: $NSHELL shell"
    if [ ! -z "$TENSOR_FIT" ]; then
	echo "Ignoring requested tensor shell. All data will be fit and tracked on the same b-bvalue."
    fi
fi

## print the # of b0s
echo Number of b0s: $NB0s 

## extract the shells and # of volumes per shell
BVALS=`mrinfo -shells ${difm}.mif`
COUNTS=`mrinfo -shellcounts ${difm}.mif`

## echo basic shell count summaries
echo -n "Shell b-values: "; echo $BVALS
echo -n "Unique Counts:  "; echo $COUNTS

## echo max lmax per shell
MLMAXS=`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
echo -n "Maximum Lmax:   "; echo $MLMAXS

## find maximum lmax that can be computed within data
MAXLMAX=`echo "$MLMAXS" | tr " " "\n" | sort -nr | head -n1`
echo "Maximum Lmax across shells: $MAXLMAX"

## setting up SFR lmax, only one value expected

## if input $SFR_LMAX is empty, set to $MAXLMAX
if [ -z $SFR_LMAX ]; then
    echo "No Single Fiber Response (SFR) Lmax values requested."
    echo "Using the maximum SFR Lmax of $MAXLMAX by default."
    SFR_LMAX=$MAXLMAX
fi

## make sure requested SFR Lmax is possible - fix if not
if [ $SFR_LMAX -gt $MAXLMAX ]; then
    
    echo "Requested maximum SFR Lmax of $SFR_LMAX is too high for this data, which supports Lmax $MAXLMAX."
    echo "Setting maximum SFR Lmax to maximum allowed by the data: Lmax $MAXLMAX."
    SFR_LMAX=$MAXLMAX

fi

## setting up FOD lmax, one or more values expected

## if input $FOD_LMAX is empty, set to $MAXLMAX
if [ -z "$FOD_LMAX" ]; then
    echo "No Fiber Orientation Distribution (FOD) Lmax values requested."
    echo "Using the maximum FOD Lmax of $MAXLMAX by default."
    FOD_LMAX=$MAXLMAX
fi

## check if more than 1 lmax passed
NMAX=`echo $FOD_LMAX | wc -w`

## find max of the requested list
if [ $NMAX -gt 1 ]; then

    ## pick the highest
    MMAXS=`echo -n "$FOD_LMAX" | tr " " "\n" | sort -nr | head -n1`
    echo "User requested Lmax(s) up to: $MMAXS"
    LMAXS=$FOD_LMAX

else

    ## take the input
    MMAXS=$FOD_LMAX
	
fi

## make sure requested FOD Lmax is possible - fix if not and create the list of ensemble lmax values. Otherwise just proceed with input FOD_LMAX
if [ $MMAXS -gt $MAXLMAX ]; then
    
    echo "Requested maximum Lmax of $MMAXS is too high for this data, which supports Lmax $MAXLMAX."
    echo "Setting maximum Lmax to maximum allowed by the data: Lmax $MAXLMAX."
    MMAXS=$MAXLMAX

fi

if [[ $FOD_LMAX == 'true' && $NMAX -eq 1 ]]; then
## create the list of the ensemble lmax values
	    
    ## create array of lmaxs to use
    emax=0
    LMAXS=''
	
    ## while less than the max requested
    while [ $emax -lt $MMAXS ]; do

	## iterate
	emax=$(($emax+2))
	LMAXS=`echo -n $LMAXS; echo -n ' '; echo -n $emax`

    done

    else

    ## or just pass the list on
    LMAXS=$FOD_LMAX

fi

## create repeated lmax argument(s) based on how many shells are found

## create the correct length of lmax
RMAX=${MAXLMAX}
iter=1

## for every shell
while [ $iter -lt $(($NSHELL+1)) ]; do
    
    ## add the $MAXLMAX to the argument
    RMAX=$RMAX,$MAXLMAX

    ## update the iterator
    iter=$(($iter+1))

done

echo RMAX: $RMAX

echo "Tractography will be created on lmax(s): $LMAXS"

## compute the required size of the final output
TOTAL=0

if [ $DO_PRB2 == "true" ]; then
    for lmax in $LMAXS; do
	for curv in $CURVS; do
	    for fa in $FA; do
		for sroi in $START_ROIs; do
			for eroi in $END_ROIs; do
	       		TOTAL=$(($TOTAL+$NUM_FIBERS))
			done
		done
	    done
       done
    done
fi

echo "Expecting $TOTAL streamlines in track.tck."

## check if $TENSOR_FIT shell exists in the data and subset data if it does, otherwise ignore
if [ ! -z $TENSOR_FIT ]; then

    ## look for the requested shell
    TFE=`echo $BVALS | grep -o $TENSOR_FIT`

    ## if it finds it
    if [ ! -z $TFE ]; then
	echo "Requested b-value for fitting the tensor, $TENSOR_FIT, exists within the data."
	echo "Extracting b-${TENSOR_FIT} shell for tensor fit..."    
	dwiextract ${difm}.mif ${difm}_ten.mif -bzero -shell ${EB0}${TENSOR_FIT} -nthreads $NCORE -quiet
	dift=${difm}_ten
    else
	echo "Requested b-value for fitting the tensor, $TENSOR_FIT, does not exist within the data."
	echo "The single-shell tensor fit will be ignored; the tensor will be fit across all b-values."
	dift=${difm}
	TENSOR_FIT=''
    fi

else

    ## just pass the data forward
    dift=${difm}
    
fi    

## fit the tensor
if [ $MS -eq 0 ]; then

    ## estimate single shell tensor
    echo "Fitting tensor model..."
    dwi2tensor -mask ${mask}.mif ${dift}.mif dt.mif -bvalue_scaling false -nthreads $NCORE -quiet

else

    ## if single shell tensor is requested, fit it
    if [ ! -z $TENSOR_FIT ]; then

	## fit the requested single shell tensor for the multishell data
	echo "Fitting single-shell b-value $TENSOR_FIT tensor model..."
	dwi2tensor -mask ${mask}.mif ${dift}.mif dt.mif -bvalue_scaling false -nthreads $NCORE -quiet

    else

	## estimate multishell tensor w/ kurtosis and b-value scaling
	echo "Fitting multi-shell tensor model..."
	dwi2tensor -mask ${mask}.mif ${dift}.mif -dkt dk.mif dt.mif -bvalue_scaling true -nthreads $NCORE -quiet

    fi

fi

## create tensor metrics either way
tensor2metric -mask ${mask}.mif -adc md.mif -fa fa.mif -ad ad.mif -rd rd.mif -cl cl.mif -cp cp.mif -cs cs.mif dt.mif -nthreads $NCORE -quiet

## if not provided, create 5-Tissue-Type tracking mask
if [ -z $FIVETT ]; then

	echo "Creating 5-Tissue-Type (5TT) tracking mask..."
	## convert anatomy 
	5ttgen fsl ${anat}.mif 5tt.mif -nocrop -sgm_amyg_hipp -tempdir ./tmp -nthreads $NCORE -quiet
	FIVETT=5tt	
fi
	## generate gm-wm interface seed mask
	5tt2gmwmi ${FIVETT}.nii.gz gmwmi_seed.mif -nthreads $NCORE -quiet

	## create visualization output
	5tt2vis ${FIVETT}.nii.gz ${FIVETT}vis.mif -nthreads $NCORE -quiet



if [ $MS -eq 0 ]; then

    echo "Estimating CSD response function..."
    dwi2response ${SFR_ALG} ${difm}.mif response.txt -lmax ${SFR_LMAX} -nthreads $NCORE -tempdir ./tmp -quiet
    
else

    echo "Estimating MSMT CSD response function..."
    dwi2response msmt_5tt ${difm}.mif ${FIVETT}.mif wmt.txt gmt.txt csf.txt -mask ${mask}.mif -lmax $RMAX -tempdir ./tmp -nthreads $NCORE -quiet

fi

## fit the CSD across requested lmax's
if [ $MS -eq 0 ]; then

    for lmax in $LMAXS; do

	echo "Fitting CSD FOD of Lmax ${lmax}..."
	dwi2fod $FOD_ALG -mask ${mask}.mif ${difm}.mif response.txt csd_lmax${lmax}.mif -lmax $lmax -shell 1600 -nthreads $NCORE -quiet

	## intensity normalization of CSD fit
	# if [ $NORM == 'true' ]; then
	#     #echo "Performing intensity normalization on Lmax $lmax..."
	#     ## function is not implemented for singleshell data yet...
	#     ## add check for fails / continue w/o?
	# fi
	
    done
    
else

    for lmax in $LMAXS; do

	# ## create an appropriate number repeated individual lmax calls
	# Rmax=${lmax}
	# iter=1

        # ## for every shell
	# while [ $iter -lt $(($NSHELL+1)) ]; do
    
        #     ## add the $lmax to the argument
	#     Rmax=$Rmax,$lmax

        #     ## update the iterator
	#     iter=$(($iter+1))

	# done

	# echo Rmax: $Rmax

	echo "Fitting MSMT CSD FOD of Lmax ${lmax}..."
	dwi2fod msmt_csd ${difm}.mif wmt.txt wmt_lmax${lmax}_fod.mif gmt.txt gmt_lmax${lmax}_fod.mif csf.txt csf_lmax${lmax}_fod.mif -mask ${mask}.mif -lmax $lmax,$lmax,$lmax -nthreads $NCORE -quiet

	if [ $NORM == 'true' ]; then

	    echo "Performing multi-tissue intensity normalization on Lmax $lmax..."
	    mtnormalise -mask ${mask}.mif wmt_lmax${lmax}_fod.mif wmt_lmax${lmax}_norm.mif gmt_lmax${lmax}_fod.mif gmt_lmax${lmax}_norm.mif csf_lmax${lmax}_fod.mif csf_lmax${lmax}_norm.mif -nthreads $NCORE -quiet

	    ## check for failure / continue w/o exiting
	    if [ -z wmt_lmax${lmax}_norm.mif ]; then
		echo "Multi-tissue intensity normalization failed for Lmax $lmax."
		echo "This processing step will not be applied moving forward."
		NORM='false'
	    fi

	fi

    done
    
fi


## preparation of tracking command

## create list of inclusion and exclusion ROIs 

including=""
for i in ${INCL_ROI}; do
	including+=-include" "$i" ";
done

excluding=""
for i in ${EXCL_ROI}; do
	excluding+=-exclude" "$i" ";
done

echo "Performing Anatomically Constrained Tractography (ACT)..."

if [ $DO_PRB2 == "true" ]; then

    echo "Tracking iFOD2 streamlines..."
    
    for lmax in $LMAXS; do

	## pick correct FOD for tracking
	if [ $MS -eq 1 ]; then
	    if [ $NORM == 'true' ]; then
		fod=wmt_lmax${lmax}_norm.mif
	    else
		fod=wmt_lmax${lmax}_fod.mif
	    fi
	else
	    fod=csd_lmax${lmax}.mif
	fi
	
	for curv in $CURVS; do

	    for cutoff in $FA; do

		for starting in ${START_ROIs}; do

			for ending in ${END_ROIs}; do

			    echo "Tracking iFOD2 streamlines at Lmax ${lmax} with a maximum curvature of ${curv} degrees and FA cut-off value of ${cutoff} for seed ROI ${starting} and target ROI ${ending}..."

				tckgen $fod -algorithm iFOD2 -act ${FIVETT}.nii.gz -backtrack -select $NUM_FIBERS -seeds $SEED -angle $curv -cutoff $FA -step $STEP -minlength $MIN_LENGTH -maxlength $MAX_LENGTH wb_iFOD2_lmax${lmax}\_curv${curv}\_cutoff${cutoff}\_start${starting::-4}\_end${ending::-4}.tck -seed_image $starting -include $ending $including $excluding -nthreads $NCORE -quiet
			
			done
		done

	   done
	    
	done
    done
fi

## combine different parameters into 1 output
tckedit wb*.tck track.tck -nthreads $NCORE -quiet

## find the final size
COUNT=`tckinfo track.tck | grep -w 'count' | awk '{print $2}'`
echo "Ensemble tractography generated $COUNT of a requested $TOTAL"

## if count is wrong, say so / fail / clean for fast re-tracking
if [ ! $COUNT -eq $TOTAL ]; then
    echo "Incorrect count. Tractography failed."
    #rm -f wb*.tck
    #rm -f track.tck
else
    echo "Correct count. Tractography complete."
    #rm -f wb*.tck
fi

## simple summary text
tckinfo track.tck > tckinfo.txt

##
## convert outputs to save to nifti
##

## tensor outputs
mrconvert fa.mif -stride 1,2,3,4 fa.nii.gz -nthreads $NCORE -quiet
mrconvert md.mif -stride 1,2,3,4 md.nii.gz -nthreads $NCORE -quiet
mrconvert ad.mif -stride 1,2,3,4 ad.nii.gz -nthreads $NCORE -quiet
mrconvert rd.mif -stride 1,2,3,4 rd.nii.gz -nthreads $NCORE -quiet

## westin shapes (also tensor)
mrconvert cl.mif -stride 1,2,3,4 cl.nii.gz -nthreads $NCORE -quiet
mrconvert cp.mif -stride 1,2,3,4 cp.nii.gz -nthreads $NCORE -quiet
mrconvert cs.mif -stride 1,2,3,4 cs.nii.gz -nthreads $NCORE -quiet

## tensor itself
mrconvert dt.mif -stride 1,2,3,4 tensor.nii.gz -nthreads $NCORE -quiet

## kurtosis, if it exists
if [ -f dk.mif ]; then
    mrconvert dk.mif -stride 1,2,3,4 kurtosis.nii.gz -nthreads $NCORE -quiet
fi

## 5 tissue type visualization
mrconvert ${FIVETT}vis.mif -stride 1,2,3,4 5tt.nii.gz -nthreads $NCORE -quiet

## clean up
rm -rf tmp

## can seed cc ROI extra as well
# tckgen -algorithm iFOD2 -select 10000 -act 5tt.mif -backtrack -crop_at_gmwmi -seed_image cc.mif -grad $grad $FODM cc.tck -nthreads $NCORE -quiet

## curvature is an angle, not a number
## these are interconverted by:
## https://www.nitrc.org/pipermail/mrtrix-discussion/2011-June/000230.html
# angle = 2 * asin (S / (2*R))
# R = curvature
# S = step-size
