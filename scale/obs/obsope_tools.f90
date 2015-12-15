MODULE obsope_tools
!=======================================================================
!
! [PURPOSE:] Observation operator tools
!
! [HISTORY:]
!   November 2014  Guo-Yuan Lien  created
!
!=======================================================================
!$USE OMP_LIB
  USE common
  USE common_mpi
  USE common_scale
  USE common_mpi_scale
  USE common_obs_scale

!  use common_scalelib

  use common_nml

  use scale_process, only: &
       PRC_myrank
!       MPI_COMM_d => LOCAL_COMM_WORLD

  use scale_grid_index, only: &
    KHALO, IHALO, JHALO

  IMPLICIT NONE
  PUBLIC

!-----------------------------------------------------------------------
! General parameters
!-----------------------------------------------------------------------



CONTAINS
!!-----------------------------------------------------------------------
!! Read namelist for obsope
!!-----------------------------------------------------------------------
!subroutine read_nml_obsope
!  implicit none

!  call read_nml_letkf
!  call read_nml_letkf_prc

!  return
!end subroutine read_nml_obsope
!!-----------------------------------------------------------------------
!! Read namelist for obsmake
!!-----------------------------------------------------------------------
!subroutine read_nml_obsmake
!  implicit none

!  call read_nml_letkf
!  call read_nml_letkf_prc
!  call read_nml_letkf_obsmake

!  return
!end subroutine read_nml_obsmake
!-----------------------------------------------------------------------
! PARAM_LETKF_OBSMAKE
!-----------------------------------------------------------------------
!subroutine read_nml_letkf_obsmake
!  implicit none
!  integer :: ierr

!  namelist /PARAM_LETKF_OBSMAKE/ &
!    OBSERR_U, &
!    OBSERR_V, &
!    OBSERR_T, &
!    OBSERR_Q, &
!    OBSERR_RH, &
!    OBSERR_PS, &
!    OBSERR_RADAR_REF, &
!    OBSERR_RADAR_VR

!  rewind(IO_FID_CONF)
!  read(IO_FID_CONF,nml=PARAM_LETKF_OBSMAKE,iostat=ierr)
!  if (ierr < 0) then !--- missing
!    write(6,*) 'xxx Not found namelist. Check!'
!    stop
!  elseif (ierr > 0) then !--- fatal error
!    write(6,*) 'xxx Not appropriate names in namelist LETKF_PARAM_OBSMAKE. Check!'
!    stop
!  endif

!  return
!end subroutine read_nml_letkf_obsmake

!-----------------------------------------------------------------------
! Observation operator calculation
!-----------------------------------------------------------------------
SUBROUTINE obsope_cal(obs)
  IMPLICIT NONE

  TYPE(obs_info),INTENT(IN) :: obs(nobsfiles)
  type(obs_da_value) :: obsda
  REAL(r_size),ALLOCATABLE :: v3dg(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: v2dg(:,:,:)

  integer :: it,islot,proc,im,iof
  integer :: n,nn,nslot,nproc,nproc_0,nprocslot
!  real(r_size) :: rig,rjg,ri,rj,rk
  real(r_size) :: rig,rjg,rk
  real(r_size),allocatable :: ri(:),rj(:)
  real(r_size) :: ritmp,rjtmp
  real(r_size) :: slot_lb,slot_ub

! -- for Himawari-8 obs --
  INTEGER :: nallprof ! H08: Num of all profiles (entire domain) required by RTTOV
  INTEGER :: ns ! H08 obs count
  INTEGER :: nprof_H08 ! num of H08 obs
  REAL(r_size),ALLOCATABLE :: ri_H08(:),rj_H08(:)
  REAL(r_size),ALLOCATABLE :: lon_H08(:),lat_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_ri_H08(:),tmp_rj_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_lon_H08(:),tmp_lat_H08(:)

  REAL(r_size),ALLOCATABLE :: yobs_H08(:),plev_obs_H08(:)
  INTEGER :: ch
  INTEGER,ALLOCATABLE :: qc_H08(:)

!-----------------------------------------------------------------------

  integer :: ierr
  REAL(r_dble) :: rrtimer00,rrtimer

!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
  rrtimer00 = MPI_WTIME()


  obsda%nobs = 0
  do iof = 1, nobsfiles
    obsda%nobs = obsda%nobs + obs(iof)%nobs
  end do
  call obs_da_value_allocate(obsda,0)
  allocate ( ri(obsda%nobs) )
  allocate ( rj(obsda%nobs) )

  allocate ( v3dg (nlevh,nlonh,nlath,nv3dd) )
  allocate ( v2dg (nlonh,nlath,nv2dd) )

  do it = 1, nitmax
    im = proc2mem(1,it,myrank+1)
    if (im >= 1 .and. im <= MEMBER) then
      write (6,'(A,I6.6,A,I4.4,A,I6.6)') 'MYRANK ',myrank,' is processing member ', &
            im, ', subdomain id #', proc2mem(2,it,myrank+1)

!write(6,*) '%%%%%%', MPI_WTIME(), 0

      nproc = 0
      obsda%qc = iqc_time

      do islot = SLOT_START, SLOT_END
        slot_lb = (real(islot-SLOT_BASE,r_size) - 0.5d0) * SLOT_TINTERVAL
        slot_ub = (real(islot-SLOT_BASE,r_size) + 0.5d0) * SLOT_TINTERVAL
        write (6,'(A,I3,A,F9.1,A,F9.1,A)') 'Slot #', islot-SLOT_START+1, ': time interval (', slot_lb, ',', slot_ub, '] sec'

        call read_ens_history_iter('hist',it,islot,v3dg,v2dg)
!  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)


