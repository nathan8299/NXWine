#!/usr/bin/env - SHELL=/bin/bash TERM=xterm COMMAND_MODE=unix2003 /bin/bash
set -ex
PS4="\[\e[31m\]+\[\e[m\] "
TMPDIR=$(getconf DARWIN_USER_TEMP_DIR); HOME=$TMPDIR; export TMPDIR HOME

readonly proj_name=NXWine
readonly proj_uuid=E43FF9C9-669C-4319-8351-FF99AFF3230C
readonly proj_root="$(cd "$(dirname "$0")"; pwd)"
readonly proj_version=$(date +%Y%m%d)
readonly proj_domain=com.github.mattintosh4.${proj_name}

readonly srcroot=${proj_root}/sources
readonly workroot=$TMPDIR/${proj_uuid}
readonly destroot=/Applications/${proj_name}.app
readonly wine_destroot=${destroot}/Contents/Resources
readonly deps_destroot=${destroot}/Contents/SharedSupport
readonly toolprefix=$deps_destroot/local
readonly toolbundle=$proj_root/tools.tar.bz2

# ------------------------------------- local tools
readonly clang=/usr/local/llvm/bin/clang
readonly ccache=/usr/local/bin/ccache
readonly git=/usr/local/git/bin/git
readonly hg=/usr/local/bin/hg
[ -x $clang ]
[ -x $ccache ]
[ -x $git ]
[ -x $hg ]

# ------------------------------------- environment variables
set -a
MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion | cut -d. -f-2)
DEVELOPER_DIR=$(xcode-select -print-path)
SDKROOT=$(xcodebuild -version -sdk macosx$MACOSX_DEPLOYMENT_TARGET | sed -n '/^Path: /s///p')
PATH=$(tr '\n' ':' <<@EOS
$deps_destroot/bin
$toolprefix/bin
/usr/local/llvm/bin
$(dirname $git)
$(getconf PATH)
@EOS); PATH=${PATH%?}
CC="$ccache $clang"
CXX="$ccache $clang++"
CFLAGS="-pipe -O3 -m32 -arch i386 -march=core2 -mtune=core2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
CXXFLAGS="$CFLAGS"
CPPFLAGS="-isysroot $SDKROOT -I$deps_destroot/include"
LDFLAGS="-arch i386 -Wl,-search_paths_first -Wl,-headerpad_max_install_names -Wl,-syslibroot,$SDKROOT -L$deps_destroot/lib"
ACLOCAL_PATH=$deps_destroot/share/aclocal:$toolprefix/share/aclocal
MAKE=$(xcrun -find gnumake)
LANG=ja_JP.UTF-8; LC_ALL=$LANG; gt_cv_locale_ja=$LANG
set +a

triple=i686-apple-darwin$(uname -r)
configure_pre_args="--prefix=$deps_destroot --build=$triple --disable-dependency-tracking"
configure_args="$(echo  $configure_pre_args \
                        --enable-{shared,static} \
                        --disable-{debug,documentation,maintainer-mode,gtk-doc{,-{html,pdf}}} \
                        --without-{html-dir,xml-catalog,x})"
make_args="-j $(($(sysctl -n hw.ncpu) + 1))"

# ------------------------------------- package sources
for pkg in \
  ${pkgsrc_7z=7z922.exe} \
  ${pkgsrc_gecko=wine_gecko-2.21-x86.msi} \
  ${pkgsrc_mono=wine-mono-0.0.8.msi} \
  autoconf-2.69.tar.gz \
  automake-1.13.2.tar.gz \
  cabextract-1.4.tar.gz \
  coreutils-8.21.tar.bz2 \
  faenza-icon-theme_1.3.zip \
  gettext-0.18.3.tar.gz \
  help2man-1.41.2.tar.gz \
  libtool-2.4.2.tar.gz \
  m4-1.4.16.tar.bz2 \
  p7zip_9.20.1_src_all.tar.bz2 \
  unixODBC-2.3.1.tar.gz \
; do [ -f $srcroot/$pkg ]; done

