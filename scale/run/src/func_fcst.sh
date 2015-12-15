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
stepexecname[1]="scale-les_pp_ens"
stepname[2]='Run SCALE init'
stepexecdir[2]="$TMPRUN/scale_init"
stepexecname[2]="scale-les_init_ens"
stepname[3]='Run ensemble forecasts'
stepexecdir[3]="$TMPRUN/scale"
stepexecname[3]="scale-les_ens"
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

Usage: $myname [STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP TIME_LIMIT]

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
TIME_LIMIT="${1:-$TIME_LIMIT}"

#-------------------------------------------------------------------------------
# if some necessary parameters are not given, print the usage help and exit

#if [ -z "$STIME" ]; then
#  echo "$USAGE" >&2
#  exit 1
#fi

#-------------------------------------------------------------------------------
# error detection

if ((MACHINE_TYPE == 10 && ONLINE_STGOUT != 0)); then
  echo "[Error] $myname: When \$MACHINE_TYPE = 10, \$ONLINE_STGOUT needs to be 0." >&2
  exit 1
fi

#... more detections...

#-------------------------------------------------------------------------------
# assign default values to and standardize the parameters

STIME=$(datetime $STIME)
ETIME=$(datetime ${ETIME:-$STIME})
if [ -z "$MEMBERS" ] || [ "$MEMBERS" = 'all' ]; then
  MEMBERS="mean $(printf "$MEMBER_FMT " $(seq $MEMBER))"
elif [ "$MEMBERS" = 'mems' ]; then
  MEMBERS=$(printf "$MEMBER_FMT " $(seq $MEMBER))
else
  tmpstr=''
  for m in $MEMBERS; do
    if [ "$m" = 'mean' ] || [ "$m" = 'sprd' ]; then
      tmpstr="$tmpstr$m "
    else
      tmpstr="$tmpstr$(printf $MEMBER_FMT $((10#$m))) "
      (($? != 0)) && exit 1
    fi
  done
  MEMBERS="$tmpstr"
fi
CYCLE=${CYCLE:-1}
CYCLE_SKIP=${CYCLE_SKIP:-1}
IF_VERF=${IF_VERF:-0}
IF_EFSO=${IF_EFSO:-0}
ISTEP=${ISTEP:-1}
FSTEP=${FSTEP:-$nsteps}
TIME_LIMIT=${TIME_LIMIT:-"0:30:00"}

#-------------------------------------------------------------------------------
# common variables

if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then
  if ((BDYCYCLE_INT % BDYINT != 0)); then
    echo "[Error] \$BDYCYCLE_INT needs to be an exact multiple of \$BDYINT" >&2
    exit 1
  fi
  BDY_STARTFRAME_MAX=$((BDYCYCLE_INT/BDYINT))
  if [ -z "$PARENT_REF_TIME" ]; then
    PARENT_REF_TIME=$(datetime $STIME $BDYCYCLE_INT s)
    for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
      if [ -s "$DATA_BDY_SCALE/${PARENT_REF_TIME}/gues/meanf/history.pe000000.nc" ]; then
        break
      elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
        echo "[Error] Cannot find boundary files from the SCALE history files." >&2
        exit 1
      fi
      PARENT_REF_TIME=$(datetime $PARENT_REF_TIME -${BDYINT} s)
    done
  fi
fi

BUILTIN_STAGING=$((MACHINE_TYPE != 10 && MACHINE_TYPE != 11))

if ((TMPRUN_MODE <= 2)); then
  PROC_OPT='one'
else
  PROC_OPT='alln'
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