!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
  rrtimer = MPI_WTIME()
  WRITE(6,'(A,I3,A,I3,A,4x,F15.7)') '###### obsope_cal:read_ens_history_iter:',it,':',islot,':',rrtimer-rrtimer00
  rrtimer00=rrtimer


        do iof = 1, nobsfiles

          nslot = 0
          nprocslot = 0

!write(6,*) '%%%===', MPI_WTIME(), 'im:', im, 'islot:', islot, 'iof:', iof

          IF(iof /= 3)THEN ! except H08 obs ! H08

            ! do this small computtion first, without OpenMP
            nproc_0 = nproc
            do n = 1, obs(iof)%nobs
              if (obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub) then
                nslot = nslot + 1
                call phys2ij(obs(iof)%lon(n),obs(iof)%lat(n),rig,rjg)
                call rij_g2l_auto(proc,rig,rjg,ritmp,rjtmp)

                if (PRC_myrank == proc) then
                  nproc = nproc + 1
                  nprocslot = nprocslot + 1
                  obsda%set(nproc) = iof
                  obsda%idx(nproc) = n
                  obsda%ri(nproc) = rig
                  obsda%rj(nproc) = rjg
                  ri(nproc) = ritmp
                  rj(nproc) = rjtmp
                end if ! [ PRC_myrank == proc ]
              end if ! [ obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub ]
            end do ! [ n = 1, obs%nobs ]

#ifdef H08
          ELSEIF( iof == 3) THEN ! for H08 obs (iof = 3) ! H08

            nprof_H08 = 0
            nproc_0 = nproc
            nallprof = obs(iof)%nobs/nch

            ALLOCATE(tmp_ri_H08(nallprof))
            ALLOCATE(tmp_rj_H08(nallprof))
            ALLOCATE(tmp_lon_H08(nallprof))
            ALLOCATE(tmp_lat_H08(nallprof))

            do n = 1, nallprof
              ns = (n - 1) * nch + 1
              if (obs(iof)%dif(ns) > slot_lb .and. obs(iof)%dif(ns) <= slot_ub) then
                nslot = nslot + 1
                call phys2ij(obs(iof)%lon(ns),obs(iof)%lat(ns),rig,rjg)
                call rij_g2l_auto(proc,rig,rjg,ritmp,rjtmp)

                if (PRC_myrank == proc) then
                  nprof_H08 = nprof_H08 + 1 ! num of prof in myrank node
                  tmp_ri_H08(nprof_H08) = ritmp
                  tmp_rj_H08(nprof_H08) = rjtmp
                  tmp_lon_H08(nprof_H08) = obs(iof)%lon(ns)
                  tmp_lat_H08(nprof_H08) = obs(iof)%lat(ns)

                  nproc = nproc + nch
                  nprocslot = nprocslot + 1
                  obsda%set(nproc-nch+1:nproc) = iof
                  obsda%ri(nproc-nch+1:nproc) = rig
                  obsda%rj(nproc-nch+1:nproc) = rjg
                  ri(nproc-nch+1:nproc) = ritmp
                  rj(nproc-nch+1:nproc) = rjtmp
                  do ch = 1, nch
                    obsda%idx(nproc-nch+ch) = ns + ch - 1
                  enddo

                end if ! [ PRC_myrank == proc ]
              end if ! [ obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub ]
            end do ! [ n = 1, nallprof ]

            IF(nprof_H08 >=1)THEN
              ALLOCATE(ri_H08(nprof_H08))
              ALLOCATE(rj_H08(nprof_H08))
              ALLOCATE(lon_H08(nprof_H08))
              ALLOCATE(lat_H08(nprof_H08))

              ri_H08 = tmp_ri_H08(1:nprof_H08)
              rj_H08 = tmp_rj_H08(1:nprof_H08)
              lon_H08 = tmp_lon_H08(1:nprof_H08)
              lat_H08 = tmp_lat_H08(1:nprof_H08)

            ENDIF

            DEALLOCATE(tmp_ri_H08,tmp_rj_H08)
            DEALLOCATE(tmp_lon_H08,tmp_lat_H08)

