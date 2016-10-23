#!/bin/bash
#===============================================================================
#
#  Script to prepare the directory of LETKF run; for each node.
#  December 2014  created  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 14)); then
  cat >&2 << EOF

[pre_letkf_node.sh]

Usage: $0 MYRANK STIME ATIME TMPDIR OBSDIR MEM_NODES MEM_NP SLOT_START SLOT_END SLOT_BASE TOPO ADAPTINFL RTPS_INFL_OUT NOBS_OUT [MEMBERSEQ]

  MYRANK      My rank number (not used)
  STIME
  ATIME       Analysis time (format: YYYYMMDDHHMMSS)
  TMPDIR      Temporary directory to run the program
  OBSDIR      Directory of SCALE data files
  MEM_NODES   Number of nodes for a member
  MEM_NP      Number of processes for a member
  SLOT_START  Start observation timeslots
  SLOT_END    End observation timeslots
  SLOT_BASE   The base slot
  TOPO        Basename of SCALE topography files
  ADAPTINFL
  RTPS_INFL_OUT
  NOBS_OUT
  MEMBERSEQ

EOF
  exit 1
fi

MYRANK="$1"; shift
STIME="$1"; shift
ATIME="$1"; shift
TMPDIR="$1"; shift
OBSDIR="$1"; shift
MEM_NODES="$1"; shift
MEM_NP="$1"; shift
SLOT_START="$1"; shift
SLOT_END="$1"; shift
SLOT_BASE="$1"; shift
TOPO="$1"; shift
ADAPTINFL="$1"; shift
RTPS_INFL_OUT="$1"; shift
NOBS_OUT="$1"; shift
MEMBERSEQ=${1:-$MEMBER}

#===============================================================================

IO_PNETCDF=".false"
if ((PNETCDF == 1)); then
  IO_PNETCDF=".true."
fi

OBS_IN_NAME_LIST=
for iobs in $(seq $OBSNUM); do
  if [ "${OBSNAME[$iobs]}" != '' ]; then
#    ln -fs $OBSDIR/${OBSNAME[$iobs]}_${ATIME}.dat $TMPDIR/${OBSNAME[$iobs]}.dat
    OBS_IN_NAME_LIST="${OBS_IN_NAME_LIST}'$OBSDIR/${OBSNAME[$iobs]}_${ATIME}.dat', "
  fi
done

OBSDA_RUN_LIST=
for iobs in $(seq $OBSNUM); do
  if [ -n "${OBSOPE_SEPARATE[$iobs]}" ] && ((${OBSOPE_SEPARATE[$iobs]} == 1)); then
    OBSDA_RUN_LIST="${OBSDA_RUN_LIST}.false., "
  else
    OBSDA_RUN_LIST="${OBSDA_RUN_LIST}.true., "
  fi
done

OBSDA_IN='.false.'
if ((OBSOPE_RUN == 1)); then
  OBSDA_IN='.true.'
fi
INFL_MUL_ADAPTIVE='.false.'
if ((ADAPTINFL == 1)); then
  INFL_MUL_ADAPTIVE='.true.'
fi
RELAX_SPREAD_OUT='.false.'
if ((RTPS_INFL_OUT == 1)); then
  RELAX_SPREAD_OUT='.true.'
fi
NOBS_OUT_TF='.false.'
if ((NOBS_OUT == 1)); then
  NOBS_OUT_TF='.true.'
fi

if ((PNETCDF == 1)); then
  HISTORY_IN_BASENAME="${TMPOUT}/${STIME}/hist/@@@@.history"
  GUES_IN_BASENAME="${TMPOUT}/${ATIME}/gues/@@@@.init"
  GUES_OUT_MEAN_BASENAME="${TMPOUT}/${ATIME}/gues/mean.init"
  GUES_OUT_SPRD_BASENAME="${TMPOUT}/${ATIME}/gues/sprd.init"
  ANAL_OUT_BASENAME="${TMPOUT}/${ATIME}/anal/@@@@.init"
  ANAL_OUT_MEAN_BASENAME="${TMPOUT}/${ATIME}/anal/mean.init"
  ANAL_OUT_SPRD_BASENAME="${TMPOUT}/${ATIME}/anal/sprd.init"
  INFL_MUL_IN_BASENAME="${TMPOUT}/${ATIME}/diag/infl"
  INFL_MUL_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/infl"
  RELAX_SPREAD_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/rtps"
  NOBS_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/nobs"
else
  HISTORY_IN_BASENAME="${TMPOUT}/${STIME}/hist/@@@@/history"
  GUES_IN_BASENAME="${TMPOUT}/${ATIME}/gues/@@@@/init"
  GUES_OUT_MEAN_BASENAME="${TMPOUT}/${ATIME}/gues/mean/init"
  GUES_OUT_SPRD_BASENAME="${TMPOUT}/${ATIME}/gues/sprd/init"
  ANAL_OUT_BASENAME="${TMPOUT}/${ATIME}/anal/@@@@/init"
  ANAL_OUT_MEAN_BASENAME="${TMPOUT}/${ATIME}/anal/mean/init"
  ANAL_OUT_SPRD_BASENAME="${TMPOUT}/${ATIME}/anal/sprd/init"
  INFL_MUL_IN_BASENAME="${TMPOUT}/${ATIME}/diag/infl/init"
  INFL_MUL_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/infl/init"
  RELAX_SPREAD_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/rtps/init"
  NOBS_OUT_BASENAME="${TMPOUT}/${ATIME}/diag/nobs/init"