staging_list () {
#-------------------------------------------------------------------------------
# Determine stage-in list of boundary files
if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then
  nfiles_all=0
  lcycles=$((LCYCLE * CYCLE_SKIP))
  time=$STIME
  while ((time <= ETIME)); do
    for c in $(seq $CYCLE); do
      time2=$(datetime $time $((lcycles * (c-1))) s)
      if ((time2 <= ETIME)); then
        history_files_for_bdy $time2 $FCSTLEN $BDYCYCLE_INT $BDYINT $PARENT_REF_TIME 0
        for ibdy in $(seq $nfiles); do
          newtime=1
          if ((nfiles_all > 0)); then
            for ibdy2 in $(seq $nfiles_all); do
              if ((${history_times[$ibdy]} == ${history_times_all[$ibdy2]})); then
                newtime=0
                break
              fi
            done
          fi
          if ((newtime == 1)); then
            nfiles_all=$((nfiles_all+1))
            history_times_all[$nfiles_all]=${history_times[$ibdy]}
          fi
        done
      fi
    done
    time=$(datetime $time $((lcycles * CYCLE)) s)
  done

#  for ibdy in $(seq $nfiles_all); do
#    echo "$ibdy - ${history_times_all[$ibdy]}"
#  done
fi

#-------------------------------------------------------------------------------
# TMPDAT

if ((TMPDAT_MODE == 1 && MACHINE_TYPE != 10)); then
#-------------------
  safe_init_tmpdir $TMPDAT
  safe_init_tmpdir $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_pp $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_init $TMPDAT/exec
  ln -fs $MODELDIR/scale-les $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_pp_ens $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_init_ens $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_ens $TMPDAT/exec
  ln -fs $COMMON_DIR/pdbash $TMPDAT/exec
  ln -fs $DATADIR/rad $TMPDAT/rad
  ln -fs $DATADIR/land $TMPDAT/land
  ln -fs $DATADIR/topo $TMPDAT
  ln -fs $DATADIR/landuse $TMPDAT

  if ((DATA_BDY_TMPLOC == 1)); then
    if ((BDY_FORMAT == 2)); then
      ln -fs $DATA_BDY_WRF $TMPDAT/bdywrf
    fi
  fi

  safe_init_tmpdir $TMPDAT/conf
  ln -fs $SCRP_DIR/config.* $TMPDAT/conf
#-------------------
else
#-------------------
  cat >> $STAGING_DIR/stagein.dat << EOF
${MODELDIR}/scale-les_pp|exec/scale-les_pp
${MODELDIR}/scale-les_init|exec/scale-les_init
${MODELDIR}/scale-les|exec/scale-les
${ENSMODEL_DIR}/scale-les_pp_ens|exec/scale-les_pp_ens
${ENSMODEL_DIR}/scale-les_init_ens|exec/scale-les_init_ens
${ENSMODEL_DIR}/scale-les_ens|exec/scale-les_ens
${COMMON_DIR}/pdbash|exec/pdbash
${SCRP_DIR}/config.nml.scale_pp|conf/config.nml.scale_pp
${SCRP_DIR}/config.nml.scale_init|conf/config.nml.scale_init
${SCRP_DIR}/config.nml.scale|conf/config.nml.scale
${SCRP_DIR}/config.nml.ensmodel|conf/config.nml.ensmodel
${DATADIR}/rad|rad
${DATADIR}/land|land
EOF

  if [ "$TOPO_FORMAT" != 'prep' ]; then
    echo "${DATADIR}/topo/${TOPO_FORMAT}/Products|topo/${TOPO_FORMAT}/Products" >> $STAGING_DIR/stagein.dat
  fi
  if [ "$LANDUSE_FORMAT" != 'prep' ]; then
    echo "${DATADIR}/landuse/${LANDUSE_FORMAT}/Products|landuse/${LANDUSE_FORMAT}/Products" >> $STAGING_DIR/stagein.dat
  fi

  if ((MACHINE_TYPE == 10)); then
    echo "${COMMON_DIR}/datetime|exec/datetime" >> $STAGING_DIR/stagein.dat
  fi
#-------------------
fi

#-------------------------------------------------------------------------------
# TMPOUT

if ((TMPOUT_MODE == 1 && MACHINE_TYPE != 10)); then
#-------------------
  mkdir -p $(dirname $TMPOUT)
  ln -fs $OUTDIR $TMPOUT

  lcycles=$((LCYCLE * CYCLE_SKIP))
  time=$STIME
  while ((time <= ETIME)); do
    for c in $(seq $CYCLE); do
      time2=$(datetime $time $((lcycles * (c-1))) s)
      if ((time2 <= ETIME)); then
        #-------------------
        if [ "$TOPO_FORMAT" = 'prep' ]; then
          ln -fs ${DATA_TOPO} $TMPOUT/${time2}/topo
        fi
        #-------------------
        if [ "$LANDUSE_FORMAT" = 'prep' ]; then
          if ((LANDUSE_UPDATE == 1)); then
            ln -fs ${DATA_LANDUSE}/${time2} $TMPOUT/${time2}/landuse
          else
            ln -fs ${DATA_LANDUSE} $TMPOUT/${time2}/landuse
          fi
        fi
        #-------------------
        if ((BDY_FORMAT == 0)); then
          ln -fs ${DATA_BDY_SCALE_PREP}/${time2} $TMPOUT/${time2}/bdy
        fi
        #-------------------
      fi
    done
    time=$(datetime $time $((lcycles * CYCLE)) s)
  done

  if ((DATA_BDY_TMPLOC == 2)); then
    if ((BDY_FORMAT == 2)); then
      ln -fs $DATA_BDY_WRF $TMPOUT/bdywrf
    fi
  fi

  if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then
    if ((DATA_BDY_TMPLOC == 1)); then
      bdyscale_dir="$TMPDAT/bdyscale"
    elif ((DATA_BDY_TMPLOC == 2)); then
      bdyscale_dir="$TMPOUT/bdyscale"
    fi
    mkdir -p $bdyscale_dir

    find_catalogue=0
    for ibdy in $(seq $nfiles_all); do
      time_bdy=${history_times_all[$ibdy]}

      if ((find_catalogue == 0)); then
        time_catalogue=$(datetime $time_bdy -$BDYCYCLE_INT s)
        if [ -s "$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt" ]; then
          pathin="$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt"
          ln -fs ${pathin} ${bdyscale_dir}/latlon_domain_catalogue.txt
          find_catalogue=1
        fi
      fi

      if ((BDY_ENS == 1)); then
        for m in $(seq $fmember); do
          mem=${name_m[$m]}
          [ "$mem" = 'mean' ] && mem='meanf'
          mkdir -p ${bdyscale_dir}/${time_bdy}/${name_m[$m]}
          for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/${mem}/history.*.nc 2> /dev/null); do
            pathin="$ifile"
            ln -fs ${pathin} ${bdyscale_dir}/${time_bdy}/${name_m[$m]}/$(basename $ifile)
          done
        done
      else
        mkdir -p ${bdyscale_dir}/${time_bdy}/mean
        for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.*.nc 2> /dev/null); do
          pathin="$ifile"
          ln -fs ${pathin} ${bdyscale_dir}/${time_bdy}/mean/$(basename $ifile)
        done
      fi
    done
  fi
