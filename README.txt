Scripts used @ OVGU for preprocessing and analysis of ACA (albinism, control, achiasma) data set.


app-ROI2ROI_track fits CSD model to input DWI data and performs tracking based on ROIs provided by user. Tracking is employing following tools and methods: Anatomically Constrained Tractography (ACT), Ensemble Tractography (ET) and iFOD2 tracking algorithm. Although script was designed primarily to perform optimal tracking in Optic Chiasm, the script can be used for any set of starting/ending/exclusion/inclusion ROIs.

app-segment-track accepts a single file containing streamlines and segments them basing on user-provided parameters and/or ROIs

app-ROI2ROI_count_and_present is an app providing visualisation of results of ACA data set analysis

irrelevant/ contains outdated/not working/trash code

slightly_irrelevant/ contains working code already incorporated in BL from different repos
