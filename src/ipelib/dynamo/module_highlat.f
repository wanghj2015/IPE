      module module_highlat
!
      PRIVATE
      PUBLIC :: highlat
      
      contains 
!-----------------------------------------------------------------------
      subroutine highlat(rc)
      use ipe_error_module
      use params_module,ONLY: kmlonp1,kmlat,kmlon
      use dynamo_module,ONLY: kmlat0,phihm,potential_model
      use module_sub_heelis,ONLY: heelis
      use module_colath,ONLY:colath
      use module_magfield
      use module_weimer2005Ipe,ONLY:setmodel2005Ipe,epotval2005Ipe
     &  ,fileLocation
      use cons_module,ONLY:xlatm_deg,xlonm_deg,pi,dtr,xlatm
      implicit none
      integer,optional,intent(out) :: rc

      integer :: i,j,lrc
      real*8,parameter::fill=1.0E36 !fill in value outside the boundary
      real*8 ::mlat,mlt,epot
!   
! am 10/04 remove weimer part: first test without any potential model
! Dynamo calls Heelis (heelis.F), Weimer (wei01gcm.F), or neither
!   for high latitude electric potential, according to user-provided
!   "model_potential".
! Get high latitude (Heelis or other) colatitudes, NH pfrac, and poten phihm.
!  If Weimer is used, then theta0,phid etc is changed before use in aurora
!   in dynamics.
!
      if (present(rc)) rc = IPE_SUCCESS

      if (potential_model == 'HEELIS') then
        call heelis

!         write(unit=4025,FMT='(20E12.4)') phihm
      else if (potential_model == 'weimer2005') then
        call heelis

        call setmodel2005Ipe(sangle,bt,stilt,swvel,swden
     &,fileLocation,'epot',rc=lrc)
        if (ipe_error_check(lrc,msg="call to setmodel2005Ipe failed",
     &    rc=rc)) return
!        mlatLoop: do j=1,kmlat0 !kmlat0=(kmlat+1)/2, from -90 to 0 SH
         mlatLoop:do j=1,kmlat

           mlat=xlatm_deg(j)      !mlat[deg]
           if ( abs(xlatm(j)) <= pi/6. ) then

              phihm(1:kmlon,j) = 0.
              CYCLE             !go to the next J

            else  !if ( abs(mlat) > pi/6. ) then

          mlonLoop: do i=1,kmlon
!mltrad = mlonRad - sunlons + pi !mlt(rad)
!here sunlons must be time dependent!
                 mlt = (xlonm_deg(i)*dtr -sunlons + pi)*12./pi !mlt(hr)
                 if (mlt>=24.) mlt=mod(mlt,24.0d0)
                 if (mlt<0.) mlt=mlt+24.

!note:mlat<0 is outside of the boundary(fill in value)!
                 call epotval2005Ipe(abs(mlat),mlt,fill,epot)

                 if ( epot == fill ) then
                    phihm(i,j) = 0.
                 else
                    phihm(i,j) = epot*1.0E+3 !epot[kV]-->[Volt]
                 end if
              end do mlonLoop   !i=1,kmlon

!periodic points:
              phihm(kmlonp1,j) = phihm(1,j)

           end if               !abs(mlat)
         end do mlatLoop      !j=1,kmlat

!         write(unit=4025,FMT='(20E12.4)') phihm

      else  !  potential_model='NONE'
        do j=1,kmlat0
          do i=1,kmlonp1
            phihm(i,j) = 0.
          enddo ! i=1,kmlonp1
        enddo ! j=1,kmlat0
        call colath
      endif
      
      end subroutine highlat
!-----------------------------------------------------------------------
      end module module_highlat
