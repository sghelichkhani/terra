*dk fetosh
C> This sub-routine computes the coefficients of the spherical harmonics
C> expansion of a given 3D grid function. The expansion is performed for each
C> layer of the radial discretisation.
C>
C> \param lun  Logical Unit Number for the output file to which the computed
C>             coefficients will be appended. IO is only performed by the MPI
C>             process with rank 0.
C> \param s    Array containing the values of the scalar function for which the
C>             expansion is to be computed
C> \param shar used for storing the computed coefficients (work array, or
C>             INTENTOUT?)
      subroutine fetosh(s,shar,plm,lmax,kr,lun)
 
c...  This routine generates spherical harmonic coefficients
 
      include 'size.h'
      include 'pcom.h'
      integer lun, lmax
      real s((nt+1)**2,nd,kr+1), shar(2,(lmax+1)*(lmax+2)/2,kr+1)
      real plm((lmax+1)*(lmax+2)), csm(0:128,2)
      common /mesh/ xn((nt+1)**2,nd,3)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      smax = 0.
      r4pi = 0.125/asin(1.)
 
      call nulvec(shar, (lmax+1)*(lmax+2)*(kr+1))

C     This 'hack' fixes a problem in the use of arn in the loop below.
C     The loop runs over all nodes in the local sub-domain. However, Terra
C     employs an element-oriented domain decomposition. Thus, nodes along the
C     subdomain edges belong to several subdomains. arn stores zeros along the
C     upper right and lower right edge. In this fashion we can avoid multiple
C     contributions from different subdomains from the loop below, when doing
C     psumlong in the end of this routine. However, those process(es) to whose
C     subdomain(s) the north and south poles belong stores the area associated
C     with those nodes. Thus, we get five contributions from these nodes.
C     We correct this by scaling the corresponding area value in arn.
C     The hack must be undone again before leaving the routine. Otherwise
C     inconsistencies might occur in other parts of the code.
      IF ( mynum .EQ. 0 .OR. (nd .EQ. 5 .AND. mynum .EQ. nproc/2)) THEN
         arn(1) = arn(1) / 5.
      ENDIF

      do ii=1,(nt+1)**2
 
         a0 = r4pi*arn(ii)
 
         do id=1,nd
 
            phi = atan2(xn(ii,id,2) + 1.e-30, xn(ii,id,1))
 
            do m=0,lmax
               csm(m,1) = cos(m*phi)
               csm(m,2) = sin(m*phi)
            end do
 
            if(mod(id, 5) .eq. 1)
     &         call plmbar(plm,plm,lmax,xn(ii,id,3),0)
 
            k = 0
 
            do l=0,lmax
 
               do m=0,l
 
                  k = k + 1
 
                  do ir=1,kr+1
 
                     aa = a0*plm(k)*s(ii,id,ir)
 
                     shar(1,k,ir) = shar(1,k,ir) + aa*csm(m,1)
                     shar(2,k,ir) = shar(2,k,ir) + aa*csm(m,2)
                     smax         = max(smax, s(ii,id,ir))
 
                  end do
 
               end do
 
            end do
 
         end do
 
      end do

C     Undo 'hack' by re-setting arn to original value
      IF ( mynum .EQ. 0 .OR. (nd .EQ. 5 .AND. mynum .EQ. nproc/2)) THEN
         arn(1) = arn(1) * 5.
      ENDIF

      if(nproc .gt. 1) call psumlong(shar,plm,(lmax+1)*(lmax+2)*(kr+1))
 
c...  Note:  Array plm must be equal in size to array shar in calling
c...  program to handle the buffer size needed in routine psumlong.
 
      if(mynum.eq.0) call sphharout(shar,smax,lmax,kr,lun)
 
      end
*dk pbar
      subroutine pbar(c,l,m,p)
 
