!-----------------------------------------------------------------------
      module weimer2005_ipe

      use ipe_error_module

      implicit none
!
! Data read from W05scEpot.dat or W05scBpot.dat:
      integer,parameter :: csize=28, d1_pot=15, d2_pot=18
      integer :: ab(csize), ls(csize), ms(csize)
      real :: alschfits(d2_pot,csize), schfits(d1_pot,csize), ex_pot(2)
      integer :: maxl_pot,maxm_pot
!
! Data read from SCHAtable.dat:
      integer,parameter :: d1_scha=19, d2_scha=7, d3_scha=68
      real :: allnkm(d1_scha,d2_scha,d3_scha)
      integer :: maxk_scha,maxm_scha
      real :: th0s(d3_scha)
!
! Data read from W05scBndy.dat:
      integer,parameter :: na=6, nb=7
      real :: bndya(na),bndyb(nb),ex_bndy(2)
!
! Location of W05scEpot.dat, W05SCHAtable.dat, W05scBndy.dat
      character*2  :: file_location = './'
      character*4  :: model
!
      real :: rad2deg,deg2rad           ! set by SetModel_new
      real :: bndyfitr                  ! calculated by setboundary
      real :: esphc(csize),bsphc(csize) ! calculated by SetModel_new
      real :: tmat(3,3),ttmat(3,3)      ! from setboundary
!mf  integer,parameter :: mxtablesize=200
      integer,parameter :: mxtablesize=500 !500 was suggested by Ben Foster, according to Mihail.
      real :: plmtable(mxtablesize,csize),colattable(mxtablesize)
      real :: nlms(csize)


      contains
!-----------------------------------------------------------------------
      subroutine weimer05(epoto,rc)
      implicit none

! Args:
      real,              intent(out) :: epoto(2,22,180)
      integer, optional, intent(out) :: rc

! Local:
      real, parameter :: angle= 0.0, bt= 4.3368, swvel=343.66
      real, parameter :: swden= 5.0, tilt  = 0.0

      integer :: lrc
      real    :: sangle, stilt

      if (present(rc)) rc = IPE_SUCCESS

      epoto = 0.0
!
! for northern hemisphere:  tilt,  angle
      call SetModel_new(angle,bt,tilt,swvel,swden,rc=lrc)
      if (ipe_error_check(lrc,msg="call to SetModel_new (NE) failed",
     &  rc=rc)) return
      call get_elec_field(epoto(1,1:22,1:180),rc=lrc)
      if (ipe_error_check(lrc,msg="call to get_elec_field (NE) failed",
     &  rc=rc)) return
!
! for southern hemisphere:  -tilt, BY will be 360-BY(north)
      sangle = mod(360.0-angle, 360.0)
      stilt  = -tilt
      call SetModel_new(sangle,bt,stilt,swvel,swden,rc=lrc)
      if (ipe_error_check(lrc,msg="call to SetModel_new (SE) failed",
     &  rc=rc)) return
      call get_elec_field(epoto(2,1:22,1:180),rc=lrc)
      if (ipe_error_check(lrc,msg="call to get_elec_field (SE) failed",
     &  rc=rc)) return

      end subroutine weimer05
!-----------------------------------------------------------------------
      subroutine get_elec_field(epot,rc)
      implicit none
! 
! Args:
      real,              intent(out) :: epot(22,180)
      integer, optional, intent(out) :: rc
! Local: 
      real, parameter   :: fill = 1.0e36
      real, parameter   :: radi = 6371.e3, pi=3.14159265358979323846
