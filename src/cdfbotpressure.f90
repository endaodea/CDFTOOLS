PROGRAM cdfbotpressure
  !!======================================================================
  !!                     ***  PROGRAM  cdfbotpressure  ***
  !!=====================================================================
  !!  ** Purpose : Compute bottom pressure from insitu density
  !!
  !!  ** Method  : Vertical integral of rho g dz
  !!               eventually takes into account the SSH, and full step
  !!
  !! History : 3.0  : 01/2013  : J.M. Molines   : Original code from cdfvint
  !!         : 4.0  : 03/2017  : J.M. Molines  
  !!----------------------------------------------------------------------
  USE cdfio
  USE eos
  USE modcdfnames
  USE modutils
  !!----------------------------------------------------------------------
  !! CDFTOOLS_4.0 , MEOM 2017 
  !! $Id$
  !! Copyright (c) 2017, J.-M. Molines 
  !! Software governed by the CeCILL licence (Licence/CDFTOOLSCeCILL.txt)
  !! @class bottom
  !!----------------------------------------------------------------------
  IMPLICIT NONE

  INTEGER(KIND=4)                           :: jk, jt              ! dummy loop index
  INTEGER(KIND=4)                           :: it                  ! time index
  INTEGER(KIND=4)                           :: ierr, iko           ! working integer
  INTEGER(KIND=4)                           :: narg, iargc, ijarg  ! command line 
  INTEGER(KIND=4)                           :: npiglo, npjglo      ! size of the domain
  INTEGER(KIND=4)                           :: npk, npt            ! size of the domain
  INTEGER(KIND=4)                           :: ncout, nvar
  INTEGER(KIND=4)                           :: nbotpres, nssheig, nsshpre,npre3d
  INTEGER(KIND=4),DIMENSION(:), ALLOCATABLE :: ipk, id_varout      ! only one output variable

  REAL(KIND=4), PARAMETER                   :: pp_grav = 9.81      ! Gravity
  REAL(KIND=4), PARAMETER                   :: pp_rau0 = 1035.e0   ! Reference density (as in NEMO)
  REAL(KIND=4), DIMENSION(:),   ALLOCATABLE :: gdepw               ! depth
  REAL(KIND=4), DIMENSION(:),   ALLOCATABLE :: e31d                ! vertical metrics in case of full step
  REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: e3t                 ! vertical metric
  REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: hdept               ! vertical metric
  REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: zt                  ! Temperature
  REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: zs                  ! Salinity
  REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: tmask               ! npiglo x npjglo

  REAL(KIND=8), DIMENSION(:),   ALLOCATABLE :: dtim                ! time counter
  REAL(KIND=8), DIMENSION(:,:), ALLOCATABLE :: dl_psurf            ! Surface pressure
  REAL(KIND=8), DIMENSION(:,:), ALLOCATABLE :: dl_bpres            ! Bottom pressure
  REAL(KIND=8), DIMENSION(:,:), ALLOCATABLE :: dl_sigi             ! insitu density

  CHARACTER(LEN=256)                        :: cf_tfil             ! input gridT file
  CHARACTER(LEN=256)                        :: cf_sfil             ! salinity file (option)
  CHARACTER(LEN=256)                        :: cf_sshfil           ! ssh file (option)
  CHARACTER(LEN=256)                        :: cf_out='botpressure.nc'   ! output file
  CHARACTER(LEN=256)                        :: cldum               ! dummy string for command line browsing
  CHARACTER(LEN=256)                        :: cglobal             ! Global attribute

  LOGICAL                                   :: lfull =.FALSE.      ! flag for full step computation
  LOGICAL                                   :: lssh  =.FALSE.      ! Use ssh and cst surf. density in the bot pressure
  LOGICAL                                   :: lssh2 =.FALSE.      ! Use ssh and variable surf.density in the bot pressure
  LOGICAL                                   :: lxtra =.FALSE.      ! Save ssh and ssh pressure
  LOGICAL                                   :: lchk  =.FALSE.      ! flag for missing files
  LOGICAL                                   :: lnc4  =.FALSE.      ! Use nc4 with chunking and deflation
  LOGICAL                                   :: llev  =.FALSE.      ! Save pressure at each level in the output
  LOGICAL                                   :: ll_teos10  = .FALSE.! teos10 flag

  TYPE(variable), DIMENSION(:), ALLOCATABLE :: stypvar             ! extension for attributes
  !!----------------------------------------------------------------------
  CALL ReadCdfNames()

  narg= iargc()
  IF ( narg == 0 ) THEN
     PRINT *,' usage : cdfbotpressure -t T-file [-s S-file] [-full] [-ssh] [-ssh2 ] [-lev] ...'
     PRINT *,'             ... [--ssh-file SSH-file] [-xtra ] [-vvl ] [-teos10] ... '
     PRINT *,'             ... [ -o OUT-file ] [-nc4]'
     PRINT *,'      '
     PRINT *,'     PURPOSE :'
     PRINT *,'          Compute the bottom pressure (pa) from in situ density.'
     PRINT *,'      '
     PRINT *,'     ARGUMENTS :'
     PRINT *,'         -t T-file : gridT file holding both temperature and salinity.'
     PRINT *,'               If salinity is not in T-file, use -s option.'
     PRINT *,'      '
     PRINT *,'     OPTIONS :'
     PRINT *,'        [-s S-file ]: specify salinity file, if not T-file.'
     PRINT *,'      [--ssh-file SSH-file] : specify the ssh file if not in T-file.'
     PRINT *,'        [-full] : for full step computation ' 
     PRINT *,'        [-lev ] : save the 3D pressure in the output file.'
     PRINT *,'        [-ssh]  : Also take SSH into account in the computation'
     PRINT *,'                In this case, use rau0=',pp_rau0,' kg/m3 for '
     PRINT *,'                surface density (as in NEMO)'
     PRINT *,'                  If you want to use 2d surface density from '
     PRINT *,'                the model, use option -ssh2'
     PRINT *,'        [-ssh2] : as option -ssh but surface density is taken from '
     PRINT *,'                the model instead of a constant'
     PRINT *,'        [-xtra] :  Using this option, the output file also contains the ssh,'
     PRINT *,'                and the pressure contribution of ssh to bottom pressure. '
     PRINT *,'                Require either -ssh or -ssh2 option. Botpressure is still'
     PRINT *,'                the total pressure, including ssh effect.'
     PRINT *,'        [-vvl]  : Use  time-varying vertical metrics e3t'
     PRINT *,'        [-o OUT-file] : specify output file instead of ',TRIM(cf_out)
     PRINT *,'        [-nc4]  : Use netcdf4 output with chunking and deflation level 1.'
     PRINT *,'                 This option is effective only if cdftools are compiled with'
     PRINT *,'                 a netcdf library supporting chunking and deflation.'
     PRINT *,'        [-teos10] : use TEOS10 equation of state instead of default EOS80'
     print *,'                  Temperature should be conservative temperature (CT) in deg C.'
     print *,'                  Salinity should be absolute salinity (SA) in g/kg.'
     PRINT *,'      '
     PRINT *,'     OPENMP SUPPORT : yes'
     PRINT *,'      '
     PRINT *,'     REQUIRED FILES :'
     PRINT *,'       ', TRIM(cn_fmsk),' and ', TRIM(cn_fzgr) 
     PRINT *,'      '
     PRINT *,'     OUTPUT : '
     PRINT *,'       netcdf file : ',TRIM(cf_out),' unless -o option is used.'
     PRINT *,'         variables :  sobotpres, [',TRIM(cn_sossheig),' sosshpre ]'
     PRINT *,'                   :  vopressure [ in case of -lev option ]'
     PRINT *,'      '
     PRINT *,'     SEE ALSO :'
     PRINT *,'        cdfvint'
     PRINT *,'      '
     STOP 
  ENDIF
  ! browse command line
  cf_sfil='none'
  cf_sshfil='none'
  ijarg = 1   ; nvar = 1
  DO WHILE ( ijarg <= narg ) 
     CALL getarg (ijarg, cldum) ; ijarg = ijarg + 1
     SELECT CASE ( cldum)
     CASE ('-t','-f'   ) ; CALL getarg (ijarg, cf_tfil) ; ijarg = ijarg + 1
     ! options
     CASE ( '-s'       ) ; CALL getarg (ijarg, cf_sfil) ; ijarg = ijarg + 1
     CASE ('--ssh-file') ; CALL getarg(ijarg, cf_sshfil); ijarg = ijarg + 1
     CASE ( '-ssh'     ) ; lssh  = .TRUE. 
     CASE ( '-ssh2'    ) ; lssh2 = .TRUE. 
     CASE ( '-lev'     ) ; llev  = .TRUE.  ; nvar = nvar+1  ! more outputs
     CASE ( '-xtra'    ) ; lxtra = .TRUE.  ; nvar = nvar+2  ! more outputs
     CASE ( '-full'    ) ; lfull = .TRUE. 
     CASE ( '-vvl'     ) ; lg_vvl= .TRUE. 
     CASE ( '-o'       ) ; CALL getarg( ijarg,cf_out) ; ijarg = ijarg + 1
     CASE ( '-nc4'     ) ; lnc4  = .TRUE.
     CASE ( '-teos10'  ) ; ll_teos10 = .TRUE. 
     CASE DEFAULT      ; PRINT *,' ERROR : ', TRIM(cldum) ,' unknown option.'  ; STOP 99
     END SELECT
  END DO

  CALL eos_init( ll_teos10 )

  IF ( cf_sfil   == 'none' ) cf_sfil   = cf_tfil
  IF ( cf_sshfil == 'none' ) cf_sshfil = cf_tfil

  CALL SetGlobalAtt(cglobal)
  ALLOCATE ( ipk(nvar), id_varout(nvar), stypvar(nvar) )

  ! Security check
  lchk = chkfile ( cf_tfil   )
  lchk = chkfile ( cf_sfil   ) .OR. lchk
  lchk = chkfile ( cf_sshfil ) .OR. lchk
  lchk = chkfile ( cn_fmsk   ) .OR. lchk
  lchk = chkfile ( cn_fzgr   ) .OR. lchk
  IF ( lchk ) STOP 99 ! missing files

  IF ( lg_vvl ) THEN 
     cn_fe3t = cf_tfil
     cn_ve3t = cn_ve3tvvl
  ENDIF

  npiglo = getdim (cf_tfil, cn_x )
  npjglo = getdim (cf_tfil, cn_y )
  npk    = getdim (cf_tfil, cn_z )
  npt    = getdim (cf_tfil, cn_t )

  PRINT *, ' NPIGLO = ', npiglo
  PRINT *, ' NPJGLO = ', npjglo
  PRINT *, ' NPK    = ', npk
  PRINT *, ' NPT    = ', npt

  ! Allocate arrays
  ALLOCATE ( dtim(npt) )
  ALLOCATE ( tmask(npiglo,npjglo) )
  ALLOCATE ( zt(npiglo,npjglo)  )
  ALLOCATE ( zs(npiglo,npjglo)  )
  ALLOCATE ( e3t(npiglo,npjglo) )
  ALLOCATE ( hdept(npiglo,npjglo) )
  ALLOCATE ( e31d(npk)   )
  ALLOCATE ( gdepw(npk)) 

  ALLOCATE ( dl_bpres(npiglo, npjglo))
  ALLOCATE ( dl_psurf(npiglo, npjglo))
  ALLOCATE ( dl_sigi (npiglo, npjglo))

  CALL CreateOutput

  DO jt = 1, npt
     IF ( lg_vvl ) THEN ; it = jt
     ELSE ;               it = 1
     ENDIF

     IF ( lssh ) THEN
        zt(:,:)       = getvar(cf_sshfil, cn_sossheig, 1, npiglo, npjglo, ktime=jt )
        dl_psurf(:,:) = pp_grav * pp_rau0 * zt(:,:)
        IF (lxtra ) THEN
           ierr = putvar(ncout, id_varout(2) ,zt      ,       1, npiglo, npjglo, ktime=jt)
           ierr = putvar(ncout, id_varout(3) ,dl_psurf,       1, npiglo, npjglo, ktime=jt)
        ENDIF
     ELSE IF ( lssh2 ) THEN 
        zt(:,:)    = getvar(cf_tfil,   cn_votemper, 1, npiglo, npjglo, ktime=jt )
        zs(:,:)    = getvar(cf_sfil,   cn_vosaline, 1, npiglo, npjglo, ktime=jt )

        dl_sigi(:,:) = 1000.d0 + sigmai(zt, zs, 0., npiglo, npjglo)

        !  CAUTION : hdept is used for reading SSH in the next line
        hdept(:,:)   = getvar(cf_tfil, cn_sossheig, 1, npiglo, npjglo, ktime=jt )
        dl_psurf(:,:) = pp_grav * dl_sigi * hdept(:,:)
        IF (lxtra ) THEN
           ierr = putvar(ncout, id_varout(2) ,hdept   ,       1, npiglo, npjglo, ktime=jt)
           ierr = putvar(ncout, id_varout(3) ,dl_psurf,       1, npiglo, npjglo, ktime=jt)
        ENDIF
     ELSE
        dl_psurf(:,:)=0.d0
     ENDIF

     dl_bpres(:,:) = dl_psurf(:,:)

     DO jk = 1, npk
        tmask(:,:) = getvar(cn_fmsk, cn_tmask,      jk, npiglo, npjglo          )