#endif
          ENDIF ! end of nproc count [if (iof = 3)]



!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
  rrtimer = MPI_WTIME()
  WRITE(6,'(A,I3,A,I3,A,I3,A,F15.7)') '###### obsope_cal:obsope_step_1:        ',it,':',islot,':',iof,':',rrtimer-rrtimer00
  rrtimer00=rrtimer


          ! then do this heavy computation with OpenMP

          IF(iof /= 3)THEN ! H08


!write(6,*) '%%%===', MPI_WTIME(), nproc_0 + 1, nproc

!$OMP PARALLEL DO SCHEDULE(DYNAMIC) PRIVATE(nn,n,rk)
            do nn = nproc_0 + 1, nproc
              n = obsda%idx(nn)

!if (mod(nn,50) == 0) then
!  write(6,*) '%%%%%%', MPI_WTIME(), nn
!end if

              if (obs(iof)%elm(n) == id_radar_ref_obs .or. obs(iof)%elm(n) == id_radar_vr_obs) then
                call phys2ijkz(v3dg(:,:,:,iv3dd_hgt),ri(nn),rj(nn),obs(iof)%lev(n),rk,obsda%qc(nn))
              else
                call phys2ijk(v3dg(:,:,:,iv3dd_p),obs(iof)%elm(n),ri(nn),rj(nn),obs(iof)%lev(n),rk,obsda%qc(nn))
              end if


!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
!  rrtimer = MPI_WTIME()
!  WRITE(6,'(A,I3,A,I3,A,I3,A,I8,A,F15.7)') '###### obsope_cal:obsope_step_2_phys2ijkz:',it,':',islot,':',iof,':',nn,':',rrtimer-rrtimer00
!  rrtimer00=rrtimer


              if (obsda%qc(nn) == iqc_good) then
                select case (obsfileformat(iof))
                case (1)
                  call Trans_XtoY(obs(iof)%elm(n),ri(nn),rj(nn),rk, &
                                  obs(iof)%lon(n),obs(iof)%lat(n),v3dg,v2dg,obsda%val(nn),obsda%qc(nn))
                case (2)
                  call Trans_XtoY_radar(obs(iof)%elm(n),obs(iof)%meta(1),obs(iof)%meta(2),obs(iof)%meta(3),ri(nn),rj(nn),rk, &
                                        obs(iof)%lon(n),obs(iof)%lat(n),obs(iof)%lev(n),v3dg,v2dg,obsda%val(nn),obsda%qc(nn))
                  if (obsda%qc(nn) == iqc_ref_low) obsda%qc(nn) = iqc_good ! when process the observation operator, we don't care if reflectivity is too small

                !!!!!! may not need to do this at this stage...
                !if (obs(iof)%elm(n) == id_radar_ref_obs) then
                !  obsda%val(nn) = 10.0d0 * log10(obsda%val(nn))
                !end if
                !!!!!!

                end select
              end if


!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
!  rrtimer = MPI_WTIME()
!  WRITE(6,'(A,I3,A,I3,A,I3,A,I8,A,F15.7)') '###### obsope_cal:obsope_step_2_Trans_XtoY_radar:',it,':',islot,':',iof,':',nn,':',rrtimer-rrtimer00
!  rrtimer00=rrtimer


            end do ! [ nn = nproc_0 + 1, nproc ]