#-------------------
else
#-------------------
  lcycles=$((LCYCLE * CYCLE_SKIP))
  time=$STIME
  loop=0
  while ((time <= ETIME)); do
    loop=$((loop+1))
    if ((ONLINE_STGOUT == 1)); then
      stgoutstep="stageout.loop.${loop}"
    else
      stgoutstep='stageout.out'
    fi

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
            for q in $(seq $mem_np); do
              path="${time2}/anal/${name_m[$mm]}/init$(printf $SCALE_SFX $((q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((mm-1)*mem_np+q))]}
            done
          done
        fi

        # anal_ocean
        #-------------------
#        if ((OCEAN_INPUT == 1)) && ((OCEAN_FORMAT == 0)); then
#          for m in $(seq $fmember); do
#            mm=$(((c-1) * fmember + m))
#            for q in $(seq $mem_np); do
#              path="${time2}/anal/${name_m[$mm]}/init_ocean$(printf $SCALE_SFX $((q-1)))"
#              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((mm-1)*mem_np+q))]}
#            done
#          done
#        fi

        # topo
        #-------------------
        if [ "$TOPO_FORMAT" = 'prep' ]; then
          for q in $(seq $mem_np); do
            pathin="${DATA_TOPO}/topo$(printf $SCALE_SFX $((q-1)))"
            path="${time2}/topo/topo$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
          done
        fi

        # landuse
        #-------------------
        if [ "$LANDUSE_FORMAT" = 'prep' ]; then
          if ((LANDUSE_UPDATE == 1)); then
            pathin_pfx="${DATA_LANDUSE}/${time2}"
          else
            pathin_pfx="${DATA_LANDUSE}"
          fi
          for q in $(seq $mem_np); do
            pathin="${pathin_pfx}/landuse$(printf $SCALE_SFX $((q-1)))"
            path="${time2}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
          done
        fi

        # bdy (prepared)
        #-------------------
        if ((BDY_FORMAT == 0)); then
          for q in $(seq $mem_np); do
            pathin="${DATA_BDY_SCALE_PREP}/${time2}/mean/boundary$(printf $SCALE_SFX $((q-1)))"
            path="${time2}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
          done
          if ((BDY_ENS == 1)); then
            for m in $(seq $MEMBER); do
              for q in $(seq $mem_np); do
                pathin="${DATA_BDY_SCALE_PREP}/${time2}/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
                path="${time2}/bdy/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
                echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
              done
            done
          fi
        fi

        #-------------------
        # stage-out
        #-------------------

        #++++++
        if ((SIMPLE_STGOUT == 1)); then
        #++++++

          if ((MAKEINIT == 1)); then
            path="${time2}/anal"
            echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          fi
          if ((TOPOOUT_OPT <= 1)); then
            path="${time2}/topo"
            echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          fi
          if ((LANDUSEOUT_OPT <= 1)); then
            path="${time2}/landuse"
            echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          fi
          if ((BDYOUT_OPT <= 2)); then
            path="${time2}/bdy"
            echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          fi
          path="${time2}/fcst"
          echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          ### anal_ocean [mean]
          path="${time2}/log/scale_pp"
          echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          path="${time2}/log/scale_init"
          echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
          path="${time2}/log/scale"
          echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}

        #++++++
        else
        #++++++
          for m in $(seq $fmember); do
            mm=$(((c-1) * fmember + m))
            #-------------------

            for q in $(seq $mem_np); do
              #-------------------

              # bdy [members]
              #-------------------
              if ((BDYOUT_OPT <= 1)) && ((BDY_ENS == 1)); then
                path="${time2}/bdy/${name_m[$mm]}/boundary$(printf $SCALE_SFX $((q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+q))]}
              fi

              # anal
              #-------------------
              if ((MAKEINIT == 1)); then
                path="${time2}/anal/${name_m[$mm]}/init$(printf $SCALE_SFX $((q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+q))]}
              fi

              # anal_ocean
              #-------------------
  #            if ((OCEAN_INPUT == 1)) && ((MAKEINIT != 1)); then
  #              path="${time2}/anal/${name_m[$mm]}/init_ocean$(printf $SCALE_SFX $((q-1)))"
  #              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+q))]}
  #            fi

              # fcst [history]
              #-------------------
              if ((OUT_OPT <= 2)); then
                path="${time2}/fcst/${name_m[$mm]}/history$(printf $SCALE_SFX $((q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+q))]}
              fi

              # fcst [restart]
              #-------------------
              if ((OUT_OPT <= 1)); then
                path="${time2}/fcst/${name_m[$mm]}/init_$(datetime ${time2} $FCSTLEN s)$(printf $SCALE_SFX $((q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+q))]}
              fi

              #-------------------
            done

            # log [scale_init: members]
            #-------------------
            if ((BDY_FORMAT > 0)) && ((LOG_OPT <= 2)) && ((BDY_ENS == 1)); then
              path="${time2}/log/scale_init/${name_m[$mm]}_init_LOG${SCALE_LOG_SFX}"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+1))]}
            fi

            # log [scale]
            #-------------------
            if ((LOG_OPT <= 3)); then
              path="${time2}/log/scale/${name_m[$mm]}_LOG${SCALE_LOG_SFX}"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+1))]}
              path="${time2}/log/scale/${name_m[$mm]}_latlon_domain_catalogue.txt"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mm-1)*mem_np+1))]}
            fi

  #          if ((LOG_OPT <= 1)); then
  #            # perturb bdy log
  #          fi

            #-------------------
          done
          #-------------------

          if ((repeat_mems <= fmember)); then
            tmpidx=0                            # mm=1
          else
            tmpidx=$((((c-1)*fmember)*mem_np))  # mm=$(((c-1) * fmember + 1))
          fi

          for q in $(seq $mem_np); do
            #-------------------

            # topo
            #-------------------
            if ((TOPOOUT_OPT <= 1)); then
              path="${time2}/topo/topo$(printf $SCALE_SFX $((q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
            fi

            # landuse
            #-------------------
            if ((LANDUSEOUT_OPT <= 1)); then
              path="${time2}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
            fi

            # bdy [mean]
            #-------------------
            if ((BDYOUT_OPT <= 2)) && ((BDY_ENS != 1)); then
              path="${time2}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
            fi

            # anal_ocean [mean]
            #-------------------
            if ((OCEAN_INPUT == 1)) && ((MAKEINIT != 1)); then
              path="${time2}/anal/mean/init_ocean$(printf $SCALE_SFX $((q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
            fi

            # log [scale_pp/scale_init/scale]
            #-------------------
            if ((LOG_OPT <= 4)); then
              if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ] && ((BDY_FORMAT != 0)); then
                path="${time2}/log/scale_pp/NOUT-$(printf $PROCESS_FMT $((tmpidx+q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
              fi
              if ((BDY_FORMAT != 0)); then
                path="${time2}/log/scale_init/NOUT-$(printf $PROCESS_FMT $((tmpidx+q-1)))"
                echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
              fi
              path="${time2}/log/scale/NOUT-$(printf $PROCESS_FMT $((tmpidx+q-1)))"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
            fi

            #-------------------
          done

          # log [scale_pp]
          #-------------------
          if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ]; then
            if ((LOG_OPT <= 2)); then
              path="${time2}/log/scale_pp/pp_LOG${SCALE_LOG_SFX}"
              echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+1))]}
            fi
          fi

          # log [scale_init: mean]
          #-------------------
          if ((BDY_FORMAT > 0)) && ((LOG_OPT <= 2)) && ((BDY_ENS != 1)); then
            path="${time2}/log/scale_init/mean_init_LOG${SCALE_LOG_SFX}"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+1))]}
          fi

          # log [scale: catalogue]
          #-------------------
          path="${time2}/log/scale/latlon_domain_catalogue.txt"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+1))]}

        #++++++
        fi # ((SIMPLE_STGOUT == 1))
        #++++++

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
  if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then
    if ((DATA_BDY_TMPLOC == 1)); then
      bdyscale_dir="$TMPDAT/bdyscale"
    elif ((DATA_BDY_TMPLOC == 2)); then
      bdyscale_dir="$TMPOUT/bdyscale"
    fi
    mkdir -p $bdyscale_dir

    find_catalogue=0
    for ibdy in $(seq $nfiles_all); do
      time_bdy=${history_times_all[$ibdy]}

      if ((find_catalogue == 0)); then
        time_catalogue=$(datetime $time_bdy -$BDYCYCLE_INT s)
        if [ -s "$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt" ]; then
          pathin="$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt"
          path="bdyscale/latlon_domain_catalogue.txt"
          if ((DATA_BDY_TMPLOC == 1)); then
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
          elif ((DATA_BDY_TMPLOC == 2)); then
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
          fi
          find_catalogue=1
        fi
      fi

      if ((BDY_ENS == 1)); then
        for m in $(seq $fmember); do
          mem=${name_m[$m]}
          [ "$mem" = 'mean' ] && mem='meanf'
          for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/${mem}/history.*.nc 2> /dev/null); do
            pathin="$ifile"
            path="bdyscale/${time_bdy}/${name_m[$m]}/$(basename $ifile)"

            if ((DATA_BDY_TMPLOC == 1)); then
              echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
            elif ((DATA_BDY_TMPLOC == 2)); then
              for c in $(seq $CYCLE); do
                mm=$(((c-1) * fmember + m))
                for q in $(seq $mem_np); do
                  echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((mm-1)*mem_np+q))]} ###### q: may be redundant ????
                done
              done
            fi
          done
