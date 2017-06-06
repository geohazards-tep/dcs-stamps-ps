#! /bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh
export PATH=/opt/anaconda/bin:$PATH
export PATH=/home/_andreas_noa/doris4-0-4/bin:$PATH
# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# source sar helpers and functions
#set_env

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_SCENE=3
ERR_ORBIT_FLAG=5
ERR_SENSING_DATE=9
ERR_MISSION=11
ERR_AUX=13
ERR_LINK_RAW=15
ERR_SLC=17
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23
ERR_MASTER=29
ERR_MASTER_REF=31
ERR_SENSING_DATE_MASTER=33
ERR_STEP_ORBIT=25
ERR_STEP_COARSE=27
ERR_INSAR_TAR=35
ERR_INSAR_PUBLISH=37

# add a trap to exit gracefully
cleanExit() {
  local retval=$?
  local msg
  msg=""
  
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_SCENE}) msg="Failed to retrieve scene";;
    ${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit file format to use";;
    ${ERR_SENSING_DATE}) msg="Couldn't retrieve scene sensing date";;
    ${ERR_MISSION}) msg="Couldn't determine the satellite mission for the scene";;
    ${ERR_AUX}) msg="Couldn't retrieve auxiliary files";;
    ${ERR_LINK_RAW}) msg="Failed to link the raw data to SLC folder";;
    ${ERR_SLC}) msg="Failed to focalize raw data with ROI-PAC";;
    ${ERR_SLC_TAR}) msg="Failed to create archive with scene";;
    ${ERR_SLC_PUBLISH}) msg="Failed to publish archive with slc";;
    ${ERR_MASTER}) msg="Failed to retrieve master";;
    ${ERR_MASTER_REF}) msg="Failed to get the reference master";;
    ${ERR_SENSING_DATE_MASTER}) msg"Failed ot get Master DAte";;
    ${ERR_STEP_ORBIT}) msg="Failed to process step_orbit";;
    ${ERR_STEP_COARSE}) msg="Failed to process step_coarse";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

