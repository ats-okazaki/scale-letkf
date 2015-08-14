#!/bin/bash
#===============================================================================
#
#  Script to prepare the directory of LETKF run; for each node.
#  December 2014  created  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 10)); then
  cat >&2 << EOF

[pre_letkf_node.sh]

Usage: $0 MYRANK ATIME TMPDIR EXECDIR OBSDIR MEM_NODES MEM_NP SLOT_START SLOT_END SLOT_BASE

  MYRANK      My rank number (not used)
  ATIME       Analysis time (format: YYYYMMDDHHMMSS)
  TMPDIR      Temporary directory to run the program
  EXECDIR     Directory of SCALE executable files
  OBSDIR      Directory of SCALE data files
  MEM_NODES   Number of nodes for a member
  MEM_NP      Number of processes for a member
  SLOT_START  Start observation timeslots
  SLOT_END    End observation timeslots
  SLOT_BASE   The base slot

EOF
  exit 1
fi

MYRANK="$1"; shift
ATIME="$1"; shift
TMPDIR="$1"; shift
EXECDIR="$1"; shift 
OBSDIR="$1"; shift
MEM_NODES="$1"; shift
MEM_NP="$1"; shift
SLOT_START="$1"; shift
SLOT_END="$1"; shift
SLOT_BASE="$1"

#===============================================================================

mkdir -p $TMPDIR
rm -fr $TMPDIR/*

ln -fs $EXECDIR/letkf $TMPDIR

for iobs in $(seq $OBSNUM); do
  if [ "${OBSNAME[$iobs]}" != '' ]; then
    ln -fs $OBSDIR/${OBSNAME[$iobs]}_${ATIME}.dat $TMPDIR/${OBSNAME[$iobs]}.dat
  fi
done

#===============================================================================

cat $TMPDAT/conf/config.nml.letkf | \
    sed -e "s/\[MEMBER\]/ MEMBER = $MEMBER,/" \
        -e "s/\[SLOT_START\]/ SLOT_START = $SLOT_START,/" \
        -e "s/\[SLOT_END\]/ SLOT_END = $SLOT_END,/" \
        -e "s/\[SLOT_BASE\]/ SLOT_BASE = $SLOT_BASE,/" \
        -e "s/\[SLOT_TINTERVAL\]/ SLOT_TINTERVAL = $LTIMESLOT.D0,/" \
        -e "s/\[NNODES\]/ NNODES = $NNODES,/" \
        -e "s/\[PPN\]/ PPN = $PPN,/" \
        -e "s/\[MEM_NODES\]/ MEM_NODES = $MEM_NODES,/" \
        -e "s/\[MEM_NP\]/ MEM_NP = $MEM_NP,/" \
    > $TMPDIR/letkf.conf

# These parameters are not important for obsope
cat $TMPDAT/conf/config.nml.scale | \
    sed -e "s/\[TIME_STARTDATE\]/ TIME_STARTDATE = 2014, 1, 1, 0, 0, 0,/" \
        -e "s/\[TIME_DURATION\]/ TIME_DURATION = 60.D0,/" \
        -e "s/\[TIME_DT_ATMOS_RESTART\]/ TIME_DT_ATMOS_RESTART = 60.D0,/" \
        -e "s/\[TIME_DT_OCEAN_RESTART\]/ TIME_DT_OCEAN_RESTART = 60.D0,/" \
        -e "s/\[TIME_DT_LAND_RESTART\]/ TIME_DT_LAND_RESTART = 60.D0,/" \
        -e "s/\[TIME_DT_URBAN_RESTART\]/ TIME_DT_URBAN_RESTART = 60.D0,/" \
        -e "s/\[HISTORY_DEFAULT_TINTERVAL\]/ HISTORY_DEFAULT_TINTERVAL = 60.D0,/" \
    >> $TMPDIR/letkf.conf

#===============================================================================

exit 0
