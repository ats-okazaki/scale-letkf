#!/bin/bash
#===============================================================================
#
#  Steps of 'fcst.sh'
#  October 2014, created   Guo-Yuan Lien
#
#===============================================================================

setting () {
#-------------------------------------------------------------------------------
# define steps

nsteps=3
stepname[1]='Run SCALE pp'
stepexecdir[1]="$TMPRUN/scale_pp"
stepexecname[1]="scale-rm_pp_ens"
stepname[2]='Run SCALE init'
stepexecdir[2]="$TMPRUN/scale_init"
stepexecname[2]="scale-rm_init_ens"
stepname[3]='Run ensemble forecasts'
stepexecdir[3]="$TMPRUN/scale"
stepexecname[3]="scale-rm_ens"
#stepname[4]='Run verification'
#stepexecdir[4]="$TMPRUN/verify"
#stepexecname[4]="verify"

#-------------------------------------------------------------------------------
# usage help string

USAGE="
[$myname] Run ensemble forecasts and (optional) verifications.

Configuration files:
  config.main
  config.cycle

Steps:
$(for i in $(seq $nsteps); do echo "  ${i}. ${stepname[$i]}"; done)

Usage: $myname [STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP CONF_MODE TIME_LIMIT]

  STIME       Time of the first cycle (format: YYYY[MMDDHHMMSS])
  ETIME       Time of the last  cycle (format: YYYY[MMDDHHMMSS])
               (default: same as STIME)
  MEMBERS     List of forecast members ('mean' for ensemble mean)
               all:     Run all members including ensemble mean (default)
               mems:    Run all members but not including ensemble mean
               '2 4 6': Run members 2, 4, 6
  CYCLE       Number of forecast cycles run in parallel
               (default: 1)
  CYCLE_SKIP  Run forecasts every ? cycles
               (default: 1)
  IF_VERF     Run verification? [Not finished!]
               0: No (default)
               1: Yes
              * to run the verification, a shared disk storing observations
                and reference model analyses needs to be used
  IF_EFSO     Use EFSO forecast length and output interval? [Not finished!]
               0: No (default)
               1: Yes
  ISTEP       The initial step in the first cycle from which this script starts
               (default: the first step)
  FSTEP       The final step in the last cycle by which this script ends
               (default: the last step)
  CONF_MODE   Mode of creating runtime configuration files: 'dynamic' or 'static'
               (default: 'dynamic')
  TIME_LIMIT  Requested time limit (only used when using a job scheduler)
               (default: 30 minutes)
"

#if [ "$1" == '-h' ] || [ "$1" == '--help' ]; then
#  echo "$USAGE"
#  exit 0
#fi

#-------------------------------------------------------------------------------
# set parameters from command line

STIME=${1:-$STIME}; shift
ETIME=${1:-$ETIME}; shift
MEMBERS=${1:-$MEMBERS}; shift
CYCLE=${1:-$CYCLE}; shift
CYCLE_SKIP=${1:-$CYCLE_SKIP}; shift
IF_VERF=${1:-$IF_VERF}; shift
IF_EFSO=${1:-$IF_EFSO}; shift
ISTEP=${1:-$ISTEP}; shift
FSTEP=${1:-$FSTEP}; shift
CONF_MODE=${1:-$CONF_MODE}; shift
TIME_LIMIT="${1:-$TIME_LIMIT}"

#-------------------------------------------------------------------------------
# if some necessary parameters are not given, print the usage help and exit

#if [ -z "$STIME" ]; then
#  echo "$USAGE" >&2
#  exit 1
#fi

#-------------------------------------------------------------------------------
# error detection

#if ((MACHINE_TYPE == 10 && ONLINE_STGOUT != 0)); then
#  echo "[Error] $myname: When \$MACHINE_TYPE = 10, \$ONLINE_STGOUT needs to be 0." >&2
#  exit 1
#fi

###### only need to check one file when $RUN_LEVEL option is implemented ######
if ((ENABLE_PARAM_USER == 1)) && [ ! -e "$SCRP_DIR/config.nml.scale_user" ] && [ ! -e "$TMPDAT/conf/config.nml.scale_user" ]; then
  echo "[Error] $myname: When \$ENABLE_PARAM_USER = 1, 'config.nml.scale_user' file is required." >&2
  exit 1
fi
if ((BDY_FORMAT == 4)) && [ ! -e "$SCRP_DIR/config.nml.grads_boundary" ] && [ ! -e "$TMPDAT/conf/config.nml.grads_boundary" ]; then
  echo "[Error] $myname: When \$BDY_FORMAT = 4, 'config.nml.grads_boundary' file is required." >&2
  exit 1
fi

#... more detections...

#-------------------------------------------------------------------------------
# assign default values to and standardize the parameters

STIME=$(datetime $STIME)
ETIME=$(datetime ${ETIME:-$STIME})
if [ -z "$MEMBERS" ] || [ "$MEMBERS" = 'all' ]; then
  MEMBERS="mean mdet $(printf "$MEMBER_FMT " $(seq $MEMBER))"
elif [ "$MEMBERS" = 'mems' ]; then
  MEMBERS=$(printf "$MEMBER_FMT " $(seq $MEMBER))
else
  tmpstr=''
  for m in $MEMBERS; do
    if [ "$m" = 'mean' ] || [ "$m" = 'mdet' ]; then
      tmpstr="$tmpstr$m "
    else
      tmpstr="$tmpstr$(printf $MEMBER_FMT $((10#$m))) "
      (($? != 0)) && exit 1
    fi
  done
  MEMBERS="$tmpstr"
fi
CYCLE=${CYCLE:-0}
CYCLE_SKIP=${CYCLE_SKIP:-1}
IF_VERF=${IF_VERF:-0}
IF_EFSO=${IF_EFSO:-0}
ISTEP=${ISTEP:-1}
FSTEP=${FSTEP:-$nsteps}
CONF_MODE=${CONF_MODE:-"dynamic"}
TIME_LIMIT=${TIME_LIMIT:-"0:30:00"}

#-------------------------------------------------------------------------------
# common variables

RUN_LEVEL=${RUN_LEVEL:-0}

if ((BDY_FORMAT >= 1)); then
  if ((BDYCYCLE_INT % BDYINT != 0)); then
    echo "[Error] \$BDYCYCLE_INT needs to be an exact multiple of \$BDYINT" >&2
    exit 1
  fi
  BDY_STARTFRAME_MAX=$((BDYCYCLE_INT / BDYINT))
  if [ -z "$PARENT_REF_TIME" ]; then
    PARENT_REF_TIME=$STIME
    for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
      if ((BDY_FORMAT == 1)) && [ -s "$DATA_BDY_SCALE/${PARENT_REF_TIME}/hist/${BDY_MEAN}/history.pe000000.nc" ]; then
        break
      elif ((BDY_FORMAT == 2 && BDY_ROTATING == 1)) && [ -s "$DATA_BDY_WRF/${PARENT_REF_TIME}/${BDY_MEAN}/wrfout_${PARENT_REF_TIME}" ]; then
        break
      elif ((BDY_FORMAT == 2 && BDY_ROTATING != 1)) && [ -s "$DATA_BDY_WRF/${BDY_MEAN}/wrfout_${PARENT_REF_TIME}" ]; then
        break
      elif ((BDY_FORMAT == 4 && BDY_ROTATING == 1)) && [ -s "$DATA_BDY_GRADS/${PARENT_REF_TIME}/${BDY_MEAN}/atm_${PARENT_REF_TIME}.grd" ]; then
        break
      elif ((BDY_FORMAT == 4 && BDY_ROTATING != 1)) && [ -s "$DATA_BDY_GRADS/${BDY_MEAN}/atm_${PARENT_REF_TIME}.grd" ]; then
        break
      elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
        echo "[Error] Cannot find boundary files." >&2
        exit 1
      fi
      PARENT_REF_TIME=$(datetime $PARENT_REF_TIME -${BDYINT} s)
    done
  fi
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

print_setting () {
#-------------------------------------------------------------------------------

for vname in DIR INDIR OUTDIR DATA_TOPO DATA_TOPO_BDY_SCALE DATA_LANDUSE DATA_BDY_SCALE \
             DATA_BDY_SCALE_PREP DATA_BDY_WRF DATA_BDY_NICAM OBS OBSNCEP TOPO_FORMAT \
             LANDUSE_FORMAT LANDUSE_UPDATE BDY_FORMAT BDY_ENS BDYINT BDYCYCLE_INT PARENT_REF_TIME \
             ENABLE_PARAM_USER OCEAN_INPUT OCEAN_FORMAT LAND_INPUT LAND_FORMAT OBSNUM WINDOW_S WINDOW_E \
             LCYCLE LTIMESLOT MEMBER NNODES NNODES_APPAR PPN PPN_APPAR THREADS SCALE_NP \
             STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP CONF_MODE \
             FCSTLEN FCSTOUT MAKEINIT OUT_OPT TOPOOUT_OPT LANDUSEOUT_OPT BDYOUT_OPT \
             LOG_OPT LOG_TYPE; do
  printf '  %-20s = %s\n' $vname "${!vname}"
done

#-------------------------------------------------------------------------------
}

#===============================================================================

staging_list () {
#-------------------------------------------------------------------------------
# TMPDAT

cat >> ${STAGING_DIR}/${STGINLIST} << EOF
${ENSMODEL_DIR}/scale-rm_pp_ens|${DAT_SUBDIR}/exec/scale-rm_pp_ens
${ENSMODEL_DIR}/scale-rm_init_ens|${DAT_SUBDIR}/exec/scale-rm_init_ens
${ENSMODEL_DIR}/scale-rm_ens|${DAT_SUBDIR}/exec/scale-rm_ens
${COMMON_DIR}/pdbash|${DAT_SUBDIR}/exec/pdbash
${SCRP_DIR}/config.nml.scale_pp|${DAT_SUBDIR}/conf/config.nml.scale_pp
${SCRP_DIR}/config.nml.scale_init|${DAT_SUBDIR}/conf/config.nml.scale_init
${SCRP_DIR}/config.nml.scale|${DAT_SUBDIR}/conf/config.nml.scale
${SCRP_DIR}/config.nml.ensmodel|${DAT_SUBDIR}/conf/config.nml.ensmodel
EOF
#${MODELDIR}/scale-rm_pp|${DAT_SUBDIR}/exec/scale-rm_pp
#${MODELDIR}/scale-rm_init|${DAT_SUBDIR}/exec/scale-rm_init
#${MODELDIR}/scale-rm|${DAT_SUBDIR}/exec/scale-rm

cat >> ${STAGING_DIR}/${STGINLIST_CONSTDB} << EOF
${DATADIR}/rad/|${DAT_SUBDIR}/rad/
${DATADIR}/land/|${DAT_SUBDIR}/land/
EOF

if [ -e "${SCRP_DIR}/config.nml.scale_user" ]; then
  echo "${SCRP_DIR}/config.nml.scale_user|${DAT_SUBDIR}/conf/config.nml.scale_user" >> ${STAGING_DIR}/${STGINLIST}
fi
if [ -e "${SCRP_DIR}/config.nml.grads_boundary" ]; then
  echo "${SCRP_DIR}/config.nml.grads_boundary|${DAT_SUBDIR}/conf/config.nml.grads_boundary" >> ${STAGING_DIR}/${STGINLIST}
fi

if [ "$TOPO_FORMAT" != 'prep' ]; then
  echo "${DATADIR}/topo/${TOPO_FORMAT}/Products/|${DAT_SUBDIR}/topo/${TOPO_FORMAT}/Products/" >> ${STAGING_DIR}/${STGINLIST_CONSTDB}
fi
if [ "$LANDUSE_FORMAT" != 'prep' ]; then
  echo "${DATADIR}/landuse/${LANDUSE_FORMAT}/Products/|${DAT_SUBDIR}/landuse/${LANDUSE_FORMAT}/Products/" >> ${STAGING_DIR}/${STGINLIST_CONSTDB}
fi

if [ "$PRESET" = 'K' ] || [ "$PRESET" = 'K_rankdir' ]; then
  echo "${COMMON_DIR}/datetime|${DAT_SUBDIR}/exec/datetime" >> ${STAGING_DIR}/${STGINLIST}
fi

#-------------------------------------------------------------------------------
# TMPOUT

lcycles=$((LCYCLE * CYCLE_SKIP))
time=$STIME
loop=0
while ((time <= ETIME)); do
  loop=$((loop+1))

  for c in $(seq $CYCLE); do
    time2=$(datetime $time $((lcycles * (c-1))) s)
    if ((time2 <= ETIME)); then
      #-------------------
      # stage-in
      #-------------------

      # anal
      #-------------------
      if ((MAKEINIT != 1)); then
        for m in $(seq $fmember); do
          mm=$(((c-1) * fmember + m))
          if ((PNETCDF == 1)); then
            path="${time2}/anal/${name_m[$mm]}.init.nc"
            echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
          else
            for q in $(seq $mem_np); do
              path="${time2}/anal/${name_m[$mm]}/init$(printf $SCALE_SFX $((q-1)))"
              echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
            done
          fi
        done
      fi

      # anal_ocean
      #-------------------
      if ((OCEAN_INPUT == 1)) && ((OCEAN_FORMAT == 0)); then
        for m in $(seq $fmember); do
          mm=$(((c-1) * fmember + m))
          if ((PNETCDF == 1)); then
            path="${time2}/anal/${name_m[$mm]}.init_ocean.nc"
            echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
          else
            for q in $(seq $mem_np); do
              path="${time2}/anal/${name_m[$mm]}/init_ocean$(printf $SCALE_SFX $((q-1)))"
              echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
            done
          fi
        done
      fi

      # anal_land
      #-------------------
      if ((LAND_INPUT == 1)) && ((LAND_FORMAT == 0)); then
        for m in $(seq $fmember); do
          mm=$(((c-1) * fmember + m))
          if ((PNETCDF == 1)); then
            path="${time2}/anal/${name_m[$mm]}.init_land.nc"
            echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
          else
            for q in $(seq $mem_np); do
              path="${time2}/anal/${name_m[$mm]}/init_land$(printf $SCALE_SFX $((q-1)))"
              echo "${INDIR}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
            done
          fi
        done
      fi

      # topo
      #-------------------
      if ((loop == 1 && c == 1)) && [ "$TOPO_FORMAT" = 'prep' ]; then
        if ((DISK_MODE == 3)); then
          for m in $(seq $fmember); do
            mm=$(((c-1) * fmember + m))
            if ((PNETCDF == 1)); then
              path="const/topo.nc"
              echo "${DATA_TOPO}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
            else
              for q in $(seq $mem_np); do
                path="const/topo/topo$(printf $SCALE_SFX $((q-1)))"
                echo "${DATA_TOPO}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
              done
            fi
          done
        else
          if ((PNETCDF == 1)); then
            path="const/topo.nc"
            echo "${DATA_TOPO}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
          else
            for q in $(seq $mem_np); do
              path="const/topo/topo$(printf $SCALE_SFX $((q-1)))"
              echo "${DATA_TOPO}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
            done
          fi
        fi
      fi

      # topo (bdy_scale)
      #-------------------
      if ((loop == 1 && c == 1 && BDY_FORMAT == 1)) && [ "$TOPO_FORMAT" != 'prep' ]; then
        if ((PNETCDF_BDY_SCALE == 1)); then
          pathin="${DATA_TOPO_BDY_SCALE}.nc"
          path="bdytopo/const/topo.nc"
        else
          pathin="${DATA_TOPO_BDY_SCALE}/"
          path="bdytopo/const/"
        fi
        echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
      fi

      # landuse
      #-------------------
      if (((loop == 1 && c == 1) || LANDUSE_UPDATE == 1)) && [ "$LANDUSE_FORMAT" = 'prep' ]; then
        if ((DISK_MODE == 3)); then
          for m in $(seq $fmember); do
            mm=$(((c-1) * fmember + m))
            if ((PNETCDF == 1)); then
              if ((LANDUSE_UPDATE == 1)); then
                path="${time2}/landuse.nc"
              else
                path="const/landuse.nc"
              fi
              echo "${DATA_LANDUSE}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
            else
              for q in $(seq $mem_np); do
                if ((LANDUSE_UPDATE == 1)); then
                  path="${time2}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
                else
                  path="const/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
                fi
                echo "${DATA_LANDUSE}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
              done
            fi
          done
        else
          if ((PNETCDF == 1)); then
            if ((LANDUSE_UPDATE == 1)); then
              path="${time2}/landuse.nc"
            else
              path="const/landuse.nc"
            fi
            echo "${DATA_LANDUSE}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
          else
            for q in $(seq $mem_np); do
              if ((LANDUSE_UPDATE == 1)); then
                path="${time2}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
              else
                path="const/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
              fi
              echo "${DATA_LANDUSE}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
            done
          fi
        fi
      fi

      # bdy (prepared)
      #-------------------
      if ((BDY_FORMAT == 0)); then
        if ((BDY_ENS == 0)); then
          if ((DISK_MODE == 3)); then
            for m in $(seq $fmember); do
              mm=$(((c-1) * fmember + m))
              if ((PNETCDF == 1)); then
                pathin="${DATA_BDY_SCALE_PREP}/${time2}/bdy/${BDY_MEAN}.boundary.nc"
                path="${time2}/bdy/mean.boundary.nc"
                echo "${pathin}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
              else
                for q in $(seq $mem_np); do
                  pathin="${DATA_BDY_SCALE_PREP}/${time2}/bdy/${BDY_MEAN}/boundary$(printf $SCALE_SFX $((q-1)))"
                  path="${time2}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
                  echo "${pathin}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
                done
              fi
            done
          else
            if ((PNETCDF == 1)); then
              pathin="${DATA_BDY_SCALE_PREP}/${time2}/bdy/${BDY_MEAN}.boundary.nc"
              path="${time2}/bdy/mean.boundary.nc"
              echo "${pathin}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
            else
              for q in $(seq $mem_np); do
                pathin="${DATA_BDY_SCALE_PREP}/${time2}/bdy/${BDY_MEAN}/boundary$(printf $SCALE_SFX $((q-1)))"
                path="${time2}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
                echo "${pathin}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}
              done
            fi
          fi
        elif ((BDY_ENS == 1)); then
          for m in $(seq $fmember); do
            mm=$(((c-1) * fmember + m))
            if ((PNETCDF == 1)); then
              path="${time2}/bdy/${name_m[$m]}.boundary.nc"
              echo "${DATA_BDY_SCALE_PREP}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+1))]}
            else
              for q in $(seq $mem_np); do
                path="${time2}/bdy/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
                echo "${DATA_BDY_SCALE_PREP}/${path}|${OUT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST}.${mem2node[$(((mm-1)*mem_np+q))]}
              done
            fi
          done
        fi
      fi

      #-------------------
      # stage-out
      #-------------------

      # anal
      #-------------------
      if ((MAKEINIT == 1)); then
        path="${time2}/anal/"
        echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
      fi

      # topo
      #-------------------
      if ((loop == 1 && c == 1 && TOPOOUT_OPT <= 1)) && [ "$TOPO_FORMAT" != 'prep' ]; then
        if ((PNETCDF == 1)); then
          path="const/topo.nc"
#            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST_NOLINK}
        else
          path="const/topo/"
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
        fi
      fi

      # landuse
      #-------------------
      if (((loop == 1 && c == 1) || LANDUSE_UPDATE == 1)) && ((LANDUSEOUT_OPT <= 1)) && [ "$LANDUSE_FORMAT" != 'prep' ]; then
        if ((PNETCDF == 1)); then
          if ((LANDUSE_UPDATE == 1)); then
            path="${time2}/landuse.nc"
          else
            path="const/landuse.nc"
          fi
#            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST_NOLINK}
        else
          if ((LANDUSE_UPDATE == 1)); then
            path="${time2}/landuse/"
          else
            path="const/landuse/"
          fi
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
        fi
      fi

      # bdy
      #-------------------
      if ((BDY_FORMAT != 0)); then
        if ((BDY_ENS == 1 && BDYOUT_OPT <= 1)); then
          path="${time2}/bdy/"
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
        elif ((BDYOUT_OPT <= 2)); then
          if ((PNETCDF == 1)); then
            path="${time2}/bdy/mean.boundary.nc"
#              echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST_NOLINK}
          else
            path="${time2}/bdy/mean/"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
          fi
        fi
      fi

      # fcst
      #-------------------
      path="${time2}/fcst/"
      echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}

      ### anal_ocean [mean]

      # log
      #-------------------
      if [ "$MPI_TYPE" = 'K' ]; then
        log_zeros='0'
      else
        log_zeros='000000'
      fi

      if ((LOG_OPT <= 2)); then
        if ((LOG_TYPE == 1)); then
          if ((c == 1)); then
            path="${time2}/log/fcst_scale_pp/${name_m[1]}_pp.conf"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale_pp/${name_m[1]}_LOG.pe000000"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale_pp/NOUT.${log_zeros}"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale_init/${name_m[1]}_init.conf"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale_init/${name_m[1]}_gradsbdy.conf"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale_init/${name_m[1]}_LOG.pe000000"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            if ((BDY_ENS == 1)); then
              path="${time2}/log/fcst_scale_init/NOUT-1.${log_zeros}"
            else
              path="${time2}/log/fcst_scale_init/NOUT.${log_zeros}"
            fi
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
          fi
        else
          path="${time2}/log/fcst_scale_pp/"
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
          path="${time2}/log/fcst_scale_init/"
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
        fi
      fi
      if ((LOG_OPT <= 3)); then
        if ((LOG_TYPE == 1)); then
          if ((c == 1)); then
            path="${time2}/log/fcst_scale/${name_m[1]}_run.conf"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale/${name_m[1]}_LOG.pe000000"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale/NOUT-1.${log_zeros}"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
            path="${time2}/log/fcst_scale/latlon_domain_catalogue.txt"
            echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}.1
          fi
        else
          path="${time2}/log/fcst_scale/"
          echo "${OUTDIR}/${path}|${OUT_SUBDIR}/${path}|${loop}" >> ${STAGING_DIR}/${STGOUTLIST}
        fi
      fi

      #-------------------
    fi
  done

  time=$(datetime $time $((lcycles * CYCLE)) s)