#--------------------------------
#       3) Main Function        
#--------------------------------
main() {

  local res

  first=TRUE
  premaster_date=""
  export TMPDIR=$( set_env $_WF_ID )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS  
  ciop-log "INFO" "creating the directory structure in $TMPDIR"
      premaster_cat="$( ciop-getparam master )"
      [ $? -ne 0 ] && return ${ERR_MASTER_REF}
  # download data into $RAW
  #counter_xml_1=0
  while read line
  #for filename in *.tar.gz
  do
    #mkdir -p ${RAW}
    ciop-log "INFO" "Processing input: ${line}"
    IFS=',' read -r premaster_slc_ref scene_ref <<< "${line}"
    
    ciop-log "DEBUG" "1:${premaster_slc_ref} 2:${scene_ref}"
    ciop-log "DEBUG" "1:${premaster_slc_ref} 2:${scene_ref} PROCESSING FILES"
    #if it's the first scene we have to download and setup the master as well
    [ "${first}" == "TRUE" ] && {
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      fix_res_path "${PROCESS}"
      #first="FALSE"
    }
    cd ${RAW}
    scene=$( get_data ${scene_ref} ${RAW} ) 
    #scene=$( ciop-copy -f -O ${RAW} $( echo ${scene_ref} | tr -d "\t")  )
    [ $? -ne 0 ] && return ${ERR_SCENE}
    fix_res_path "$RAW"
    ciop-log "INFO" "Processing scene: ${scene}"
    
	#ciop-log "INFO" "Get sensing date"
    #sensing_date=$( get_sensing_date ${scene} )
    #[ $? -ne 0 ] && return ${ERR_SENSING_DATE}
	bname=$( basename ${scene} )
	sensing_date=$(echo $bname | awk {'print substr($bname,28,8)'} )
	new_name_temp=$(echo $bname | awk {'print substr($bname,1,59)'} )
	ciop-log "INFO" "Name of file: ${new_name_temp}"
	#add the "tar.gz" to the file
	new_name="${new_name_temp}.tar.gz"
	mv ${new_name_temp} ${new_name}
	mkdir ${new_name_temp}
	cd ${new_name_temp}
	tar xvzf ${RAW}/$new_name
    
	ciop-log "INFO" "Name of file: ${new_name}"
    ciop-log "INFO" "Sensing date: ${sensing_date}"
    cp ${new_name} ${new_name_temp} 
	
    ciop-log "INFO" "Running link_slcs"
    cd ${PROCESS}
    link_slcs ${RAW}
    #sensing_date=${list[${counter_xml_1}]}
	ciop-log "INFO" "Processing input: ${sensing_date}"
    ciop-log "INFO" "Preparing step_read_geo"   
    scene_folder=${SLC}/${sensing_date}
    ciop-log "INFO" "Scene folder... ${scene_folder}"
    premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`
    ciop-log "INFO" "Premaster_date ${premaster_date}"
    [ ! -d "${PROCESS}/INSAR_${premaster_date}" ] && ciop-log "DEBUG" "${PROCESS}/INSAR_${premaster_date} does not exist" || ciop-log "DEBUG" "${PROCESS}/INSAR_${premaster_date} exists"
    if [ ! -d "${PROCESS}/INSAR_${premaster_date}" ]
    then
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      [ $? -ne 0 ] && return ${ERR_MASTER}
      fix_res_path "${PROCESS}"
    
      premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`
      [ $? -ne 0 ] && return ${ERR_SENSING_DATE_MASTER}
      ciop-log "INFO" "Pre-Master Date: ${premaster_date}"
    fi
    set -x
    cd ${scene_folder}
    cp ${PROCESS}/INSAR_${premaster_date}/cropfiles.dorisin ../ 
    cp ${PROCESS}/INSAR_${premaster_date}/readfiles.dorisin ../
    #slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
    slc_bin="step_read_geo"
    ciop-log "INFO" "Run ${slc_bin} for ${sensing_date}"
    ${slc_bin}
    [ $? -ne 0 ] && return ${ERR_SLC}
    
    # writing original image url for node master_select (need for newly master)
    echo ${scene_ref} > ${sensing_date}.url  
	cd ${PROCESS}/INSAR_${premaster_date}/
	echo ${premaster_cat} > ${premaster_date}.url  
	cp ${premaster_date}.url ${scene_folder}/
    ciop-log "INFO" "Sensing Date URL: ${sensing_date}.url"
	ciop-log "INFO" "Master Date URL: ${premaster_date}.url"
    # publish for next node
    cd ${SLC}
    ciop-log "INFO" "create tar"
    tar cvfz ${sensing_date}.tgz ${sensing_date}
    [ $? -ne 0 ] && return ${ERR_SLC_TAR}
    
    ciop-log "INFO" "Publishing -a"
    slc_folders="$( ciop-publish -a ${SLC}/${sensing_date})"
    [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}
	#
    ciop-log "INFO" "Sensing date before if: $sensing_date vs ${premaster_date}"
    
    if [ "${sensing_date}" != "${premaster_date}" ]
    
    then
      cd ${PROCESS}/INSAR_${premaster_date}
      mkdir ${sensing_date}
      cd ${sensing_date}
     # mkdir SLC/
      cp  ${PROCESS}/INSAR_${premaster_date}/master.res ${PROCESS}/INSAR_${premaster_date}/${sensing_date}/master.res
      
      cp  ${PROCESS}/SLC/${sensing_date}/slave.res ${PROCESS}/INSAR_${premaster_date}/${sensing_date}/slave.res
      cp  ${PROCESS}/SLC/${sensing_date}/slave.res ${PROCESS}/INSAR_${premaster_date}/slave.res
    
      ciop-log "INFO" "doing image coarse correlation for ${sensing_date}"
      step_coarse
      [ $? -ne 0 ] && return ${ERR_STEP_COARSE}
    
      cd ../
    
      ciop-log "INFO" "create tar"
      tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}
      [ $? -ne 0 ] && return ${ERR_INSAR_TAR}
    
      ciop-log "INFO" "Publish -a insar_slaves"
      #rm -rf ${PROCESS}/INSAR_${premaster_date}/${sensing_date}/slave.res
      #change the below line from INSAR_${sensing_date}.tgz to  INSAR_${premaster_date}.tgz
      insar_slaves="$( ciop-publish -a ${PROCESS}/INSAR_${premaster_date}/INSAR_${sensing_date}.tgz )"
      ciop-log "INFO" "Publish $insar_slaves"
      
    else
      insar_slaves=""
    fi 
    raw_data="$( ciop-publish -a ${RAW}/${new_name_temp})"
    ciop-log "INFO" "Publish -s"
    echo "${premaster_slc_ref},${slc_folders},${insar_slaves},${raw_data}" | ciop-publish -s
	rm -rf ${RAW}/*
	#rm -rf ${scene}
    #counter_xml_1=$((${counter_xml_1}+1))
    cd -
  done
  
  ciop-log "INFO" "removing RAW folder"
  #rm -rf ${TMPDIR}
}

cat | main
exit $?