!  real, parameter   :: dellat = 1.0, dellt = 0.10, delmlt = 1.20
      real, parameter   :: dellat = 1.0, dellt = 0.10, delmlt = 0.133333333333
      integer           :: l, m, lrc
      real              :: rad2deg
      real              :: gmlt, gmlte, gmltw, dely
      real              :: glat, glatu, glatd, delx
      real              :: epotu, epotd, epote, epotw
      real              :: epx, epy, phir, cphi, sphi

      if (present(rc)) rc = IPE_SUCCESS

      rad2deg = pi/180.00
      delx = radi * 2.0 * dellat * rad2deg 

      epot = 0.

      mlt_loop: do l = 1, 180 
        gmlt  = real(mod((l-1)*delmlt+12.0,24.0d0))
        gmlte = real(mod(gmlt+dellt,24.d0))
        gmltw = real(mod(gmlt-dellt,24.d0))
        lat_loop: do m = 2, 22 
          glat  = 90.0 - (m-1.0)*2.0
          glatu = glat + dellat
          glatd = glat - dellat
          dely  = radi*cos(glat*rad2deg)*2.0*dellt*15.0*rad2deg

          call EpotVal_new(glat,  gmlt, epot(m,l), rc=lrc)
          if (ipe_error_check(lrc,msg="call to EpotVal_new failed",
     &      rc=rc)) return

        enddo lat_loop
      enddo mlt_loop

      end subroutine get_elec_field
!-----------------------------------------------------------------------
      subroutine SetModel_new(angle,bt,tilt,swvel,swden,rc)
        implicit none
!
! Args:
!
! file_path: directory in which to find data file (must have "/" at end)
!
        real,            intent(in)  :: angle,bt,tilt,swvel,swden
        integer,optional,intent(out) :: rc
!
! Local:
        integer :: i,j
        real :: pi,stilt,stilt2,sw,swp,swe,c0,rang,cosa,sina,cos2a,sin2a
        real :: cfits(d1_pot,csize),a(d1_pot)

        if (present(rc)) rc = IPE_SUCCESS
!
        if (trim(model) /= 'epot'.and.trim(model) /= 'bpot') then
!          write(iulog,"('>>> model=',a)") trim(model)
          call ipe_error_set(msg="SetModel_new: unsuported model "//
     c      model, rc=rc)
          return
        endif
!
! Read data:
        pi = 4.*atan(1.)
        rad2deg = 180./pi
        deg2rad = pi/180.
!
        call setboundary(angle,bt,tilt,swvel,swden)
!
        stilt = sin(tilt*deg2rad)
        stilt2 = stilt**2
        sw = bt*swvel/1000.
        swe = (1.-exp(-sw*ex_pot(2)))*sw**ex_pot(1)
        c0 = 1.
        swp = swvel**2 * swden*1.6726e-6
        rang = angle*deg2rad
        cosa = cos(rang)
        sina = sin(rang)
        cos2a = cos(2.*rang)
        sin2a = sin(2.*rang)
        if (bt < 1.) then ! remove angle dependency for IMF under 1 nT
          cosa = -1.+bt*(cosa+1.)
          cos2a = 1.+bt*(cos2a-1.)
          sina = bt*sina
          sin2a = bt*sin2a
        endif
        cfits = schfits ! schfits(d1_pot,csize) is in module w05read_data
        a = (/c0      , swe       , stilt      , stilt2     , swp,
     c        swe*cosa, stilt*cosa, stilt2*cosa, swp*cosa,
     c        swe*sina, stilt*sina, stilt2*sina, swp*sina,
     c        swe*cos2a,swe*sin2a/)
        if (trim(model) == 'epot') then
          esphc(:) = 0.
          do j=1,csize
            do i=1,int(d1_pot)
              esphc(j) = esphc(j)+cfits(i,j)*a(i)
            enddo
          enddo
        else
          bsphc(:) = 0.
          do j=1,csize
            do i=1,int(d1_pot)
              bsphc(j) = bsphc(j)+cfits(i,j)*a(i)
            enddo
          enddo
        endif
      end subroutine SetModel_new
!-----------------------------------------------------------------------
       subroutine setboundary(angle,bt,tilt,swvel,swden)        ! Zhuxiao
        implicit none
!
! Args:
!
! file_path: directory in which to find data file (must have "/" at end)
!    character(len=*),intent(in) :: file_path   ! by Zhuxiao
        real,intent(in) :: angle,bt,tilt,swvel,swden