# ------------------------------------- utilities functions
makeallins(){ $MAKE $make_args && $MAKE install; }
mkdircd(){ mkdir -p "${@:?}" && cd "$_"; }
scmcopy(){ cp -RHf $srcroot/${1:?} $workroot; cd $workroot/$1; }
DocCompress_ ()
{
  local n=$1
  set -- $(cd ${workroot} && find -E $1 -maxdepth 1 -type f -regex '.*/(ANNOUNCE|AUTHORS|CHANGES|ChangeLog|COPYING(.LIB)?|LICENSE|NEWS|README|RELEASE|TODO|VERSION)(\.txt)?')
  if [ $# = 0 ]; then return
  else
    (cd $workroot && tar cf - "$@" | 7z a -si $deps_destroot/share/doc/doc_$n.tar.xz) || false
  fi
} # end DocCompress_

# ------------------------------------- build processing functions
BuildDeps_ ()
{
  7z x -y -so $srcroot/$1-* | tar x - -C $workroot
  cd $workroot/$1-*
  case $1 in
    cabextract)
      set -- ${configure_args/$deps_destroot/$wine_destroot}
    ;;
    gsm)
      $"patch_gsm"
      $MAKE
      $MAKE install
      $(xcrun -find libtool 2>/dev/null || echo /usr/bin/libtool) -dynamic -v -o $deps_destroot/lib/libgsm.1.dylib -install_name $deps_destroot/lib/libgsm.1.dylib -compatibility_version 1.0.0 -current_version 1.0.13 -lc lib/libgsm.a
      ln -s libgsm.1.dylib $deps_destroot/lib/libgsm.dylib
      (cd $workroot && tar cf - gsm-1.0-pl13/{ChangeLog,COPYRIGHT,README} | 7z a -si $deps_destroot/share/doc/doc_gsm.tar.xz) || false
      return
    ;;
    *)
      set -- $configure_args
    ;;
  esac
  ./configure "$@"
  $"makeallins"
} # end BuildDeps_

