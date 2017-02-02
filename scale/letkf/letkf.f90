PROGRAM letkf
!=======================================================================
!
! [PURPOSE:] Main program of LETKF
!
! [HISTORY:]
!   01/16/2009   Takemasa Miyoshi  created
!   October 2014 Guo-Yuan Lien     modified for SCALE model
!   ............ See git history for the following revisions
!
!=======================================================================
!$USE OMP_LIB
  USE common
  USE common_mpi
  USE common_scale
  USE common_mpi_scale
  USE common_obs_scale
  USE common_nml
  USE letkf_obs
  USE letkf_tools
  use obsope_tools, only: &
    obsope_cal

  IMPLICIT NONE
  REAL(r_size),ALLOCATABLE :: gues3d(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: gues2d(:,:,:)
  REAL(r_size),ALLOCATABLE :: anal3d(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: anal2d(:,:,:)
  REAL(r_dble) :: rtimer00,rtimer
  INTEGER :: ierr
  CHARACTER(7) :: stdoutf='-000000'
  CHARACTER(11) :: timer_fmt='(A30,F10.2)'

  character(len=6400) :: cmd1, cmd2, icmd
  character(len=10) :: myranks
  integer :: iarg

!-----------------------------------------------------------------------
! Initial settings
!-----------------------------------------------------------------------

  CALL initialize_mpi_scale
  rtimer00 = MPI_WTIME()

  if (command_argument_count() >= 4) then
    call get_command_argument(3, icmd)
    call chdir(trim(icmd))
    write (myranks, '(I10)') myrank
    call get_command_argument(4, icmd)
    cmd1 = 'bash ' // trim(icmd) // ' letkf_1' // ' ' // trim(myranks)
    cmd2 = 'bash ' // trim(icmd) // ' letkf_2' // ' ' // trim(myranks)
    do iarg = 5, command_argument_count()
      call get_command_argument(iarg, icmd)
      cmd1 = trim(cmd1) // ' ' // trim(icmd)
      cmd2 = trim(cmd2) // ' ' // trim(icmd)
    end do
  end if

  if (command_argument_count() >= 2) then
    call get_command_argument(2, icmd)
    if (trim(icmd) /= '') then
      WRITE(stdoutf(2:7), '(I6.6)') myrank
!      WRITE(6,'(3A,I6.6)') 'STDOUT goes to ',trim(icmd)//stdoutf,' for MYRANK ', myrank
      OPEN(6,FILE=trim(icmd)//stdoutf)
      WRITE(6,'(A,I6.6,2A)') 'MYRANK=',myrank,', STDOUTF=',trim(icmd)//stdoutf
    end if
  end if

  WRITE(6,'(A)') '============================================='
  WRITE(6,'(A)') '  LOCAL ENSEMBLE TRANSFORM KALMAN FILTERING  '
  WRITE(6,'(A)') '                                             '
  WRITE(6,'(A)') '   LL      EEEEEE  TTTTTT  KK  KK  FFFFFF    '
  WRITE(6,'(A)') '   LL      EE        TT    KK KK   FF        '
  WRITE(6,'(A)') '   LL      EEEEE     TT    KKK     FFFFF     '
  WRITE(6,'(A)') '   LL      EE        TT    KK KK   FF        '
  WRITE(6,'(A)') '   LLLLLL  EEEEEE    TT    KK  KK  FF        '
  WRITE(6,'(A)') '                                             '
  WRITE(6,'(A)') '             WITHOUT LOCAL PATCH             '
  WRITE(6,'(A)') '                                             '
  WRITE(6,'(A)') '          Coded by Takemasa Miyoshi          '
  WRITE(6,'(A)') '  Based on Ott et al (2004) and Hunt (2005)  '
  WRITE(6,'(A)') '  Tested by Miyoshi and Yamane (2006)        '
  WRITE(6,'(A)') '============================================='

!-----------------------------------------------------------------------
! Pre-processing scripts
!-----------------------------------------------------------------------

  if (command_argument_count() >= 4) then
    write (6,'(A)') 'Run pre-processing scripts'
    write (6,'(A,I6.6,3A)') 'MYRANK ',myrank,' is running a script: [', trim(cmd1), ']'
    call system(trim(cmd1))
  end if

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(PRE_SCRIPT):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------

  call set_common_conf(nprocs)

  call read_nml_obs_error
  call read_nml_obsope
  call read_nml_letkf
  call read_nml_letkf_obs
  call read_nml_letkf_var_local
  call read_nml_letkf_monitor
  call read_nml_letkf_radar
  call read_nml_letkf_h08

  call set_mem_node_proc(MEMBER+2)

  call set_scalelib

  if (myrank_use) then

    call set_common_scale
    call set_common_mpi_scale
    call set_common_obs_scale

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(INITIALIZE):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Read observations
!-----------------------------------------------------------------------

    allocate(obs(OBS_IN_NUM))
    call read_obs_all_mpi(obs)

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(READ_OBS):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Observation operator
!-----------------------------------------------------------------------

    if (OBSDA_IN) then
      call get_nobs_da_mpi(nobs_extern)
    else
      nobs_extern = 0
    end if

    !
    ! Compute observation operator, return the results in obsda
    ! with additional space for externally processed observations
    !
    call obsope_cal(obsda_return=obsda, nobs_extern=nobs_extern)

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(OBS_OPERATOR):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Process observation data
!-----------------------------------------------------------------------

    CALL set_letkf_obs

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(PROCESS_OBS):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! First guess ensemble
!-----------------------------------------------------------------------

    ALLOCATE(gues3d(nij1,nlev,nens,nv3d))
    ALLOCATE(gues2d(nij1,nens,nv2d))
    ALLOCATE(anal3d(nij1,nlev,nens,nv3d))
    ALLOCATE(anal2d(nij1,nens,nv2d))

    !
    ! LETKF GRID setup
    !
    call set_common_mpi_grid

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(SET_GRID):',rtimer-rtimer00
    rtimer00=rtimer

    !
    ! READ GUES
    !
    call read_ens_mpi(gues3d, gues2d)

    if (mmdetin /= mmdet) then
      gues3d(:,:,mmdet,:) = gues3d(:,:,mmdetin,:)
      gues2d(:,mmdet,:) = gues2d(:,mmdetin,:)
    end if

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(READ_GUES):',rtimer-rtimer00
    rtimer00=rtimer

    !
    ! WRITE ENS MEAN and SPRD
    !
    call write_ensmean(GUES_MEAN_INOUT_BASENAME, gues3d, gues2d, calced=.false.,&
                       monit=DEPARTURE_STAT, caption='OBSERVATIONAL DEPARTURE STATISTICS [GUESS]')

    if (GUES_SPRD_OUT) then
      call write_enssprd(GUES_SPRD_OUT_BASENAME, gues3d, gues2d)
    end if

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(GUES_MEAN):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Data Assimilation
!-----------------------------------------------------------------------

    !
    ! LETKF
    !
    CALL das_letkf(gues3d,gues2d,anal3d,anal2d)

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(DAS_LETKF):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Analysis ensemble
!-----------------------------------------------------------------------

    !
    ! COMPUTE ENS MEAN and SPRD
    !
    call ensmean_grd(MEMBER, nij1, anal3d, anal2d)
    ! write analysis mean later in write_ens_mpi

    if (ANAL_SPRD_OUT) then
      call write_enssprd(ANAL_SPRD_OUT_BASENAME, anal3d, anal2d)
    end if

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(ANAL_MEAN):',rtimer-rtimer00
    rtimer00=rtimer

    !
    ! WRITE ANAL and ENS MEAN
    !
!    CALL MPI_BARRIER(MPI_COMM_a,ierr)

    call write_ens_mpi(anal3d, anal2d, &
                       monit=DEPARTURE_STAT, caption='OBSERVATIONAL DEPARTURE STATISTICS [ANALYSIS]')

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(WRITE_ANAL):',rtimer-rtimer00
    rtimer00=rtimer

!!-----------------------------------------------------------------------
!! Monitor
!!-----------------------------------------------------------------------
!  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
!  CALL monit_obs
!!
!  rtimer = MPI_WTIME()
!  WRITE(6,timer_fmt) '### TIMER(MONIT_MEAN):',rtimer-rtimer00
!  rtimer00=rtimer

    deallocate(obs)

    CALL unset_common_mpi_scale

    call unset_scalelib

  else ! [ myrank_use ]

    write (6, '(A,I6.6,A)') 'MYRANK=',myrank,': This process is not used!'

  end if ! [ myrank_use ]

!-----------------------------------------------------------------------

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(FINALIZE):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------
! Post-processing scripts
!-----------------------------------------------------------------------

  if (command_argument_count() >= 4) then
    write (6,'(A)') 'Run post-processing scripts'
    write (6,'(A,I6.6,3A)') 'MYRANK ',myrank,' is running a script: [', trim(cmd2), ']'
    call system(trim(cmd2))
  end if

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(POST_SCRIPT):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------
! Finalize
!-----------------------------------------------------------------------

  CALL finalize_mpi_scale

  STOP
END PROGRAM letkf