!
! Local:
        integer :: i
        real :: swp,xc,theta,ct,st,tilt2,cosa,btx,x(na),c(na)
        real, parameter :: num_0 = 0., num_1 = 1. 
!
! Calculate the transformation matrix to the coordinate system
! of the offset pole.
!
        xc = 4.2
        theta = xc*(deg2rad)
        ct = cos(theta)
        st = sin(theta)
!
        tmat(1,:) = (/ ct, num_0, st/)   ! avoid conflict
        tmat(2,:) = (/ 0., 1., 0./) 
        tmat(3,:) = (/-st, num_0, ct/)   ! avoid conflict
!
        ttmat(1,:) = (/ct, num_0,-st/)
        ttmat(2,:) = (/ 0.,1., 0./)
        ttmat(3,:) = (/st, num_0, ct/)   ! avoid conflict
!
        swp = swden*swvel**2*1.6726e-6 ! pressure
        tilt2 = tilt**2
        cosa = cos(angle*deg2rad)
        btx = 1.-exp(-bt*ex_bndy(1))
        if (bt > 1.) then
          btx = btx*bt**ex_bndy(2)
        else
          cosa = 1.+bt*(cosa-1.) ! remove angle dependency for IMF under 1 nT
        endif
        x = (/num_1, cosa, btx, btx*cosa, swvel, swp/)
        c = bndya
        bndyfitr = 0.
        do i=1,na
          bndyfitr = bndyfitr+x(i)*c(i)
        enddo

      end subroutine setboundary
!-----------------------------------------------------------------------
      subroutine EpotVal_new(lat,mlt,epot,rc)
        implicit none
!
! Args:
        real,            intent(in)  :: lat,mlt
        real,            intent(out) :: epot
        integer,optional,intent(out) :: rc
!
! Local:
        integer :: inside,j,m,mm,skip,lrc
        real :: z,phir,plm,colat,nlm
        real :: phim(2),cospm(2),sinpm(2)

        if (present(rc)) rc = IPE_SUCCESS
!
! checkinputs returns inside=1 if lat is inside model boundary,
! inside=0 otherwise. Phir and colat are also returned by checkinputs.
!
        call checkinputs(lat,mlt,inside,phir,colat)

        if (inside == 0) then
          epot = 0.
          return
        endif

