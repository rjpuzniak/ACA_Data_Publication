#!/bin/bash

## define number of threads to use
NCORE=12

## input fibre bundle
FIBERS=`jq -r .fibers config.json`

## switch for OC tracts analysis and corresponding ROIs
DO_OC=`jq -r .do_oc config.json`

if [ $DO_OC == true ]; then

	## segmentation ROIs
	SR_ROI=`jq -r .sr_roi config.json`
	SL_ROI=`jq -r .sl_roi config.json`
	ER_ROI=`jq -r .er_roi config.json`
	EL_ROI=`jq -r .el_roi config.json`

	## optional dilation of seed and target ROIs
	DIL=`jq -r .dil config.json`

	## segment streamlines using dilated starting and ending ROIs

	tckedit ${FIBERS}.tck -include $(maskfilter ${SR_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${ER_ROI}.mif dilate -npass $DIL - -quiet) SR_2_ER.tck
	tckedit ${FIBERS}.tck -include $(maskfilter ${SR_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${EL_ROI}.mif dilate -npass $DIL - -quiet) SR_2_EL.tck
	tckedit ${FIBERS}.tck -include $(maskfilter ${SL_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${ER_ROI}.mif dilate -npass $DIL - -quiet) SL_2_ER.tck
	tckedit ${FIBERS}.tck -include $(maskfilter ${SL_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${EL_ROI}.mif dilate -npass $DIL - -quiet) SL_2_EL.tck

	## count streamlines and save numbers to the product.json file
	
	touch product.json
	
	echo "{" >> product.json
	
	echo -n \"right_to_right\":" " >> product.json ; echo \"$(tckstats -output count SR_2_ER.tck -quiet)\"\, >> product.json
	echo -n \"right_to_left\":" " >> product.json ; echo \"$(tckstats -output count SR_2_EL.tck -quiet)\"\, >> product.json
	echo -n \"left_to_right\":" " >> product.json ; echo \"$(tckstats -output count SL_2_ER.tck -quiet)\"\, >> product.json
	echo -n \"left_to_left\":" " >> product.json ; echo \"$(tckstats -output count SL_2_EL.tck -quiet)\" >> product.json
	echo "}" >> product.json

fi


: <<'END'

Region Of Interest processing options

    -include spec specify an inclusion region of interest, as either a binary mask image, or as a sphere using 4 comma-separared values (x,y,z,radius). Streamlines must traverse ALL inclusion regions to be accepted.
    -exclude spec specify an exclusion region of interest, as either a binary mask image, or as a sphere using 4 comma-separared values (x,y,z,radius). Streamlines that enter ANY exclude region will be discarded.
    -mask spec specify a masking region of interest, as either a binary mask image, or as a sphere using 4 comma-separared values (x,y,z,radius). If defined, streamlines exiting the mask will be truncated.

Streamline length threshold options

    -maxlength value set the maximum length of any streamline in mm
    -minlength value set the minimum length of any streamline in mm

Streamline count truncation options

    -number count set the desired number of selected streamlines to be propagated to the output file
    -skip count omit this number of selected streamlines before commencing writing to the output file

Thresholds pertaining to per-streamline weighting

    -maxweight value set the maximum weight of any streamline
    -minweight value set the minimum weight of any streamline

Other options specific to tckedit

    -inverse output the inverse selection of streamlines based on the criteria provided, i.e. only those streamlines that fail at least one criterion will be written to file.
    -ends_only only test the ends of each streamline against the provided include/exclude ROIs

Options for handling streamline weights

    -tck_weights_in path specify a text scalar file containing the streamline weights
    -tck_weights_out path specify the path for an output text scalar file containing streamline weights



##
## parse inputs
##

## raw inputs
DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`
ANAT=`jq -r '.anat' config.json`

## parse potential ensemble / individual lmaxs
ENS_LMAX=`jq -r '.ens_lmax' config.json`
IMAXS=`jq -r '.imaxs' config.json`

## tracking params
CURVS=`jq -r '.curvs' config.json`
NUM_FIBERS=`jq -r '.num_fibers' config.json`
MIN_LENGTH=`jq -r '.min_length' config.json`
MAX_LENGTH=`jq -r '.max_length' config.json`

## models to fit / data sets to make
TENSOR_FIT=`jq -r '.tensor_fit' config.json`

## perform multi-tissue intensity normalization
NORM=`jq -r '.norm' config.json`

## tracking types
DO_PRB2=`jq -r '.do_prb2' config.json`
DO_PRB1=`jq -r '.do_prb1' config.json`
DO_DETR=`jq -r '.do_detr' config.json`
DO_DTDT=`jq -r '.do_dtdt' config.json`
DO_DTPB=`jq -r '.do_dtpb' config.json`

## FACT kept separately
DO_FACT=`jq -r '.do_fact' config.json`
FACT_DIRS=`jq -r '.fact_dirs' config.json`
FACT_FIBS=`jq -r '.fact_fibs' config.json`

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

## create b0 
dwiextract ${difm}.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0.mif -axis 3 -nthreads $NCORE -quiet

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

## if input $IMAXS is empty, set to $MAXLMAX
if [ -z $IMAXS ]; then
    echo "No Lmax values requested."
    echo "Using the maximum Lmax of $MAXLMAX by default."
    IMAXS=$MAXLMAX
fi

## check if more than 1 lmax passed
NMAX=`echo $IMAXS | wc -w`

## find max of the requested list
if [ $NMAX -gt 1 ]; then

    ## pick the highest
    MMAXS=`echo -n "$IMAXS" | tr " " "\n" | sort -nr | head -n1`
    echo "User requested Lmax(s) up to: $MMAXS"
    LMAXS=$IMAXS

else

    ## take the input
    MMAXS=$IMAXS
	
fi

## make sure requested Lmax is possible - fix if not
if [ $MMAXS -gt $MAXLMAX ]; then
    
    echo "Requested maximum Lmax of $MMAXS is too high for this data, which supports Lmax $MAXLMAX."
    echo "Setting maximum Lmax to maximum allowed by the data: Lmax $MAXLMAX."
    MMAXS=$MAXLMAX

fi

## create the list of the ensemble lmax values
if [[ $ENS_LMAX == 'true' && $NMAX -eq 1 ]]; then
    
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
    LMAXS=$IMAXS

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
	    TOTAL=$(($TOTAL+$NUM_FIBERS))
	done
    done
fi

if [ $DO_PRB1 == "true" ]; then
    for lmax in $LMAXS; do
	for curv in $CURVS; do
	    TOTAL=$(($TOTAL+$NUM_FIBERS))
	done
    done
fi

if [ $DO_DETR == "true" ]; then
    for lmax in $LMAXS; do
	for curv in $CURVS; do
	    TOTAL=$(($TOTAL+$NUM_FIBERS))
	done
    done
fi

if [ $DO_FACT == "true" ]; then
    for lmax in $LMAXS; do
	TOTAL=$(($TOTAL+$FACT_FIBS))
    done
fi

if [ $DO_DTDT == "true" ]; then
    for curv in $CURVS; do
	TOTAL=$(($TOTAL+$NUM_FIBERS))
    done
fi

if [ $DO_DTPB == "true" ]; then
    for curv in $CURVS; do
	TOTAL=$(($TOTAL+$NUM_FIBERS))
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

echo "Creating 5-Tissue-Type (5TT) tracking mask..."

## convert anatomy 
5ttgen fsl ${anat}.mif 5tt.mif -nocrop -sgm_amyg_hipp -tempdir ./tmp -nthreads $NCORE -quiet

## generate gm-wm interface seed mask
5tt2gmwmi 5tt.mif gmwmi_seed.mif -nthreads $NCORE -quiet

## create visualization output
5tt2vis 5tt.mif 5ttvis.mif -nthreads $NCORE -quiet

if [ $MS -eq 0 ]; then

    echo "Estimating CSD response function..."
    dwi2response tournier ${difm}.mif response.txt -lmax $MAXLMAX -nthreads $NCORE -tempdir ./tmp -quiet
    
else

    echo "Estimating MSMT CSD response function..."
    dwi2response msmt_5tt ${difm}.mif 5tt.mif wmt.txt gmt.txt csf.txt -mask ${mask}.mif -lmax $RMAX -tempdir ./tmp -nthreads $NCORE -quiet

fi

## fit the CSD across requested lmax's
if [ $MS -eq 0 ]; then

    for lmax in $LMAXS; do

	echo "Fitting CSD FOD of Lmax ${lmax}..."
	dwi2fod -mask ${mask}.mif csd ${difm}.mif response.txt csd_lmax${lmax}.mif -lmax $lmax -nthreads $NCORE -quiet

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

	    echo "Tracking iFOD2 streamlines at Lmax ${lmax} with a maximum curvature of ${curv} degrees..."
	    tckgen $fod -algorithm iFOD2 \
		   -select $NUM_FIBERS -act 5tt.mif -backtrack -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
		   -angle ${curv} -minlength $MIN_LENGTH -maxlength $MAX_LENGTH \
		   wb_iFOD2_lmax${lmax}_curv${curv}.tck -nthreads $NCORE -quiet
	    
	done
    done
fi

if [ $DO_PRB1 == "true" ]; then

    ## MRTrix 0.2.12 probabilistic
    echo "Tracking iFOD1 streamlines..."
    
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

	    echo "Tracking iFOD1 streamlines at Lmax ${lmax} with a maximum curvature of ${curv} degrees..."
	    tckgen $fod -algorithm iFOD1 \
		   -select $NUM_FIBERS -act 5tt.mif -backtrack -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
		   -angle ${curv} -minlength $MIN_LENGTH -maxlength $MAX_LENGTH \
		   wb_iFOD1_lmax${lmax}_curv${curv}.tck -nthreads $NCORE -quiet
	    
	done
    done
fi

if [ $DO_DETR == "true" ]; then

    ## MRTrix 0.2.12 deterministic
    echo "Tracking SD_STREAM streamlines..."
    
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

	    echo "Tracking SD_STREAM streamlines at Lmax ${lmax} with a maximum curvature of ${curv} degrees..."
	    tckgen $fod -algorithm SD_STREAM \
		   -select $NUM_FIBERS -act 5tt.mif -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
		   -angle ${curv} -minlength $MIN_LENGTH -maxlength $MAX_LENGTH \
		   wb_SD_STREAM_lmax${lmax}_curv${curv}.tck -nthreads $NCORE -quiet
	    
	done
    done
fi

if [ $DO_FACT == "true" ]; then

    echo "Tracking FACT streamlines..."

    ## create vector to pass for FACT tracking
    #tensor2metric -vector vector.mif -mask ${mask.mif} dt.mif
    ## this would override variation of Lmax (sh2peaks) below

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
	    
	echo "Extracting $FACT_DIRS peaks from FOD Lmax $lmax for FACT tractography..."
	pks=peaks_lmax$lmax.mif
	sh2peaks $fod $pks -num $FACT_DIRS -nthread $NCORE -quiet

	echo "Tracking FACT streamlines at Lmax ${lmax} using ${FACT_DIRS} maximum directions..."
	tckgen $pks -algorithm FACT -select $FACT_FIBS -act 5tt.mif -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
	       -minlength $MIN_LENGTH -maxlength $MAX_LENGTH wb_FACT_lmax${lmax}.tck -nthreads $NCORE -quiet
	
    done

fi

if [ $DO_DTDT == "true" ]; then

    echo "Tracking deterministic tensor streamlines..."
    
    for curv in $CURVS; do

	echo "Tracking deterministic tensor streamlines with a maximum curvature of ${curv} degrees..."
	tckgen ${difm}.mif -algorithm Tensor_Det \
	       -select $NUM_FIBERS -act 5tt.mif -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
	       -angle ${curv} -minlength $MIN_LENGTH -maxlength $MAX_LENGTH \
	       wb_Tensor_Det_curv${curv}.tck -nthreads $NCORE -quiet
	
    done

fi

if [ $DO_DTPB == "true" ]; then

    echo "Tracking probabilistic tensor streamlines..."
    
    for curv in $CURVS; do

	echo "Tracking probabilistic tensor streamlines at with a maximum curvature of ${curv} degrees..."
	tckgen ${difm}.mif -algorithm Tensor_Prob \
	       -select $NUM_FIBERS -act 5tt.mif -crop_at_gmwmi -seed_gmwmi gmwmi_seed.mif \
	       -angle ${curv} -minlength $MIN_LENGTH -maxlength $MAX_LENGTH \
	       wb_Tensor_Prob_curv${curv}.tck -nthreads $NCORE -quiet
	    
    done

fi

## combine different parameters into 1 output
tckedit wb*.tck track.tck -nthreads $NCORE -quiet

## find the final size
COUNT=`tckinfo track.tck | grep -w 'count' | awk '{print $2}'`
echo "Ensemble tractography generated $COUNT of a requested $TOTAL"

## if count is wrong, say so / fail / clean for fast re-tracking
if [ $COUNT -ne $TOTAL ]; then
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
mrconvert 5ttvis.mif -stride 1,2,3,4 5tt.nii.gz -nthreads $NCORE -quiet

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


END