fi

#===============================================================================

cat $TMPDAT/conf/config.nml.letkf | \
    sed -e "/!--MEMBER--/a MEMBER = $MEMBERSEQ," \
        -e "/!--IO_PNETCDF--/a IO_PNETCDF = ${IO_PNETCDF}," \
        -e "/!--OBS_IN_NUM--/a OBS_IN_NUM = $OBSNUM," \
        -e "/!--OBS_IN_NAME--/a OBS_IN_NAME = $OBS_IN_NAME_LIST" \
        -e "/!--OBSDA_RUN--/a OBSDA_RUN = $OBSDA_RUN_LIST" \
        -e "/!--OBSDA_OUT--/a OBSDA_OUT = .true." \
        -e "/!--OBSDA_OUT_BASENAME--/a OBSDA_OUT_BASENAME = \"${TMPOUT}/${ATIME}/obsgues/@@@@/obsda\"," \
        -e "/!--HISTORY_IN_BASENAME--/a HISTORY_IN_BASENAME = \"${HISTORY_IN_BASENAME}\"," \
        -e "/!--SLOT_START--/a SLOT_START = $SLOT_START," \
        -e "/!--SLOT_END--/a SLOT_END = $SLOT_END," \
        -e "/!--SLOT_BASE--/a SLOT_BASE = $SLOT_BASE," \
        -e "/!--SLOT_TINTERVAL--/a SLOT_TINTERVAL = $LTIMESLOT.D0," \
        -e "/!--OBSDA_IN--/a OBSDA_IN = $OBSDA_IN," \
        -e "/!--OBSDA_IN_BASENAME--/a OBSDA_IN_BASENAME = \"${TMPOUT}/${ATIME}/obsgues/@@@@/obsda.ext\"," \
        -e "/!--GUES_IN_BASENAME--/a GUES_IN_BASENAME = \"${GUES_IN_BASENAME}\"," \
        -e "/!--GUES_OUT_MEAN_BASENAME--/a GUES_OUT_MEAN_BASENAME = \"${GUES_OUT_MEAN_BASENAME}\"," \
        -e "/!--GUES_OUT_SPRD_BASENAME--/a GUES_OUT_SPRD_BASENAME = \"${GUES_OUT_SPRD_BASENAME}\"," \
        -e "/!--ANAL_OUT_BASENAME--/a ANAL_OUT_BASENAME = \"${ANAL_OUT_BASENAME}\"," \
        -e "/!--ANAL_OUT_MEAN_BASENAME--/a ANAL_OUT_MEAN_BASENAME = \"${ANAL_OUT_MEAN_BASENAME}\"," \
        -e "/!--ANAL_OUT_SPRD_BASENAME--/a ANAL_OUT_SPRD_BASENAME = \"${ANAL_OUT_SPRD_BASENAME}\"," \
        -e "/!--LETKF_TOPO_IN_BASENAME--/a LETKF_TOPO_IN_BASENAME = \"${TOPO}\"," \
        -e "/!--INFL_MUL_ADAPTIVE--/a INFL_MUL_ADAPTIVE = ${INFL_MUL_ADAPTIVE}," \
        -e "/!--INFL_MUL_IN_BASENAME--/a INFL_MUL_IN_BASENAME = \"${INFL_MUL_IN_BASENAME}\"," \
        -e "/!--INFL_MUL_OUT_BASENAME--/a INFL_MUL_OUT_BASENAME = \"${INFL_MUL_OUT_BASENAME}\"," \
        -e "/!--RELAX_SPREAD_OUT--/a RELAX_SPREAD_OUT = ${RELAX_SPREAD_OUT}," \
        -e "/!--RELAX_SPREAD_OUT_BASENAME--/a RELAX_SPREAD_OUT_BASENAME = \"${RELAX_SPREAD_OUT_BASENAME}\"," \
        -e "/!--NOBS_OUT--/a NOBS_OUT = ${NOBS_OUT_TF}," \
        -e "/!--NOBS_OUT_BASENAME--/a NOBS_OUT_BASENAME = \"${NOBS_OUT_BASENAME}\"," \
        -e "/!--NNODES--/a NNODES = $NNODES," \
        -e "/!--PPN--/a PPN = $PPN," \
        -e "/!--MEM_NODES--/a MEM_NODES = $MEM_NODES," \
        -e "/!--MEM_NP--/a MEM_NP = $MEM_NP," \
    > $TMPDIR/letkf.conf

# Most of these parameters are not important for letkf
cat $TMPDAT/conf/config.nml.scale | \
    sed -e "/!--IO_PNETCDF--/a IO_PNETCDF = ${IO_PNETCDF}," \
    >> $TMPDIR/letkf.conf

#===============================================================================

exit 0