done

#-------------------
# stage-in
#-------------------

# bdy
#-------------------
if ((BDY_FORMAT >= 1)); then
  if ((BDY_FORMAT == 1)); then
    if [ -s "$DATA_BDY_SCALE/${PARENT_REF_TIME}/log/scale/latlon_domain_catalogue.txt" ]; then
      pathin="$DATA_BDY_SCALE/${PARENT_REF_TIME}/log/scale/latlon_domain_catalogue.txt"
      path="bdyorg/latlon_domain_catalogue.txt"
      echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
    else
      echo "[Error] Cannot find a lat/lon domain catalogue file at" >&2
      echo "        '$DATA_BDY_SCALE/${PARENT_REF_TIME}/log/scale/latlon_domain_catalogue.txt'" >&2
      exit 1
    fi
  fi

  nbdy_all=0
  time=$STIME
  while ((time <= ETIME)); do
    for c in $(seq $CYCLE); do
      time2=$(datetime $time $((lcycles * (c-1))) s)
      if ((time2 <= ETIME)); then

        bdy_setting $time2 $FCSTLEN $BDYCYCLE_INT "$BDYINT" "$PARENT_REF_TIME" "$BDY_SINGLE_FILE"

        for ibdy in $(seq $nbdy); do
          time_bdy=${bdy_times[$ibdy]}

          bdy_processed=0
          for ibdy2 in $(seq $nbdy_all); do
            if ((${bdy_times_all[$ibdy2]} == $time_bdy)); then
              bdy_processed=1
              break
            fi
          done

          if ((bdy_processed == 0)); then
            nbdy_all=$((nbdy_all+1))
            bdy_times_all[${nbdy_all}]=$time_bdy
          fi

          if ((bdy_processed == 0 || BDY_ROTATING == 1)); then
            if ((BDY_FORMAT == 1)); then

              if ((BDY_ENS == 1)); then
                for m in $(seq $fmember); do
                  if ((PNETCDF_BDY_SCALE == 1)); then
                    pathin="$DATA_BDY_SCALE/${time_bdy}/${BDY_SCALE_DIR}/${name_m[$m]}.history.nc"
                    if ((BDY_ROTATING == 1)); then
                      path="bdyorg/${time_bdy}/${time_bdy}/${name_m[$m]}.history.nc"
                    else
                      path="bdyorg/const/${time_bdy}/${name_m[$m]}.history.nc"
                    fi
                  else
                    pathin="$DATA_BDY_SCALE/${time_bdy}/${BDY_SCALE_DIR}/${name_m[$m]}/"
                    if ((BDY_ROTATING == 1)); then
                      path="bdyorg/${time_bdy}/${time_bdy}/${name_m[$m]}/"
                    else
                      path="bdyorg/const/${time_bdy}/${name_m[$m]}/"
                    fi
                  fi
                  echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
                done
              else
                if ((PNETCDF_BDY_SCALE == 1)); then
                  pathin="$DATA_BDY_SCALE/${time_bdy}/${BDY_SCALE_DIR}/${BDY_MEAN}.history.nc"
                  if ((BDY_ROTATING == 1)); then
                    path="bdyorg/${time_bdy}/${time_bdy}/mean.history.nc"
                  else
                    path="bdyorg/const/${time_bdy}/mean.history.nc"
                  fi
                else
                  pathin="$DATA_BDY_SCALE/${time_bdy}/${BDY_SCALE_DIR}/${BDY_MEAN}/"
                  if ((BDY_ROTATING == 1)); then
                    path="bdyorg/${time_bdy}/${time_bdy}/mean/"
                  else
                    path="bdyorg/const/${time_bdy}/mean/"
                  fi
                fi
                echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
              fi

            elif ((BDY_FORMAT == 2 || BDY_FORMAT == 4)); then

              if ((BDY_FORMAT == 2)); then
                data_bdy_i=$DATA_BDY_WRF
                filenum=1
                filename_prefix[1]='wrfout_'
                filename_suffix[1]=''
              elif ((BDY_FORMAT == 4)); then
                data_bdy_i=$DATA_BDY_GRADS
                filenum=3
                filename_prefix[1]='atm_'
                filename_suffix[1]='.grd'
                filename_prefix[2]='sfc_'
                filename_suffix[2]='.grd'
                filename_prefix[3]='land_'
                filename_suffix[3]='.grd'
              fi

              if ((BDY_ENS == 1)); then
                for m in $(seq $fmember); do
                  for ifile in $(seq $filenum); do
                    if ((BDY_ROTATING == 1)); then
                      pathin="$data_bdy_i/${time2}/${name_m[$m]}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                      path="bdyorg/${time2}/${name_m[$m]}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                    else
                      pathin="$data_bdy_i/${name_m[$m]}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                      path="bdyorg/const/${name_m[$m]}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                    fi
                    echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
                  done
                done
              else
                for ifile in $(seq $filenum); do
                  if ((BDY_ROTATING == 1)); then
                    pathin="$data_bdy_i/${time2}/${BDY_MEAN}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                    path="bdyorg/${time2}/mean/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                  else
                    pathin="$data_bdy_i/${BDY_MEAN}/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                    path="bdyorg/const/mean/${filename_prefix[$ifile]}${time_bdy}${filename_suffix[$ifile]}/"
                  fi
                  echo "${pathin}|${DAT_SUBDIR}/${path}" >> ${STAGING_DIR}/${STGINLIST_BDYDATA}
                done
              fi

            fi
          fi # ((bdy_processed == 0 || BDY_ROTATING == 1))
        done # [ ibdy in $(seq $nbdy) ]

      fi # ((time2 <= ETIME))
    done
    time=$(datetime $time $((lcycles * CYCLE)) s)
  done