#            pathin="$DATA_BDY_SCALE/${time_bdy}/gues/${mem}"
#            path="bdyscale/${time_bdy}/${name_m[$m]}"
#            if ((DATA_BDY_TMPLOC == 1)); then
#              echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.dat
#            elif ((DATA_BDY_TMPLOC == 2)); then
#              for q in $(seq $mem_np); do
#                echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]} ###### q: may be redundant ????
#              done
#            fi
        done
      else
        for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.*.nc 2> /dev/null); do
          pathin="$ifile"
          path="bdyscale/${time_bdy}/mean/$(basename $ifile)"

          if ((DATA_BDY_TMPLOC == 1)); then
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
          elif ((DATA_BDY_TMPLOC == 2)); then
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
          fi
        done
#          pathin="$DATA_BDY_SCALE/${time_bdy}/gues/meanf"
#          path="bdyscale/${time_bdy}/mean"
#            if ((DATA_BDY_TMPLOC == 1)); then
#            echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.dat
#          elif ((DATA_BDY_TMPLOC == 2)); then
#            echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.out
#          fi
      fi
    done

  #-------------------
  elif ((BDY_FORMAT == 2)); then

    time_dby=${STIME}
    etime_bdy=$(datetime ${ETIME} $((FCSTLEN+BDYINT)) s)
