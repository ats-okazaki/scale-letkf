PROGRAM letkf
!=======================================================================
!
! [PURPOSE:] Main program of LETKF
!
! [HISTORY:]
!   01/16/2009 Takemasa Miyoshi  created
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

  IMPLICIT NONE
  REAL(r_size),ALLOCATABLE :: gues3d(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: gues2d(:,:,:)
  REAL(r_size),ALLOCATABLE :: anal3d(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: anal2d(:,:,:)
  REAL(r_dble) :: rtimer00,rtimer
  INTEGER :: ierr
  CHARACTER(11) :: stdoutf='NOUT-000000'
  CHARACTER(11) :: timer_fmt='(A30,F10.2)'

!  TYPE(obs_info) :: obs
!  TYPE(obs_da_value) :: obsval

  character(len=6400) :: cmd1, cmd2, icmd
  character(len=10) :: myranks
  integer :: iarg

!-----------------------------------------------------------------------
! Initial settings
!-----------------------------------------------------------------------

! New added for SYNC
  external conn_init
  external conn_finalize
  external pub_client_connect
  external pub_recv_data
  external pub_recv_data1
  external pub_server_connect
  character a*5, b*3
  a = "letkf"
  b = "obs"
  !  call conn_init("sample.ini", a)
  CALL initialize_mpi
  call conn_init("sample.ini", a)
  rtimer00 = MPI_WTIME()
  call sleep(2)
  call pub_client_connect(b)
  call pub_server_connect(a)
  call pub_recv_data(a)
  call pub_recv_data1(b)
  rtimer00 = MPI_WTIME()
!
  if (command_argument_count() >= 3) then
    call get_command_argument(2, icmd)
    call chdir(trim(icmd))
    write (myranks, '(I10)') myrank
    call get_command_argument(3, icmd)
    cmd1 = 'bash ' // trim(icmd) // ' letkf_1' // ' ' // trim(myranks)
    cmd2 = 'bash ' // trim(icmd) // ' letkf_2' // ' ' // trim(myranks)
    do iarg = 4, command_argument_count()
      call get_command_argument(iarg, icmd)
      cmd1 = trim(cmd1) // ' ' // trim(icmd)
      cmd2 = trim(cmd2) // ' ' // trim(icmd)
    end do
  end if
!
  WRITE(stdoutf(6:11), '(I6.6)') myrank
!  WRITE(6,'(3A,I6.6)') 'STDOUT goes to ',stdoutf,' for MYRANK ', myrank
  OPEN(6,FILE=stdoutf)
  WRITE(6,'(A,I6.6,2A)') 'MYRANK=',myrank,', STDOUTF=',stdoutf
!
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
!  WRITE(6,'(A)') '              LETKF PARAMETERS               '
!  WRITE(6,'(A)') ' ------------------------------------------- '
!  WRITE(6,'(A,I15)')   '  nbv          :',nbv
!  WRITE(6,'(A,F15.2)') '  sigma_obs    :',sigma_obs
!  WRITE(6,'(A,F15.2)') '  sigma_obsv   :',sigma_obsv
!  WRITE(6,'(A,F15.2)') '  sigma_obst   :',sigma_obst
!  WRITE(6,'(A)') '============================================='

!-----------------------------------------------------------------------
! Pre-processing scripts
!-----------------------------------------------------------------------

  if (command_argument_count() >= 3) then
    write (6,'(A)') 'Run pre-processing scripts'
    write (6,'(A,I6.6,3A)') 'MYRANK ',myrank,' is running a script: [', trim(cmd1), ']'
    call system(trim(cmd1))
  end if

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  rtimer = MPI_WTIME()
  WRITE(6,timer_fmt) '### TIMER(PRE_SCRIPT):',rtimer-rtimer00
  rtimer00=rtimer

!-----------------------------------------------------------------------

  call set_common_conf

  call read_nml_letkf
  call read_nml_letkf_obs
  call read_nml_letkf_obserr
  call read_nml_letkf_obs_radar

  call set_mem_node_proc(MEMBER+1,NNODES,PPN,MEM_NODES,MEM_NP)

  if (myrank_use) then

    call set_scalelib

    call set_common_scale
    call set_common_mpi_scale
    call set_common_obs_scale

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(INITIALIZE):',rtimer-rtimer00
    rtimer00=rtimer

!-----------------------------------------------------------------------
! Observations
!-----------------------------------------------------------------------

    !
    ! Read observations
    !
    call read_obs_all(obs, radarlon, radarlat, radarz)

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(READ_OBS):',rtimer-rtimer00
    rtimer00=rtimer

    !
    ! Read and process observation data
    !
    CALL set_letkf_obs

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(PROCESS_OBS):',rtimer-rtimer00
    rtimer00=rtimer



!!  write (6,*) obsda%idx
!!  write (6,*) obsda%val(3)
!!  write (6,*) obsda%ensval(:,3)
!!  write (6,*) obsda%qc(3)
!!  write (6,*) obsda%ri(3)
!!  write (6,*) obsda%rj(3)
!!  write (6,*) obsda2%idx
!!  write (6,*) obsda2%val(3)
!!  write (6,*) obsda2%ensval(:,3)
!!  write (6,*) obsda2%qc(3)
!!  write (6,*) obsda2%ri(3)
!!  write (6,*) obsda2%rj(3)
!  write (6,*) obsda2%ri
!  write (6,*) obsda2%rj


!-----------------------------------------------------------------------
! First guess ensemble
!-----------------------------------------------------------------------

    ALLOCATE(gues3d(nij1,nlev,MEMBER,nv3d))
    ALLOCATE(gues2d(nij1,MEMBER,nv2d))
    ALLOCATE(anal3d(nij1,nlev,MEMBER,nv3d))
    ALLOCATE(anal2d(nij1,MEMBER,nv2d))


    !
    ! LETKF GRID setup
    !
    call set_common_mpi_grid('topo')

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(SET_GRID):',rtimer-rtimer00
    rtimer00=rtimer



    !
    ! READ GUES
    !

    call read_ens_mpi('gues',gues3d,gues2d)

!  write (6,*) gues3d(20,:,3,iv3d_t)
!!  write (6,*) gues2d


    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(READ_GUES):',rtimer-rtimer00
    rtimer00=rtimer


    !
    ! WRITE ENS MEAN and SPRD
    !
    CALL write_ensmspr_mpi('gues',gues3d,gues2d,obs,obsda2)
!
    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(GUES_MEAN):',rtimer-rtimer00
    rtimer00=rtimer
!!-----------------------------------------------------------------------
!! Data Assimilation
!!-----------------------------------------------------------------------
    !
    ! LETKF
    !

!    anal3d = gues3d
!    anal2d = gues2d

    CALL das_letkf(gues3d,gues2d,anal3d,anal2d)
!
    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(DAS_LETKF):',rtimer-rtimer00
    rtimer00=rtimer
!-----------------------------------------------------------------------
! Analysis ensemble
!-----------------------------------------------------------------------
    !
    ! WRITE ANAL
    !
!    CALL MPI_BARRIER(MPI_COMM_a,ierr)

    CALL write_ens_mpi('anal',anal3d,anal2d)

    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(WRITE_ANAL):',rtimer-rtimer00
    rtimer00=rtimer
    !
    ! WRITE ENS MEAN and SPRD
    !
    CALL write_ensmspr_mpi('anal',anal3d,anal2d,obs,obsda2)
    !
    CALL MPI_BARRIER(MPI_COMM_a,ierr)
    rtimer = MPI_WTIME()
    WRITE(6,timer_fmt) '### TIMER(ANAL_MEAN):',rtimer-rtimer00
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

  if (command_argument_count() >= 3) then
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

  call conn_finalize
  CALL finalize_mpi

  STOP
END PROGRAM letkf