BuildDevel_ ()
{
  $"scmcopy" $1
  
  case $1 in
    flac)
      ./autogen.sh
      ./configure $configure_args --disable-{asm-optimizations,xmms-plugin}
    ;;
    freetype)
      git checkout -f master
      ./autogen.sh
      ./configure $configure_args
    ;;
    glib)
      git checkout -f 2.37.2
      ./autogen.sh $configure_args --disable-{selinux,fam,xattr} --with-threads=posix CC="$ccache $(xcrun -find gcc-4.2)" CXX="$ccache $(xcrun -find g++-4.2)"
    ;;
    gmp-5.1)
      sed -n '/^@set/p' .bootstrap >doc/version.texi
      autoreconf -i
      $"mkdircd" build
      ../configure $configure_pre_args CC=$clang CXX=$clang++ ABI=32
      $MAKE $make_args
      $MAKE check
      $MAKE install
    ;;
    gnutls)
      git checkout -f master
      git log | grep -v "^commit" > ChangeLog
      $MAKE CFGFLAGS="$configure_args --disable-guile --without-p11-kit" bootstrap
    ;;
    guile)
      git checkout -f stable-2.0
      ./autogen.sh
      ./configure $configure_args
    ;;
    icu-release-51-2) # rev 33743, release-51-2
      cd source
      ./configure ${configure_args} --enable-rpath --with-library-bits=32
      $"makeallins"
      (cd $workroot && tar cf - icu/{license,readme}.html | 7z a -si $deps_destroot/share/doc/doc_icu.tar.xz) || false
      return
    ;;
    Little-CMS)
      git checkout -f master
      ./configure $configure_args
    ;;
    libffi)
      git checkout -f master
      ./configure ${configure_args}
    ;;
    libjpeg-turbo)
      git checkout -f master
      autoreconf -i
      ./configure ${configure_args} --with-jpeg8
      make $make_args
      set -- $deps_destroot/share/doc/libjpeg-turbo
      make docdir=$1 exampledir=$1 install
      return
    ;;
    libmodplug)
      autoreconf -i
      ./configure $configure_args
    ;;
    libpng)
      git checkout -f libpng16
      autoreconf -i
      ./configure ${configure_args}
    ;;
    libtasn1)
      git checkout -f master
      git log --date=short --pretty=format:"%ad %an <%ae>%n%n"$'\t'"%s%n%b" > ChangeLog
      autoreconf -i
      ./configure $configure_args --disable-silent-rules
      # note: libtasn1-devel will fail with parallel build.
      $MAKE
      $MAKE install
      return
    ;;
    libtiff)
      ./configure ${configure_args}
      $"makeallins"
      return
    ;;
    libusb|libusb-compat-0.1)
      ./autogen.sh ${configure_args}
    ;;
    libxml2)
      git checkout -f master
      ./autogen.sh ${configure_args} --with-{icu,python} --disable-silent-rules
    ;;
    libxslt)
      git checkout -f master
      ./autogen.sh ${configure_args} --disable-silent-rules
    ;;
    mpg123)
      autoreconf -i
      ./configure ${configure_args} --with-default-audio=coreaudio --with-optimization=3
    ;;
    nettle)
      git checkout -f nettle-2.7-fixes
      ./.bootstrap
      ./configure ${configure_args}
    ;;
    ogg)
      sed -i '' 's/--enable-maintainer-mode //' autogen.sh
      sed -i '' 's/-O4 //' configure.in
      ./autogen.sh $configure_args
    ;;
    orc)
      git checkout -f master
      autoreconf -fi
      ./configure $configure_args CC="$ccache $(xcrun -find gcc-4.2)" CXX="$ccache $(xcrun -find g++-4.2)"
    ;;
    pkg-config)
      git checkout -f master
      ./autogen.sh  ${configure_args} \
                    --disable-host-tool \
                    --with-internal-glib \
                    --with-pc-path=${deps_destroot}/lib/pkgconfig:${deps_destroot}/share/pkgconfig:/usr/lib/pkgconfig
    ;;
    python) # python 2.7
      $hg checkout -C 2.7
      $"mkdircd" build
      ../configure $configure_args
      # note: python will fail with parallel build.
      $MAKE
      $MAKE install
      return
    ;;
    readline)
      git checkout -f master
      $"patch_readline"
      ./configure ${configure_args} --enable-multibyte --with-curses
    ;;
    sane-backends)
      git checkout -f master
      ./configure $configure_args
    ;;
    SDL)
      $hg checkout -C SDL-1.2
      ./autogen.sh
      # note: mercurial repository must be separated a build directory.
      $"mkdircd" build
      ../configure ${configure_args}
    ;;
    SDL_sound)
      ./bootstrap
      # note: mercurial repository must be separated a build directory.
      $"mkdircd" build
      ../configure ${configure_args}
    ;;
    theora)
      ./autogen.sh ${configure_args} --disable-{oggtest,vorbistest,examples,asm}
    ;;
    vorbis)
      sed -i '' 's/--enable-maintainer-mode //' autogen.sh
      sed -i '' 's/-O4 //' configure.ac
      ./autogen.sh $configure_args
    ;;
    xz)
      git checkout -f v5.0
      ./autogen.sh
      ./configure ${configure_args}
      $"makeallins"
      return
    ;;
    zlib)
      git checkout -f master
      ./configure --prefix=${deps_destroot}
    ;;
    harfbuzz|cairo|gobject-introspection)
      ./autogen.sh $configure_args
    ;;
  esac
  $"makeallins"
  DocCompress_ $1
} # end BuildDevel_

