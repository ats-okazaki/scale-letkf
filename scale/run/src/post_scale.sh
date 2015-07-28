#!/bin/bash
#===============================================================================
#
#  Script to post-process the SCALE model outputs.
#  November 2014  created,  Guo-Yuan Lien
#
#===============================================================================

. config.main
. src/func_datetime.sh

if (($# < 6)); then
  cat >&2 << EOF

[post_scale.sh] Post-process the SCALE model outputs.

Usage: $0 MYRANK MEM_NP STIME MEM FCSTLEN TMPDIR

  MYRANK   My rank number (not used)
  MEM_NP   Number of processes per member (not used !!!)
  STIME    Start time (format: YYYYMMDDHHMMSS)
  MEM      Name of the ensemble member
  FCSTLEN  Forecast length (second)
  TMPDIR   Temporary directory to run the model
  SCPCALL  Called from which script? (fcst/cycle)

EOF
  exit 1
fi

MYRANK="$1"; shift
MEM_NP="$1"; shift
STIME="$1"; shift
MEM="$1"; shift
FCSTLEN="$1"; shift
TMPDIR="$1"; shift
SCPCALL="$1"

ATIME=$(datetime $STIME $LCYCLE s)

restartbaselen=23  # 7 + 16

#===============================================================================


#echo
#echo '##### post #####'
#ls -lL $TMPDIR
#echo


#if [ "$SCPCALL" == 'fcst' ] && ((OUT_OPT <= 2)); then
#  mkdir -p $TMPOUT/${STIME}/fcst/${MEM}
#  mv -f $TMPDIR/history*.nc $TMPOUT/${STIME}/fcst/${MEM}
#elif [ "$SCPCALL" == 'cycle' ]; then
#  mkdir -p $TMPOUT/${ATIME}/gues/${MEM}
#  mv -f $TMPDIR/history*.nc $TMPOUT/${ATIME}/gues/${MEM}
#fi

#if [ "$SCPCALL" == 'fcst' ] && ((OUT_OPT <= 1)); then
#  mkdir -p $TMPOUT/${STIME}/fcst/${MEM}
#  for ifile in $(cd $TMPDIR ; ls restart*.nc); do
#    mv -f ${TMPDIR}/${ifile} $TMPOUT/${STIME}/fcst/${MEM}/init_$(datetime ${STIME} $FCSTLEN s)${ifile:$restartbaselen}
#  done
#elif [ "$SCPCALL" == 'cycle' ]; then
#  mkdir -p $TMPOUT/${ATIME}/gues/${MEM}
#  for ifile in $(cd $TMPDIR ; ls restart*.nc); do
#    mv -f ${TMPDIR}/${ifile} $TMPOUT/${ATIME}/gues/${MEM}/init${ifile:$restartbaselen}
#  done
#fi

if [ "$SCPCALL" == 'fcst' ]; then
  mkdir -p $TMPOUT/${STIME}/fcst/${MEM}
  mv -f $TMPDIR/history*.nc $TMPOUT/${STIME}/fcst/${MEM}
  file_prefix=$(cd $TMPDIR ; ls restart*.nc | head -n 1) # pick up the first restart output. ###### TO DO: explicitly calculate the time string???
  for ifile in $(cd $TMPDIR ; ls ${file_prefix:0:$restartbaselen}*.nc); do
    mv -f ${TMPDIR}/${ifile} $TMPOUT/${STIME}/fcst/${MEM}/init_$(datetime ${STIME} $FCSTLEN s)${ifile:$restartbaselen}
  done
elif [ "$SCPCALL" == 'cycle' ]; then
  MEMtmp=$MEM
  if [ "$MEM" == 'mean' ]; then
    MEMtmp='meanf'
  fi
  mkdir -p $TMPOUT/${ATIME}/gues/${MEMtmp}
  mv -f $TMPDIR/history*.nc $TMPOUT/${ATIME}/gues/${MEMtmp}
  file_prefix=$(cd $TMPDIR ; ls restart*.nc | head -n 1) # pick up the first restart output. ###### TO DO: explicitly calculate the time string???
  for ifile in $(cd $TMPDIR ; ls ${file_prefix:0:$restartbaselen}*.nc); do
    mv -f ${TMPDIR}/${ifile} $TMPOUT/${ATIME}/gues/${MEMtmp}/init${ifile:$restartbaselen}
  done
fi

if ((LOG_OPT <= 3)); then
  mkdir -p $TMPOUT/${STIME}/log/scale
  if [ -f "$TMPDIR/LOG${SCALE_LOG_SFX}" ]; then
    mv -f $TMPDIR/LOG${SCALE_LOG_SFX} $TMPOUT/${STIME}/log/scale/${MEM}_LOG${SCALE_LOG_SFX}
  fi
fi

mkdir -p $TMPOUT/${STIME}/log/scale
if [ -f "$TMPDIR/latlon_domain_catalogue.txt" ]; then
  mv -f $TMPDIR/latlon_domain_catalogue.txt $TMPOUT/${STIME}/log/scale/${MEM}_latlon_domain_catalogue.txt
fi

#===============================================================================

exit 0
