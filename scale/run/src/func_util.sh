#!/bin/bash
#===============================================================================
#
#  Common utilities (using built-in 'datetime' program)
#  August 2014, Guo-Yuan Lien
#
#  *Require source 'config.main' first.
#
#===============================================================================

safe_init_tmpdir () {
#-------------------------------------------------------------------------------
# Safely initialize a temporary directory
#
# Usage: safe_init_tmpdir DIRNAME
#
#   DIRNAME  The temporary directory
#
#-------------------------------------------------------------------------------

local DIRNAME="$1"



#echo "###### $DIRNAME ######"



#-------------------------------------------------------------------------------

if [ -z "$DIRNAME" ]; then
  echo "[Warning] $FUNCNAME: '\$DIRNAME' is not set." >&2
  exit 1
fi

mkdir -p $DIRNAME
res=$? && ((res != 0)) && exit $res

if [ ! -d "$DIRNAME" ]; then
  echo "[Error] $FUNCNAME: '$DIRNAME' is not a directory." >&2
  exit 1
fi
if [ ! -O "$DIRNAME" ]; then
  echo "[Error] $FUNCNAME: '$DIRNAME' is not owned by you." >&2
  exit 1
fi

rm -fr $DIRNAME/*
res=$? && ((res != 0)) && exit $res

#-------------------------------------------------------------------------------
}

#===============================================================================

safe_rm_tmpdir () {
#-------------------------------------------------------------------------------
# Safely remove a temporary directory
#
# Usage: safe_rm_tmpdir DIRNAME
#
#   DIRNAME  The temporary directory
#
#-------------------------------------------------------------------------------

local DIRNAME="$1"



#echo "!!!!!! $DIRNAME !!!!!!"



#-------------------------------------------------------------------------------

if [ -z "$DIRNAME" ]; then
  echo "[Error] $FUNCNAME: '\$DIRNAME' is not set." >&2
  exit 1
fi
if [ ! -e "$DIRNAME" ]; then
  return 0
fi
if [ ! -d "$DIRNAME" ]; then
  echo "[Error] $FUNCNAME: '$DIRNAME' is not a directory." >&2
  exit 1
fi
if [ ! -O "$DIRNAME" ]; then
  echo "[Error] $FUNCNAME: '$DIRNAME' is not owned by you." >&2
  exit 1
fi

rm -fr $DIRNAME
res=$? && ((res != 0)) && exit $res

#-------------------------------------------------------------------------------
}

#===============================================================================

mpirunf () {
#-------------------------------------------------------------------------------
# Submit a MPI job according to nodefile
#
# Usage: mpirunf NODEFILE RUNDIR PROG [ARGS]
#
#   NODEFILE  Name of nodefile (omit the directory $NODEFILE_DIR)
#   RUNDIR    Working directory
#             -: the current directory
#   PROG      Program
#   ARGS      Arguments passed into the program
#
# Other input variables:
#   $NODEFILE_DIR  Directory of nodefiles
#-------------------------------------------------------------------------------

if (($# < 3)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local NODEFILE="$1"; shift
local RUNDIR="$1"; shift
local PROG="$1"; shift
local ARGS="$@"

#-------------------------------------------------------------------------------

if ((MACHINE_TYPE == 1)); then

  local HOSTLIST=$(cat ${NODEFILE_DIR}/${NODEFILE})
  HOSTLIST=$(echo $HOSTLIST | sed 's/  */,/g')

  if [ "$RUNDIR" == '-' ]; then
    $MPIRUN $HOSTLIST 1 $PROG $ARGS
#    $MPIRUN $HOSTLIST 1 omplace -nt ${THREADS} $PROG $ARGS
  else
    $MPIRUN -d $RUNDIR $HOSTLIST 1 $PROG $ARGS
#    $MPIRUN -d $RUNDIR $HOSTLIST 1 omplace -nt ${THREADS} $PROG $ARGS
  fi

elif ((MACHINE_TYPE == 10 || MACHINE_TYPE == 11 || MACHINE_TYPE == 12)); then

#echo 21
  local vcoordfile="${NODEFILE_DIR}/${NODEFILE}"

#echo 22
#echo $vcoordfile
#echo "mpirunf $NODEFILE $RUNDIR $PROG $ARGS"

  if [ "$RUNDIR" == '-' ]; then
    mpiexec -n $(cat $vcoordfile | wc -l) -vcoordfile $vcoordfile $PROG $ARGS
  else
    ( cd $RUNDIR && mpiexec -n $(cat $vcoordfile | wc -l) -vcoordfile $vcoordfile $PROG $ARGS )
  fi

#echo 23

fi

#-------------------------------------------------------------------------------
}

#===============================================================================