!$OMP END PARALLEL DO

#ifdef H08
          ELSEIF((iof == 3).and.(nprof_H08 >=1 ))THEN ! H08
! -- Note: Trans_XtoY_H08 is called without OpenMP but it can use a parallel (with OpenMP) RTTOV routine
!

            ALLOCATE(yobs_H08(nprof_H08*nch))
            ALLOCATE(plev_obs_H08(nprof_H08*nch))
            ALLOCATE(qc_H08(nprof_H08*nch))

            CALL Trans_XtoY_H08(nprof_H08,ri_H08,rj_H08,&
                                lon_H08,lat_H08,v3dg,v2dg,&
                                yobs_H08,plev_obs_H08,&
                                qc_H08)

            obsda%qc(nproc_0+1:nproc) = iqc_obs_bad

            ns = 0
            DO nn = nproc_0 + 1, nproc
              ns = ns + 1

              obsda%val(nn) = yobs_H08(ns)
              obsda%qc(nn) = qc_H08(ns)

!
!  NOTE: T.Honda (10/16/2015)
!  The original H08 obs does not inlcude the level information.
!  However, we have the level information derived by RTTOV (plev_obs_H08) here, 
!  so that we substitute the level information into obsda%lev.  
!  The substituted level information is used in letkf_tools.f90
!
              obsda%lev(nn) = plev_obs_H08(ns)

!              write(6,'(a,f12.1,i9)')'H08 debug_plev',obsda%lev(nn),nn

            END DO ! [ nn = nproc_0 + 1, nproc ]

            DEALLOCATE(ri_H08, rj_H08)
            DEALLOCATE(lon_H08, lat_H08)
            DEALLOCATE(yobs_H08, plev_obs_H08)
            DEALLOCATE(qc_H08)

#endif
          ENDIF ! H08

          write (6,'(3A,I10)') ' -- [', trim(obsfile(iof)), '] nobs in the slot = ', nslot
          write (6,'(3A,I6,A,I10)') ' -- [', trim(obsfile(iof)), '] nobs in the slot and processed by rank ' &
                                    , myrank, ' = ', nprocslot


!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
  rrtimer = MPI_WTIME()
  WRITE(6,'(A,I3,A,I3,A,I3,A,F15.7)') '###### obsope_cal:obsope_step_2:        ',it,':',islot,':',iof,':',rrtimer-rrtimer00
  rrtimer00=rrtimer


        end do ! [ do iof = 1, nobsfiles ]



!      IF(NINT(elem(n)) == id_ps_obs .AND. odat(n) < -100.0d0) THEN
!        CYCLE
!      END IF
!      IF(NINT(elem(n)) == id_ps_obs) THEN
!        CALL itpl_2d(v2d(:,:,iv2d_orog),ri,rj,dz)
!        rk = rlev(n) - dz
!        IF(ABS(rk) > threshold_dz) THEN ! pressure adjustment threshold
!!          WRITE(6,'(A)') '* PS obs vertical adjustment beyond threshold'
!!          WRITE(6,'(A,F10.2,A,F6.2,A,F6.2,A)') '*   dz=',rk,&
!!           & ', (lon,lat)=(',elon(n),',',elat(n),')'
!          CYCLE
!        END IF
!      END IF

      end do ! [ islot = SLOT_START, SLOT_END ]

!write(6,*) '%%%%%%', MPI_WTIME(), nproc

      obsda%nobs = nproc

      write (6,'(A,I6.6,A,I4.4,A,I6.6)') 'MYRANK ',myrank,' finishes processing member ', &
            im, ', subdomain id #', proc2mem(2,it,myrank+1)
      write (6,'(A,I8,A)') ' -- ', nproc, ' observations found'

      write (obsdafile(7:10),'(I4.4)') im
      write (obsdafile(12:17),'(I6.6)') proc2mem(2,it,myrank+1)
      call write_obs_da(obsdafile,obsda,0)


!  CALL MPI_BARRIER(MPI_COMM_a,ierr)
  rrtimer = MPI_WTIME()
  WRITE(6,'(A,I3,A,8x,F15.7)') '###### obsope_cal:write_obs_da:         ',it,':',rrtimer-rrtimer00
  rrtimer00=rrtimer


    end if ! [ im >= 1 .and. im <= MEMBER ]

  end do ! [ it = 1, nitmax ]

  deallocate ( ri, rj, v3dg, v2dg )