fi # ((BDY_FORMAT >= 1))

### EFSO outputs...

#-------------------------------------------------------------------------------
}

#===============================================================================

enspp_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[1]}: Pre-processing script start" >&2
fi

if [ "$TOPO_FORMAT" == 'prep' ] && [ "$LANDUSE_FORMAT" == 'prep' ]; then
  echo "  ... skip this step (use prepared topo and landuse files)"
  exit 1
elif ((BDY_FORMAT == 0)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
elif ((LANDUSE_UPDATE != 1 && loop > 1)); then
  echo "  ... skip this step (already done in the first cycle)"
  exit 1
fi

if ((BDY_FORMAT == 1)); then
  bdycatalogue=${TMPDAT_BDYDATA}/bdyorg/latlon_domain_catalogue.txt
  bdytopo=${TMPDAT_BDYDATA}/bdytopo/const/topo
fi

if ((DISK_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
#  MEMBER_RUN=1
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_pp_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale_pp $MEMBER_RUN $iter fcst
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[1]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= MEMBER_RUN)); then
      if ((DISK_MODE <= 2)); then
        c=$m
      else
        c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
      fi

      if [ -n "${stimes[$c]}" ]; then
        bash $SCRP_DIR/src/pre_scale_pp.sh $MYRANK ${stimes[$c]} ${name_m[$m]} \
             $TMPRUN/scale_pp/$(printf '%04d' $m) $TMPDAT \
             fcst ${bdytopo} ${bdycatalogue}
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

enspp_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

if [ "$TOPO_FORMAT" == 'prep' ] && [ "$LANDUSE_FORMAT" == 'prep' ]; then
  return 1
elif ((BDY_FORMAT == 0)); then
  return 1
fi

if ((DISK_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= MEMBER_RUN)); then
      if ((DISK_MODE <= 2)); then
        c=$m
      else
        c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
      fi

      if [ -n "${stimes[$c]}" ]; then
        bash $SCRP_DIR/src/post_scale_pp.sh $MYRANK ${stimes[$c]} \
             ${name_m[$m]} $TMPRUN/scale_pp/$(printf '%04d' $m) $LOG_OPT fcst
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensinit_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[2]}: Pre-processing script start" >&2
fi

