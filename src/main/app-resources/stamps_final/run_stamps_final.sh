#! /bin/bash
mode=$1
#set -x 

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# source sar helpers and functions
set_env

MCR="/usr/local/MATLAB/MATLAB_Compiler_Runtime/v717"

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_MASTER_RETRIEVE=7
ERR_DEM_RETRIEVE=9
ERR_INSAR_SLAVE_RETRIEVE=11
ERR_STEP_GEO=13
ERR_MT_PREP=15
ERR_STAMPS_1=17
ERR_INSAR_TAR=19
ERR_INSAR_PUBLISH=21
ERR_PATCH_TAR=23
ERR_PATCH_PUBLISH=25
ERR_FINAL_PUBLISH=27

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_MASTER_RETRIEVE}) msg="Failed to retrieve Master folder";;
${ERR_STAMPS_5}
${ERR_STAMPS_6}
${ERR_STAMPS_7}
${ERR_STAMPS_8}
${ERR_EXPORT}
${ERR_STAMPS_6}

${ERR_DEM_RETRIEVE}) msg="Failed to retrieve DEM folder";;
${ERR_INSAR_SLAVE_RETRIEVE}) msg="Failed to tar Insar Slave folder";;
${ERR_STEP_GEO}) msg="Failed to geoference the image stack";; 
${ERR_MT_PREP}) msg="Failed to run mt_prep routine";;
${ERR_STAMPS_1}) msg="Failed to process step 1 of StaMPS";;
${ERR_INSAR_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_INSAR_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_PATCH_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_PATCH_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_FINAL_PUBLISH}) msg="Failed to publish all output together";;
esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
#[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ -n "${TMPDIR}" ] && chmod -R 777 $TMPDIR
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

main() {
local res
#	master_date=""

[ ${first} == "TRUE" ] && {

while read line; do     

	ciop-log "INFO" "Retrieving Master folder"
	ciop-copy -O ${PROCESS} ${line}
	[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}

	master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
	ciop-log "INFO" "Final Master Date: $master_date"
	
	
	cd ${PROCESS}/INSAR_${master_date}
	ciop-log "INFO" "StaMPS step 5: Phase Correction"
	/opt/StaMPS_v3.3b1/matlab/stamps $MCR 5 5
	[ $? -ne 0 ] && return ${ERR_STAMPS_5}

	ciop-log "INFO" "StaMPS step 6: PS unwrapping"
	/opt/StaMPS_v3.3b1/matlab/stamps $MCR 6 6
	[ $? -ne 0 ] && return ${ERR_STAMPS_6}

	ciop-log "INFO" "StaMPS step 7: Estimation of SCLA"
	/opt/StaMPS_v3.3b1/matlab/stamps $MCR 7 7
	[ $? -ne 0 ] && return ${ERR_STAMPS_7}

	ciop-log "INFO" "StaMPS step 8: Spatio-temporal Filtering"
	/opt/StaMPS_v3.3b1/matlab/stamps $MCR 8 8
	[ $? -ne 0 ] && return ${ERR_STAMPS_8}


	cd ${PROCESS}
	ciop-log "INFO" "creating tar for InSAR Master folder"
	tar cvfz ${PROCESS}/STAMPS_FILES_${master_date}.tgz  INSAR_${master_date}
	[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

	ciop-log "INFO" "creating tar InSAR Master folder for final export"
	ciop-publish ${PROCESS}/STAMPS_FILES_${master_date}.tgz
	[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}
	

	cd ${PROCESS}/INSAR_${master_date}
	ciop-log "INFO" "StaMPS export for GIS layers"
	/opt/StaMPS_v3.3b1/matlab/export_L0_V_DOS $MCR
	[ $? -ne 0 ] && return ${ERR_EXPORT}
	
	# Stamps Mode of Velocity
	SUF_VEL=V-DOS
	# Stamps Mode of Std.dev.
	SUF_STD=VS-DO

	# export folder wth csv
	SOURCE=${PROCESS}/INSAR_${master_date}/export

	# output folder for GIS layers
	GIS_RESULTS=$PROCESS/INSAR_${master_date}/GIS-RESULTS
	mkdir -p $GIS_RESULTS

	# Output Resolution in degree
	RESOL=0.001

	# write shapefile/tif in result folder script
	ogr2ogr -overwrite -f "ESRI Shapefile" $GIS_RESULTS/$SUF_VEL.shp $SOURCE/$SUF_VEL.vrt
	gdal_rasterize -a VEL -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/$SUF_VEL.tif
	gdal_rasterize -a V_STDEV -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/$SUF_STD.tif
	gdal_rasterize -a COH -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/Coherence.tif

	ciop-log "INFO" "creating tar for GIS result layers"
	tar cvfz GIS_${master_date}.tgz  GIS-RESULTS
	[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

	ciop-log "INFO" "publishing GIS result layers"
	ciop-publish ${PROCESS}/STAMPS_FILES_${master_date}.tgz
	[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}

 done