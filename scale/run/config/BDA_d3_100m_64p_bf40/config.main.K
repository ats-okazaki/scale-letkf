#!/bin/bash
#===============================================================================
#
#  Main settings for SCALE-LETKF scripts
#
#===============================================================================

PRESET='K_rankdir'                          # 'K' or 'K_rankdir' or 'K_micro'

#===============================================================================

DIR="$(cd "$(pwd)/.." && pwd)"   # Root directory of the SCALE-LETKF

OUTDIR="/volume63/data/hp150019/gylien/exp/scale-letkf/BDA_case130713/d3_100m_100mem_19_1" # Directory for SCALE-LETKF output

#===============================================================================
# Location of model/data files

SCALEDIR="$DIR/../.."                                   # Directory of the SCALE model
DATADIR="/volume63/data/hp150019/gylien/scale-letkf/database"

DATA_TOPO="/volume63/data/hp150019/gylien/scale-letkf/database/topo_prep/BDA_d3_100m_64p_bf40"
DATA_TOPO_BDY_SCALE="/volume63/data/hp150019/gylien/scale-letkf/database/topo_prep/BDA_d2_1km_42p_bf10"
DATA_LANDUSE="/volume63/data/hp150019/gylien/scale-letkf/database/landuse_prep/BDA_d3_100m_64p_bf40"
DATA_BDY_SCALE="/volume63/data/hp150019/gylien/exp/scale-letkf/BDA_case130713/d2_1km_100mem"
DATA_BDY_SCALE_PRC_NUM_X=7
DATA_BDY_SCALE_PRC_NUM_Y=6
DATA_BDY_SCALE_PREP=
DATA_BDY_WRF=
DATA_BDY_NICAM=

OBS="/volume63/data/hp150019/gylien/obs/QCED_100M_v3"    # directory of observation data in LETKF obs format
OBSNCEP=                                                 # directory of observation data in NCEP BUFR format

#===============================================================================
# model/data file options

TOPO_FORMAT='DEM50M'    # 'prep': Use prepared topo files in $DATA_TOPO
                        # 'GTOPO30' (requires compatible 'config.nml.scale_pp')
                        # 'DEM50M'  (requires compatible 'config.nml.scale_pp')

LANDUSE_FORMAT='LU100M' # 'prep': Use prepared landuse files in $DATA_LANDUSE
                        # 'GLCCv2' (requires compatible 'config.nml.scale_pp')
                        # 'LU100M' (requires compatible 'config.nml.scale_pp')
LANDUSE_UPDATE=0        # 0: Time-invariant landuse files
                        # 1: Time-variant landuse files

BDY_FORMAT=1            # 0: SCALE boundary files (with exactly same domain settings; do not need additional preprocessing)
                        # 1: SCALE history (requires compatible 'config.nml.scale_init')
                        # 2: WRF           (requires compatible 'config.nml.scale_init')
                        # 3: NICAM         (requires compatible 'config.nml.scale_init')
BDY_ENS=1               # 0: Fixed boundary files for all memebers
                        # 1: Ensemble boundary files

BDYINT=30
BDYCYCLE_INT=3600

OCEAN_INPUT=0           # 0: No ocean input (use cycling ocean variables)
                        # 1: Update the ocean variables every cycle

OCEAN_FORMAT=99         # 0: SCALE init files (with exactly same domain settings; do not need additional preprocessing)
                        # 99: From the same file as used in generating the boundary conditions ($BDY_FORMAT)

OBSNUM=1
OBSNAME[1]=radar

#===============================================================================
# Cycling settings

WINDOW_S=30        # SCALE forecast time when the assimilation window starts (second)
WINDOW_E=30        # SCALE forecast time when the assimilation window ends (second)
LCYCLE=30          # Length of a DA cycle (second)
LTIMESLOT=30       # Timeslot interval for 4D-LETKF (second)

#===============================================================================
# Parallelization settings

MEMBER=3           # Ensemble size

NNODES=256         # Number of nodes
PPN=1              # Number of processes per node

THREADS=8          # Number of threads per process

SCALE_NP=64        # Number of processes to run SCALE

BGJOB_INT='0.1s'   # Interval of multiple background job submissions

#===============================================================================
# Temporary directories to store runtime files

ONLINE_STGOUT=0             # Stage out right after each cycle (do not wait until the end of the job)?
                            #  0: No
                            #  1: Yes

SYSNAME="$(basename $OUTDIR)"                # A unique name in the machine
TMPSUBDIR="scale-letkf_${SYSNAME}"           # (used to identify multiple runs in the same time)

TMP="/scratch/$(id -ng)/gylien/$TMPSUBDIR" # Temporary directory shared among all nodes
TMPS="$DIR/tmp/$TMPSUBDIR"  # Temporary directory only on the server node
#TMPL=

#===============================================================================
# Environmental settings

MPIRUN="mpiexec"
if (which $MPIRUN > /dev/null 2>&1); then
  MPIRUN=$(which $MPIRUN)
fi

SCP='cp -L'
SCP_HOSTPREFIX=''
#SCP="scp -q"
#SCP_HOSTPREFIX="XXXX:"

PYTHON="python"

#BUFRBIN=

#===============================================================================
# Machine-independent source file

. config.rc

#===============================================================================
