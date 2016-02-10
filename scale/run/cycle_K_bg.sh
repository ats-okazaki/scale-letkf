#!/bin/bash
#===============================================================================
#
#  Wrap cycle.sh in a K-computer job script and run it.
#
#  October 2014, created,                 Guo-Yuan Lien
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    cycle_K.sh [STIME ETIME ISTEP FSTEP TIME_LIMIT]
#
#===============================================================================

cd "$(dirname "$0")"
myname1='cycle'

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

if ((TMPDAT_MODE == 1 || TMPRUN_MODE == 1 || TMPOUT_MODE == 1)); then
  echo "[Error] $0: When using 'micro' resource group," >&2
  echo "        \$TMPDAT_MODE, \$TMPRUN_MODE, \$TMPOUT_MODE all need to be 2 or 3." >&2
  exit 1
fi

#-------------------------------------------------------------------------------

setting "$1" "$2" "$3" "$4" "$5"

jobscrp="${myname1}_job.sh"

#-------------------------------------------------------------------------------

echo "[$(datetime_now)] Start $(basename $0) $@"
echo

for vname in DIR OUTDIR DATA_TOPO DATA_LANDUSE DATA_BDY DATA_BDY_WRF OBS OBSNCEP MEMBER NNODES PPN THREADS \
             WINDOW_S WINDOW_E LCYCLE LTIMESLOT OUT_OPT LOG_OPT \
             STIME ETIME ISTEP FSTEP; do
  printf '  %-10s = %s\n' $vname "${!vname}"
done

echo

#-------------------------------------------------------------------------------

safe_init_tmpdir $TMPS

#===============================================================================
# Determine the distibution schemes

# K computer
NNODES_real=$NNODES
PPN_real=$PPN
NNODES=$((NNODES*PPN))
PPN=1

if ((ENABLE_SET == 1)); then          ##
  NNODES_real_all=$((NNODES_real*3))  ##
  NNODES_all=$((NNODES*3))            ##
fi                                    ##

declare -a node
declare -a node_m
declare -a name_m
declare -a mem2node
declare -a mem2proc
declare -a proc2node
declare -a proc2group
declare -a proc2grpproc

safe_init_tmpdir $TMPS/node
if ((ENABLE_SET == 1)); then            ##
  distribute_da_cycle_set - $TMPS/node  ##
else                                    ##
  distribute_da_cycle - $TMPS/node
fi                                      ##

#===============================================================================
# Determine the staging list

STAGING_DIR="$TMPS/staging"

safe_init_tmpdir $STAGING_DIR
staging_list

#-------------------------------------------------------------------------------

cp $SCRP_DIR/config.main $TMPS

echo "SCRP_DIR=\"\$(pwd)\"" >> $TMPS/config.main
echo "NODEFILE_DIR=\"\$(pwd)/node\"" >> $TMPS/config.main
echo "LOGDIR=\"\$(pwd)/log\"" >> $TMPS/config.main

echo "NNODES=$NNODES" >> $TMPS/config.main
echo "PPN=$PPN" >> $TMPS/config.main
echo "NNODES_real=$NNODES_real" >> $TMPS/config.main
echo "PPN_real=$PPN_real" >> $TMPS/config.main

if ((ENABLE_SET == 1)); then                                    ##
  echo "NNODES_all=$NNODES_all" >> $TMPS/config.main            ##
  echo "NNODES_real_all=$NNODES_real_all" >> $TMPS/config.main  ##
                                                                ##
  NNODES=$NNODES_all                                            ##
  NNODES_real=$NNODES_real_all                                  ##
fi                                                              ##

#===============================================================================
# Creat a job script

echo "[$(datetime_now)] Create a job script '$jobscrp'"

if ((NNODES_real > 36864)); then
  rscgrp="huge"
elif ((NNODES_real > 384)); then
  rscgrp="large"
else
  rscgrp="small"
fi

cat > $jobscrp << EOF
#!/bin/sh
##PJM -g ra000015
#PJM -N ${myname1}_${SYSNAME}
#PJM -s
#PJM --rsc-list "node=${NNODES_real}"
#PJM --rsc-list "elapse=${TIME_LIMIT}"
#PJM --rsc-list "rscgrp=${rscgrp}"
##PJM --rsc-list "node-quota=29G"
##PJM --mpi "shape=${NNODES_real}"
#PJM --mpi "proc=$NNODES"
#PJM --mpi assign-online-node
#PJM --stg-transfiles all
EOF

if ((USE_RANKDIR == 1)); then
  echo "#PJM --mpi \"use-rankdir\"" >> $jobscrp
fi

bash $SCRP_DIR/src/stage_K.sh $STAGING_DIR $myname1 >> $jobscrp

#########################
#cat >> $jobscrp << EOF
##PJM --stgout "./* /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/ stgout=all"
##PJM --stgout-dir "./node /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/node stgout=all"
##PJM --stgout-dir "./dat /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/dat stgout=all"
##PJM --stgout-dir "./run /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/run stgout=all"
##PJM --stgout-dir "./out /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/out stgout=all"
##PJM --stgout-dir "./log /volume63/data/ra000015/gylien/scale-letkf/scale/run/tmp/run stgout=all"
#EOF
#########################

cat >> $jobscrp << EOF

. /work/system/Env_base
export OMP_NUM_THREADS=${THREADS}
export PARALLEL=${THREADS}

./cycle_bg.sh "$STIME" "$ETIME" "$ISTEP" "$FSTEP"
EOF

#===============================================================================
# Check the staging list

echo "[$(datetime_now)] Run pjstgchk"
echo

pjstgchk $jobscrp
res=$? && ((res != 0)) && exit $res
echo

#-------------------------------------------------------------------------------
# Run the job

echo "[$(datetime_now)] Run ${myname1} job on PJM"
echo

job_submit_PJM $jobscrp
echo

job_end_check_PJM $jobid

#-------------------------------------------------------------------------------

#safe_rm_tmpdir $TMPS

#===============================================================================

echo "[$(datetime_now)] Finish $(basename $0) $@"

exit 0