#    tmp_etime_bdy=$(datetime ${ETIME} $((BDYINT+BDYINT)) s)  # T. Honda (may be not necessary?)
#    if (( etime_bdy < tmp_etime_bdy )); then                 #
#      etime_bdy=${tmp_etime_bdy}                             #
#    fi                                                       #
    while ((time_dby < etime_bdy)); do
      if ((BDY_ENS == 1)); then
        for m in $(seq $fmember); do
          pathin="$DATA_BDY_WRF/${name_m[$m]}/wrfout_${time_dby}"
          path="bdywrf/${name_m[$m]}/wrfout_${time_dby}"

          if ((DATA_BDY_TMPLOC == 1)); then
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
          elif ((DATA_BDY_TMPLOC == 2)); then
            for c in $(seq $CYCLE); do
              mm=$(((c-1) * fmember + m))
              for q in $(seq $mem_np); do
                echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((mm-1)*mem_np+q))]} ###### q: may be redundant ????
              done
            done
          fi
        done
      else
        pathin="$DATA_BDY_WRF/mean/wrfout_${time_dby}"
        path="bdywrf/mean/wrfout_${time_dby}"

        if ((DATA_BDY_TMPLOC == 1)); then
          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
        elif ((DATA_BDY_TMPLOC == 2)); then
          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
        fi
      fi
      time_dby=$(datetime $time_dby $BDYINT s)
    done

  fi

  #-------------------

