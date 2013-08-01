#!/bin/sh
#
# NXWine - No X11 Wine for Mac OS X
#
# Created by mattintosh4 on @DATE@.
# Copyright (C) 2013 mattintosh4, https://github.com/mattintosh4/NXWine
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
prefix=/Applications/NXWine.app/Contents/Resources
set -- ${prefix}/libexec/wine "$@"

# note: usage options and non-arguments have to be processed before standard run.
case $2 in (--help|--version|"") exec "$@";; esac

# -------------------------------------
SetEnv_ ()
{
  
  dataprefix="$(osascript -e 'POSIX path of (path to library folder from user domain) & "NXWine"')"
  
  # WINEPREFIX
  if [ "${WINEPREFIX+set}" != set ]; then
    export WINEPREFIX="${dataprefix}"/prefixies/default
  fi
  
  export PATH=${prefix}/libexec:${prefix}/bin:/usr/bin:/bin:/usr/sbin:/sbin
  export LANG=${LANG:=ja_JP.UTF-8}
  
  # note: glu32.dll still needs Mesa libraries.
  export DYLD_FALLBACK_LIBRARY_PATH=/opt/X11/lib:/usr/lib
  
  # special Windows applications path
  #export WINEPATH=
  
} # end SetEnv_

SetDebug_ ()
{
  export PS4="\[\e[33m\]DEBUG:\[\e[m\] "
  set -x
  export WINEDEBUG=+loaddll
  
} # end SetDebug_

CreateWP_ ()
{
  save_WINEDEBUG="${WINEDEBUG}"
  WINEDEBUG=
  
  # initialize
  mkdir -p "${WINEPREFIX}"
  $1 wineboot.exe --init
  
  # symlink to NXWinetricks cache directory
  ln -hfs "${dataprefix}"/caches "${WINEPREFIX}"/drive_c/nxwinetricks
  
  # extract native dlls pack
  $1 7z.exe x -y -o'C:\windows' ${prefix}/share/nxwine/nativedlls/nativedlls.exe
  cat <<@REGEDIT4 | $1 regedit.exe -
[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
$(printf '"*D3DCompiler_%d"="native"\n' {37..43})
$(printf '"*d3dcompiler_%d"="native"\n' {33..36})
$(printf '"*d3dx9_%d"="native"\n' {24..43})
"*XAPOFX1_1"="native"
"*amstream"="native"
"*d3dim"="native"
"*d3drm"="native"
"*d3dxof"="native"
"*ddrawex"="native"
"*devenum"="native"
"*dinput"="native"
"*dinput8"="native"
"*dplayx"="native"
"*dpwsockx"="native"
"*dxdiag.exe"="native"
"*dxdiagn"="native"
"*gdiplus"="builtin,native"
"*mciqtz32"="native"
"*qcap"="native"
"*qedit"="native"
"*quartz"="native"
@REGEDIT4
  
  $1 regsvr32.exe \
{\
l3codecx,\
ksolay,\
ksproxy,\
mpg2splt}.ax \
{\
XAudio2_{0..7},\
amstream,\
ddrawex,\
devenum,\
diactfrm,\
dinput,\
dplayx,\
dpnhupnp,\
dpvacm,\
dpvoice,\
dpvvox,\
dsdmo{,prp},\
dxdiagn,\
dx{7,8}vb,\
encapi,\
mswebdvd,\
qasf,\
qcap,\
qdv,\
qdvd,\
qedit,\
quartz}.dll
  
  local n
  for n in diactfrm ks{,capture,filter,reg}
  do
    $1 rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 128 ${n}.inf
  done
  
  if [ "$2" = --force-init ]; then
    exit
  fi
  
  WINEDEBUG="${save_WINEDEBUG}"
} # end CreateWP_

# -------------------------------------
SetEnv_
# note: some debug options is enabled because this script is incomplete yet.
if [ "${WINEDEBUG+set}" != set ]; then
  SetDebug_
fi
if [ ! -d "${WINEPREFIX}" ] || [ "$2" = --force-init ]; then
  CreateWP_ "$@"
fi

exec "$@"