c...  This routine calculates the value of the normalized associated
c...  Legendre function of the first kind of degree l and order m
c...  for the real argument c, for 0 .le. m .le. l.
 
      sqrt2 = 1.414213562373092
 
      if(m .ne. 0) then
         p = sqrt2
         s = sqrt(1. - c**2)
         do i=1,m
            p = sqrt(real(2*i + 1)/real(2*i))*s*p
         end do
      else
         p = 1.
      endif
 
      if(l .eq. m) return
 
      p1 = sqrt2
      do j=m+1,l
         p2 = p1
         p1 = p
         p  = 2.*sqrt((real(j**2) - 0.25)/real(j**2 - m**2))*c*p1
     &         - sqrt (real((2*j + 1)*(j - m - 1)*(j + m - 1))
     &                /real((2*j - 3)*(j - m)*(j + m)))*p2
      end do
 
      end
*dk plmbar
c>    Evaluates normalized associated Legendre function P(l,m) as
c>    function of z=cos(colatitude); also derivative dP/d(colatitude).
c>    Uses recurrence relation starting with P(l,l) and then increasing
c>    l keeping m fixed.  Normalization is:
c>                  Integral(Y(l,m)*Y(l,m)) = 4.*pi,
c>                  where Y(l,m) = P(l,m)*exp(i*m*longitude),
c>    which is incorporated into the recurrence relation. p(k) contains
c>    p(l,m) with k=(l+1)*l/2+m+1; i.e. m increments through range 0 to
c>    l before incrementing l. Routine is stable in single and double
c>    precision to l,m = 511 at least; timing is proportional to lmax**2
c>    R.J.O'Connell 7 Sept. 1989; added dp(z) 10 Jan. 1990
c>
c>    Added precalculation and storage of square roots srl(k) 31 Dec 1992
      subroutine plmbar(p,dp,lmax,z,ideriv)
 
      parameter (lmaxx=32)
      dimension p(*),dp(*)
c     --dimensions must be p((lmax+1)*(lmax+2)/2) in calling program
 
      common /plm0/   f1((lmaxx+1)*(lmaxx+2)/2),
     &                f2((lmaxx+1)*(lmaxx+2)/2),
     &              fac1((lmaxx+1)*(lmaxx+2)/2),
     &              fac2((lmaxx+1)*(lmaxx+2)/2), srt(2*lmaxx+2)
      data ifirst /1/
      save ifirst
 
      if (lmax.lt.0.or.abs(z).gt.1.) pause 'bad arguments'
 
c     --set up sqrt and factors on first pass
 
      if(ifirst.eq.1) then
 
         ifirst = 0
 
         do k=1,2*lmax+2
            srt(k) = sqrt(real(k))
         end do
 
         if (lmax .eq. 0) then
            p(1) = 1.0
            if(ideriv .ne. 0) dp(1) = 0.
            return
         end if

c        --case for m > 0
 
         kstart = 1
 
         do m=1,lmax
        
c           --case for P(m,m)
 
            kstart = kstart + m + 1
 
            if(m .ne. lmax) then
 
c              --case for P(m+1,m)
 
               k = kstart + m + 1
 
c              --case for P(l,m) with l > m+1
 
               if(m .lt. lmax-1) then
 
                  do l=m+2,lmax
                     k = k + l
                     f1(k) =  srt(2*l+1)*srt(2*l-1)/(srt(l+m)*srt(l-m))
                     f2(k) = (srt(2*l+1)*srt(l-m-1)*srt(l+m-1))
     &                      /(srt(2*l-3)*srt(l+m)*srt(l-m))
                  end do
 
               end if
 
            end if
 
         end do
 
         k = 3
 
         do l=2,lmax
            k = k + 1
            do m=1,l-1
               k = k + 1
               fac1(k) = srt(l-m)*srt(l+m+1)
               fac2(k) = srt(l+m)*srt(l-m+1)
               if(m .eq. 1) fac2(k) = fac2(k)*srt(2)
            end do
            k = k + 1
         end do
 
      end if
 
c     --start calculation of Plm, etc.
 
