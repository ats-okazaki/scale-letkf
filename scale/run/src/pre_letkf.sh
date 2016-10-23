#!/bin/bash
#===============================================================================
#
#  Script to prepare the directory of LETKF run; for each member.
#  December 2014  created  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 6)); then
  cat >&2 << EOF

[pre_letkf.sh]

Usage: $0 MYRANK ATIME MEM ADAPTINFL RTPS_INFL_OUT NOBS_OUT

  MYRANK  My rank number (not used)
  ATIME   Analysis time (format: YYYYMMDDHHMMSS)
  MEM     Name of the ensemble member
  ADAPTINFL
  RTPS_INFL_OUT
  NOBS_OUT

EOF
  exit 1
fi

MYRANK="$1"; shift
ATIME="$1"; shift
MEM="$1"; shift
ADAPTINFL="$1"; shift
RTPS_INFL_OUT="$1"; shift
NOBS_OUT="$1"

#===============================================================================

if ((PNETCDF == 1)); then
  if [ "$MEM" == 'mean' ]; then ###### using a variable for 'meanf', 'mean', 'sprd'
    mkdir -p $TMPOUT/${ATIME}/anal
    cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/gues/mean.init.nc
    cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/anal/mean.init.nc
    cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/gues/sprd.init.nc
    cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/anal/sprd.init.nc
    if ((ADAPTINFL == 1)) && [ ! -e "$TMPOUT/${ATIME}/diag/infl.nc" ]; then
      mkdir -p $TMPOUT/${ATIME}/diag
      cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/diag/infl.nc
    fi
    if ((RTPS_INFL_OUT == 1)); then
      mkdir -p $TMPOUT/${ATIME}/diag
      cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/diag/rtps.nc
    fi
    if ((NOBS_OUT == 1)); then
      mkdir -p $TMPOUT/${ATIME}/diag
      cp -f $TMPOUT/${ATIME}/gues/meanf.init.nc $TMPOUT/${ATIME}/diag/nobs.nc
    fi
  else
    mkdir -p $TMPOUT/${ATIME}/obsgues/${MEM}
    mkdir -p $TMPOUT/${ATIME}/anal
    cp -f $TMPOUT/${ATIME}/gues/${MEM}.init.nc $TMPOUT/${ATIME}/anal/${MEM}.init.nc
  fi
else
  if [ "$MEM" == 'mean' ]; then ###### using a variable for 'meanf', 'mean', 'sprd'
    for ifile in $(cd $TMPOUT/${ATIME}/gues/meanf ; ls init*.nc 2> /dev/null); do
      mkdir -p $TMPOUT/${ATIME}/gues/mean
      cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/gues/mean
      mkdir -p $TMPOUT/${ATIME}/anal/mean
      cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/anal/mean
      mkdir -p $TMPOUT/${ATIME}/gues/sprd
      cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/gues/sprd
      mkdir -p $TMPOUT/${ATIME}/anal/sprd
      cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/anal/sprd
      if ((ADAPTINFL == 1)) && [ ! -d "$TMPOUT/${ATIME}/diag/infl" ]; then
        mkdir -p $TMPOUT/${ATIME}/diag/infl
        cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/diag/infl
      fi
      if ((RTPS_INFL_OUT == 1)); then
        mkdir -p $TMPOUT/${ATIME}/diag/rtps
        cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/diag/rtps
      fi
      if ((NOBS_OUT == 1)); then
        mkdir -p $TMPOUT/${ATIME}/diag/nobs
        cp -f $TMPOUT/${ATIME}/gues/meanf/${ifile} $TMPOUT/${ATIME}/diag/nobs
      fi
    done
  else
    mkdir -p $TMPOUT/${ATIME}/obsgues/${MEM}
    for ifile in $(cd $TMPOUT/${ATIME}/gues/${MEM} ; ls init*.nc 2> /dev/null); do
      mkdir -p $TMPOUT/${ATIME}/anal/${MEM}
      cp -f $TMPOUT/${ATIME}/gues/${MEM}/${ifile} $TMPOUT/${ATIME}/anal/${MEM}
    done
  fi
fi

#===============================================================================

exit 0
