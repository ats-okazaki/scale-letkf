#!/bin/bash
#===============================================================================
#
#  Script to prepare the directory of scale run; for each node.
#  June      2015  created  Guo-Yuan Lien
#
#===============================================================================

. config.main

if (($# < 6)); then
  cat >&2 << EOF

[pre_scale_init_node.sh] 

Usage: $0 MYRANK MEM_NODES MEM_NP TMPDIR MEMBER_RUN MEMBER_ITER [SCPCALL]

  MYRANK     My rank number (not used)
  MEM_NODES  Number of nodes for a member
  MEM_NP     Number of processes per member
  TMPDIR     Temporary directory to run the model
  MEMBER_RUN
  MEMBER_ITER
  SCPCALL

EOF
  exit 1
fi

MYRANK="$1"; shift
MEM_NODES="$1"; shift
MEM_NP="$1"; shift
TMPDIR="$1"; shift
MEMBER_RUN="$1"; shift
MEMBER_ITER="$1"; shift
SCPCALL="${1:-cycle}"

#===============================================================================

if [ "$SCPCALL" = 'cycle' ]; then
  MEMBER_TOT=$MEMBER
  ENS_WITH_MEAN_TF='.true.'
  ENS_WITH_MDET_TF='.false.'
  if ((DET_RUN == 1)); then
    ENS_WITH_MDET_TF='.true.'
  fi
else
  MEMBER_TOT=$((MEMBER+1))
  if ((DET_RUN == 1)); then
    MEMBER_TOT=$((MEMBER+2))
  fi
  ENS_WITH_MEAN_TF='.false.'
  ENS_WITH_MDET_TF='.false.'
fi

#===============================================================================

cat $TMPDAT/conf/config.nml.ensmodel | \
    sed -e "/!--MEMBER--/a MEMBER = $MEMBER_TOT," \
        -e "/!--ENS_WITH_MEAN--/a ENS_WITH_MEAN = $ENS_WITH_MEAN_TF," \
        -e "/!--ENS_WITH_MDET--/a ENS_WITH_MDET = $ENS_WITH_MDET_TF," \
        -e "/!--MEMBER_RUN--/a MEMBER_RUN = $MEMBER_RUN," \
        -e "/!--MEMBER_ITER--/a MEMBER_ITER = $MEMBER_ITER," \
        -e "/!--CONF_FILES--/a CONF_FILES = \"${TMPDIR}/@@@@/init.conf\"," \
        -e "/!--PPN--/a PPN = $PPN_APPAR," \
        -e "/!--MEM_NODES--/a MEM_NODES = $MEM_NODES," \
        -e "/!--NUM_DOMAIN--/a NUM_DOMAIN = 1," \
        -e "/!--PRC_DOMAINS--/a PRC_DOMAINS = $MEM_NP," \
    > $TMPDIR/scale-rm_init_ens.conf

#===============================================================================

exit 0