BuildTools_ ()
{
  set -- \
    gettext     \
    m4          \
    autoconf    \
    automake    \
    libtool     \
    coreutils   \
    help2man    \
    texinfo     \
    pkg-config  \
    nasm        \
    yasm        \
    p7zip
  
  local CPPFLAGS="${CPPFLAGS/$deps_destroot/$toolprefix}"
  local LDFLAGS="${LDFLAGS/$deps_destroot/$toolprefix}"
  local configure_args="${configure_pre_args/$deps_destroot/$toolprefix}"
  
  set -- dummy "$@"
  while shift && [ "$1" ]
  do
    case $1 in
      # ------------------------------------- scm sources
      nasm)
        $"scmcopy" $1
        git checkout -f master
        ./autogen.sh
        ./configure $configure_args
      ;;
      texinfo) # texinfo required from libtasn1-devel
        $"scmcopy" $1
        ./autogen.sh
        ./configure $configure_args
      ;;
      pkg-config)
        $"scmcopy" $1
        git checkout -f master
        ./autogen.sh  $configure_args \
                      --disable-host-tool \
                      --with-internal-glib \
                      --with-pc-path=$(set -- {$deps_destroot/{lib,share},/usr/lib}/pkgconfig; IFS=:; echo "$*")
      ;;
      yasm) # yasm required from mpg123
        $"scmcopy" $1
        git checkout -f master
        sed -i '' 's/--enable-maintainer-mode //' autogen.sh
        ./autogen.sh $configure_args
      ;;
      
      # ------------------------------------- tarball sources
      *)
        tar xf $srcroot/$1[-_]* -C $workroot
        cd $workroot/$1[-_]*
        
        case $1 in
          coreutils)
            ./configure $configure_args --program-prefix=g --enable-threads=posix --without-gmp
            $"makeallins"
            ln -s {g,$toolprefix/bin/}readlink
            continue
          ;;
          gettext)
            $"mkdircd" prebuild
            ../configure $configure_args
          ;;
          help2man) # help2man required from texinfo
            ./configure $configure_args
          ;;
          libtool)
            ./configure $configure_args --program-prefix=g
            $"makeallins"
            ln -s {g,$toolprefix/bin/}libtool
            ln -s {g,$toolprefix/bin/}libtoolize
            continue
          ;;
          m4)
            ./configure $configure_args --program-prefix=g
            $"makeallins"
            ln -s {g,$toolprefix/bin/}m4
            continue
          ;;
          p7zip)
            sed "
              s#^CXX=c++#CXX=$CXX#
              s#^CC=cc#CC=$CC#
            " makefile.macosx_32bits > makefile.machine
            sed -i "" "
              s#444#644#g
              s#555#755#g
              s#777#755#g
            " install.sh
            $MAKE $make_args all3
            $MAKE DEST_HOME=$toolprefix install
            continue
          ;;
          *)
            ./configure $configure_args
          ;;
        esac
      ;;
    esac
    $"makeallins"
  done
  tar cjf $toolbundle -C $(dirname $toolprefix) $(basename $toolprefix)
}



Bootstrap_ ()
{
# ------------------------------------- begin preparing
  rm -rf ${workroot} ${destroot}
  sed "s|@DATE@|$(date +%F)|g" ${proj_root}/scripts/main.applescript | osacompile -s -o ${destroot}
  install -m 0644 ${proj_root}/nxwine.icns ${destroot}/Contents/Resources/droplet.icns
  install -d  ${deps_destroot}/{bin,include,share/{man,doc}} \
              ${wine_destroot}/lib \
              ${workroot}
  ln -fhs {../Resources,${deps_destroot}}/lib
  
  # ------------------------------------- begin tools build
  if [ -f $toolbundle ]
  then
    tar xf $toolbundle -C $deps_destroot
  else
    BuildTools_
  fi
  
  # ------------------------------------- begin build
  BuildDeps_  gsm
#  BuildDevel_ icu-release-51-2
  BuildDeps_  gettext
  BuildDeps_  libtool
  BuildDevel_ readline
  BuildDevel_ zlib
  BuildDevel_ xz
#  BuildDevel_ python
#  BuildDevel_ libxml2
#  BuildDevel_ libxslt
} # end Bootstrap_

BuildStage1_ ()
{
  BuildDevel_ gmp-5.1
  BuildDevel_ libffi
  BuildDevel_ glib
} # end BuildStage1_

BuildStage2_ ()
{
  BuildDevel_ libpng
  BuildDevel_ freetype                # freetype requires libpng
  BuildDevel_ libjpeg-turbo
  BuildDevel_ libtiff
  BuildDevel_ Little-CMS
} # end BuildStage3_

BuildStage3_ ()
{
  BuildDevel_ libtasn1
  BuildDevel_ nettle                  # nettle requires gmp
  BuildDevel_ gnutls
  BuildDevel_ libusb
  BuildDevel_ libusb-compat-0.1
  BuildDevel_ sane-backends           # sane-backends requires jpeg
  BuildDevel_ orc
  BuildDeps_  unixODBC
} # end BuildStage2_