!
! IDL code: 
! phim=phir # replicate(1,maxm) * ((indgen(maxm)+1) ## replicate(1,n_elements(phir)))
!   where the '#' operator multiplies columns of first array by rows of second array,
!   and the '##' operator multiplies rows of first array by columns of second array.
! Here, maxm == maxm_pot == 2 (from w05read_data module), and phir is a scalar. The 
!   above IDL statement then becomes: phim = ([phir] # [1,1]) * ([1,2] ## [phir]) where
!   phim will be dimensioned [1,2]
!
        phim(1) = phir
        phim(2) = phir*2.
        cospm(:) = cos(phim(:))
        sinpm(:) = sin(phim(:))
!
        z = 0.
        skip=0
        do j=1,csize
          if (skip == 1) then
            skip = 0
            cycle
          endif
          m = ms(j)
          if (ab(j)==1) then

            plm = scplm(j,colat,nlm,rc=lrc) ! scplm function is in this module
            if (ipe_error_check(lrc,msg="call to plm failed",rc=rc))
     c        return

            skip = 0
            if (m == 0) then
              z = z+plm*esphc(j)
            else
              z = z+plm*(esphc(j)*cospm(m)+esphc(j+1)*sinpm(m))
              skip = 1
            endif

          endif ! ab(j)
        enddo
        epot = z 
      end subroutine EpotVal_new
!-----------------------------------------------------------------------
      subroutine mpfac(lat,mlt,mpmpfac,rc)
        implicit none
!
! Args:
        real,            intent(in)  :: lat,mlt
        real,            intent(out) :: mpmpfac
        integer,optional,intent(out) :: rc
!
! Local:
        integer :: j,m,inside,skip,lrc
        real :: phim(2),cospm(2),sinpm(2),cfactor
        real :: re,z,phir,plm,colat,nlm,pi

        if (present(rc)) rc = IPE_SUCCESS
!
        re = 6371.2 + 110. ! km radius (allow default ht=110)
!
! checkinputs returns inside=1 if lat is inside model boundary,
! inside=0 otherwise. Phir and colat are also returned by checkinputs.
!
        call checkinputs(lat,mlt,inside,phir,colat)
        if (inside == 0) then
          mpmpfac = 0.
          return
        endif
!
        phim(1) = phir
        phim(2) = phir*2.
        cospm(:) = cos(phim(:))
        sinpm(:) = sin(phim(:))
!
        z = 0.
        skip=0
        jloop: do j=1,csize
          if (skip == 1) then
            skip = 0
            cycle
          endif
          if (ls(j) >= 11) exit jloop
          m = ms(j)
          if (ab(j) == 1) then
            plm = scplm(j,colat,nlm,rc=lrc) ! colat and nlm are returned (both reals)
            if (ipe_error_check(lrc,msg="call to scplm failed",rc=rc))
     c        return
            plm = plm*(nlm*(nlm+1.))
!
! bsphc was calculated in SetModel_new (when SetModel_new called with 'bpot')
            if (m==0) then
              z = z-plm*bsphc(j)
            else
              z = z-(plm*(bsphc(j)*cospm(m)+bsphc(j+1)*sinpm(m)))
              skip = 1
            endif
          endif
        enddo jloop ! j=1,csize
        pi = 4.*atan(1.)
        cfactor = -1.e5/(4.*pi*re**2) ! convert to uA/m2
        z = z*cfactor
        mpmpfac = z
      end subroutine mpfac
!-----------------------------------------------------------------------
      real function scplm(indx,colat,nlm,rc)
        implicit none
!
! Args:
        integer,         intent(in)  :: indx
        real,            intent(in)  :: colat
        real,            intent(out) :: nlm
        integer,optional,intent(out) :: rc
!
! Local:
        integer,save :: tablesize
        integer :: istat,i,j,l,m,skip
        real :: th0,output(1),colata(1),plm1
        real :: cth(mxtablesize)
        real,save :: prevth0=1.e36

        if (present(rc)) rc = IPE_SUCCESS

        scplm = 0.
        th0 = bndyfitr
        if (prevth0 /= th0) then
          tablesize = 3*nint(th0)
          if (ipe_status_check(tablesize <= mxtablesize,
     c      msg="tablesize exceeds mxtablesize", rc=rc)) return
 
          do i=1,tablesize
            colattable(i) = float(i-1)*(th0/float(tablesize-1))
            cth(i) = cos(colattable(i)*deg2rad)
          enddo


          prevth0 = th0
          nlms = 0. ! whole array init 
          skip=0
          do j=1,csize
            if (skip == 1) then
              skip = 0
              cycle
            endif
            l = ls(j)
            m = ms(j)

            nlms(j) = nkmlookup(l,m,th0) ! nkmlookup in this module


            call pm_n(m,nlms(j),cth,plmtable(1:tablesize,j),tablesize)

            skip = 0
            if (m /= 0 .and. ab(j) > 0) then
              plmtable(1,j+1) = plmtable(1,j)
              nlms(j+1) = nlms(j)
              skip = 1
            endif

          enddo ! j=1,csize

        endif ! prevth0
        nlm = nlms(indx)
        colata(1) = colat

        call interpol_quad(plmtable(1:tablesize,indx),
     c      colattable(1:tablesize),colata,output)
        scplm = output(1)

      end function scplm
!-----------------------------------------------------------------------
      subroutine pm_n(m,r,cth,plmtable,tablesize)
        implicit none
!
! Args:
        integer,intent(in) :: m,tablesize
        real,intent(in) :: r
        real,intent(in) :: cth(tablesize)
        real,intent(out) :: plmtable(tablesize)
!
! Local:
        integer :: i,k,ii
        real :: rm,rk,div,ans,xn
        real,dimension(tablesize) :: a,x,tmp,table
!
        if (m == 0) then 
          a = 1. ! whole array op
        else
          do i=1,tablesize
            a(i) = sqrt(1.-cth(i)**2)**m
          enddo
        endif
        xn = r*(r+1.)
        x(:) = (1.-cth(:))/2.

        table = a ! whole array init
!
        k = 1
        pmn_loop: do         ! repeat-until loop in idl code
          do i=1,tablesize
            rm = float(m)
            rk = float(k)
            a(i) = a(i)*(x(i)*((rk+rm-1.)*(rk+rm)-xn)/(rk*(rk+rm)))
            table(i) = table(i)+a(i) ! "result" in idl code
          enddo


          k = k+1
          do i=1,tablesize
            div = abs(table(i))
            if (div <= 1.e-6) div = 1.e-6
            tmp(i) = abs(a(i)) / div
          enddo


          if (maxval(tmp) < 1.e-6) exit pmn_loop
        enddo pmn_loop
        ans = km_n(m,r)

        plmtable(:) = table(:)*ans

      end subroutine pm_n
!-----------------------------------------------------------------------
      real function km_n(m,rn)
        implicit none
!
! Args:
        integer,intent(in) :: m
        real,intent(in) :: rn
!
! Local:
        integer :: i,n
        real :: rm
!
        if (m == 0) then 
          km_n = 1.
          return
        endif
        
        rm = float(m)
        km_n = sqrt(2.*exp(lngamma(rn+rm+1.)-lngamma(rn-rm+1.))) /
     c             (2.**m*factorial(m))

      end function km_n
!-----------------------------------------------------------------------
      real function nkmlookup(k,m,th0)
        implicit none
!
! Args:
        integer,intent(in) :: k,m
        real,intent(in) :: th0
!
! Local:
        integer :: kk,mm
        real :: th0a(1),out(1)

        if (th0 == 90.) then
          nkmlookup = float(k)
          return
        endif
        th0a(1) = th0
        kk = k+1
        mm = m+1
        if (kk > maxk_scha) then
          call interpol_quad(allnkm(maxk_scha,mm,:),th0s,th0a,out)
        endif
        if (mm > maxm_scha) then
          call interpol_quad(allnkm(kk,maxm_scha,:),th0s,th0a,out)
        endif
        if (th0 < th0s(1)) then
!         write(iulog,"('>>> nkmlookup: th0 < th0s(1): th0=',e12.4,' th0s(1)=',e12.4)")
!    c       th0,th0s(1)
        endif


        call interpol_quad(allnkm(kk,mm,:),th0s,th0a,out)

        nkmlookup = out(1)

      end function nkmlookup
!-----------------------------------------------------------------------
      subroutine checkinputs(lat,mlt,inside,phir,colat)
        implicit none
!
! Args:
        real,intent(in) :: lat,mlt
        integer,intent(out) :: inside
        real,intent(out) :: phir,colat
!
! Local:
        real :: lon,tlat,tlon,radii

        lon = mlt*15.
        call dorotation(lat,lon,tlat,tlon)
        radii = 90.-tlat
        inside = 0
        if (radii <= bndyfitr) inside = 1 ! bndyfitr from setboundary
        phir = tlon*deg2rad
        colat = radii

      end subroutine checkinputs
!-----------------------------------------------------------------------
      subroutine dorotation(latin,lonin,latout,lonout)
        implicit none
!
! Args:
        real,intent(in) :: latin,lonin
        real,intent(out) :: latout,lonout
!
! Local:
        real :: latr,lonr,stc,ctc,sf,cf,a,b,pos(3)
        integer :: i

        latr = latin*deg2rad
        lonr = lonin*deg2rad
        stc = sin(latr)
        ctc = cos(latr)
        sf = sin(lonr)
        cf = cos(lonr)
        a = ctc*cf
        b = ctc*sf
!
! IDL code: Pos= TM ## [[A],[B],[STC]]
! The ## operator multiplies rows of first array by columns of second array.
! Currently, TM(3,3) = Tmat (or TTmat if "reversed" was set)
! If called w/ single lat,lon, then a,b,stc are dimensioned (1), and
!   Pos is then (1,3)
!
        do i=1,3
          pos(i) = tmat(1,i)*a + tmat(2,i)*b + tmat(3,i)*stc
        enddo
      
        latout = asin(pos(3))*rad2deg
        lonout = atan2(pos(2),pos(1))*rad2deg
      
      end subroutine dorotation
!-----------------------------------------------------------------------
      subroutine interpol_quad(v,x,u,p)
!
! f90 translation of IDL function interpol(v,x,u,/quadratic)
!
        implicit none
!
! Args:
        real,intent(in) :: v(:),x(:),u(:)
        real,intent(out) :: p(:)
!
! Local:
        integer :: nv,nx,nu,i,ix
        real :: x0,x1,x2
!
        nv = size(v)
        nx = size(x)
        nu = size(u)
        if (nx /= nv) then
!          write(iulog,"('>>> interpol_quad: nx /= nv: nx=',i4,' nv=',i4)") nx,nv
          p(:) = 0.
          return
        endif
        do i=1,nu
          ix = value_locate(x,u(i))
          if (ix <= 1.or.ix >= nx) then
!       write(iulog,"('>>> interpol_quad: ix out of range: nu=',i4,' ix=',i4)") nu,ix
            p(i) = 0.
            cycle
          endif
          x1 = x(ix)
          x0 = x(ix-1)
          x2 = x(ix+1)
          if(x0.eq.0..and.x1.eq.0.)then
           p(i) =0.0
          else
           p(i) = v(ix-1) * (u(i)-x1)*(u(i)-x2) / ((x0-x1)*(x0-x2))+
     c            v(ix)   * (u(i)-x0)*(u(i)-x2) / ((x1-x0)*(x1-x2))+
     c            v(ix+1) * (u(i)-x0)*(u(i)-x1) / ((x2-x0)*(x2-x1))
          endif 
        enddo

      end subroutine interpol_quad
!-----------------------------------------------------------------------
      integer function value_locate(vec,val)
!
! f90 translation of IDL function value_locate
! Return index i into vec for which vec(i) <= val >= vec(i+1)
! Input vec must be monotonically increasing
!
        implicit none
!
! Args:
        real,intent(in) :: vec(:),val
!
! Local:
        integer :: n,i
!
        value_locate = 0
        n = size(vec)
        if (val < vec(1)) return
        if (val > vec(n)) then
          value_locate = n
          return
        endif
        do i=1,n-1
          if (val >= vec(i) .and. val <= vec(i+1)) then
            value_locate = i
            return
          endif
        enddo

      end function value_locate
!-----------------------------------------------------------------------
      real function lngamma(xx)
!
! This is an f90 translation from C code copied from 
! www.fizyka.umk.pl/nrbook/c6-1.pdf (numerical recipes gammln)
!
      implicit none
      real,intent(in) :: xx
      real,parameter :: cof(6)= (/76.18009172947146, -86.50532032941677,
     c                   24.01409824083091, -1.231739572450155,
     c               0.1208650973866179e-2, -0.5395239384953e-5/)
      real :: x,y,tmp,ser
      integer :: j
!
      y = xx
      x = xx
      tmp = x+5.5
      tmp = tmp-(x+0.5)*log(tmp)
      ser = 1.000000000190015
      do j=1,5
        y = y+1
        ser = ser+cof(j)/y
      enddo
      lngamma = -tmp+log(2.5066282746310005*ser/x)
      end function lngamma
!-----------------------------------------------------------------------
      real function factorial(n)
      implicit none
      integer,intent(in) :: n
      integer :: m
      if (n <= 0) then
!        write(iulog,"('>>> factorial: n must be positive: n=',i4)") n
        factorial = 0.
        return
      endif
      if (n == 1) then
        factorial = 1.
        return
      endif
      factorial = float(n)
      do m = n-1,1,-1
        factorial = factorial * float(m)
      enddo
      end function factorial
!-----------------------------------------------------------------------
      subroutine read_potential(infile,rc)
!
! Read ascii data file W05scEpot.dat or W05scBpot.dat, written by 
!   pro write_potential (write_data.pro)
!
      implicit none
!
! Args:
      character(len=*),  intent(in)  :: infile
      integer, optional, intent(out) :: rc
!
! Local:
!
      character(len=16) :: fname
      character(len=1024) :: errmsg
      integer :: i,lu=20
      integer :: csize_rd,d1_rd,d2_rd
      integer :: iulog=6, ios
!
      if (present(rc)) rc = IPE_SUCCESS
!
      open(lu,file=infile,status='old', ACCESS ='SEQUENTIAL',
     &     iostat=ios)
      if (ipe_iostatus_check(ios,msg="error opening file "//infile,
     &  rc=rc)) return

      read(lu,"(a)",iostat=ios) fname
      if (ipe_iostatus_check(ios,msg="error reading filename",
     &  rc=rc)) return
      read(lu,"(28i3)",iostat=ios) ab
      if (ipe_iostatus_check(ios,msg="error reading ab",
     &  rc=rc)) return
      read(lu,"(3i3)",iostat=ios) csize_rd,d1_rd,d2_rd
      if (ipe_iostatus_check(ios,
     &  msg="error reading csize_rd,d1_rd,d2_rd",rc=rc)) return
      if (csize_rd /= csize) then
        write(errmsg,"('>>> read_potential: file ',a,':
     c     incompatable csize: ',
     c     'csize_rd=',i4,' csize=',i4)") fname,csize_rd,csize
        call ipe_error_set(msg=errmsg, rc=rc)
        return
      endif
!      if (d1_rd /= d1_pot) then
!        write(iulog,"('>>> read_potential: file ',a,': 
!     c   incompatable d1: ',
!     c   'd1_rd=',i4,' d1_pot=',i4)") fname,d1_rd,d1_pot
!      endif
!      if (d2_rd /= d2_pot) then
!        write(iulog,"('>>> read_potential: file ',a,': 
!     c   incompatable d2: ',
!     c   'd2_rd=',i4,' d2_pot=',i4)") fname,d2_rd,d2_pot
!      endif
      do i=1,csize
        read(lu,"(6e20.9)",iostat=ios) alschfits(:,i)
        if (ipe_iostatus_check(ios,msg="error reading alschfits",
     &    rc=rc)) return
      enddo
      read(lu,"(2f10.3)",iostat=ios) ex_pot
      if (ipe_iostatus_check(ios,msg="error reading ex_pot",
     &  rc=rc)) return
      read(lu,"(28i3)",iostat=ios) ls
      if (ipe_iostatus_check(ios,msg="error reading ls",
     &  rc=rc)) return
      read(lu,"(2i3)",iostat=ios) maxl_pot,maxm_pot
      if (ipe_iostatus_check(ios,msg="error reading maxl_pot,maxm_pot",
     &  rc=rc)) return
      read(lu,"(28i3)",iostat=ios) ms
      if (ipe_iostatus_check(ios,msg="error reading ms",
     &  rc=rc)) return

      do i=1,csize
        read(lu,"(6e20.9)",iostat=ios) schfits(:,i)
        if (ipe_iostatus_check(ios,msg="error reading schfits",
     &    rc=rc)) return
      enddo
      close(lu,iostat=ios)
      if (ipe_iostatus_check(ios,msg="error closing file "//infile,
     &  rc=rc)) return
      end subroutine read_potential
!-----------------------------------------------------------------------
      subroutine read_schatable(infile,rc)
!
! Read ascii data file SCHAtable.dat, written by pro write_scha
!   (write_data.pro)
!
      implicit none
!
! Args:
      character(len=*),intent(in)  :: infile
      integer,optional,intent(out) :: rc
!
! Local:
!
      character(len=16) :: fname
      integer :: i,j,lu=20
      integer :: iulog=6, ios
!
      if (present(rc)) rc = IPE_SUCCESS
!
      open(lu,file=infile,status='old', ACCESS ='SEQUENTIAL',
     &     iostat=ios)
      if (ipe_iostatus_check(ios,msg="error opening file "//infile,
     &  rc=rc)) return
      
      read(lu,"(a)",iostat=ios) fname
      if (ipe_iostatus_check(ios,msg="error reading filename",
     &  rc=rc)) return
      read(lu,"(2i3)",iostat=ios) maxk_scha,maxm_scha
      if (ipe_iostatus_check(ios,
     &  msg="error reading maxk_scha,maxm_scha",rc=rc)) return
      do i=1,d3_scha
        do j=1,d2_scha
          read(lu,"(6e20.9)",iostat=ios) allnkm(:,j,i)
          if (ipe_iostatus_check(ios,msg="error reading allnkm",
     &      rc=rc)) return
        enddo
      enddo
      read(lu,"(8f10.4)",iostat=ios) th0s
      if (ipe_iostatus_check(ios,msg="error reading th0s",
     &  rc=rc)) return

      close(lu,iostat=ios)
      if (ipe_iostatus_check(ios,msg="error closing file "//infile,
     &  rc=rc)) return
      end subroutine read_schatable
!-----------------------------------------------------------------------
      subroutine read_bndy(infile,rc)
!
! Read ascii data file W05scBndy.dat, written by pro write_bndy
!   (write_data.pro)
!
      implicit none
!
! Args:
      character(len=*),intent(in)  :: infile
      integer,optional,intent(out) :: rc
!
! Local:
!
      character(len=16) :: fname
      integer :: rd_na,rd_nb,lu=20
      integer :: iulog=6, ios
!
      if (present(rc)) rc = IPE_SUCCESS
!
      open(lu,file=infile,status='old', ACCESS ='SEQUENTIAL',
     &     iostat=ios)
      if (ipe_iostatus_check(ios,msg="error opening file "//infile,
     &  rc=rc)) return

      read(lu,"(a)",iostat=ios) fname
      if (ipe_iostatus_check(ios,msg="error reading filename",
     &  rc=rc)) return
      read(lu,"(2i3)",iostat=ios) rd_na,rd_nb
      if (ipe_iostatus_check(ios,msg="error reading rd_na,rd_nb",
     &  rc=rc)) return
!      if (rd_na /= na) then
!        write(iulog,"('>>> read_potential: file ',a,': 
!     c  incompatable na: ',
!     c     'rd_na=',i4,' na=',i4)") fname,rd_na,na
!      endif
!      if (rd_nb /= nb) then
!        write(iulog,"('>>> read_potential: file ',a,': 
!     c  incompatable nb: ',
!     c  'rd_nb=',i4,' nb=',i4)") fname,rd_nb,nb
!      endif
      read(lu,"(8e20.9)",iostat=ios) bndya
      if (ipe_iostatus_check(ios,msg="error reading bndya",
     &  rc=rc)) return
      read(lu,"(8e20.9)",iostat=ios) bndyb
      if (ipe_iostatus_check(ios,msg="error reading bndyb",
     &  rc=rc)) return
      read(lu,"(8e20.9)",iostat=ios) ex_bndy
      if (ipe_iostatus_check(ios,msg="error reading ex_bndy",
     &  rc=rc)) return

      close(lu,iostat=ios)
      if (ipe_iostatus_check(ios,msg="error closing file "//infile,
     &  rc=rc)) return
      end subroutine read_bndy
!-----------------------------------------------------------------------
      end module weimer2005_ipe

