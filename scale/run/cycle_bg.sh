#!/bin/bash
#===============================================================================
#
#  Run data assimilation cycles.
#
#  November 2014, modified from GFS-LETKF, Guo-Yuan Lien
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    cycle.sh [STIME ETIME ISTEP FSTEP]
#
#  Use settings:
#    config.main
#    config.cycle
#    config.nml.scale_pp_topo
#    config.nml.scale_pp_landuse
#    config.nml.scale_init
#    config.nml.scale
#    config.nml.obsope
#    config.nml.letkf
#
#===============================================================================

cd "$(dirname "$0")"
myname='cycle.sh'
myname1=${myname%.*}

#===============================================================================
# Configuration

. config.main
res=$? && ((res != 0)) && exit $res
. config.$myname1
res=$? && ((res != 0)) && exit $res

. src/func_distribute.sh
. src/func_datetime.sh
. src/func_util.sh
. src/func_$myname1.sh

#-------------------------------------------------------------------------------

if ((USE_RANKDIR == 1)); then
  SCRP_DIR="."
  if ((TMPDAT_MODE <= 2)); then
    TMPDAT="../dat"
  else
    TMPDAT="./dat"
  fi
  if ((TMPRUN_MODE <= 2)); then
    TMPRUN="../run"
  else
    TMPRUN="./run"
  fi
fi

setting "$1" "$2" "$3" "$4"

#-------------------------------------------------------------------------------

mkdir -p $LOGDIR
exec 3>&1 4>&2
#exec 2>> $LOGDIR/${myname1}.err
exec 2> >(tee -a $LOGDIR/${myname1}.err >&2)

echo "[$(datetime_now)] Start $myname $@" >&2

for vname in DIR OUTDIR DATA_TOPO DATA_LANDUSE DATA_BDY DATA_BDY_WRF OBS OBSNCEP MEMBER NNODES PPN THREADS \
             WINDOW_S WINDOW_E LCYCLE LTIMESLOT OUT_OPT LOG_OPT \
             STIME ETIME ISTEP FSTEP; do
  printf '                      %-10s = %s\n' $vname "${!vname}" >&2
done

#-------------------------------------------------------------------------------

if ((BUILTIN_STAGING && ISTEP == 1)); then
  if ((TMPDAT_MODE <= 2 || TMPRUN_MODE <= 2 || TMPOUT_MODE <= 2)); then
    safe_init_tmpdir $TMP
  fi
  if ((TMPDAT_MODE == 3 || TMPRUN_MODE == 3 || TMPOUT_MODE == 3)); then
    safe_init_tmpdir $TMPL
  fi
fi

#===============================================================================
# Determine the distibution schemes

declare -a node
declare -a node_m
declare -a name_m
declare -a mem2node
declare -a mem2proc
declare -a proc2node
declare -a proc2group
declare -a proc2grpproc

#if ((BUILTIN_STAGING && ISTEP == 1)); then
if ((BUILTIN_STAGING)); then
  safe_init_tmpdir $NODEFILE_DIR
  distribute_da_cycle machinefile $NODEFILE_DIR
else
  distribute_da_cycle - - $NODEFILE_DIR/distr
fi

#===============================================================================
# Determine the staging list and then stage in

if ((BUILTIN_STAGING && ISTEP == 1)); then
  echo "[$(datetime_now)] Initialization (stage in)" >&2

  safe_init_tmpdir $STAGING_DIR
  staging_list
  if ((TMPDAT_MODE >= 2 || TMPOUT_MODE >= 2)); then
    pdbash node all $SCRP_DIR/src/stage_in.sh
  fi
fi

#===============================================================================
# Run initialization scripts on all nodes

if ((TMPRUN_MODE <= 2)); then
  pdbash node one $SCRP_DIR/src/init_all_node.sh $myname1
else
  pdbash node all $SCRP_DIR/src/init_all_node.sh $myname1
fi

#===============================================================================
# Run data assimilation cycles

s_flag=1
e_flag=0
time=$STIME
atime=$(datetime $time $LCYCLE s)
loop=0

#-------------------------------------------------------------------------------
while ((time <= ETIME)); do
#-------------------------------------------------------------------------------

  timefmt="$(datetime_fmt ${time})"
  loop=$((loop+1))
  if (($(datetime $time $LCYCLE s) > ETIME)); then
    e_flag=1
  fi
  obstime $time

#-------------------------------------------------------------------------------
# Write the header of the log file

