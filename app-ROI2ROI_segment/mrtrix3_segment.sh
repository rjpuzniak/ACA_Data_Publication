#!/bin/bash

## define number of threads to use
NCORE=12

## input fibre bundle
LIST_OF_FIBERS=`jq -r .fibers config.json`

## switches - app will either: (1) merge all input .tck files, (2) perform segmentation specific to Optic Chiasm or (3) apply all defined segmentation criteria to all input .tck files and output single file
## (1) switch for merging tracts
DO_MERGE=`jq -r .do_merge config.json`
## (2) switch for OC tracts analysis and corresponding ROIs
DO_OC=`jq -r .do_oc config.json`
## (3) switch for .tck file editing
DO_EDIT=`jq -r .do_edit config.json`

## make sure .tck files are properly named

FIBERS=""
for a in $LIST_OF_FIBERS; do
	FIBERS+=${a}.tck" "
done

if [ $DO_MERGE == true ]; then

	tckedit $FIBERS merged_output.tck

elif [ $DO_OC == true ]; then

	## segmentation ROIs
	SR_ROI=`jq -r .sr_roi config.json`
	SL_ROI=`jq -r .sl_roi config.json`
	ER_ROI=`jq -r .er_roi config.json`
	EL_ROI=`jq -r .el_roi config.json`

	## optional dilation of seed and target ROIs
	DIL=`jq -r .dil config.json`

	## segment streamlines using dilated starting and ending ROIs

	tckedit ${FIBERS} -include $(maskfilter ${SR_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${ER_ROI}.mif dilate -npass $DIL - -quiet) SR_2_ER.tck
	tckedit ${FIBERS} -include $(maskfilter ${SR_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${EL_ROI}.mif dilate -npass $DIL - -quiet) SR_2_EL.tck
	tckedit ${FIBERS} -include $(maskfilter ${SL_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${ER_ROI}.mif dilate -npass $DIL - -quiet) SL_2_ER.tck
	tckedit ${FIBERS} -include $(maskfilter ${SL_ROI}.mif dilate -npass $DIL - -quiet) -include $(maskfilter ${EL_ROI}.mif dilate -npass $DIL - -quiet) SL_2_EL.tck

	## count streamlines and save numbers to the product.json file
	
	touch product.json
	
	echo "{" >> product.json
	
	echo -n \"right_to_right\":" " >> product.json ; echo \"$(tckstats -output count SR_2_ER.tck -quiet)\"\, >> product.json
	echo -n \"right_to_left\":" " >> product.json ; echo \"$(tckstats -output count SR_2_EL.tck -quiet)\"\, >> product.json
	echo -n \"left_to_right\":" " >> product.json ; echo \"$(tckstats -output count SL_2_ER.tck -quiet)\"\, >> product.json
	echo -n \"left_to_left\":" " >> product.json ; echo \"$(tckstats -output count SL_2_EL.tck -quiet)\" >> product.json
	echo "}" >> product.json

else
	## (3) apply all defined criteria to all input .tck files and output single .tck file containing all streamlines fulfilling defined conditions
	## parameters 

	INCL_ROI=`jq -r .incl_roi config.json`
	EXCL_ROI=`jq -r .excl_roi config.json`
	MASK=`jq -r .mask config.json`

	MAX_LENGTH=`jq -r .max_length config.json`
	MIN_LENGTH=`jq -r .min_length config.json`

	NUMBER=`jq -r .number config.json`
	SKIP=`jq -r .skip config.json`

	INVERSE=`jq -r .inverse config.json`
	ENDS_ONLY=`jq -r .ends_only config.json`

	## creating list of inlusion ROIs
	inclusion=""
	for i in ${INCL_ROI}; do
		inclusion+=-include" "$i".mif ";
	done

	## creating list of exclusion ROIs
	exclusion=""
	for j in ${EXCL_ROI}; do
		exclusion+=-exclude" "$j".mif ";
	done

	## creating lisk of masks
	masking=""
	for k in ${MASK}; do
		masking+=-mask" "$k".mif ";
	done

	## creating command which will include all the options
	command=""

	if [ ! -z $MAX_LENGTH ]; then
		command+=-maxlength" "$MAX_LENGTH" ";
	fi

	if [ ! -z $MIN_LENGTH ]; then
		command+=-minlength" "$MIN_LENGTH" ";
	fi

	if [ ! -z $NUMBER ]; then
		command+=-number" "$NUMBER" ";
	fi

	if [ ! -z $SKIP ]; then
		command+=-skip" "$SKIP" ";
	fi

	if [ $INVERSE == true ]; then
		command+=-inverse" ";
	fi

	if [ $ENDS_ONLY == true ]; then
		command+=-ends_only" ";
	fi

	tckedit ${FIBERS} $inclusion $exclusion $mask $command edited_output.tck

fi
