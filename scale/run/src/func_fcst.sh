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

nsteps=4
stepname[1]='Prepare boundary files'
stepfunc[1]='boundary'
stepname[2]='Perturb boundaries'
stepfunc[2]='pertbdy'
stepname[3]='Run ensemble forecasts'
stepfunc[3]='ensfcst'
stepname[4]='Run verification'
stepfunc[4]='verf'

#-------------------------------------------------------------------------------
# usage help string

USAGE="
[$myname] Run ensemble forecasts and (optional) verifications.

Configuration files:
  config.main
  config.$myname1

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

if [ "$1" == '-h' ] || [ "$1" == '--help' ]; then
  echo "$USAGE"
  exit 0
fi

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

if [ -z "$STIME" ]; then
  echo "$USAGE" >&2
  exit 1
fi

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
# TMPDAT

if ((TMPDAT_MODE == 1 && MACHINE_TYPE != 10)); then
#-------------------
  safe_init_tmpdir $TMPDAT
  safe_init_tmpdir $TMPDAT/exec
  ln -fs $MODELDIR/scale-les $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_init $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_pp $TMPDAT/exec
  ln -fs $COMMON_DIR/pdbash $TMPDAT/exec
  ln -fs $DATADIR/rad $TMPDAT/rad
  ln -fs $DATADIR/land $TMPDAT/land
  ln -fs $DATADIR/topo $TMPDAT
  ln -fs $DATADIR/landuse $TMPDAT

  safe_init_tmpdir $TMPDAT/conf
  ln -fs $SCRP_DIR/config.* $TMPDAT/conf
#-------------------
else
#-------------------
  cat >> $STAGING_DIR/stagein.dat << EOF
${MODELDIR}/scale-les|exec/scale-les
${MODELDIR}/scale-les_init|exec/scale-les_init
${MODELDIR}/scale-les_pp|exec/scale-les_pp
${COMMON_DIR}/pdbash|exec/pdbash
${SCRP_DIR}/config.nml.scale|conf/config.nml.scale
${SCRP_DIR}/config.nml.scale_init|conf/config.nml.scale_init
${DATADIR}/rad|rad
${DATADIR}/land|land
EOF

  if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ]; then
    echo "${SCRP_DIR}/config.nml.scale_pp|conf/config.nml.scale_pp" >> $STAGING_DIR/stagein.dat
  fi
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

  if ((BDY_FORMAT == 2)); then
    ln -fs $DATA_BDY_WRF $TMPOUT/bdywrf
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

        # topo/landuse
        #-------------------
        for q in $(seq $mem_np); do
          if ((TOPOOUT_OPT <= 1)); then
            path="${time2}/topo/topo$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
          fi
          if ((LANDUSEOUT_OPT <= 1)); then
            path="${time2}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
          fi
        done

        # bdy [mean]
        #-------------------
        for q in $(seq $mem_np); do
          if ((BDYOUT_OPT <= 2)) && ((BDY_ENS != 1)); then
            path="${time2}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
          fi
        done

        # anal_ocean [mean]
        #-------------------
        for q in $(seq $mem_np); do
          if ((OCEAN_INPUT == 1)) && ((MAKEINIT != 1)); then
            path="${time2}/anal/mean/init_ocean$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$((tmpidx+q))]}
          fi
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

        #-------------------
      fi
    done

    time=$(datetime $time $((lcycles * CYCLE)) s)
  done

  #-------------------

  time_dby=${STIME}
  etime_bdy=$(datetime ${ETIME} $((FCSTLEN+BDYINT)) s)
  while ((time_dby < etime_bdy)); do
    #-------------------
    # stage-in
    #-------------------

    # bdy
    #-------------------
    if ((BDY_FORMAT == 2)); then
      if ((BDY_ENS == 1)); then
        for m in $(seq $fmember); do
          mm=$(((c-1) * fmember + m))
          for q in $(seq $mem_np); do
            pathin="$DATA_BDY_WRF/${name_m[$mm]}/wrfout_${time_dby}"
            path="bdywrf/${name_m[$mm]}/wrfout_${time_dby}"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((mm-1)*mem_np+q))]}
          done
        done
      else
        for q in $(seq $mem_np); do
          pathin="$DATA_BDY_WRF/mean/wrfout_${time_dby}"
          path="bdywrf/mean/wrfout_${time_dby}"
          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
        done
      fi
    fi
    #-------------------

    time_dby=$(datetime $time_dby $BDYINT s)
  done
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