!    JMM BUG ?  cn_hdept use to be 2D and give the depth of the bottom T point
!               in this case, hdept is used to compute the in situ density of layer jk
!               hence, should use gdept_0 ...
!        hdept(:,:) = getvar(cn_fzgr, cn_hdept,     jk, npiglo, npjglo           )
        hdept(:,:) = getvar(cn_fzgr,   cn_dept3d,    jk, npiglo, npjglo           )
        zt(:,:)    = getvar(cf_tfil,   cn_votemper,  jk, npiglo, npjglo, ktime=jt )
        zs(:,:)    = getvar(cf_sfil,   cn_vosaline,  jk, npiglo, npjglo, ktime=jt )

        dl_sigi(:,:) = 1000.d0 + sigmai(zt, zs, hdept, npiglo, npjglo)
        IF ( lfull ) THEN ; e3t(:,:) = e31d(jk)
        ELSE ; e3t(:,:) = getvar(cn_fe3t, cn_ve3t, jk, npiglo, npjglo, ktime=it, ldiom=.NOT.lg_vvl)
        ENDIF
        dl_bpres(:,:) = dl_bpres(:,:) + dl_sigi(:,:) * e3t(:,:) * pp_grav * 1.d0 * tmask(:,:) 
        IF ( llev) THEN
           ierr= putvar(ncout,id_varout(npre3d), REAL(dl_bpres),jk, npiglo, npjglo, ktime=jt)
        ENDIF

     END DO  ! loop to next level
     ierr = putvar(ncout, id_varout(1) ,REAL(dl_bpres), 1, npiglo, npjglo, ktime=jt)
  END DO  ! next time frame

  ierr = closeout(ncout)