if ((BDY_FORMAT == 0)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
fi

bdyorgf=${TMPDAT_BDYDATA}/bdyorg

if ((BDY_ENS == 1)); then
  MEMBER_RUN=$((fmember*rcycle))
elif ((DISK_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_init_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale_init $MEMBER_RUN $iter fcst
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[2]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= MEMBER_RUN)); then
      if ((BDY_ENS == 1)); then
        c=$(((m-1)/fmember+1))
        mem_bdy=${name_m[$m]}
      elif ((DISK_MODE <= 2)); then
        c=$m
        mem_bdy='mean'
      else
        c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
        mem_bdy='mean'
      fi

      if [ -n "${stimes[$c]}" ]; then
        bdy_setting ${stimes[$c]} $FCSTLEN $BDYCYCLE_INT "$BDYINT" "$PARENT_REF_TIME" "$BDY_SINGLE_FILE"
        bdy_time_list=''
        for ibdy in $(seq $nbdy); do
          bdy_time_list="${bdy_time_list}${bdy_times[$ibdy]} "
        done

        if ((LANDUSE_UPDATE == 1)); then
          time_l=${stimes[$c]}
        else
          time_l='const'
        fi

        if ((PNETCDF == 1)); then
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK \
               $TMPOUT/const/topo $TMPOUT/${time_l}/landuse \
               ${bdyorgf} ${stimes[$c]} $mkinit ${name_m[$m]} $mem_bdy \
               $TMPRUN/scale_init/$(printf '%04d' $m) \
               "$bdy_time_list" $ntsteps $ntsteps_skip fcst
        else
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK \
               $TMPOUT/const/topo/topo $TMPOUT/${time_l}/landuse/landuse \
               ${bdyorgf} ${stimes[$c]} $mkinit ${name_m[$m]} $mem_bdy \
               $TMPRUN/scale_init/$(printf '%04d' $m) \
               "$bdy_time_list" $ntsteps $ntsteps_skip fcst
        fi
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensinit_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

if ((BDY_FORMAT == 0)); then
  return 1
fi

if ((BDY_ENS == 1)); then
  MEMBER_RUN=$((fmember*rcycle))
elif ((DISK_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= MEMBER_RUN)); then
      if ((BDY_ENS == 1)); then
        c=$(((m-1)/fmember+1))
        mem_bdy=${name_m[$m]}
      elif ((DISK_MODE <= 2)); then
        c=$m
        mem_bdy='mean'
      else
        c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
        mem_bdy='mean'
      fi

      if [ -n "${stimes[$c]}" ]; then
        bash $SCRP_DIR/src/post_scale_init.sh $MYRANK ${stimes[$c]} \
             $mkinit $mem_bdy $TMPRUN/scale_init/$(printf '%04d' $m) $LOG_OPT fcst
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Post-processing script (member) start" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensfcst_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[3]}: Pre-processing script start" >&2
fi
 
MEMBER_RUN=$((fmember*rcycle))

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale $MEMBER_RUN $iter fcst
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[3]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= fmembertot)); then
      c=$(((m-1)/fmember+1))

      if [ -n "${stimes[$c]}" ]; then