boundary_sub () {
#-------------------------------------------------------------------------------
# Run a series of scripts (topo/landuse/init) to make the boundary files.
#
# Usage: make_boundary NODEFILE
#
#   NODEFILE          $NODEFILE in functions 'pdbash' and 'mpirunf'
#
# Other input variables:
#   $c       Cycle number
#   $cf      Formatted cycle number
#   $stimes  Start time of this cycle
#   $SCRP_DIR
#   $TMPRUN
#   $TMPDAT
#   $mem_np
#   $PREP_TOPO
#   $PREP_LANDUSE
#   $PROC_OPT
#-------------------------------------------------------------------------------

if (($# < 1)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local NODEFILE="$1"

#-------------------------------------------------------------------------------
# pp (topo/landuse)

if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ]; then
  pdbash $NODEFILE $PROC_OPT \
    $SCRP_DIR/src/pre_scale_pp.sh ${stimes[$c]} $TMPRUN/scale_pp/${cf} $TMPDAT/exec $TMPDAT
  mpirunf $NODEFILE \
    $TMPRUN/scale_pp/${cf} ./scale-les_pp pp.conf
  pdbash $NODEFILE $PROC_OPT \
    $SCRP_DIR/src/post_scale_pp.sh ${stimes[$c]} $TMPRUN/scale_pp/${cf}
fi

#-------------------------------------------------------------------------------
# init

if ((BDY_ENS != 1)); then
  if ((BDY_FORMAT == 2)); then
    pdbash $NODEFILE $PROC_OPT \
      $SCRP_DIR/src/pre_scale_init.sh $mem_np \
      $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
      $TMPOUT/bdywrf/mean/wrfout \
      ${stimes[$c]} $FCSTLEN $MAKEINIT mean $TMPRUN/scale_init/${cf}_mean $TMPDAT/exec $TMPDAT
    mpirunf $NODEFILE \
      $TMPRUN/scale_init/${cf}_mean ./scale-les_init init.conf
    pdbash $NODEFILE $PROC_OPT \
      $SCRP_DIR/src/post_scale_init.sh ${stimes[$c]} $MAKEINIT mean $TMPRUN/scale_init/${cf}_mean
  fi
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

boundary () {
#-------------------------------------------------------------------------------

echo
if ((BDY_FORMAT == 0)); then
  echo "  ... skip this step (use prepared boundaries)"
  return 1
fi

if ((BDY_ENS == 1)); then
  echo "     -- topo/landuse"
  echo
fi

if ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
#-------------------
  ipm=0
  for c in $(seq $rcycle); do
    cf=$(printf $CYCLE_FMT $c)
    ipm=$((ipm+1))
    if ((ipm > parallel_mems)); then wait; ipm=1; fi
    cfr=$(printf $CYCLE_FMT $(((ipm-1)/fmember+1))) # try to use processes in parallel
    echo "  ${stimesfmt[$c]}: node ${node_m[$ipm]} [$(datetime_now)]"

    boundary_sub proc.${cfr}.${name_m[$ipm]} &
    sleep $BGJOB_INT
  done
  wait
#-------------------
else # local run directory: run multiple members as needed
#-------------------
  if ((repeat_mems <= fmember)); then
    ipm=0
    for c in $(seq $rcycle); do
      cf=$(printf $CYCLE_FMT $c)
      for m in $(seq $repeat_mems); do
        ipm=$((ipm+1))
        if ((ipm > parallel_mems)); then wait; ipm=1; fi
        echo "  ${stimesfmt[$c]}: node ${node_m[$m]} [$(datetime_now)]"

        boundary_sub proc.$(printf $CYCLE_FMT 1).${name_m[$m]} &
        sleep $BGJOB_INT
      done
    done
    wait
  else
    ipm=0
    for c in $(seq $rcycle); do
      cf=$(printf $CYCLE_FMT $c)
      for m in $(seq $fmember); do
        mm=$(((c-1) * fmember + m))
        ipm=$((ipm+1))
        if ((ipm > parallel_mems)); then wait; ipm=1; fi
        echo "  ${stimesfmt[$c]}: node ${node_m[$mm]} [$(datetime_now)]"

        boundary_sub proc.${cf}.${name_m[$mm]} &
        sleep $BGJOB_INT
      done
    done
    wait
  fi
#-------------------
fi

#-------------------------------------------------------------------------------

if ((BDY_ENS == 1)); then
  echo
  echo "     -- boundary"
  echo

  ipm=0
  for c in $(seq $rcycle); do
    cf=$(printf $CYCLE_FMT $c)

    for m in $(seq $fmember); do
      mm=$(((c-1) * fmember + m))
      ipm=$((ipm+1))
      if ((ipm > parallel_mems)); then wait; ipm=1; fi
      echo "  ${stimesfmt[$c]}, member ${name_m[$mm]}: node ${node_m[$mm]} [$(datetime_now)]"

#      if ((PERTURB_BDY == 1)); then
#        ...
#      fi

      if ((BDY_FORMAT == 2)); then
        ( pdbash proc.${cf}.${name_m[$mm]} $PROC_OPT $SCRP_DIR/src/pre_scale_init.sh $mem_np \
            $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
            $TMPOUT/bdywrf/${name_m[$mm]}/wrfout ${stimes[$c]} $FCSTLEN $MAKEINIT ${name_m[$mm]} \
            $TMPRUN/scale_init/${cf}_${name_m[$mm]} $TMPDAT/exec $TMPDAT ;
          mpirunf proc.${cf}.${name_m[$mm]} \
            $TMPRUN/scale_init/${cf}_${name_m[$mm]} ./scale-les_init init.conf ;
          pdbash proc.${cf}.${name_m[$mm]} $PROC_OPT \
            $SCRP_DIR/src/post_scale_init.sh ${stimes[$c]} $MAKEINIT ${name_m[$mm]} \
            $TMPRUN/scale_init/${cf}_${name_m[$mm]} ) &
      fi

      sleep $BGJOB_INT
    done
  done
  wait
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

pertbdy () {
#-------------------------------------------------------------------------------

echo
if ((PERTURB_BDY == 0)); then
  echo "  ... skip this step (do not perturb boundaries)"
  return 1
fi

###### not finished yet...
echo "pertbdy..."
######

ipm=0
for c in $(seq $rcycle); do
  cf=$(printf $CYCLE_FMT $c)
  if ((PREP_BDY == 1)); then
    bdy_base="$TMPDAT/bdy_prep/bdy_${stimes[$c]}"
  else
    bdy_base="$TMPRUN/scale_init/${cf}/boundary"
  fi

  for m in $(seq $fmember); do
    mm=$(((c-1) * fmember + m))
    ipm=$((ipm+1))
    if ((ipm > parallel_mems)); then wait; ipm=1; fi
    echo "  ${stimesfmt[$c]}, member ${name_m[$mm]}: node ${node_m[$mm]} [$(datetime_now)]"

#   ......
#    ( pdbash proc.${cf}.${name_m[$mm]} $PROC_OPT $SCRP_DIR/src/pre_scale.sh $mem_np \
#        $TMPOUT/${stimes[$c]}/anal/${name_m[$mm]}/init $bdy_base $topo_base $landuse_base \
#        ${stimes[$c]} $FCSTLEN $FCSTOUT $TMPRUN/scale/${cf}_${name_m[$mm]} $TMPDAT/exec $TMPDAT ;
#      mpirunf proc.${cf}.${name_m[$mm]} $TMPRUN/scale/${cf}_${name_m[$mm]} \
#        ./scale-les run.conf ) &
#   ......
#   $TMPRUN/pertbdy/${cf}_${name_m[$mm]}

    sleep $BGJOB_INT
  done
done
wait

#-------------------------------------------------------------------------------
}

#===============================================================================

ensfcst () {
#-------------------------------------------------------------------------------

echo

ipm=0
for c in $(seq $rcycle); do
  cf=$(printf $CYCLE_FMT $c)

  for m in $(seq $fmember); do
    mm=$(((c-1) * fmember + m))
    ipm=$((ipm+1))
    if ((ipm > parallel_mems)); then wait; ipm=1; fi
    echo "  ${stimesfmt[$c]}, member ${name_m[$mm]}: node ${node_m[$mm]} [$(datetime_now)]"

#    if ((PERTURB_BDY == 1)); then
#      ...
#    fi

    if ((BDY_ENS == 1)); then
      bdy_base="$TMPOUT/${stimes[$c]}/bdy/${name_m[$mm]}/boundary"
    else
      bdy_base="$TMPOUT/${stimes[$c]}/bdy/mean/boundary"
    fi
    if ((OCEAN_INPUT == 1)); then
      if ((MKINIT == 1 && OCEAN_FORMAT == 99)); then
        ocean_base='-'
      else
        ocean_base="$TMPOUT/${stimes[$c]}/anal/mean/init_ocean"  ### always use mean???
      fi
    else
      ocean_base='-'
    fi
    ( pdbash proc.${cf}.${name_m[$mm]} $PROC_OPT $SCRP_DIR/src/pre_scale.sh $mem_np \
        $TMPOUT/${stimes[$c]}/anal/${name_m[$mm]}/init $ocean_base $bdy_base \
        $TMPOUT/${stimes[$c]}/topo/topo $TMPOUT/${stimes[$c]}/landuse/landuse \
        ${stimes[$c]} $FCSTLEN $FCSTLEN $FCSTOUT $TMPRUN/scale/${cf}_${name_m[$mm]} $TMPDAT/exec $TMPDAT ;
      mpirunf proc.${cf}.${name_m[$mm]} $TMPRUN/scale/${cf}_${name_m[$mm]} \
        ./scale-les run.conf > /dev/null ;
      pdbash proc.${cf}.${name_m[$mm]} $PROC_OPT $SCRP_DIR/src/post_scale.sh $mem_np \
        ${stimes[$c]} ${name_m[$mm]} $FCSTLEN $TMPRUN/scale/${cf}_${name_m[$mm]} $myname1 ) &

    sleep $BGJOB_INT
  done
done
wait

#-------------------------------------------------------------------------------
}

#===============================================================================

verf () {
#-------------------------------------------------------------------------------

echo
if ((IF_VERF == 0)); then
  echo "  ... skip this step (do not run verification)"
  return 1
fi

echo "verf..."


#cd $TMPMPI
#cp -f $RUNDIR/datetime.sh .

#cat > fcst_31.sh << EOF
#. datetime.sh
#mem="\$1"
#cyc="\$2"
#stime="\$3"
#Syyyymmddhh=\${stime:0:10}
#mkdir -p $ltmpout/fcst/\${Syyyymmddhh}/\${mem}
#mkdir -p $ltmpout/fcstg/\${Syyyymmddhh}/\${mem}
#mkdir -p $ltmpout/fcstgp/\${Syyyymmddhh}/\${mem}

#mkdir -p $ltmpssio/\${cyc}_\${mem}
#cd $ltmpssio/\${cyc}_\${mem}
#ln -fs $ltmpprog/ss2grd .
#ln -fs $ltmpprog/ss2grdp .
#fh=0
#while [ "\$fh" -le "$FCSTLEN" ]; do
#  fhh="\$(printf '%02d' \$fh)"
#  fhhh="\$(printf '%03d' \$fh)"
#  Fyyyymmddhh=\$(datetime \$stime \$fh h | cut -c 1-10)
#  cd $ltmpssio/\${cyc}_\${mem}
#  rm -f fort.*
#  if [ "\$fh" -eq 0 ]; then
#    ln -fs $ltmpgfs/\${cyc}_\${mem}/sig_ini fort.11
#    ln -fs $ltmpgfs/\${cyc}_\${mem}/sfc_ini fort.12
#  else
#    ln -fs $ltmpgfs/\${cyc}_\${mem}/SIG.F\${fhh} fort.11
#    ln -fs $ltmpgfs/\${cyc}_\${mem}/SFC.F\${fhh} fort.12
#  fi
#  ./ss2grd
#  mv -f fort.31 $ltmpout/fcstg/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd
#EOF
#if [ "$OUT_OPT" -le 2 ]; then
#  cat >> fcst_31.sh << EOF
#  ./ss2grdp
#  mv -f fort.31 $ltmpout/fcstgp/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd
#EOF
#fi
#if [ "$OUT_OPT" -le 1 ]; then
#  cat >> fcst_31.sh << EOF
#  if [ "\$fh" -eq 0 ]; then
#    cp -fL $ltmpgfs/\${cyc}_\${mem}/sig_ini $ltmpout/fcst/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.sig
#    cp -fL $ltmpgfs/\${cyc}_\${mem}/sfc_ini $ltmpout/fcst/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.sfc
#  else
#    mv -f $ltmpgfs/\${cyc}_\${mem}/SIG.F\${fhh} $ltmpout/fcst/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.sig
#    mv -f $ltmpgfs/\${cyc}_\${mem}/SFC.F\${fhh} $ltmpout/fcst/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.sfc
#  fi
#EOF
#fi
#cat >> fcst_31.sh << EOF
#fh=\$((fh+$FCSTOUT))
#done
#EOF

##-------------------------------------------------------------------------------

#echo
#ppnl=$((ppn*2))
#np=1
#pcount=0
#for c in `seq $CYCLES`; do
#  cf=`printf $CYCLE_FMT $c`
#  for m in `seq $fmember`; do
#    mt=$(((c-1) * fmember + m))
#    if [ "${node_m[$mt]}" = "${node[1]}" ]; then
#      pcount=$((pcount+np))
#      if [ "$pcount" -gt "$ppnl" ]; then
#        echo "    wait..."
#        wait
#        pcount=$np
#      fi
#    fi
#    echo "  ${stimef[$c]}, member ${name_m[$mt]} on node '${node_m[$mt]}'"
#    $MPIBIN/mpiexec -host ${node_m[$mt]} bash fcst_31.sh ${name_m[$mt]} $cf "${STIME[$c]}" &
#    sleep $BGJOB_INT
#  done
#done
#echo "    wait..."
#wait

#======================###

#cd $TMPMPI
#cp -f $RUNDIR/datetime.sh .

#cat > fcst_41.sh << EOF
#. datetime.sh
#mem="\$1"
#cyc="\$2"
#stime="\$3"
#Syyyymmddhh=\${stime:0:10}

#mkdir -p $ltmpverify/\${cyc}_\${mem}
#cd $ltmpverify/\${cyc}_\${mem}
#ln -fs $ltmpprog/verify .
#fh=0
#while [ "\$fh" -le "$FCSTLEN" ]; do
#  fhhh=\$(printf '%03d' \$fh)
#  Fyyyymmddhh=\$(datetime \$stime \$fh h | cut -c 1-10)

#  if [ -s "$ltmpout/fcstg/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd" ] &&
#     [ -s "$ltmpout/fcstgp/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd" ]; then
#    cd $ltmpverify/\${cyc}_\${mem}
#    rm -f fcst.grd fcstp.grd obs??.dat ana??.grd
#    ln -s $ltmpout/fcstg/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd fcst.grd
#    ln -s $ltmpout/fcstgp/\${Syyyymmddhh}/\${mem}/\${Fyyyymmddhh}.grd fcstp.grd
####### only support shared disk
#    cat $OBS/obs\${Fyyyymmddhh}/t.dat > obs01.dat
#    cat $OBS/obs\${Fyyyymmddhh}/t-1.dat >> obs01.dat
#    cat $OBS/obs\${Fyyyymmddhh}/t+1.dat >> obs01.dat
#    ln -s $ANLGRDP/\${Fyyyymmddhh}.grd ana01.grd
##    ln -s $ANLGRDP2/\${Fyyyymmddhh}.grd ana02.grd
#######
#    ./verify > /dev/null 2>&1

#    mkdir -p $ltmpout/verfo1/\${fhhh}/\${mem}
#    mkdir -p $ltmpout/verfa1/\${fhhh}/\${mem}
#    mkdir -p $ltmpout/verfa2/\${fhhh}/\${mem}
#    mv -f vrfobs01.dat $ltmpout/verfo1/\${fhhh}/\${mem}/\${Fyyyymmddhh}.dat
#    mv -f vrfana01.dat $ltmpout/verfa1/\${fhhh}/\${mem}/\${Fyyyymmddhh}.dat
##    mv -f vrfana02.dat $ltmpout/verfa2/\${fhhh}/\${mem}/\${Fyyyymmddhh}.dat
#  fi
#fh=\$((fh+$FCSTOUT))
#done
#EOF

##-------------------------------------------------------------------------------

#echo
#ppnl=$ppn
##ppnl=$((ppn*2))
#np=1
#pcount=0
#for c in `seq $CYCLES`; do
#  cf=`printf $CYCLE_FMT $c`
#  for m in `seq $fmember`; do
#    mt=$(((c-1) * fmember + m))
#    if [ "${node_m[$mt]}" = "${node[1]}" ]; then
#      pcount=$((pcount+np))
#      if [ "$pcount" -gt "$ppnl" ]; then
#        echo "    wait..."
#        wait
#        pcount=$np
#      fi
#    fi
#    echo "  ${stimef[$c]}, member ${name_m[$mt]} on node '${node_m[$mt]}'"
#    $MPIBIN/mpiexec -host ${node_m[$mt]} bash fcst_41.sh ${name_m[$mt]} $cf "${STIME[$c]}" &
#    sleep $BGJOB_INT
#  done
#done
#echo "    wait..."
#wait

#-------------------------------------------------------------------------------
}

#===============================================================================