CONTAINS
  SUBROUTINE CreateOutput
    !!---------------------------------------------------------------------
    !!                  ***  ROUTINE CreateOutput  ***
    !!
    !! ** Purpose : Create netCDF output file 
    !!
    !! ** Method  : Use Global information to create the file
    !!----------------------------------------------------------------------
    INTEGER(KIND=4) ::  ivar

    ivar=0

    ivar=ivar+1
    nbotpres=ivar
    ipk(nbotpres)                       = 1
    stypvar(nbotpres)%ichunk            = (/npiglo,MAX(1,npjglo/30),1,1 /)
    stypvar(nbotpres)%cname             = 'sobotpres'
    stypvar(nbotpres)%cunits            = 'Pascal'
    stypvar(nbotpres)%rmissing_value    = 0.
    stypvar(nbotpres)%valid_min         = 0
    stypvar(nbotpres)%valid_max         =  1.e15
    stypvar(nbotpres)%clong_name        = 'Bottom Pressure'
    stypvar(nbotpres)%cshort_name       = 'sobotpres'
    stypvar(nbotpres)%cprecision        = 'r8'
    stypvar(nbotpres)%conline_operation = 'N/A'
    stypvar(nbotpres)%caxis             = 'TYX'

    IF ( lxtra ) THEN
       ivar=ivar+1
       nssheig=ivar
       ipk(nssheig)                       = 1
       stypvar(nssheig)%ichunk            = (/npiglo,MAX(1,npjglo/30),1,1 /)
       stypvar(nssheig)%cname             = TRIM(cn_sossheig)
       stypvar(nssheig)%cunits            = 'm'
       stypvar(nssheig)%rmissing_value    =  0.
       stypvar(nssheig)%valid_min         = -10.
       stypvar(nssheig)%valid_max         =  10.
       stypvar(nssheig)%clong_name        = 'Sea Surface Height'
       stypvar(nssheig)%cshort_name       = TRIM(cn_sossheig)
       stypvar(nssheig)%conline_operation = 'N/A'
       stypvar(nssheig)%caxis             = 'TYX'

       ivar=ivar+1
       nsshpre=ivar
       ipk(nsshpre)                       = 1
       stypvar(nsshpre)%ichunk            = (/npiglo,MAX(1,npjglo/30),1,1 /)
       stypvar(nsshpre)%cname             = 'sosshpre'
       stypvar(nsshpre)%cunits            = 'Pascal'
       stypvar(nsshpre)%rmissing_value    =  0.
       stypvar(nsshpre)%valid_min         = -100000.
       stypvar(nsshpre)%valid_max         =  100000.
       stypvar(nsshpre)%clong_name        = 'Pressure due to SSH'
       stypvar(nsshpre)%cshort_name       = 'sosshpre'
       stypvar(nsshpre)%cprecision        = 'r8'
       stypvar(nsshpre)%conline_operation = 'N/A'
       stypvar(nsshpre)%caxis             = 'TYX'
    ENDIF
   
    IF ( llev ) THEN
       ivar=ivar+1
       npre3d=ivar
       ipk(npre3d)                       = npk
       stypvar(npre3d)%ichunk            = (/npiglo,MAX(1,npjglo/30),1,1 /)
       stypvar(npre3d)%cname             = 'vopressure'
       stypvar(npre3d)%cunits            = 'Pascal'
       stypvar(npre3d)%rmissing_value    =  0.
       stypvar(npre3d)%valid_min         = -100000.
       stypvar(npre3d)%valid_max         =  100000.
       stypvar(npre3d)%clong_name        = '3D Pressure'
       stypvar(npre3d)%cshort_name       = 'vopressure'
       stypvar(npre3d)%cprecision        = 'r8'
       stypvar(npre3d)%conline_operation = 'N/A'
       stypvar(npre3d)%caxis             = 'TYX'
    ENDIF

    ! Initialize output file
    gdepw(:) = getvare3(cn_fzgr, cn_gdepw, npk )
    e31d(:)  = getvare3(cn_fzgr, cn_ve3t1d,  npk )

    IF (llev) THEN
      ncout = create      (cf_out, cf_tfil, npiglo, npjglo, npk, cdep=cn_vdepthw , ld_nc4=lnc4  )
      ierr  = createvar   (ncout, stypvar, nvar, ipk, id_varout, cdglobal=cglobal, ld_nc4=lnc4  )
      ierr  = putheadervar(ncout, cf_tfil,   npiglo, npjglo, npk, pdep=gdepw,  cdep=cn_vdepthw  ) 
    ELSE
      ncout = create      (cf_out, cf_tfil, npiglo, npjglo, 1                    , ld_nc4=lnc4  )
      ierr  = createvar   (ncout, stypvar, nvar, ipk, id_varout, cdglobal=cglobal, ld_nc4=lnc4  )
      ierr  = putheadervar(ncout, cf_tfil,   npiglo, npjglo, 1                                  ) 
    ENDIF

    dtim  = getvar1d    (cf_tfil, cn_vtimec, npt     )
    ierr  = putvar1d    (ncout, dtim,        npt, 'T')

    PRINT *, 'Output files initialised ...'

  END SUBROUTINE CreateOutput

END PROGRAM cdfbotpressure