BuildStage3a_ ()
{
  routine_(){
    7z x -so $srcroot/$1-* | tar x - -C $workroot
    cd $workroot/$1-*
    shift
    ./configure $configure_args "$@"
    $"makeallins"
  }
  routine_ gnome-common
  routine_ libart_lgpl
  routine_ libcroco --disable-Bsymbolic
  routine_ pixman
  routine_ ragel
  BuildDevel_ cairo
  BuildDevel_ gobject-introspection
  BuildDevel_ harfbuzz
  routine_ pango
  routine_ gdk-pixbuf                 # gdk-pixbuf-2.29 required glib 2.37
  routine_ librsvg --disable-Bsymbolic
  unset routine_
}

BuildStage4_ ()
{
#  BuildDevel_ libmodplug
#  BuildDevel_ ogg
#  BuildDevel_ vorbis
#  BuildDevel_ flac
#  BuildDevel_ SDL                     # SDL required nasm
  BuildDevel_ mpg123                  # mpg123 required SDL
#  BuildDevel_ SDL_sound
#  BuildDevel_ theora                  # libtheora required SDL
} # end BuildStage4_

BuildStage5_ ()
{
  set -- $wine_destroot
  # ------------------------------------- cabextract
  BuildDeps_ cabextract
  (set -- $1/share/doc/cabextract-1.4 && mkdir -p $1 && install -m 0644 $workroot/cabextract-1.4/{AUTHORS,ChangeLog,COPYING,NEWS,README,TODO} $1) || false
  # ------------------------------------- winetricks
  (set -- $1/libexec                  && mkdir -p $1 && install -m 0755 $srcroot/winetricks/src/winetricks      $1) || false
  (set -- $1/share/man/man1           && mkdir -p $1 && install -m 0644 $srcroot/winetricks/src/winetricks.1    $1) || false
  (set -- $1/share/doc/winetricks     && mkdir -p $1 && install -m 0644 $srcroot/winetricks/src/COPYING         $1) || false
  # ------------------------------------- nxwinetricks
  (set -- $1/bin                      && mkdir -p $1 && install -m 0755 $proj_root/scripts/winetricksloader.sh  $1/winetricks) || false
  # ------------------------------------- 7-Zip
  7z x -y -o$1/share/nxwine/programs/7-Zip -x\!\$\* $srcroot/$pkgsrc_7z
  
  # strip out debug and non-global symbols
  find ${deps_destroot}/lib -type f \( -name "*.dylib" -o -name "*.so" \) | xargs strip -S -x
} # end BuildStage5_

BuildWine_ ()
{
  $"scmcopy" wine
  git checkout -f master

  patch -Np1 < $proj_root/patches/changelocale.patch
  patch -Np1 < $proj_root/patches/autorelease.patch
  patch -Np1 < $proj_root/patches/autohidemenu.patch
  patch -Np1 < $proj_root/patches/excludefonts.patch
  
  args=(
    --prefix=$wine_destroot
    --build=$triple
    --with-opengl
    --with-x
    --without-capi
    --without-gphoto
    --without-oss
    --without-v4l
    --x-includes=/opt/X11/include
    --x-libraries=/opt/X11/lib
  )
  
  ./configure $args
  $"makeallins"
  
  mkdir -p $wine_destroot/libexec && mv $wine_destroot/bin/wine $_
  install -m 0755 $proj_root/scripts/wineloader.sh    $wine_destroot/bin/wine
  install -m 0755 $proj_root/scripts/nxwinetricks.sh  $wine_destroot/bin/nxwinetricks
  sed -i "" "s|@DATE@|$(date +%F)|g" $bindir/{wine,nxwinetricks}
} # end BuildWine_

