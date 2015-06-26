#!/bin/bash
#===============================================================================
#
#  Script to post-process the SCALE model outputs.
#  November 2014  created,  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 3)); then
  cat >&2 << EOF

[post_scale_pp.sh] Post-process the scale-les_init outputs.

Usage: $0 MYRANK STIME TMPDIR

  MYRANK   My rank number (not used)
  STIME    Start time (format: YYYYMMDDHHMMSS)
  TMPDIR   Temporary directory to run the model

EOF
  exit 1
fi

MYRANK="$1"; shift
STIME="$1"; shift
TMPDIR="$1"

#===============================================================================

if [ "$TOPO_FORMAT" != 'prep' ]; then
  mkdir -p $TMPOUT/${STIME}/topo
  mv -f $TMPDIR/topo*.nc $TMPOUT/${STIME}/topo
fi

if [ "$LANDUSE_FORMAT" != 'prep' ]; then
  mkdir -p $TMPOUT/${STIME}/landuse
  mv -f $TMPDIR/landuse*.nc $TMPOUT/${STIME}/landuse
fi

if ((LOG_OPT <= 2)); then
  mkdir -p $TMPOUT/${STIME}/log/scale_pp
  if [ -f "$TMPDIR/pp_LOG${SCALE_LOG_SFX}" ]; then
    mv -f $TMPDIR/pp_LOG${SCALE_LOG_SFX} $TMPOUT/${STIME}/log/scale_pp/pp_LOG${SCALE_LOG_SFX}
  fi
fi

if [ "$MEM" == '0001' ] && ((LOG_OPT <= 4)); then ###### using a variable for '0001'
  mkdir -p $TMPOUT/${ATIME}/log/scale_pp_ens
  for q in $(seq $MEM_NP); do
    if [ -e "$TMPDIR/NOUT-$(printf $PROCESS_FMT $((q-1)))" ]; then
      mv -f $TMPDIR/NOUT-$(printf $PROCESS_FMT $((q-1))) $TMPOUT/${ATIME}/log/scale_pp_ens
    fi
  done
fi

#===============================================================================

exit 0
