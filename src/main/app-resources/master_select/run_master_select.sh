#! /bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

## source sar helpers and functions
#set_env

DEM_ROUTINES="${_CIOP_APPLICATION_PATH}/master_select/bin"
PATH=$DEM_ROUTINES:$PATH

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_PREMASTER=5
ERR_INSAR_SLAVES=7
ERR_MASTER_SELECT=9
ERR_MASTER_COPY=11
ERR_MASTER_SLC=12
ERR_MASTER_READ_GEO=13
ERR_DEM=14
ERR_MASTER_TIMING=21
ERR_INSAR_TAR=15
ERR_INSAR_PUBLISH=17
ERR_FINAL_PUBLISH=19
ERR_DEM_TAR=21
ERR_DEM_PUBLISH=23
ERR_MASTER_SLAVE=45

# add a trap to exit gracefully
cleanExit() {
  local retval=$?
  local msg
  msg=""

  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_PREMASTER}) msg="couldn't retrieve ";; 
    ${ERR_INSAR_SLAVES}) msg="couldn't retrieve insar slave folders";;
    ${ERR_INSAR_SLAVES_TAR}) msg="couldn't extract insar slave folders";;
    ${ERR_MASTER_SELECT}) msg="couldn't calculate most suited master image";;
    ${ERR_MASTER_COPY}) msg="couldn't retrieve final master";;
    ${ERR_MASTER_SLC_TAR}) msg="couldn't untar final master SLC";;
    ${ERR_MASTER_READ_GEO}) msg="couldn't run master read geo";;
    ${ERR_DEM}) msg="could not create DEM";;
    ${ERR_MASTER_TIMING}) msg="couldn't run step_master_timing";;
    ${ERR_INSAR_TAR}) msg="couldn't create tgz archive for publishing";;
    ${ERR_INSAR_PUBLISH}) msg="couldn't publish new INSAR_MASTER folder";;
    ${ERR_DEM_TAR}) msg="couldn't create DEM.tgz archive for publishing";;
    ${ERR_DEM_PUBLISH}) msg="couldn't publish the DEM folder";;
	${ERR_FINAL_PUBLISH}) msg="couldn't publish final output";;
    ${ERR_STEP_READ_GEO}) msg="couldn't MAKE READ GEO";;
	${ERR_MASTER_REF}) msg="couldn't retrieve master";;
	${ERR_MASTER_SENSING_DATE}) msg="couldn't retrieve sensing date";;
	${ERR_MASTER_SLAVE}) msg="couldn't retrieve slave";;
	${ERR_raw}) msg="couldn't retrieve raw";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

dem() {
  local dataset_ref=$1
  local target=$2
  local bbox
  local wkt
 
  #wkt="$( ciop-casmeta -f "dct:spatial" "${dataset_ref}" )"
  wkt="$( opensearch-client "${dataset_ref}" wkt | head -1 )"
  ciop-log "INFO" "Printing ${wkt}"
  [ -n "${wkt}" ] && bbox="$( mbr.py "${wkt}" )" || return 1
  ciop-log "INFO" "Printing ${wkt}"
  

  wdir=${PWD}/.wdir
  mkdir ${wdir}
  mkdir -p ${target}

  target=$( cd ${target} && pwd )

  cd ${wdir}
  construct_dem.sh dem ${bbox} SRTM3 || return 1
  
  cp -v ${wdir}/dem/final_dem.dem ${target}
  cp -v ${wdir}/dem/input.doris_dem ${target}
  cp -v ${wdir}/dem/srtm_dem.ps ${target}
  
  sed -i "s#\(SAM_IN_DEM *\).*/\(final_dem.dem\)#\1$target/\2#g" ${target}/input.doris_dem
  cd - &> /dev/null

  rm -fr ${wdir}
  return 0
}

