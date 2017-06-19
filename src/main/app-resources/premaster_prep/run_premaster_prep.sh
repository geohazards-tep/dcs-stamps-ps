#!/bin/bash
mode=$1

export PATH=${_CIOP_APPLICATION_PATH}/master_slc/bin:$PATH

export MANPATH=/opt/libxml2/share/man/:$MANPATH

export PATH=/opt/libxml2/bin/:$PATH
export PATH=/opt/anaconda/bin:$PATH
export PATH=/home/gep-noa/doris4.04/bin:$PATH

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# define the exit codes
SUCCESS=0
ERR_ORBIT_FLAG=5
ERR_MASTER_EMPTY=7
ERR_MASTER_SENSING_DATE=9
ERR_MISSION_MASTER=11 
ERR_AUX=13
ERR_SLC=15 
ERR_READ=14
ERR_MASTER_SETUP=16
ERR_SLC_AUX_TAR=17
ERR_SLC_AUX_PUBLISH=19
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23

# add a trap to exit gracefully
function cleanExit() {
  local retval=$?
  local msg

  msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit files to use";;
    ${ERR_MASTER_EMPTY}) msg="Couldn't retrieve master";;
    ${ERR_MASTER_SENSING_DATE}) msg="Couldn't retrieve master sensing date";;
    ${ERR_MISSION_MASTER}) msg="Couldn't determine master mission";;
    ${ERR_AUX}) msg="Couldn't retrieve auxiliary files";;
    ${ERR_SLC}) msg="Failed to process slc";;
    ${ERR_SLC_AUX_TAR}) msg="Failed to create archive with master ROI_PAC aux files";;
    ${ERR_SLC_AUX_PUBLISH}) msg="Failed to publish archive with master ROI_PAC aux files";;
    ${ERR_SLC_TAR}) msg="Failed to create archive with master slc";;
    ${ERR_SLC_PUBLISH}) msg="Failed to publish archive with master slc";;
    ${ERR_READ}) msg="Error reading the whole TSX";;
  esac
   
  [ "${retval}" != "0" ] && ciop-log "ERROR" \
  "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}

trap cleanExit EXIT


	  
main() {
set -x
  local res
  FIRST="TRUE"

  export TMPDIR=$( set_env $_WF_ID )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS
  cd ${RAW}
      premaster_cat="$( ciop-getparam master )"
      [ $? -ne 0 ] && return ${ERR_MASTER_REF}
      ciop-log "INFO" "Retrieving preliminary master"
	  ciop-log "INFO" "Get ${premaster_ref}"
      premaster_ref=$( get_data ${premaster_cat} ${RAW} ) #for final version
	  ciop-copy -f -O ${RAW} ${premaster_cat}
	  [ $? -ne 0 ] && return ${ERR_MASTER_REF}
	  ciop-log "INFO" "Get sensing date"
     # premaster_ref_date=$( get_sensing_date ${premaster_ref} )
      premaster_ref_date=$( opensearch-client ${premaster_cat} startdate | cut -d'T' -f1 | sed 's/-//g')
	  ciop-log "INFO" "Get ${premaster_ref}"
      [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DATE}
	  bname=$( basename ${premaster_ref} )
	  new_name_temp=$(echo $bname | awk {'print substr($bname,1,59)'} )
	  ciop-log "INFO" "Name of file: ${new_name_temp}"
	  #add the "tar.gz" to the file
	  new_name="${new_name_temp}.tar.gz"
	  mv ${new_name_temp} ${new_name}
	  mkdir ${new_name_temp}
	  cd ${new_name_temp}
	  tar xvzf ${RAW}/$new_name
	  cd ${PROCESS}
	  ciop-log "INFO" "Linking SLCs ${RAW}/${new_name_temp}/ "
	  link_slcs ${RAW}
	  premaster_folder=${SLC}/${premaster_ref_date}
      cd ${premaster_folder}
      read_bin="step_read_whole_CSK"
      ciop-log "INFO" "Run ${read_bin} for ${premaster_ref_date}"
      ln -s ${premaster}   
      ${read_bin}
      [ $? -ne 0 ] && return ${ERR_READ}
	  
      ciop-log "INFO" "Will run step_master_read_geo"
      echo "lon 25.41" > master_crop_geo.in
      echo "lat 36.40" >> master_crop_geo.in
      echo "n_lines 9500" >> master_crop_geo.in
      echo "n_pixels 8850" >> master_crop_geo.in
      cp master_crop_geo.in /tmp/
      cp master_crop_geo.in ../  
      step_master_read_geo
	  cp ../cropfiles.dorisin ${PROCESS}/INSAR_${premaster_ref_date}
      cp ../readfiles.dorisin ${PROCESS}/INSAR_${premaster_ref_date}
      cd ${PROCESS}
	  rm -rf ${RAW}/*
      tar cvfz premaster_${premaster_ref_date}.tgz INSAR_${premaster_ref_date} 
      [ $? -ne 0 ] && return ${ERR_SLC_TAR}
	  
	  premaster_slc_ref="$( ciop-publish -a ${PROCESS}/premaster_${premaster_ref_date}.tgz )"
      [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}

  ciop-log "INFO" "creating the directory structure in $TMPDIR"
  while read scene_ref
  do
      ciop-log "INFO" "Retrieving preliminary master"
	  ciop-log "INFO" "Retrieving ${scene_ref}"
      premaster=$( get_data ${scene_ref} ${RAW} ) #for final version
      [ $? -ne 0 ] && return ${ERR_MASTER_EMPTY}
      ciop-log "INFO" "Retrieving preliminary master ${scene_ref}"
        cd ${RAW}
    	  bname=$( basename ${premaster} )
          sensing_date=$(echo $bname | awk {'print substr($bname,28,8)'} )
		  new_name_temp=$(echo $bname | awk {'print substr($bname,1,59)'} )
	      ciop-log "INFO" "Name of file: ${new_name_temp}"
		  #add the "tar.gz" to the file
		  new_name="${new_name_temp}.tar.gz"
		  mv ${new_name_temp} ${new_name}
		  mkdir ${new_name_temp}
	      cd ${new_name_temp}
	      tar xvzf ${RAW}/$new_name
	      rm ${RAW}/$new_name
		  ciop-log "INFO" "Name of file: ${new_name}"
        cd ${PROCESS}
        link_slcs ${RAW}
	  ciop-log "INFO" "Linkinng SLCs in ${RAW}"
      cd ${SLC}/${sensing_date}
      read_bin="step_read_whole_CSK"
      ciop-log "INFO" "Run ${read_bin} for ${sensing_date}"
      #ln -s ${premaster}  
      ${read_bin}
      [ $? -ne 0 ] && return ${ERR_READ}
	  ciop-log "INFO" "Publishing ${premaster_slc_ref},${scene_ref} files for next node"
	  echo "${premaster_slc_ref},${scene_ref}" | ciop-publish -s
  done
     ciop-log "INFO" "removing temporary files $TMPDIR"
     rm -rf ${TMPDIR}
 
}
cat | main
exit $?