#-------------------
fi


#for c in `seq $CYCLES`; do
#  for m in `seq $fmember`; do
#    mt=$(((c-1) * fmember + m))
#    echo "rm|anal/${name_m[$mt]}/${Syyyymmddhh[$c]}.sig" >> $tmpstageout/out.${node_m[$mt]}
#    echo "rm|anal/${name_m[$mt]}/${Syyyymmddhh[$c]}.sfc" >> $tmpstageout/out.${node_m[$mt]}
#    fh=0
#    while [ "$fh" -le "$FCSTLEN" ]; do
#      fhhh=`printf '%03d' $fh`
#      Fyyyymmddhh=$(datetime ${STIME[$c]} $fh h | cut -c 1-10)
#      if [ "$OUT_OPT" -le 1 ]; then
#        echo "mv|fcst/${Syyyymmddhh[$c]}/${name_m[$mt]}/${Fyyyymmddhh}.sig" >> $tmpstageout/out.${node_m[$mt]}
#        echo "mv|fcst/${Syyyymmddhh[$c]}/${name_m[$mt]}/${Fyyyymmddhh}.sfc" >> $tmpstageout/out.${node_m[$mt]}
#      fi
#      echo "mv|fcstg/${Syyyymmddhh[$c]}/${name_m[$mt]}/${Fyyyymmddhh}.grd" >> $tmpstageout/out.${node_m[$mt]}
#      if [ "$OUT_OPT" -le 2 ]; then
#        echo "mv|fcstgp/${Syyyymmddhh[$c]}/${name_m[$mt]}/${Fyyyymmddhh}.grd" >> $tmpstageout/out.${node_m[$mt]}
#      fi
#      echo "mv|verfo1/${fhhh}/${name_m[$mt]}/${Fyyyymmddhh}.dat" >> $tmpstageout/out.${node_m[$mt]}
#      echo "mv|verfa1/${fhhh}/${name_m[$mt]}/${Fyyyymmddhh}.dat" >> $tmpstageout/out.${node_m[$mt]}
#      echo "mv|verfa2/${fhhh}/${name_m[$mt]}/${Fyyyymmddhh}.dat" >> $tmpstageout/out.${node_m[$mt]}
#    fh=$((fh + FCSTOUT))
#    done
#  done
#done

#-------------------------------------------------------------------------------
}

#===============================================================================

enspp_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if [ "$TOPO_FORMAT" == 'prep' ] && [ "$LANDUSE_FORMAT" == 'prep' ]; then
  echo "  ... skip this step (use prepared topo and landuse files)"
  exit 1