pdbash () {
#-------------------------------------------------------------------------------
# Submit bash parallel scripts according to nodefile, only one process in each node
#
# Usage: pdbash NODEFILE PROC_OPT SCRIPT [ARGS]
#
#   NODEFILE  Name of nodefile (omit the directory $NODEFILE_DIR)
#   PROC_OPT  Options of using processes
#             all:  run the script in all processes listed in $NODEFILE
#             alln: run the script in all nodes list in $NODEFILE, one process per node
#             one:  run the script only in the first process and node in $NODEFILE
#   SCRIPT    Script (the working directory is set to $SCRP_DIR)
#   ARGS      Arguments passed into the program
#
# Other input variables:
#   $NODEFILE_DIR  Directory of nodefiles
#-------------------------------------------------------------------------------

if (($# < 3)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local NODEFILE="$1"; shift
local PROC_OPT="$1"; shift
local SCRIPT="$1"; shift
local ARGS="$@"

if [ -x "$TMPDAT/exec/pdbash" ]; then
  pdbash_exec="$TMPDAT/exec/pdbash"
elif [ -x "$COMMON_DIR/pdbash" ]; then
  pdbash_exec="$COMMON_DIR/pdbash"
else
  echo "[Error] $FUNCNAME: Cannot find 'pdbash' program." >&2
  exit 1
fi

#-------------------------------------------------------------------------------

if ((MACHINE_TYPE == 1)); then

  if [ "$PROC_OPT" == 'all' ]; then
    local HOSTLIST=$(cat ${NODEFILE_DIR}/${NODEFILE})
  elif [ "$PROC_OPT" == 'alln' ]; then
    local HOSTLIST=$(cat ${NODEFILE_DIR}/${NODEFILE} | sort | uniq)
  elif [ "$PROC_OPT" == 'one' ]; then
    local HOSTLIST=$(head -n 1 ${NODEFILE_DIR}/${NODEFILE})
  else
    exit 1
  fi
  HOSTLIST=$(echo $HOSTLIST | sed 's/  */,/g')

  $MPIRUN -d $SCRP_DIR $HOSTLIST 1 $pdbash_exec $SCRIPT $ARGS
#  $MPIRUN -d $SCRP_DIR $HOSTLIST 1 bash $SCRIPT - $ARGS

elif ((MACHINE_TYPE == 10 || MACHINE_TYPE == 11 || MACHINE_TYPE == 12)); then

#echo 11
  if [ "$PROC_OPT" == 'all' ]; then
    local vcoordfile="${NODEFILE_DIR}/${NODEFILE}"
  elif [ "$PROC_OPT" == 'alln' ]; then
    local vcoordfile="${NODEFILE_DIR}/${NODEFILE}_tmp"
    cat ${NODEFILE_DIR}/${NODEFILE} | sort | uniq > $vcoordfile
  elif [ "$PROC_OPT" == 'one' ]; then
    local vcoordfile="${NODEFILE_DIR}/${NODEFILE}_tmp"
    head -n 1 ${NODEFILE_DIR}/${NODEFILE} > $vcoordfile
  else
    exit 1
  fi

#echo 12
#echo "======"
#echo "pdbash $NODEFILE $PROC_OPT $SCRIPT $ARGS"
#echo $vcoordfile
#cat $vcoordfile
#echo "======"

  ( cd $SCRP_DIR && mpiexec -n $(cat $vcoordfile | wc -l) -vcoordfile $vcoordfile $pdbash_exec $SCRIPT $ARGS )

#echo 13

fi

#-------------------------------------------------------------------------------
}

#===============================================================================

job_submit_PJM () {
#-------------------------------------------------------------------------------
# Submit a PJM job.
#
# Usage: job_submit_PJM
#
#   JOBSCRP  Job script
#
# Return variables:
#   jobid  Job ID monitered
#-------------------------------------------------------------------------------

if (($# < 1)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local JOBSCRP="$1"

local rundir=$(dirname $JOBSCRP)
local scrpname=$(basename $JOBSCRP)

#-------------------------------------------------------------------------------

res=$(cd $rundir && pjsub $scrpname 2>&1)
echo $res

if [ -z "$(echo $res | grep '\[ERR.\]')" ]; then
  jobid=$(echo $res | grep 'submitted' | cut -d ' ' -f 6)
  if [ -z "$jobid" ]; then
    echo "[Error] $FUNCNAME: Error found when submitting a job." 1>&2
    exit 1
  fi
else
  echo "[Error] $FUNCNAME: Error found when submitting a job." 1>&2
  exit 1
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

job_end_check_PJM () {
#-------------------------------------------------------------------------------
# Check if a K-computer job has ended.
#
# Usage: job_end_check_PJM JOBID
#
#   JOBID  Job ID monitored
#-------------------------------------------------------------------------------

if (($# < 1)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local JOBID="$1"

#-------------------------------------------------------------------------------

while (($(pjstat $JOBID | sed -n '2p' | awk '{print $10}') >= 1)); do
  sleep 5s
done

#-------------------------------------------------------------------------------
}

#===============================================================================