c     --case for P(l,0)
 
      pm2   = 1.
      p(1)  = 1.
      if(ideriv .ne. 0) dp(1) = 0.
 
      if(lmax .eq. 0) return
 
      pm1   = z
      p(2)  = srt(3)*pm1
      k     = 2
 
      do l=2,lmax
         k = k + l
         plm  = (real(2*l-1)*z*pm1 - real(l-1)*pm2)/real(l)
         p(k) =   srt(2*l+1)*plm
         pm2  =   pm1
         pm1  =   plm
      end do
 
c     --case for m > 0
 
      pmm    =  1.
      sintsq = (1.-z)*(1.+z)
      fnum   = -1.
      fden   =  0.
      kstart =  1
 
      do m=1,lmax
 
c        --case for P(m,m)
 
         kstart = kstart + m + 1
         fnum   = fnum + 2.
         fden   = fden + 2.0
         pmm    = pmm*sintsq*fnum/fden
         pm2    = sqrt(real(4*m+2)*pmm)
         p(kstart) = pm2
 
         if(m .ne. lmax) then
 
c           --case for P(m+1,m)
 
            pm1  = z*srt(2*m+3)*pm2
            k    = kstart + m + 1
            p(k) = pm1
 
c           --case for P(l,m) with l > m+1
 
            if(m .lt. lmax-1) then
 
               do l=m+2,lmax
                  k    = k + l
c                 f1   =  srt(2*l+1)*srt(2*l-1)/(srt(l+m)*srt(l-m))
c                 f2   = (srt(2*l+1)*srt(l-m-1)*srt(l+m-1))
c     &                 /(srt(2*l-3)*srt(l+m)*srt(l-m))
                  plm  = z*f1(k)*pm1 - f2(k)*pm2
                  p(k) = plm
                  pm2  = pm1
                  pm1  = plm
               end do
        
            endif
 
         endif
        
      end do
 
      if(ideriv .eq. 0) return
 
c     ---derivatives of P(z) wrt theta, where z=cos(theta)
 
      dp(2) = -p(3)
      dp(3) =  p(2)
      k     =  3
 
      do l=2,lmax
 
         k = k + 1
 
c        --treat m=0 and m=l separately
 
         dp(k)   = -srt(l)*srt(l+1)/srt(2)*p(k+1)
         dp(k+l) =  srt(l)/srt(2)*p(k+l-1)
 
            do m=1,l-1
 
               k     = k + 1
c              fac1  = srt(l-m)*srt(l+m+1)
c              fac2  = srt(l+m)*srt(l-m+1)
c              if(m .eq. 1) fac2 = fac2*srt(2)
               dp(k) = 0.5*(fac2(k)*p(k-1) - fac1(k)*p(k+1))
 
            end do
 
         k = k + 1
 
      end do
 
      end
*dk shtofe
C> Generate a grid function from spherical harmonics coefficients
C>
C> The sub-routine generates a 3D grid function from the given coefficients of
C> the expansion of that function in terms of spherical harmonics on each
C> radial layer.
      subroutine shtofe(s,shar,plm,lmaximum,lmax,kr)
 
      include 'size.h'
      include 'pcom.h'
      real s((nt+1)**2,nd,kr+1), shar(2,(lmax+1)*(lmax+2)/2,kr+1)
      real plm((lmax+1)*(lmax+2)), csm(0:128,2)
      common /mesh/ xn((nt+1)**2,nd,3)
 
      call nulvec(s,(nt+1)**2*nd*(kr+1))
 
      do ii=1,(nt+1)**2
         do id=1,nd
 
            phi = atan2(xn(ii,id,2) + 1.e-30, xn(ii,id,1))
 
            do m=0,lmaximum
               csm(m,1) = cos(m*phi)
               csm(m,2) = sin(m*phi)
            end do
 
            if(mod(id, 5) .eq. 1)
     &         call plmbar(plm,plm,lmaximum,xn(ii,id,3),0)
 
            k = 0
 
            do l=0,lmaximum
               do m=0,l
                  k = k + 1
 
                  do ir=1,kr+1
                     s(ii,id,ir) = ((s(ii,id,ir)
     &                           +  (plm(k)*csm(m,1))*shar(1,k,ir))
     &                           +  (plm(k)*csm(m,2))*shar(2,k,ir))
                  end do
 
               end do
            end do
 
         end do
      end do
 
      end