#        if ((PERTURB_BDY == 1)); then
#          ...
#        fi

        if ((BDY_ENS == 1)); then
          mem_bdy=${name_m[$m]}
        else
          mem_bdy='mean'
        fi

        ocean_base='-'
        if ((OCEAN_INPUT == 1)); then
          if ((OCEAN_FORMAT == 0)); then
            if ((PNETCDF == 1)); then
              ocean_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}.init_ocean"
            else
              ocean_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}/init_ocean"
            fi
          elif ((OCEAN_FORMAT == 99 && mkinit != 1)); then
            if ((PNETCDF == 1)); then
              ocean_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}.init_bdy"
            else
              ocean_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}/init_bdy"
            fi
          fi
        fi

        land_base='-'
        if ((LAND_INPUT == 1)); then
          if ((LAND_FORMAT == 0)); then
            if ((PNETCDF == 1)); then
              land_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}.init_land"
            else
              land_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}/init_land"
            fi
          elif ((LAND_FORMAT == 99 && mkinit != 1)); then
            if ((PNETCDF == 1)); then
              land_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}.init_bdy"
            else
              land_base="$TMPOUT/${stimes[$c]}/anal/${mem_bdy}/init_bdy"
            fi
          fi
        fi

        if ((PNETCDF == 1)); then
          bdy_base="$TMPOUT/${stimes[$c]}/bdy/${mem_bdy}.boundary"
        else
          bdy_base="$TMPOUT/${stimes[$c]}/bdy/${mem_bdy}/boundary"
        fi

        bdy_setting ${stimes[$c]} $FCSTLEN $BDYCYCLE_INT "$BDYINT" "$PARENT_REF_TIME" "$BDY_SINGLE_FILE"

        if ((LANDUSE_UPDATE == 1)); then
          time_l=${stimes[$c]}
        else
          time_l='const'
        fi

        if ((PNETCDF == 1)); then
          bash $SCRP_DIR/src/pre_scale.sh $MYRANK ${name_m[$m]} \
               $TMPOUT/${stimes[$c]}/anal/${name_m[$m]}.init $ocean_base $land_base $bdy_base \
               $TMPOUT/const/topo $TMPOUT/${time_l}/landuse \
               ${stimes[$c]} $FCSTLEN $FCSTLEN $FCSTOUT $TMPRUN/scale/$(printf '%04d' $m) $OUT_OPT \
               fcst $bdy_start_time
        else
          bash $SCRP_DIR/src/pre_scale.sh $MYRANK ${name_m[$m]} \
               $TMPOUT/${stimes[$c]}/anal/${name_m[$m]}/init $ocean_base $land_base $bdy_base \
               $TMPOUT/const/topo/topo $TMPOUT/${time_l}/landuse/landuse \
               ${stimes[$c]} $FCSTLEN $FCSTLEN $FCSTOUT $TMPRUN/scale/$(printf '%04d' $m) $OUT_OPT \
               fcst $bdy_start_time
        fi
      fi
    fi
  fi

  if ((MYRANK == 0)); then
     echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensfcst_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  if (pdrun $g $PROC_OPT); then
    m=$(((it-1)*parallel_mems+g))
    if ((m >= 1 && m <= fmembertot)); then
      c=$(((m-1)/fmember+1))

      if [ -n "${stimes[$c]}" ]; then