elif ((BDY_FORMAT == 0)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
fi

if ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_pp_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale_pp $TMPDAT/exec $TMPDAT $MEMBER_RUN $iter
fi

for it in $(seq $its $ite); do
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if ((TMPRUN_MODE <= 2)); then
      c=$m
    else
      c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
    fi
    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      echo "  [Pre-processing  script] ${stimesfmt[$c]}, node ${node_m[$m]} [$(datetime_now)]"
    fi

    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/pre_scale_pp.sh $MYRANK ${stimes[$c]} \
           $TMPRUN/scale_pp/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
    fi
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

if ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

for it in $(seq $its $ite); do
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if ((TMPRUN_MODE <= 2)); then
      c=$m
    else
      c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
    fi
    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      echo "  [Post-processing script] ${stimesfmt[$c]}, node ${node_m[$m]} [$(datetime_now)]"
    fi

    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_scale_pp.sh $MYRANK $mem_np ${stimes[$c]} \
           ${name_m[$m]} $TMPRUN/scale_pp/$(printf '%04d' $m) $LOG_OPT      ###### ${name_m[$m]}... will be buggy...
    fi
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

if ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
elif ((BDY_FORMAT == 1)); then
  if ((DATA_BDY_TMPLOC == 1)); then
    bdyscale_loc=$TMPDAT/bdyscale
  elif ((DATA_BDY_TMPLOC == 2)); then
    bdyscale_loc=$TMPOUT/bdyscale
  fi
elif ((BDY_FORMAT == 2)); then
  if ((DATA_BDY_TMPLOC == 1)); then
    bdywrf_loc=$TMPDAT/bdywrf
  elif ((DATA_BDY_TMPLOC == 2)); then
    bdywrf_loc=$TMPOUT/bdywrf
  fi
fi

if ((BDY_ENS == 1)); then
  MEMBER_RUN=$((fmember*rcycle))
elif ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
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
       $mem_nodes $mem_np $TMPRUN/scale_init $TMPDAT/exec $TMPDAT $MEMBER_RUN $iter
fi

for it in $(seq $its $ite); do
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if ((BDY_ENS == 1)); then
      c=$(((m-1)/fmember+1))
    elif ((TMPRUN_MODE <= 2)); then
      c=$m
    else
      c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
    fi

    history_files_for_bdy ${stimes[$c]} $FCSTLEN $BDYCYCLE_INT $BDYINT $PARENT_REF_TIME 0
    time_bdy=${history_times[1]}

    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      if ((BDY_ENS == 1)); then
        echo "  [Pre-processing  script] ${stimesfmt[$c]}, member ${name_m[$m]}: node ${node_m[$m]} [$(datetime_now)]"
      else
        echo "  [Pre-processing  script] ${stimesfmt[$c]}, node ${node_m[$m]} [$(datetime_now)]"
      fi
    fi

    if (pdrun $g $PROC_OPT); then
      #------
      if ((BDY_FORMAT == 1)); then
      #------
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
               ${bdyscale_loc}/${time_bdy}/${name_m[$m]}/history \
               ${stimes[$c]} $FCSTLEN $mkinit ${name_m[$m]} \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT \
               $((ntsteps_skip+1))
        else
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
               ${bdyscale_loc}/${time_bdy}/mean/history \
               ${stimes[$c]} $FCSTFLEN $mkinit mean \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT \
               $((ntsteps_skip+1))
        fi
      #------
      elif ((BDY_FORMAT == 2)); then
      #------
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
               ${bdywrf_loc}/${name_m[$m]}/wrfout \
               ${stimes[$c]} $FCSTLEN $mkinit ${name_m[$m]} \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
        else
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
               ${bdywrf_loc}/mean/wrfout \
               ${stimes[$c]} $FCSTLEN $mkinit mean \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
        fi
      #------
#      elif ((BDY_FORMAT == 3)); then
      #------
      #------
      fi
      #------
    fi
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
elif ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=$rcycle
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= fmember ? $((repeat_mems*rcycle)) : $((fmember*rcycle))))
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

for it in $(seq $its $ite); do
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if ((BDY_ENS == 1)); then
      c=$(((m-1)/fmember+1))
    elif ((TMPRUN_MODE <= 2)); then
      c=$m
    else
      c=$((repeat_mems <= fmember ? $(((m-1)/repeat_mems+1)) : $(((m-1)/fmember+1))))
    fi
    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      if ((BDY_ENS == 1)); then
        echo "  [Post-processing script] ${stimesfmt[$c]}, member ${name_m[$m]}: node ${node_m[$m]} [$(datetime_now)]"
      else
        echo "  [Post-processing script] ${stimesfmt[$c]}, node ${node_m[$m]} [$(datetime_now)]"
      fi
    fi

    if (pdrun $g $PROC_OPT); then
