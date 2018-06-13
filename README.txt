Scripts
-----------------------------------------------------------------------------------------------
DONE

mrtrix_preproc_fix

	- modification of existing mrtrix_preproc enabling to use images with opposing PE directions for eddy_correction

app-5ttgen

	- wrapper for 5ttgen script from mrtrix, uses either FSL or FREESURFER
	
app-ACA_data_postproc*

	- input: data run through mrtrix_preproc and dtiInit
	- output: files required for tracking with ROI2ROI_tracking script

* to be merged with app-ROI2ROI_track
-----------------------------------------------------------------------------------------------
IN PROGRESS

app-ROI2ROI_track

	- fix to already existing mrtrix ACT tracking
	- will merge app-ACA_data_postprocc with already existing tracking and add it as a fix to app already registered on BL
	- combines postproc and tracking
	- introduces wider choice of parameters and using ROIs in tracking

app-ROI2ROI_count

	- new script
	- segments fibers in given bundle using ROIs exlusion/inclusion
-----------------------------------------------------------------------------------------------
TO BE DONE
  
Results_presentation
  - outputs counts, graphs and tracts profile for given set of 
  