!write(6,*) ri(1),rj(1)
!write(6,*) '$$$$ 0'
!!  deallocate ( ri )
!write(6,*) '$$$$ 1'
!!  deallocate ( rj )
!write(6,*) '$$$$ 2'
!!  deallocate ( v3dg )
!write(6,*) '$$$$ 3'
!!  deallocate ( v2dg )
!write(6,*) '$$$$ 4'

end subroutine obsope_cal

!-----------------------------------------------------------------------
! Observation generator calculation
!-----------------------------------------------------------------------
SUBROUTINE obsmake_cal(obs)
  IMPLICIT NONE

  TYPE(obs_info),INTENT(INOUT) :: obs(nobsfiles)
  REAL(r_size),ALLOCATABLE :: v3dg(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: v2dg(:,:,:)

  integer :: islot,proc
  integer :: n,nslot,nproc,nprocslot,ierr,iqc,iof
  integer :: nobsmax,nobsall
  real(r_size) :: rig,rjg,ri,rj,rk
  real(r_size) :: slot_lb,slot_ub
  real(r_size),allocatable :: bufr(:)
  real(r_size),allocatable :: error(:)

  CHARACTER(10) :: obsoutfile = 'obsout.dat'

! -- for Himawari-8 obs --
  INTEGER :: nallprof ! H08: Num of all profiles (entire domain) required by RTTOV
  INTEGER :: ns ! H08 obs count
  INTEGER :: nprof_H08 ! num of H08 obs
  REAL(r_size),ALLOCATABLE :: ri_H08(:),rj_H08(:)
  REAL(r_size),ALLOCATABLE :: lon_H08(:),lat_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_ri_H08(:),tmp_rj_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_lon_H08(:),tmp_lat_H08(:)

  REAL(r_size),ALLOCATABLE :: yobs_H08(:),plev_obs_H08(:)
  INTEGER,ALLOCATABLE :: qc_H08(:)
  INTEGER,ALLOCATABLE :: idx_H08(:) ! index array
  INTEGER :: ich

!-----------------------------------------------------------------------

  write (6,'(A,I6.6,A,I6.6)') 'MYRANK ',myrank,' is processing subdomain id #', proc2mem(2,1,myrank+1)

  allocate ( v3dg (nlevh,nlonh,nlath,nv3dd) )
  allocate ( v2dg (nlonh,nlath,nv2dd) )

  do iof = 1, nobsfiles
    obs(iof)%dat = 0.0d0
  end do

  nproc = 0
  do islot = SLOT_START, SLOT_END
    slot_lb = (real(islot-SLOT_BASE,r_size) - 0.5d0) * SLOT_TINTERVAL
    slot_ub = (real(islot-SLOT_BASE,r_size) + 0.5d0) * SLOT_TINTERVAL
    write (6,'(A,I3,A,F9.1,A,F9.1,A)') 'Slot #', islot-SLOT_START+1, ': time interval (', slot_lb, ',', slot_ub, '] sec'

    call read_ens_history_iter('hist',1,islot,v3dg,v2dg)

    do iof = 1, nobsfiles
      IF(iof/=3)THEN ! except H08 obs
        nslot = 0
        nprocslot = 0
        do n = 1, obs(iof)%nobs

          if (obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub) then
            nslot = nslot + 1

            call phys2ij(obs(iof)%lon(n),obs(iof)%lat(n),rig,rjg)
            call rij_g2l_auto(proc,rig,rjg,ri,rj)

  !          if (PRC_myrank == 0) then
  !            print *, proc, rig, rjg, ri, rj
  !          end if

            if (proc < 0 .and. PRC_myrank == 0) then ! if outside of the global domain, processed by PRC_myrank == 0
              obs(iof)%dat(n) = undef
            end if

            if (PRC_myrank == proc) then
              nproc = nproc + 1
              nprocslot = nprocslot + 1

  !IF(NINT(elem(n)) == id_ps_obs) THEN
  !  CALL itpl_2d(v2d(:,:,iv2d_orog),ri,rj,dz)
  !  rk = rlev(n) - dz
  !  IF(ABS(rk) > threshold_dz) THEN ! pressure adjustment threshold
  !    ! WRITE(6,'(A)') '* PS obs vertical adjustment beyond threshold'
  !    ! WRITE(6,'(A,F10.2,A,F6.2,A,F6.2,A)') '* dz=',rk,&
  !    ! & ', (lon,lat)=(',elon(n),',',elat(n),')'
  !    CYCLE
  !  END IF
  !END IF

              if (obs(iof)%elm(n) == id_radar_ref_obs .or. obs(iof)%elm(n) == id_radar_vr_obs) then
                call phys2ijkz(v3dg(:,:,:,iv3dd_hgt),ri,rj,obs(iof)%lev(n),rk,iqc)
              else
                call phys2ijk(v3dg(:,:,:,iv3dd_p),obs(iof)%elm(n),ri,rj,obs(iof)%lev(n),rk,iqc)
              end if

              if (iqc /= iqc_good) then
                obs(iof)%dat(n) = undef
              else
                select case (obsfileformat(iof))
                case (1)
                  call Trans_XtoY(obs(iof)%elm(n),ri,rj,rk, &
                                  obs(iof)%lon(n),obs(iof)%lat(n),v3dg,v2dg,obs(iof)%dat(n),iqc)
                case (2)
                  call Trans_XtoY_radar(obs(iof)%elm(n),obs(iof)%meta(1),obs(iof)%meta(2),obs(iof)%meta(3),ri,rj,rk, &
                                        obs(iof)%lon(n),obs(iof)%lat(n),obs(iof)%lev(n),v3dg,v2dg,obs(iof)%dat(n),iqc)
                end select

 !!! For radar observation, when reflectivity value is too low, do not generate ref/vr observations
 !!! No consideration of the terrain blocking effects.....

                if (iqc /= iqc_good) then
                  obs(iof)%dat(n) = undef
                end if
              end if

            end if ! [ PRC_myrank == proc ]

          end if ! [ obs%dif(n) > slot_lb .and. obs%dif(n) <= slot_ub ]

        end do ! [ n = 1, obs%nobs ]

#ifdef H08
! -- H08 part --
      ELSEIF(iof==3)THEN ! H08
        nslot = 0
        nprocslot = 0
        nprof_H08 = 0

        nallprof = obs(iof)%nobs/nch

        ALLOCATE(tmp_ri_H08(nallprof))
        ALLOCATE(tmp_rj_H08(nallprof))
        ALLOCATE(tmp_lon_H08(nallprof))
        ALLOCATE(tmp_lat_H08(nallprof))
        ALLOCATE(idx_H08(nallprof))

        do n = 1, nallprof
          ns = (n - 1) * nch + 1
          if (obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub) then
            nslot = nslot + 1

            call phys2ij(obs(iof)%lon(ns),obs(iof)%lat(ns),rig,rjg)
            call rij_g2l_auto(proc,rig,rjg,ri,rj)


            if (proc < 0 .and. PRC_myrank == 0) then ! if outside of the global domain, processed by PRC_myrank == 0
              obs(iof)%dat(ns:ns+nch-1) = undef
            end if

            if (PRC_myrank == proc) then
              nprof_H08 = nprof_H08 + 1 ! num of prof in myrank node
              idx_H08(nprof_H08) = ns ! idx of prof in myrank node
              tmp_ri_H08(nprof_H08) = ri
              tmp_rj_H08(nprof_H08) = rj
              tmp_lon_H08(nprof_H08) = obs(iof)%lon(ns)
              tmp_lat_H08(nprof_H08) = obs(iof)%lat(ns)

              nproc = nproc + nch
              nprocslot = nprocslot + nch

            end if ! [ PRC_myrank == proc ]

          end if ! [ obs%dif(n) > slot_lb .and. obs%dif(n) <= slot_ub ]

        end do ! [ n = 1, nallprof ]

        IF(nprof_H08 >=1)THEN
          ALLOCATE(ri_H08(nprof_H08))
          ALLOCATE(rj_H08(nprof_H08))
          ALLOCATE(lon_H08(nprof_H08))
          ALLOCATE(lat_H08(nprof_H08))

          ri_H08 = tmp_ri_H08(1:nprof_H08)
          rj_H08 = tmp_rj_H08(1:nprof_H08)
          lon_H08 = tmp_lon_H08(1:nprof_H08)
          lat_H08 = tmp_lat_H08(1:nprof_H08)

          ALLOCATE(yobs_H08(nprof_H08*nch))
          ALLOCATE(plev_obs_H08(nprof_H08*nch))
          ALLOCATE(qc_H08(nprof_H08*nch))

          CALL Trans_XtoY_H08(nprof_H08,ri_H08,rj_H08,&
                              lon_H08,lat_H08,v3dg,v2dg,&
                              yobs_H08,plev_obs_H08,&
                              qc_H08)

          DO n = 1, nprof_H08
            ns = idx_H08(n)

            obs(iof)%lon(ns:ns+nch-1)=lon_H08(n:n+nch-1)
            obs(iof)%lat(ns:ns+nch-1)=lat_H08(n:n+nch-1)

            DO ich = 1, nch-1
              IF(qc_H08(n+ich-1) == iqc_good)THEN
                obs(iof)%dat(ns+ich-1)=undef
              ELSE
                obs(iof)%dat(ns+ich-1)=yobs_H08(n+ich-1)
              ENDIF
            ENDDO
          ENDDO

        ENDIF

        DEALLOCATE(tmp_ri_H08,tmp_rj_H08)
        DEALLOCATE(tmp_lon_H08,tmp_lat_H08)


! -- end of H08 part --
#endif
      ENDIF

    end do ! [ iof = 1, nobsfiles ]

    write (6,'(3A,I10)') ' -- [', trim(obsfile(iof)), '] nobs in the slot = ', nslot
    write (6,'(3A,I6,A,I10)') ' -- [', trim(obsfile(iof)), '] nobs in the slot and processed by rank ', myrank, ' = ', nprocslot

  end do ! [ islot = SLOT_START, SLOT_END ]

  deallocate ( v3dg, v2dg )

  if (PRC_myrank == 0) then
    nobsmax = 0
    nobsall = 0
    do iof = 1, nobsfiles
      if (obs(iof)%nobs > nobsmax) nobsmax = obs(iof)%nobs
      nobsall = nobsall + obs(iof)%nobs
    end do

    allocate ( bufr(nobsmax) )
    allocate ( error(nobsall) )

    call com_randn(nobsall, error) ! generate all random numbers at the same time
    ns = 0
  end if

  do iof = 1, nobsfiles

    call MPI_REDUCE(obs(iof)%dat,bufr(1:obs(iof)%nobs),obs(iof)%nobs,MPI_r_size,MPI_SUM,0,MPI_COMM_d,ierr)

    if (PRC_myrank == 0) then
      obs(iof)%dat = bufr(1:obs(iof)%nobs)

      do n = 1, obs(iof)%nobs
        select case(obs(iof)%elm(n))
        case(id_u_obs)
          obs(iof)%err(n) = OBSERR_U
        case(id_v_obs)
          obs(iof)%err(n) = OBSERR_V
        case(id_t_obs,id_tv_obs)
          obs(iof)%err(n) = OBSERR_T
        case(id_q_obs)
          obs(iof)%err(n) = OBSERR_Q
        case(id_rh_obs)
          obs(iof)%err(n) = OBSERR_RH
        case(id_ps_obs)
          obs(iof)%err(n) = OBSERR_PS
        case(id_radar_ref_obs)
          obs(iof)%err(n) = OBSERR_RADAR_REF
        case(id_radar_vr_obs)
          obs(iof)%err(n) = OBSERR_RADAR_VR
        case(id_H08IR_obs) ! H08
          obs(iof)%err(n) = OBSERR_H08 !H08
        case default
          write(6,'(A)') 'warning: skip assigning observation error (unsupported observation type)' 
        end select

        if (obs(iof)%dat(n) /= undef .and. obs(iof)%err(n) /= undef) then
          obs(iof)%dat(n) = obs(iof)%dat(n) + obs(iof)%err(n) * error(ns+n)
        end if

!print *, '######', obs%elm(n), obs%dat(n)
      end do ! [ n = 1, obs(iof)%nobs ]

      ns = ns + obs(iof)%nobs
    end if ! [ PRC_myrank == 0 ]

  end do ! [ iof = 1, nobsfiles ]

  if (PRC_myrank == 0) then
    deallocate ( bufr )
    deallocate ( error )

    call write_obs_all(obs, missing=.false., file_suffix='.out') ! only at the head node
  end if

end subroutine obsmake_cal
!=======================================================================

END MODULE obsope_tools
