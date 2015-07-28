#!/bin/bash
#===============================================================================
#
#  Script to post-process the SCALE model outputs.
#  November 2014  created,  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 5)); then
  cat >&2 << EOF

[post_scale_init.sh] Post-process the SCALE model outputs.

Usage: $0 MYRANK STIME MKINIT MEM TMPDIR

  MYRANK   My rank number (not used)
  STIME    Start time (format: YYYYMMDDHHMMSS)
  MKINIT   Make initial condition as well?
            0: No
            1: Yes
  MEM      Name of the ensemble member
  TMPDIR   Temporary directory to run the model

EOF
  exit 1
fi

MYRANK="$1"; shift
STIME="$1"; shift
MKINIT="$1"; shift
MEM="$1"; shift
TMPDIR="$1"

initbaselen=20

#===============================================================================

mkdir -p $TMPOUT/${STIME}/bdy/${MEM}
mv -f $TMPDIR/boundary*.nc $TMPOUT/${STIME}/bdy/${MEM}

if ((MKINIT == 1)); then
  mkdir -p $TMPOUT/${STIME}/anal/${MEM}
  for ifile in $(cd $TMPDIR ; ls init_*.nc 2> /dev/null); do
    mv -f $TMPDIR/${ifile} $TMPOUT/${STIME}/anal/${MEM}/init${ifile:$initbaselen}
  done
elif ((OCEAN_INPUT == 1 && OCEAN_FORMAT == 99)); then
  mkdir -p $TMPOUT/${STIME}/anal/${MEM}
  for ifile in $(cd $TMPDIR ; ls init_*.nc 2> /dev/null); do
    mv -f $TMPDIR/${ifile} $TMPOUT/${STIME}/anal/${MEM}/init_ocean${ifile:$initbaselen}
  done
fi

if ((LOG_OPT <= 2)); then
  mkdir -p $TMPOUT/${STIME}/log/scale_init
  if [ -f "$TMPDIR/init_LOG${SCALE_LOG_SFX}" ]; then
    mv -f $TMPDIR/init_LOG${SCALE_LOG_SFX} $TMPOUT/${STIME}/log/scale_init/${MEM}_init_LOG${SCALE_LOG_SFX}
  fi
fi

#===============================================================================

exit 0