main() {

  local res
  premaster_date=""

  export TMPDIR=$( set_env )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS
  cd ${RAW}
  ciop-log "INFO" "creating the directory structure in $TMPDIR"
  premaster_ref="$( ciop-getparam master )"
  [ $? -ne 0 ] && return ${ERR_MASTER_REF}
  ciop-log "INFO" "Retrieving preliminary master ${premaster_ref}"
  premaster_ref=$( get_data ${premaster_ref} ${RAW} ) #for final version
  [ $? -ne 0 ] && return ${ERR_MASTER_REF}
  bname=$( basename ${premaster_ref} )
  new_name_temp=$(echo $bname | awk {'print substr($bname,1,59)'} )
  ciop-log "INFO" "Name of file: ${new_name_temp}"
  #add the "tar.gz" to the file
  new_name="${new_name_temp}.tar.gz"
  mv ${new_name_temp} ${new_name}
  tar xvzf $new_name
  FIRST="TRUE"
  ciop-log "INFO" "Processing input: ${line}"
  while read line
  do
  
  
    ciop-log "INFO" "Processing input: ${line}"
	ciop-log "INFO" "Temp folder: ${TMPDIR}"
	ciop-log "INFO" "Raw folder: ${RAW}"
	
	
    IFS=',' read -r premaster_slc_ref slc_folders insar_slaves raw_data<<< "${line}"
    ciop-log "DEBUG" "1:${premaster_slc_ref} 2:${slc_folders} 3:${insar_slaves} 4:${raw_data}"	
	
	if [ "${FIRST}" == "TRUE" ];
	then
     ciop-log "INFO" "Retrieving raw data ${raw_data}"
     [ $? -ne 0 ] && return ${ERR_raw}
	 ciop-copy -f -O ${RAW} ${raw_data}
	 mv ${RAW}/RAW/RAW/* ${RAW}/
	 rm -rf ${RAW}/RAW/
	 ${FIRST}="FALSE"
	fi
	

    if [ ! -d ${PROCESS}/INSAR_${premaster_date} ]
    then
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      [ $? -ne 0 ] && return ${ERR_PREMASTER}
      fix_res_path "${PROCESS}"

      premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`   
      ciop-log "INFO" "Pre-Master Date: ${premaster_date}"
    fi
    #change bperp.txt to be print inside the loop
    ciop-log "INFO" "Retrieve folder: ${insar_slaves}">Bperp.txt
    ciop-copy -f -O ${PROCESS}/INSAR_${premaster_date}/ ${insar_slaves}
    [ $? -ne 0 ] && return ${ERR_INSAR_SLAVES}  
    fix_res_path "${PROCESS}/INSAR_${premaster_date}"
  
    echo ${slc_folders} >> ${TMPDIR}/slc_folders.tmp  
  done
  cd $PROCESS/INSAR_${premaster_date}
  #ciop-log "INFO" "Retrieve folder: ${insar_slaves}"> Bperp.txt
  echo ${insar_slaves}
  brep=$(cat Bperp.txt)
  #ciop-log "INFO" "Retrieve folder: $brep"
  master_select > master.date
  [ $? -ne 0 ] && return ${ERR_MASTER_SELECT}
  master_date=`awk 'NR == 12' master.date | awk $'{print $1}'`
  
  ciop-log "INFO" "Choose SLC from ${master_date} as final master"
  master=`grep ${master_date} ${TMPDIR}/slc_folders.tmp`

  ciop-log "INFO" "Retrieve final master SLC from ${master_date}"
  ciop-copy -f -O ${SLC}/ ${master}
  fix_res_path "${SLC}"
  ciop-log "INFO" "Running link_slcs"
  cd ${PROCESS}
  link_slcs ${RAW}
  mkdir ${PROCESS}/INSAR_${master_date}/
  
  cd ${PROCESS}/INSAR_${master_date}/
  cp ${PROCESS}/SLC/${master_date}/* ${PROCESS}/INSAR_${master_date}
  rm -rf INSAR_${premaster_date}
  #cp ${PROCESS}/SLC/
  ciop-log "INFO" "Master date folder... ${PROCESS}/INSAR_${master_date}"
  #
  # get extents
  #MAS_WIDTH=`grep WIDTH ${master_date}.slc.rsc | awk '{print $2}' `
  #MAS_LENGTH=`grep FILE_LENGTH ${master_date}.slc.rsc | awk '{print $2}' `
  
  read_bin="step_read_whole_TSX"
  ciop-log "INFO" "Run ${read_bin} for ${sensing_date}"
  #ln -s ${PROCESS}/INSAR_${master_date}  
  ${read_bin}
  [ $? -ne 0 ] && return ${ERR_READ}
  #echo `ls -l ../` 

  #MAS_WIDTH=`grep WIDTH  ${sensing_date}.slc.rsc | awk '{print $2}' `
  #MAS_LENGTH=`grep FILE_LENGTH  ${sensing_date}.slc.rsc | awk '{print $2}' `

  MAS_WIDTH=`grep WIDTH  image.slc.rsc | awk '{print $2}' `
  MAS_LENGTH=`grep FILE_LENGTH  image.slc.rsc | awk '{print $2}' `

  #set default values for lines(9500) and pixels(8850)
  ciop-log "INFO" "Running step_master_read_geo"

  echo "lon 25.41" > master_crop_geo.in
  echo "lat 36.40" >> master_crop_geo.in
  echo "n_lines 9500" >> master_crop_geo.in
  echo "n_pixels 8850" >> master_crop_geo.in
  cp master_crop_geo.in /tmp/
  cp master_crop_geo.in ../
  step_master_read_geo
  [ $? -ne 0 ] && return ${ERR_MASTER_READ_GEO} 
  cp ${PROCESS}/cropfiles.dorisin ${PROCESS}/INSAR_${master_date}
  cp ${PROCESS}/readfiles.dorisin ${PROCESS}/INSAR_${master_date}
  cp ${PROCESS}/master_readfiles.dorisin ${PROCESS}/INSAR_${master_date}
  cp ${TMPDIR}/INSAR_INSAR_${master_date}/* ${PROCESS}/INSAR_${master_date}
  rm -rf ${TMPDIR}/INSAR_INSAR_${master_date}
  cd ${RAW}
  counter_xml_1=0
  for f in $(find ./ -name "T*.xml"); do
   bname=$( basename ${f} )
   ciop-log "INFO" "filenames: $( basename ${f} )"
   sensing_temp_date=$(echo $bname | awk -F '_' {'print substr($13,1,8)'} )
   list_files[counter_xml]=${sensing_temp_date}
   ciop-log "INFO" "Name of slave image ${sensing_temp_date}"
   ciop-log "INFO" "Name of master image ${master_date}"
   if [ "${sensing_temp_date}" != "${master_date}" ]
   then
	cp -r ${PROCESS}/SLC/${sensing_temp_date} ${PROCESS}/INSAR_${master_date}/
    ciop-log "INFO" "Running step_read_geo"
	cd ${PROCESS}/INSAR_${master_date}/${sensing_temp_date}
	step_read_geo
    [ $? -ne 0 ] && return ${ERR_STEP_READ_GEO}
   fi
   counter_xml=$((${counter_xml}+1))
   cd ${RAW}
  done
  cd ${PROCESS}/INSAR_${master_date}/
  # DEM steps
  # getting the original file url for dem fucntion
  master_ref=`cat $master_date.url`
  ciop-log "INFO" "Prepare DEM with: $master_ref"    
  dem ${master_ref} ${TMPDIR}/DEM
  [ $? -ne 0 ] && return ${ERR_DEM}

  head -n 28 ${STAMPS}/DORIS_SCR/timing.dorisin > ${PROCESS}/INSAR_${master_date}/timing.dorisin
  cat ${TMPDIR}/DEM/input.doris_dem >> ${PROCESS}/INSAR_${master_date}/timing.dorisin  
  tail -n 13 ${STAMPS}/DORIS_SCR/timing.dorisin >> ${PROCESS}/INSAR_${master_date}/timing.dorisin  

  cd ${PROCESS}/INSAR_${master_date}/
  ciop-log "INFO" "Running step_master_timing"    
  step_master_timing
  [ $? -ne 0 ] && return ${ERR_MASTER_TIMING}

  ciop-log "INFO" "Archiving the newly created INSAR_$master_date folder"
  cd ${PROCESS}
  tar cvfz INSAR_${master_date}.tgz INSAR_${master_date}
  [ $? -ne 0 ] && return ${ERR_INSAR_TAR}

  ciop-log "INFO" "Publishing the newly created INSAR_${master_date} folder"
  insar_master=$( ciop-publish -a ${PROCESS}/INSAR_${master_date}.tgz )
  [ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}

  cd ${TMPDIR}
  ciop-log "INFO" "Archiving the DEM folder"
  tar cvfz DEM.tgz DEM
  [ $? -ne 0 ] && return ${ERR_DEM_TAR}

  ciop-log "INFO" "Publishing the DEM folder"
  dem=$( ciop-publish -a ${TMPDIR}/DEM.tgz )
  [ $? -ne 0 ] && return ${ERR_DEM_PUBLISH}
  counter_xml=0
  for slcs in `cat ${TMPDIR}/slc_folders.tmp`
  do
   sensing_temp_date=list_files[counter_xml]
    if [ "${sensing_temp_date}" != "${master_date}" ]
	 then
      ciop-log "INFO" "Will publish the final output ${insar_master},${slcs},${dem}"
	  
      echo "${insar_master},${slcs},${dem}" | ciop-publish -s  
      [ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}

      echo "${insar_master},${slcs},${dem}" >> ${TMPDIR}/output.list
	fi
	counter_xml=$((${counter_xml}+1))
  done
  slc_folders="$( ciop-publish -a ${SLC}/${premaster_date})"
  echo "${insar_master},${slc_folders},${dem}" | ciop-publish -s 
  ciop-log "INFO" "Will publish the final output ${insar_master},${slc_folders},${dem}"
  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?

