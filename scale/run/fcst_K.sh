#!/bin/bash
#===============================================================================
#
#  Wrap fcst.sh in a K-computer job script and run it.
#
#  October 2014, created,                 Guo-Yuan Lien
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    fcst_K.sh [STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP TIME_LIMIT]
#
#===============================================================================

cd "$(dirname "$0")"
myname1='fcst'

#===============================================================================
# Configuration

. config.all
(($? != 0)) && exit $?
. config.$myname1
(($? != 0)) && exit $?

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

setting

jobscrp="${myname1}_job.sh"

#-------------------------------------------------------------------------------

echo "[$(datetime_now)] Start $(basename $0) $@"
echo

for vname in DIR OUTDIR ANLWRF OBS OBSNCEP MEMBER NNODES PPN \
             FCSTLEN FCSTOUT EFSOFLEN EFSOFOUT FOUT_OPT \
             STIME ETIME MEMBERS CYCLE CYCLE_SKIP IF_VERF IF_EFSO ISTEP FSTEP; do
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

declare -a procs
declare -a mem2proc
declare -a node
declare -a name_m
declare -a node_m

safe_init_tmpdir $TMPS/node
distribute_fcst "$MEMBERS" $CYCLE - $TMPS/node

#===============================================================================
# Determine the staging list

STAGING_DIR="$TMPS/staging"

safe_init_tmpdir $STAGING_DIR
staging_list

#-------------------------------------------------------------------------------

cp $SCRP_DIR/config.all $TMPS

echo "SCRP_DIR=\"\$(pwd)\"" >> $TMPS/config.all
echo "NODEFILE_DIR=\"\$(pwd)/node\"" >> $TMPS/config.all
echo "LOGDIR=\"\$(pwd)/log\"" >> $TMPS/config.all

echo "NNODES=$NNODES" >> $TMPS/config.all
echo "PPN=$PPN" >> $TMPS/config.all
echo "NNODES_real=$NNODES_real" >> $TMPS/config.all
echo "PPN_real=$PPN_real" >> $TMPS/config.all

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
##PJM --rsc-list "node-quota=29GB"
#PJM --mpi "shape=${NNODES_real}"
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

ls -l .
ls -l dat
ls -l dat/conf

./${myname1}.sh "$ETIME" "$MEMBERS" "$CYCLE" "$CYCLE_SKIP" "$IF_VERF" "$IF_EFSO" "$ISTEP" "$FSTEP"

ls -l .

EOF

#===============================================================================
# Check the staging list

echo "[$(datetime_now)] Run pjstgchk"
echo

pjstgchk $jobscrp
(($? != 0)) && exit $?
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