#      if ((BDY_FORMAT == 1 || BDY_FORMAT == 2)); then
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/post_scale_init.sh $MYRANK $mem_np ${stimes[$c]} \
               $mkinit ${name_m[$m]} $TMPRUN/scale_init/$(printf '%04d' $m) $LOG_OPT
        else
          bash $SCRP_DIR/src/post_scale_init.sh $MYRANK $mem_np ${stimes[$c]} \
               $mkinit mean $TMPRUN/scale_init/$(printf '%04d' $m) $LOG_OPT
        fi
#      elif ((BDY_FORMAT == 3)); then
#        ...
#      fi
    fi
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

############
if ((BDY_FORMAT == 1)); then
  if ((DATA_BDY_TMPLOC == 1)); then
    bdyscale_loc=$TMPDAT/bdyscale
  elif ((DATA_BDY_TMPLOC == 2)); then
    bdyscale_loc=$TMPOUT/bdyscale
  fi

  ######
  ######

#  time_bdy=$(datetime $time $BDYCYCLE_INT s)
#  for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
#    if [ -s "$bdyscale_loc/${time_bdy}/mean/history.pe000000.nc" ]; then
#      break
#    elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
#      echo "[Error] Cannot find boundary files from the SCALE history files." >&2
#      exit 1
#    fi
#    time_bdy=$(datetime $time_bdy -${BDYINT} s)
#  done
#  time_bdy=$(datetime $time_bdy -$BDYCYCLE_INT s)
fi
############

MEMBER_RUN=$((fmember*rcycle))

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale $TMPDAT/exec $TMPDAT $MEMBER_RUN $iter
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

ocean_base='-'
if ((OCEAN_INPUT == 1)); then
  if ((mkinit != 1 || OCEAN_FORMAT != 99)); then
    ocean_base="$TMPOUT/${stimes[$c]}/anal/mean/init_ocean"  ### always use mean???
  fi
fi

for it in $(seq $its $ite); do
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= fmembertot)); then
    c=$(((m-1)/fmember+1))
    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      echo "  [Pre-processing  script] ${stimesfmt[$c]}, member ${name_m[$m]}: node ${node_m[$m]} [$(datetime_now)]"
    fi

#    if ((PERTURB_BDY == 1)); then
#      ...
#    fi

    if ((BDY_ENS == 1)); then
      bdy_base="$TMPOUT/${stimes[$c]}/bdy/${name_m[$m]}/boundary"
    else
      bdy_base="$TMPOUT/${stimes[$c]}/bdy/mean/boundary"
    fi

    if (pdrun $g $PROC_OPT); then
      if ((BDY_FORMAT == 1)); then
        bash $SCRP_DIR/src/pre_scale.sh $MYRANK $mem_np \
             $TMPOUT/${stimes[$c]}/anal/${name_m[$m]}/init $ocean_base $bdy_base \
             $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
             ${stimes[$c]} $FCSTLEN $FCSTLEN $FCSTOUT $TMPRUN/scale/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT $time_bdy
      elif ((BDY_FORMAT == 2)); then
        bash $SCRP_DIR/src/pre_scale.sh $MYRANK $mem_np \
             $TMPOUT/${stimes[$c]}/anal/${name_m[$m]}/init $ocean_base $bdy_base \
             $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
             ${stimes[$c]} $FCSTLEN $FCSTLEN $FCSTOUT $TMPRUN/scale/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
#      elif ((BDY_FORMAT == 3)); then
      fi
      
    fi
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
  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= fmembertot)); then
    c=$(((m-1)/fmember+1))
    if [ ! -z "${proc2grpproc[$((MYRANK+1))]}" ] && ((${proc2grpproc[$((MYRANK+1))]} == 1)); then
      echo "  [Post-processing script] ${stimesfmt[$c]}, member ${name_m[$m]}: node ${node_m[$m]} [$(datetime_now)]"
    fi

#    if ((PERTURB_BDY == 1)); then
#      ...
#    fi

    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_scale.sh $MYRANK $mem_np \
           ${stimes[$c]} ${name_m[$m]} $FCSTLEN $TMPRUN/scale/$(printf '%04d' $m) $LOG_OPT fcst
    fi
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================
