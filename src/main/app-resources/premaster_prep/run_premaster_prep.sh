#!/bin/bash
mode=$1

export PATH=${_CIOP_APPLICATION_PATH}/master_slc/bin:$PATH

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
ERR_MASTER_SETUP=16
ERR_SLC_AUX_TAR=17
ERR_SLC_AUX_PUBLISH=19
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23
ERR_LOOKS_PRM=39
ERR_CROP_PRM=41

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
	${ERR_LOOKS_PRM}) msg="Couldn't retrieve looks parameter";;
	${ERR_CROP_PRM}) msg="Couldn't retrieve crop parameter";;	
  esac
   
  [ "${retval}" != "0" ] && ciop-log "ERROR" \
  "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}

trap cleanExit EXIT

main() {

  local res
  FIRST="TRUE"
  
  while read scene_ref
  do
 
    [ ${FIRST} == "TRUE" ] && {
      # creates the adore directory structure
      export TMPDIR=$( set_env )
      export RAW=${TMPDIR}/RAW
      export PROCESS=${TMPDIR}/PROCESS
      export SLC=${PROCESS}/SLC
      export VOR_DIR=${TMPDIR}/VOR
      export INS_DIR=${TMPDIR}/INS

      ciop-log "INFO" "creating the directory structure in $TMPDIR"
  
      # which orbits
      orbits="$( get_orbit_flag )"
      [ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}
	  
	  # Looks parameter
	  looks_prm="$( ciop-getparam looks )"
	  [ $? -ne 0 ] && return ${ERR_LOOKS_PRM}
  
	  ciop-log "INFO" "Retrieving preliminary master"
      premaster_ref="$( ciop-getparam master )"
      [ $? -ne 0 ] && return ${ERR_MASTER_REF}

	  premaster=$( get_data ${premaster_ref} ${RAW} ) #for final version
      #premaster=$( get_data ${scene_ref} ${RAW} ) #for final version
      [ $? -ne 0 ] && return ${ERR_MASTER_EMPTY}
  
      ciop-log "INFO" "Get sensing date"
      sensing_date=$( get_sensing_date ${premaster} )
      [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DATE}
  
      mission=$( get_mission ${premaster} | tr "A-Z" "a-z" )
      [ $? -ne 0 ] && return ${ERR_MISSION_MASTER}
      [ ${mission} == "asar" ] && flag="envi"
  
      # TODO manage ERS and ALOS
      # [ ${mission} == "alos" ] && flag="alos"
      # [ ${mission} == "ers" ] && flag="ers"
      # [ ${mission} == "ers_envi" ] && flag="ers_envi"
  
      premaster_folder=${SLC}/${sensing_date}
      mkdir -p ${premaster_folder}
  
      get_aux "${mission}" "${sensing_date}" "${orbits}"
      [ $? -ne 0 ] && return ${ERR_AUX}
	  
	  echo ${looks_prm} > ${SLC}/looks.txt
	  ## echo ${looks_prm} > INSAR_${sensing_date}/looks.txt
  
      cd ${premaster_folder}
      slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
      ciop-log "INFO" "Run ${slc_bin} for ${sensing_date}"
      ln -s ${premaster}   
      ${slc_bin}
      [ $? -ne 0 ] && return ${ERR_SLC}
 
      ## MAS_WIDTH=`grep WIDTH  ${sensing_date}.slc.rsc | awk '{print $2}' `
      ## MAS_LENGTH=`grep FILE_LENGTH  ${sensing_date}.slc.rsc | awk '{print $2}' `
	  
	  MAS_FL="$( ciop-getparam firstline )"
	  [ $? -ne 0 ] && return ${ERR_CROP_PRM}
	  MAS_LL="$( ciop-getparam lastline )"
	  [ $? -ne 0 ] && return ${ERR_CROP_PRM}
	  MAS_FC="$( ciop-getparam firstcol )"
	  [ $? -ne 0 ] && return ${ERR_CROP_PRM}
	  MAS_LC="$( ciop-getparam lastcol )"	  
	  [ $? -ne 0 ] && return ${ERR_CROP_PRM}
	  
	  #MAS_FL=12400
	  #MAS_LL=16950	
	  #MAS_FC=280	
	  #MAS_LC=1640	  

      ciop-log "INFO" "Will run step_master_setup"
	  ciop-log "INFO" "$(pwd)"
	  ## ciop-log "INFO" "$MAS_WIDTH"
	  ## ciop-log "INFO" "$MAS_LENGTH"
	  
	  ciop-log "INFO" "$MAS_FL"
	  ciop-log "INFO" "$MAS_LL"
	  ciop-log "INFO" "$MAS_FC"
	  ciop-log "INFO" "$MAS_LC"
	  
      ## echo "first_l 1" > master_crop.in
      ## echo "last_l $MAS_LENGTH" >> master_crop.in
      ## echo "first_p 1" >> master_crop.in
      ## echo "last_p $MAS_WIDTH" >> master_crop.in
	  
      echo "first_l $MAS_FL" > master_crop.in
      echo "last_l $MAS_LL" >> master_crop.in
      echo "first_p $MAS_FC" >> master_crop.in
      echo "last_p $MAS_LC" >> master_crop.in

	  roiproc='../roi.proc'
	  MPR=$(((($MAS_LC-$MAS_FC) / 2) + (($MAS_LC-$MAS_FC) % 2 > 0) ))
	  MPR=$((MPR + MAS_FC))

	  #echo "use1dopp=1" > $roiproc
	  #echo "mean_pixel_rng=$MPR" >> $roiproc	  	  
      #echo "ymin=$MAS_FL" >> $roiproc
      #echo "ymax=$MAS_LL" >> $roiproc
	  
	  echo "before_z_ext= -9000" > $roiproc
	  echo "after_z_ext= -9000" >> $roiproc
	  echo "near_rng_ext= +300" >> $roiproc
	  echo "far_rng_ext= -4500" >> $roiproc	  
	  	  
      step_master_setup
      [ $? -ne 0 ] && return ${ERR_MASTER_SETUP} 
	  
	  #roiproc=${PROCESS%%/}/INSAR_${sensing_date%%/}/roi.proc
	  
	  #echo "use1dopp=1" > $roiproc
	  #echo "mean_pixel_rng=$MPR" >> $roiproc	  	  
      #echo "ymin=$MAS_FL" >> $roiproc
      #echo "ymax=$MAS_LL" >> $roiproc	  
 
      cd ${PROCESS}
	  echo ${looks_prm} > INSAR_${sensing_date}/looks.txt
      tar cvfz premaster_${sensing_date}.tgz INSAR_${sensing_date}
      [ $? -ne 0 ] && return ${ERR_SLC_TAR}

      premaster_slc_ref="$( ciop-publish -a ${PROCESS}/premaster_${sensing_date}.tgz )"
      [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}
    }

    echo "${premaster_slc_ref},${scene_ref}" | ciop-publish -s
    FIRST="FALSE"
  done

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?
