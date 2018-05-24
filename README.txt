Scripts

01_fix_to_mrtrix_preproc

	- enables to use full dwipreproc script features (correction of images with pair )
	- requires new flag: type of phase-encoding design
	- optional argument: pair(s) of images with different PE directions


app_5ttgen

	- wrapper for 5ttgen script from mrtrix

Preprocessing
  - requires modification of brents script, apart from that we are good
  
ACPC_registration
  - also uses existing function
  
Postprocessing_mrtrix
  - new function, requires ACPC output
  
5TT_gen
  - new function
  
Tracking_mrtrix_ROIs
  - new function, requires ROIs
  - optionally returns count
  
Results_presentation
  - only for publication purposes
  
  
*
mrtrix_preprocessing solved
ROIs handling required
  
  

ACPC registration
Postprocessing
Tracking




Files

Raw -Preprocessing-> Preprocessed