*dk sphharout
      subroutine sphharout(shar,smax,lmax,nr,lun)
 
c...  This routine writes to logical unit lun the file of spherical
c...  harmonic components shar.
 
      real shar((lmax+1)*(lmax+2),nr+1)
 
      nhar = (lmax+1)*(lmax+2)/2
 
      write(lun,15) lmax, nhar, nr+1, smax, 0
 15   format(3(1x,i5),(1x,1pe15.5),(1x,e25.15))
 
      write(lun,25) shar
 25   format(1p2e25.15)
 
      end
*dk uharmonic
      subroutine uharmonic(u,uhar,plm,lmax)
 
c...  This routine generates spherical harmonic coefficients
c...  that describe a vector TERRA field u.
 
      include 'size.h'
      include 'pcom.h'
      real u((nt+1)**2,nd,3), uhar(2,(lmax+1)*(lmax+2)/2)
      real plm((lmax+1)*(lmax+2)/2,2), csm(0:128,2)
      common /mesh/ xn((nt+1)**2,nd,3)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      r4pi = 0.125/asin(1.)
 
      call nulvec(uhar, (lmax+1)*(lmax+2))
 
      do ii=1,(nt+1)**2
 
         a0 = r4pi*arn(ii)
 
         do id=1,nd
 
            t1 = -xn(ii,id,2)
            t2 =  xn(ii,id,1)
            tn =  1./sqrt((1.e-100 + t1**2) + t2**2)
            t1 =  tn*t1
            t2 =  tn*t2
            uphi   =  t1*u(ii,id,1) + t2*u(ii,id,2)
            utheta =  xn(ii,id,3)*t2*u(ii,id,1)
     &             -  xn(ii,id,3)*t1*u(ii,id,2)
     &             + (xn(ii,id,2)*t1 - xn(ii,id,1)*t2)*u(ii,id,3)
 
            phi = atan2(xn(ii,id,2) + 1.e-30, xn(ii,id,1))
 
            do m=0,lmax
               csm(m,1) = a0*cos(m*phi)
               csm(m,2) = a0*sin(m*phi)
            end do
 
            b0  = 1./sqrt(1. - xn(ii,id,3)**2 + 1.e-15)
 
            if(mod(id, 5) .eq. 1)
     &         call plmbar(plm,plm(1,2),lmax,xn(ii,id,3),1)
 
            k = 1
 
            do l=1,lmax
 
               aa = 1./(l*(l + 1))
 
               do m=0,l
 
                  k  =  k + 1
                  a1 =  aa*plm(k,2)*csm(m,1)
                  a2 =  aa*plm(k,2)*csm(m,2)
                  b1 = -aa*plm(k,1)*csm(m,2)*b0*m
                  b2 =  aa*plm(k,1)*csm(m,1)*b0*m
 
                  uhar(1,k) = ((uhar(1,k) + a1*utheta) + b1*uphi)
                  uhar(2,k) = ((uhar(2,k) + a2*utheta) + b2*uphi)
 
               end do
 
            end do
 
         end do
 
      end do
 
      if(nproc .gt. 1) call psumlong(uhar, plm, (lmax+1)*(lmax+2))
 
      if(mynum .eq. 0) then
         write(6,'(/"Harmonic Coefficients for Poloidal Velocity:"/)')
         k = 1
         do l=1,lmax
            do m=0,l
               k = k + 1
               write(6,'(2i5,1p2e15.7)') l,m,uhar(1,k),uhar(2,k)
            end do
         end do
      end if
 
      end