#  exec > $LOGDIR/${myname1}_${time}.log
  exec > >(tee $LOGDIR/${myname1}_${time}.log)

  echo
  echo " +----------------------------------------------------------------+"
  echo " |                          SCALE-LETKF                           |"
  echo " +----------------------------------------------------------------+"
  for s in $(seq $nsteps); do
    if (((s_flag == 0 || s >= ISTEP) && (e_flag == 0 || s <= FSTEP))); then
      printf " | %2d. %-58s |\n" ${s} "${stepname[$s]}"
    fi
  done
  echo " +----------------------------------------------------------------+"
  echo
  echo "  Start time:               ${timefmt}"
  echo "  Forecast length:          $CYCLEFLEN s"
  echo "  Assimilation window:      $WINDOW_S - $WINDOW_E s ($((WINDOW_E-WINDOW_S)) s)"
  echo
  echo "  Observation timeslots:"
  for is in $(seq $slot_s $slot_e); do
    if ((is == slot_b)); then
      printf "  %4d - %s [base]\n" ${is} "${timefmt_sl[$is]}"
    else
      printf "  %4d - %s\n" ${is} "${timefmt_sl[$is]}"
    fi
  done
  echo
  echo "  Nodes used:               $NNODES"
#  if ((MTYPE == 1)); then
    for n in $(seq $NNODES); do
      echo "    ${node[$n]}"
    done
#  fi
  echo
  echo "  Processes per node:       $PPN"
  echo "  Total processes:          $totalnp"
  echo
  echo "  Nodes per SCALE run:      $mem_nodes"
  echo "  Processes per SCALE run:  $mem_np"
  echo
  echo "  Ensemble size:            $MEMBER"
  for m in $(seq $msprd); do
    echo "      ${name_m[$m]}: ${node_m[$m]}"
  done
  echo
  echo "===================================================================="

#-------------------------------------------------------------------------------
# Call functions to run the job

  for s in $(seq $nsteps); do
    if (((s_flag == 0 || s >= ISTEP) && (e_flag == 0 || s <= FSTEP))); then

      echo "[$(datetime_now)] ${time}: ${stepname[$s]}" >&2
      echo
      printf " %2d. %-55s\n" $s "${stepname[$s]}"

      ${stepfunc[$s]}

      echo
      echo "===================================================================="

    fi
  done

#-------------------------------------------------------------------------------
# Online stage out

  if ((ONLINE_STGOUT == 1)); then
    if ((MACHINE_TYPE == 11)); then
      touch $TMP/loop.${loop}.done
    fi
    if ((BUILTIN_STAGING && $(datetime $time $LCYCLE s) <= ETIME)); then
      if ((MACHINE_TYPE == 12)); then
        echo "[$(datetime_now)] ${time}: Online stage out"
        bash $SCRP_DIR/src/stage_out.sh s $loop
        pdbash node all $SCRP_DIR/src/stage_out.sh $loop
      else
        echo "[$(datetime_now)] ${time}: Online stage out (background job)"
        ( bash $SCRP_DIR/src/stage_out.sh s $loop ;
          pdbash node all $SCRP_DIR/src/stage_out.sh $loop ) &
      fi
    fi
  fi

#-------------------------------------------------------------------------------
# Write the footer of the log file

  echo
  echo " +----------------------------------------------------------------+"
  echo " |               SCALE-LETKF successfully completed               |"
  echo " +----------------------------------------------------------------+"
  echo

  exec 1>&3

#-------------------------------------------------------------------------------

  time=$(datetime $time $LCYCLE s)
  atime=$(datetime $time $LCYCLE s)
  s_flag=0

#-------------------------------------------------------------------------------
done
#-------------------------------------------------------------------------------

#===============================================================================
# Stage out

if ((BUILTIN_STAGING)); then
  echo "[$(datetime_now)] Finalization (stage out)" >&2

  if ((TMPOUT_MODE >= 2)); then
    if ((ONLINE_STGOUT == 1)); then
      wait
      bash $SCRP_DIR/src/stage_out.sh s $loop
      pdbash node all $SCRP_DIR/src/stage_out.sh $loop
    else
      bash $SCRP_DIR/src/stage_out.sh s
      pdbash node all $SCRP_DIR/src/stage_out.sh
    fi
  fi

#  if ((TMPDAT_MODE <= 2 || TMPRUN_MODE <= 2 || TMPOUT_MODE <= 2)); then
#    safe_rm_tmpdir $TMP
#  fi
#  if ((TMPDAT_MODE == 3 || TMPRUN_MODE == 3 || TMPOUT_MODE == 3)); then
#    safe_rm_tmpdir $TMPL
#  fi
fi

#===============================================================================

echo "[$(datetime_now)] Finish $myname $@" >&2

exit 0