#        if ((PERTURB_BDY == 1)); then
#          ...
#        fi

        bash $SCRP_DIR/src/post_scale.sh $MYRANK ${stimes[$c]} \
             ${name_m[$m]} $FCSTLEN $TMPRUN/scale/$(printf '%04d' $m) $LOG_OPT $OUT_OPT fcst
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

archive_log () {
#-------------------------------------------------------------------------------

if ((LOG_TYPE >= 3)); then
  lcycles=$((LCYCLE * CYCLE_SKIP))
  time=$STIME
  while ((time <= ETIME)); do
    if ((LOG_OPT <= 2)) && [ -d "$OUTDIR/${time}/log/fcst_scale_pp" ]; then
      if ((TAR_THREAD > 1)); then
        while (($(jobs -p | wc -l) >= TAR_THREAD)); do
          sleep 1s
        done
        if ((LOG_TYPE == 3)); then
          ( tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale_pp.tar fcst_scale_pp && rm -fr $OUTDIR/${time}/log/fcst_scale_pp ) &
        elif ((LOG_TYPE == 4)); then
          ( tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale_pp.tar.gz fcst_scale_pp && rm -fr $OUTDIR/${time}/log/fcst_scale_pp ) &
        fi
      else
        if ((LOG_TYPE == 3)); then
          tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale_pp.tar fcst_scale_pp && rm -fr $OUTDIR/${time}/log/fcst_scale_pp
        elif ((LOG_TYPE == 4)); then
          tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale_pp.tar.gz fcst_scale_pp && rm -fr $OUTDIR/${time}/log/fcst_scale_pp
        fi
      fi
    fi

    if ((LOG_OPT <= 2)) && [ -d "$OUTDIR/${time}/log/fcst_scale_init" ]; then
      if ((TAR_THREAD > 1)); then
        while (($(jobs -p | wc -l) >= TAR_THREAD)); do
          sleep 1s
        done
        if ((LOG_TYPE == 3)); then
          ( tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale_init.tar fcst_scale_init && rm -fr $OUTDIR/${time}/log/fcst_scale_init ) &
        elif ((LOG_TYPE == 4)); then
          ( tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale_init.tar.gz fcst_scale_init && rm -fr $OUTDIR/${time}/log/fcst_scale_init ) &
        fi
      else
        if ((LOG_TYPE == 3)); then
          tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale_init.tar fcst_scale_init && rm -fr $OUTDIR/${time}/log/fcst_scale_init
        elif ((LOG_TYPE == 4)); then
          tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale_init.tar.gz fcst_scale_init && rm -fr $OUTDIR/${time}/log/fcst_scale_init
        fi
      fi
    fi

    if ((LOG_OPT <= 3)) && [ -d "$OUTDIR/${time}/log/fcst_scale" ]; then
      if ((TAR_THREAD > 1)); then
        while (($(jobs -p | wc -l) >= TAR_THREAD)); do
          sleep 1s
        done
        if ((LOG_TYPE == 3)); then
          ( tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale.tar fcst_scale && rm -fr $OUTDIR/${time}/log/fcst_scale ) &
        elif ((LOG_TYPE == 4)); then
          ( tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale.tar.gz fcst_scale && rm -fr $OUTDIR/${time}/log/fcst_scale ) &
        fi
      else
        if ((LOG_TYPE == 3)); then
          tar -C $OUTDIR/${time}/log -cf $OUTDIR/${time}/log/fcst_scale.tar fcst_scale && rm -fr $OUTDIR/${time}/log/fcst_scale
        elif ((LOG_TYPE == 4)); then
          tar -C $OUTDIR/${time}/log -czf $OUTDIR/${time}/log/fcst_scale.tar.gz fcst_scale && rm -fr $OUTDIR/${time}/log/fcst_scale
        fi
      fi
    fi

    time=$(datetime $time $lcycles s)
  done
  if ((TAR_THREAD > 1)); then
    wait
  fi
fi

#-------------------------------------------------------------------------------
}

#===============================================================================