BuildStage6_ ()
{
  local bindir=$wine_destroot/bin
  local libdir=$wine_destroot/lib
  local datadir=$wine_destroot/share
  local docdir=$datadir/doc
  
#  mkdir -p $datadir/wine/gecko  && install -m 0644 $srcroot/$pkgsrc_gecko $_
#  mkdir -p $datadir/wine/mono   && install -m 0644 $srcroot/$pkgsrc_mono $_
  mkdir -p $docdir/wine         && install -m 0644 $srcroot/wine/{ANNOUNCE,AUTHORS,COPYING.LIB,LICENSE,README,VERSION} $_
  
  # ------------------------------------- fonts
  tar xf $srcroot/fonts/sazanami-20040629.tar.bz2 -C $docdir
  mv $docdir/*/*.ttf $datadir/wine/fonts
  
  # ------------------------------------- inf
  (
    set -- $datadir/wine/wine.inf &&
    mv $1 $1.orig &&
    m4 $proj_root/scripts/inf.m4 | cat $1.orig /dev/fd/3 3<&0 | uconv -f UTF-8 -t UTF-8 --add-signature -o $1 &&
    :
  ) || false
  
  # ------------------------------------- native dlls
  InstallNativedlls_ ()
  {
    ## DirectX 9.0c
    7z e -o$datadir/wine/directx9/feb2010 $srcroot/nativedlls/directx_feb2010_redist.exe
    7z e -o$datadir/wine/directx9/jun2010 $srcroot/nativedlls/directx_Jun2010_redist.exe -x'!*200?*'
    
    ## Visual C++
    ditto {$srcroot/nativedlls,$datadir/wine}/vcrun2005/vcredist_x86.exe
    ditto {$srcroot/nativedlls,$datadir/wine}/vcrun2008sp1/vcredist_x86.exe
    ditto {$srcroot/nativedlls,$datadir/wine}/vcrun2010sp1/vcredist_x86.exe
    
    ## Visual Basic 6.0 SP 6
    ## http://www.microsoft.com/ja-jp/download/details.aspx?id=24417
    7z e -o$datadir/wine/vbrun60sp6 $srcroot/nativedlls/vbrun6sp6/VB6.0-KB290887-X86.exe vbrun60sp6.exe
  }
  InstallNativedlls_
    
  # ------------------------------------- plist
  wine_version=$(GIT_DIR=$workroot/wine/.git git describe HEAD 2>/dev/null)
  : ${wine_version:?}
  
  plist=$destroot/Contents/Info.plist
  while read
  do
    /usr/libexec/PlistBuddy -c "$REPLY" $plist
  done <<EOS
Set :CFBundleIconFile         string droplet
Add :NSHumanReadbuleCopyright string ${wine_version}, Copyright © 2013 mattintosh4, https://github.com/mattintosh4/NXWine
Add :CFBundleVersion          string ${proj_version}
Add :CFBundleIdentifier       string ${proj_domain}
EOS
  
  i=1
  while read e n
  do
    while read
    do
      /usr/libexec/PlistBuddy -c "$REPLY" $plist
    done <<EOS
Add :CFBundleDocumentTypes:${i}:CFBundleTypeExtensions    array
Add :CFBundleDocumentTypes:${i}:CFBundleTypeExtensions:0  string ${e}
Add :CFBundleDocumentTypes:${i}:CFBundleTypeIconFile      string droplet
Add :CFBundleDocumentTypes:${i}:CFBundleTypeName          string ${n}
Add :CFBundleDocumentTypes:${i}:CFBundleTypeRole          string Viewer
EOS
    ((i++))
  done <<__EOS__
exe   Windows Executble File
msi   Microsoft Windows Installer
lnk   Windows Shortcut File
7z    7z archive
cab   cab Archive
lha   lha Archive
lzh   lzh Archive
lzma  lzma Archive
rar   rar Archive
xz    xz Archive
zip   zip Archive
__EOS__
  
  
  # faenza icon theme
  (set -- faenza-icon-theme_1.3 && unzip -od $docdir/$1 $srcroot/$1.zip AUTHORS ChangeLog COPYING README) || false
  (set -- $docdir/nxwine && mkdir -p $1 && install -m 0644 $proj_root/COPYING $1) || false
  
  # remove unnecessary files for wine
  rm -f ${libdir:?}/*.{a,la}
  rm -rf ${datadir:?}/applications
  
  # move dependencies documents
  cp -R ${deps_destroot}/share/doc ${wine_destroot}/share
  
  # remove unnecessary files for dependencies
  find ${deps_destroot:?} -mindepth 1 -type d | xargs rm -rf
  
  mod_rpath(){
    set -- $(find $wine_destroot/lib/*.dylib -type f)
    while [ "$1" ]
    do
      install_name_tool -id @rpath/$(basename $1) $1
      otool -L $1 | awk 'NR >= 2 && /\/Applications/ { print $1 }' | while read
      do
        install_name_tool -change $REPLY @rpath/$(basename $REPLY) $1
      done
      shift
    done
  }
#  mod_rpath
  
} # end BuildStage6_

BuildDmg_ ()
{
  set -- $workroot/$proj_name.{dst,pkg}
  mkdir -p $1
  mv $destroot $1
  
  # create installer
  args=(
    --component-plist     $proj_root/scripts/installer-component.plist
    --install-location    /Applications
    --ownership           preserve
    --root                $1
    $2
  )
  pkgbuild "${args[@]}"
  
  # create disk image
  args=(
    -ov
    -srcdir $2
    -volname $proj_name
    $proj_root/${proj_name}_${proj_version}_${wine_version/wine-}.dmg
  )
  hdiutil create "${args[@]}"
  
  rm -rf $1
} # end BuildDmg_

# -------------------------------------- patch
patch_gsm(){
  m4  -D_CC="$CC" \
      -D_CFLAGS="$CFLAGS" \
      -D_PREFIX=$deps_destroot \
<<\@EOS | patch -Np0
--- Makefile.orig
+++ Makefile
@@ -43,8 +43,8 @@
 # CC		= /usr/lang/acc
 # CCFLAGS 	= -c -O
 
-CC		= gcc -ansi -pedantic
-CCFLAGS 	= -c -O2 -DNeedFunctionPrototypes=1
+CC		= _CC -ansi -pedantic
+CCFLAGS 	= -c _CFLAGS -DNeedFunctionPrototypes=1
 
 LD 		= $(CC)
 
@@ -71,7 +71,7 @@
 # Leave INSTALL_ROOT empty (or just don't execute "make install") to
 # not install gsm and toast outside of this directory.
 
-INSTALL_ROOT	=
+INSTALL_ROOT	= _PREFIX
 
 # Where do you want to install the gsm library, header file, and manpages?
 #
@@ -80,7 +80,7 @@
 
 GSM_INSTALL_ROOT = $(INSTALL_ROOT)
 GSM_INSTALL_LIB = $(GSM_INSTALL_ROOT)/lib
-GSM_INSTALL_INC = $(GSM_INSTALL_ROOT)/inc
+GSM_INSTALL_INC = $(GSM_INSTALL_ROOT)/include
 GSM_INSTALL_MAN = $(GSM_INSTALL_ROOT)/man/man3
 
 
@@ -100,7 +100,7 @@
 BASENAME 	= basename
 AR		= ar
 ARFLAGS		= cr
-RMFLAGS		=
+RMFLAGS		= -f
 FIND		= find
 COMPRESS 	= compress
 COMPRESSFLAGS 	= 
@@ -258,18 +258,12 @@
 
 GSM_INSTALL_TARGETS =	\
 		$(GSM_INSTALL_LIB)/libgsm.a		\
-		$(GSM_INSTALL_INC)/gsm.h		\
-		$(GSM_INSTALL_MAN)/gsm.3		\
-		$(GSM_INSTALL_MAN)/gsm_explode.3	\
-		$(GSM_INSTALL_MAN)/gsm_option.3		\
-		$(GSM_INSTALL_MAN)/gsm_print.3
+		$(GSM_INSTALL_INC)/gsm.h
 
 TOAST_INSTALL_TARGETS =	\
 		$(TOAST_INSTALL_BIN)/toast		\
 		$(TOAST_INSTALL_BIN)/tcat		\
-		$(TOAST_INSTALL_BIN)/untoast		\
-		$(TOAST_INSTALL_MAN)/toast.1
-
+		$(TOAST_INSTALL_BIN)/untoast
 
 # Default rules
 
@@ -351,25 +345,25 @@
 		fi
 
 $(TOAST_INSTALL_BIN)/toast:	$(TOAST)
-		-rm $@
+		-rm $(RMFLAGS) $@
 		cp $(TOAST) $@
 		chmod 755 $@
 
 $(TOAST_INSTALL_BIN)/untoast:	$(TOAST_INSTALL_BIN)/toast
-		-rm $@
+		-rm $(RMFLAGS) $@
 		ln $? $@
 
 $(TOAST_INSTALL_BIN)/tcat:	$(TOAST_INSTALL_BIN)/toast
-		-rm $@
+		-rm $(RMFLAGS) $@
 		ln $? $@
 
 $(TOAST_INSTALL_MAN)/toast.1:	$(MAN)/toast.1
-		-rm $@
+		-rm $(RMFLAGS) $@
 		cp $? $@
 		chmod 444 $@
 
 $(GSM_INSTALL_MAN)/gsm.3:	$(MAN)/gsm.3
-		-rm $@
+		-rm $(RMFLAGS) $@
 		cp $? $@
 		chmod 444 $@
 
@@ -389,12 +383,12 @@
 		chmod 444 $@
 
 $(GSM_INSTALL_INC)/gsm.h:	$(INC)/gsm.h
-		-rm $@
+		-rm $(RMFLAGS) $@
 		cp $? $@
 		chmod 444 $@
 
 $(GSM_INSTALL_LIB)/libgsm.a:	$(LIBGSM)
-		-rm $@
+		-rm $(RMFLAGS) $@
 		cp $? $@
 		chmod 444 $@
 
@EOS
}

patch_readline (){ patch -Np1 <<\@EOS
--- a/support/shobj-conf
+++ b/support/shobj-conf
@@ -157,19 +157,19 @@ freebsd[4-9]*|freebsdelf*|dragonfly*)
 	;;
 
 # Darwin/MacOS X
-darwin[89]*|darwin1[012]*)
+darwin[89]*|darwin1[0-9]*)
 	SHOBJ_STATUS=supported
 	SHLIB_STATUS=supported
 	
 	SHOBJ_CFLAGS='-fno-common'
 
-	SHOBJ_LD='MACOSX_DEPLOYMENT_TARGET=10.3 ${CC}'
+	SHOBJ_LD='${CC}'
 
 	SHLIB_LIBVERSION='$(SHLIB_MAJOR)$(SHLIB_MINOR).$(SHLIB_LIBSUFF)'
 	SHLIB_LIBSUFF='dylib'
 
-	SHOBJ_LDFLAGS='-dynamiclib -dynamic -undefined dynamic_lookup -arch_only `/usr/bin/arch`'
-	SHLIB_XLDFLAGS='-dynamiclib -arch_only `/usr/bin/arch` -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
+	SHOBJ_LDFLAGS='-dynamiclib -dynamic -undefined dynamic_lookup'
+	SHLIB_XLDFLAGS='-dynamiclib -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
 
 	SHLIB_LIBS='-lncurses'	# see if -lcurses works on MacOS X 10.1 
 	;;
@@ -186,11 +186,11 @@ darwin*|macosx*)
 	SHLIB_LIBSUFF='dylib'
 
 	case "${host_os}" in
-	darwin[789]*|darwin1[012]*)	SHOBJ_LDFLAGS=''
-			SHLIB_XLDFLAGS='-dynamiclib -arch_only `/usr/bin/arch` -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
+	darwin[789]*|darwin1[0-9]*)	SHOBJ_LDFLAGS=''
+			SHLIB_XLDFLAGS='-dynamiclib -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
 			;;
 	*)		SHOBJ_LDFLAGS='-dynamic'
-			SHLIB_XLDFLAGS='-arch_only `/usr/bin/arch` -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
+			SHLIB_XLDFLAGS='-install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
 			;;
 	esac
 
@EOS
}

# -------------------------------------- begin processing section
Bootstrap_
BuildStage1_
BuildStage2_
BuildStage3_
#BuildStage3a_
BuildStage4_
BuildStage5_
BuildWine_
BuildStage6_
BuildDmg_

# -------------------------------------- end processing section

:
echo "$(($SECONDS / 60)) min ($SECONDS sec)"
afplay /System/Library/Sounds/Hero.aiff
