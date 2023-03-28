#!/bin/sh
set -uC  # Add -e later

#        1         2         3         4         5         6         7         8
#2345678901234567890123456789012345678901234567890123456789012345678901234567890

# buildrpms.sh expects a colon (:) separated list of tar archive paths
# (including simple names) as each item.  The archive paths may either be
# truncated (i.e., provide only a path including the beginning of a name) or
# contain shell type wildcards (? * []).  No white-space or control characters
# are allowed in the argument string or real file paths processed, except for
# the simple space character, which must be quoted by a backslash (\) in the
# argument string, as all other critical characters (|  & ; ( ) < >), too.
# buildrpms.sh currently recognises the mutually exclusive options "-?|--help",
# "-i|--in-place" and "-n|--no-move".  By default buildrpms.sh extracts the
# spec file of each archive found, processes it and moves each valid archive
# to the ./SOURCES directory; "-n|--no-move" links each valid archive instead
# of moving.  "-i|--in-place" omits extracting and processing of spec files
# and directly uses the archives at their original location.
# If no archive list is provided, buildrpms.sh will use an internal list.

# Minimum requirements of RPM for %{name}-%{version} strings, according to
# https://rpm-software-management.github.io/rpm/manual/spec.html#preamble-tags
# [[:graph:]][[:graph:]]*-[[:alnum:]][[:alnum:].+_~^]*"
# This also covers %{name}-%{version}-%{release} strings, because
# "[[:graph:]]*" includes "-[[:alnum:]][[:alnum:].+_~^]*" and the
# requirements for %{release} are the same as for %{version}.
# My stronger, but usual requirements for %{name}-%{version} strings are
# "[[:alnum:]][-[:alnum:].+_~^]*-[[:digit:]][[:alnum:].+_~^]*" plus for
# -%{release} strings "-[[:alnum:]][[:alnum:].+_~^]*".
  
# Exit codes:
#   0  Everything worked fine: all applicable checks, all applicable preparatory steps, and the rpmbuild run(s)
#   1  A check failed
#   2  Help called
#   3  Called incorrectly (e.g., with wrong parameters)
#   4  Aborted upon user request
#   5  Error while interacting with the OS (reading / writing from the filesystem, calling programs, etc.)
#   6  Error while executing one of the preparatory steps
#   7  Error internal to this script

export LC_ALL=POSIX  # For details see https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_02
export POSIXLY_CORRECT=1  # Also necessary for a sane `df` output, see https://github.com/Olf0/sfos-upgrade/issues/73 

Separator=":"
MyPWD="$PWD"

Called="$(basename "$0")"
if printf '%s' " $(id -un) $(id -Gn) " | fgrep -q ' root '
then
  printf '%s\n' "Aborting: $Called shall not be started with root privileges!" >&2
  exit 3
fi

ProgramName="$(printf '%s' "$Called" | rev | cut -d '.' -f 2- | rev)"
LogFile="${ProgramName}.log.txt"
if ! touch "$LogFile"
then
  printf '%s\n' 'Aborting: Failed to create logfile!' >&2
  exit 5
fi
printf '%s\n' "Starting $Called at $(date -Iseconds)" | tee "$LogFile"

InPlace=N
NoMove=N
case "$1" in
-i|--in-place)
  InPlace=Y
  shift
  ;;
-n|--no-move)
  NoMove=Y
  shift
  ;;
-\?|--help)
  printf '%s\n' "Help text for $called not yet written." >&2
  exit 2
  ;;
esac

if [ -n "$2" ]
then
  printf '%s\n' "Aborting: No extra arguments expected, but called with \"${*}\"." | tee -a "$LogFile" >&2
  exit 3
elif [ -n "$1" ]
then
  Targets="$1"
else
  Targets="crypto-sdcard${Separator}mount-sdcard${Separator}sfos-upgrade'
fi
Targets="$(printf %s "$Targets" | tr "$Separator" '\n')"

if printf '%s' "$Targets" | tr ' ' '_' | egrep -q '[[:space:]]|[[:cntrl:]]'
then
  printf '%s\n' "Aborting: Argument string \"$Targets\" contains a white-space other than the simple space or control character!" | tee -a "$LogFile" >&2
  exit 3
fi

Fuzzy=N
# Quote each line and append "*" to fuzzy entries.
# Both Path- and File-Targets will only be expanded when used.
if ! printf '%s' "$Targets" | grep -vxq '[/[:alnum:]][- +./[:alnum:]_~^]*'
then
  Fuzzy=Y
  FTargets="$(printf '%s' "$Targets" | fgrep -v / | sed -e "s/^/'/" -e "s/$/*'/")"
  PTargets="$(printf '%s' "$Targets" | fgrep / | sed -e "s/^/'/" -e "s/$/*'/")"
else
  FTargets="$(printf '%s' "$Targets" | fgrep -v / | sed -e "s/^/'/" -e "s/$/'/")"
  PTargets="$(printf '%s' "$Targets" | fgrep / | sed -e "s/^/'/" -e "s/$/'/")"
fi

# Check PathTargets coarsly
RTargets=""
for i in $PTargets
do
  if ! eval eval file -L --mime-type "$i" | grep '^application/'
  then continue
  fi
  RTargets="$RTargets$(printf '\n%s' "$i")"
done

# Search for FileTargets
printf '\n%s\n' 'Fetching tar archive(s) from download directories:' | tee -a "$LogFile"
DDirs='~/Downloads ~/android_storage/Download'
gTargets=""
# find -L $DDirs -type f \! -executable \! -empty  -perm /444 -name "${i}*.tar*" -print  # Output not directly sortable by mtime, but mtime can be prepended, see line below.
# find -L . -path SOURCES -prune -o -type f \! -executable \! -empty -perm /444 -name "${i}*.tar*" -printf '%T@ %p\n' | sed 's/\.//' | sort -nr
# For "maxdepth=1":  ls -QL1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here. 
# For "maxdepth=2":  ls -QL1pFt SOURCES/${i}*.tar* 2>/dev/null | egrep -v '/$|:$|^$' | tr -d '@'  # needs complex post-processing, directories appended with ":" must be prepended recursively
# For no "maxdepth": ls -RQL1pFt SOURCES/${i}*.tar* 2>/dev/null | egrep -v '/$|:$|^$')"  # "| tr -d '@'" discards appended link markers 

for i in $FTargets
do
  if [ "$InPlace" = Y ]
  then
    # For double-eval into '%s\n':  eval eval printf "\"'%s\n'\"" …
    # or more quirky "\''%s\n'\'" or even "\'%s'\n'\'"
    gTargets="$gTargets$(printf '\n%s' "$(eval find -L "$DDirs" -type f \! -executable \! -empty -perm /444 -name "$i" -print 2> /dev/null)")"
    gTargets="$gTargets$(printf '\n%s' "$(eval find -L "." -path "'*SOURCES'" -prune -o -type f \! -executable \! -empty -perm /444 -name "$i" -print 2> /dev/null)")"
  else
    gTargets="$gTargets$(printf '\n%s' "$(eval find -L ". $DDirs" -type f \! -executable \! -empty -perm /444 -name "$i" -print 2> /dev/null)")"
  fi
done
for i in $gTargets
do
  if ! eval eval file -L --mime-type "$i" | grep '^application/'
  then continue
  fi
  RTargets="${RTargets}$(printf '\n%s' "$i")"
done

# Ultimately determine archives (ZTargets) and spec files rsp. first archive entries (STargets)
ZTargets=""
STargets=""
for i in $RTargets
do
  if k="$(eval eval tar -tf "$i" 2> /dev/null)"
  then
    # SpecFile="$(tar --wildcards -tf "$FilePath" 'rpm/*.spec')"
    # SpecFile="$(tar -tf "$FilePath" | grep -x 'rpm/.*\.spec')"
    if s="$(printf '%s' "$k" | grep '\.spec$')"
    then
      # ZTargets and STargets lists MUST be synchronised, i.e., each line
      # in both variables MUST correspond to each other, hence solely a
      # single spec file pro archive file is allowed for InPlace!=Y.
      # Alternatively the first spec file found could be selected above by, e.g.,
      # SpecFile="$(eval eval tar -tf "$i" 2> /dev/null | grep -m 1 'rpm/.*\.spec$')"
      if [ "$InPlace" = Y ]
      then
        ZTargets="$ZTargets$(printf '\n%s' "$i")"
        STargets="$STargets$(printf '\n%s' "$(printf '%s' "$k" | head -1)")"  # E.g., "xz-5.0.4/", note the trailing slash
      elif [ "$(printf '%s' "$s" | wc -l)" = 1 ]
      then
        ZTargets="$ZTargets$(printf '\n%s' "$i")"
        STargets="$STargets$(printf '\n%s' "$s")"
      else printf '%s\n%s\n' "Warning: Skipping archive \"${i}\", because more than a single spec file found in it:" "$s" | tee -a "$LogFile" >&2
      fi
    fi
  fi
done

if [ -z "$ZTargets" ]
then
  if [ -z "$RTargets" ]
  then printf '%s\n%s\n' 'No archive files found, when processing these target strings:' "$Targets"
  else printf '%s\n%s\n' 'No archive files containing a spec file found, but these archives without one:' "$RTargets"
  fi
  exit 1
fi

printf '%s\n' "Processing:'
# Building the (S)RPMs
k=0
if [ "$InPlace" = Y ]
then
  for i in $ZTargets
  do
    k=$((k+1))
    eval eval printf "\"'%s. %s\n'\"" "'\"\$k\"'" "$i" | tee -a "$LogFile"
    o="$(printf '%s' "$STargets" | sed -n "${k}P")"  # archive-internal path to first entry
    p="${o%%/*}"
    if [ "$p" = rpm ] || [ "$p" = "$o" ]
    then p="$(eval basename "$i" | sed -e 's/\.[Tt][Gg][Zz]$//' -e 's/\.[Pp][Aa][Xx]$//' -e 's/\.[Uu][Ss][Tt][Aa][Rr]$//' -e 's/\.tar[.[:alnum:]]*$//')"
    fi
    case "$(find -L RPMS -maxdepth 2 -name "${p}*.[Rr][Pp][Mm]" -print | wc -l)_$(find -L SRPMS -maxdepth 1 -name "${p}*.[Ss]*[Rr][Pp][Mm]" -print | wc -l)" in
    0_0)
      printf '%s' "  Building RPM(s) & SRPM from archive $i" | tee -a "$LogFile"
      if eval eval rpmbuild -v -ta "$i" >> "'\"\$LogFile\"'" 2>&1
      then printf '%s\n' ' succeeded.'
      else printf '%s\n' ' failed!'
      fi
      ;;
    0_*)
      printf '%s' "  Building RPM(s) from archive $i (because its SRPM already exists)" | tee -a "$LogFile"
      if eval eval rpmbuild -v -tb "$i" >> "'\"\$LogFile\"'" 2>&1
      then printf '%s\n' ' succeeded.' | tee -a "$LogFile"
      else printf '%s\n' ' failed!' | tee -a "$LogFile"
      fi
      ;;
    *_0)
      printf '%s' "  Building SRPM from archive $i (because an RPM for it already exists)" | tee -a "$LogFile"
      if eval eval rpmbuild -v -ts "$i" >> "'\"\$LogFile\"'" 2>&1
      then printf '%s\n' ' succeded.' | tee -a "$LogFile"
      else printf '%s\n' ' failed!' | tee -a "$LogFile"
      fi
      ;;
    *_*)
     printf '%s\n' "  Skip building from archive $i because its SRPM & an RPM both already exist." | tee -a "$LogFile"
      ;;
    *)
      printf '%s\n' "  Warning: Something went wrong when determining what to build (RPM and/or SRPM) from archive $i: Thus skipping it!" | tee -a "$LogFile"
      ;;
    esac
  done
else
  TmpDir="$(mktemp -p -d "${ProgramName}.XXX")"  # -t instead of -p should yield the same
  printf '\n%s\n' 'Extracting spec file from:' | tee -a "$LogFile"
  for i in $ZTargets
  do
    k=$((k+1))
    eval eval printf "\"'%s. %s'\"" "'\"\$k\"'" "$i" | tee -a "$LogFile"
    o="$(printf '%s' "$STargets" | sed -n "${k}P")"  # archive-internal path to a file ending in ".spec"
    p="${o%%/*}"
    if [ "$p" = rpm ] || [ "$p" = "$o" ]
    then p="$(eval basename "$i" | sed -e 's/\.[Tt][Gg][Zz]$//' -e 's/\.[Pp][Aa][Xx]$//' -e 's/\.[Uu][Ss][Tt][Aa][Rr]$//' -e 's/\.tar[.[:alnum:]]*$//')"
    fi
    t="$TmpDir/$p"
    mkdir "$t"
    eval eval ln -s "$i" "'\"\${t}.lnk\"'"  # Results in `ln -s <expanded path> "${t}.lnk"`
    cd "$t"
    if tar -xof "../${t}.lnk" "$o"
    then
      cd "$MyPWD"
      printf '%s' " succeded" | tee -a "$LogFile"
    else
      cd "$MyPWD"
      printf '%s/n' " failed!" | tee -a "$LogFile"
      continue
    fi
    mkdir -p SOURCES
    sPre="$(sed -n '1,\_^[[:blank:]]*%prep$_P' "$t$o" | sed -n '1,\_^[[:blank:]]*%prep[[:blank:]]*$_P' | sed -n '1,\_^[[:blank:]]*%prep[[:blank:]]*#_P')"
    sNam="$(printf %s "$sPre" | grep '^[[:blank:]]*Name:' | tail -1 | cut -s -d ':' -f 2 | cut -d '#' -f 1 | tr -d '[[:blank:]]' | grep -o '^[[:alnum:]][-+.[:alnum:]_~^]*')"
    sVer="$(printf %s "$sPre" | grep '^[[:blank:]]*Version:' | tail -1 | cut -s -d ':' -f 2 | cut -d '#' -f 1 | tr -d '[[:blank:]]' | grep -o '^[[:alnum:]][+.[:alnum:]_~^]*')"
    sRel="$(printf %s "$sPre" | grep '^[[:blank:]]*Release:' | tail -1 | cut -s -d ':' -f 2 | cut -d '#' -f 1 | tr -d '[[:blank:]]' | grep -o '^[[:alnum:]][+.[:alnum:]_~^]*')"
    if [ -n "$sNam" ] && [ -n "$sVer" ]
    then sNVR="${sNam}*-${sVer}*-${sRel}"
    else sNVR="$p"
    fi
    uIco=N
    if sIco="$(printf %s "$sPre" | grep '^[[:blank:]]*Icon:' | tail -1 | cut -s -d ':' -f 2 | cut -d '#' -f 1 | tr -d '[[:blank:]]' | grep -x '[[:alnum:]][+.[:alnum:]_~^]*\.[GgXx][IiPp][FfMm]')"
    then : # Icon tag with path detected
    elif sIco="$(printf %s "$sPre" | grep '^#Icon:' | head -1 | cut -s -d ':' -f 2 | cut -d '#' -f 1 | tr -d '[[:blank:]]' | grep -x '[[:alnum:]][+.[:alnum:]_~^]*.[GgXx][IiPp][FfMm]')"
    then  # Icon tag to uncomment with path detected; mind that the first such tag is uncommented!
      uIco=Y
    fi
    if [-n "$sIco" ]
      if [ -e "SOURCES/$sIco" ]
      then
        if [ -r "SOURCES/$sIco" ] && [ ! -d "SOURCES/$sIco" ] && [ -s "SOURCES/$sIco" ]
        then [ $uIco = Y ] && sed -i 's/^#Icon:/Icon:/' "$t$o"
        else printf '%s' ", though notice that icon file referenced in spec file $o exists at SOURCES/${sIco}, but is not usable" | tee -a "$LogFile"
        fi
      else
        if tIco="$(tar -tf "$TempDir/${t}.lnk" | fgrep "$sIco")"
        then
          cd "$t"
          tar -xof "../${t}.lnk" $tIco
          cd "$MyPWD"
          cp -sf "$(find "$t" -type f \! -executable \! -empty -perm /444 -name "$sIco" -print)" SOURCES/
          [ $uIco = Y ] && sed -i 's/^#Icon:/Icon:/' "$t$o"
        else printf '%s' ", though notice that icon file $sIco is referenced in spec file ${o}, but not found in archive $i" | tee -a "$LogFile"
        fi
      fi
    fi
    if [ "$NoMove" = Y ]
    then eval eval cp -sf "$i" SOURCES/
    else eval eval mv -f "$i" SOURCES/
    fi
    printf '%s\n' "." | tee -a "$LogFile"
    case "$(find -L RPMS -maxdepth 2 -name "${sNVR}*.[Rr][Pp][Mm]" -print | wc -l)_$(find -L SRPMS -maxdepth 1 -name "${sNVR}*.[Ss]*[Rr][Pp][Mm]" -print | wc -l)" in
    0_0)
      printf '%s' "  Building RPM(s) & SRPM from archive $i" | tee -a "$LogFile"
      if rpmbuild -v -ba "$t$o" >> "$LogFile" 2>&1
      then printf '%s\n' ' succeeded.' | tee -a "$LogFile"
      else printf '%s\n' ' failed!' | tee -a "$LogFile"
      fi
      ;;
    0_*)
      printf '%s' "  Building RPM(s) from archive $i (because its SRPM already exists)" | tee -a "$LogFile"
      if rpmbuild -v -bb "$t$o" >> "$LogFile" 2>&1
      then printf '%s\n' ' succeeded.' | tee -a "$LogFile"
      else printf '%s\n' ' failed!' | tee -a "$LogFile"
      fi
      ;;
    *_0)
      printf '%s' "  Building SRPM from archive $i (because an RPM for it already exists)" | tee -a "$LogFile"
      if rpmbuild -v -bs "$t$o" >> "$LogFile" 2>&1
      then printf '%s\n' ' succeeded.' | tee -a "$LogFile"
      else printf '%s\n' ' failed!' | tee -a "$LogFile"
      fi
      ;;
    *_*)
     printf '%s\n' "  Skip building from archive $i because its SRPM & an RPM both already exist." | tee -a "$LogFile"
      ;;
    *)
      printf '%s\n' "  Warning: Something went wrong when determining what to build (RPM and/or SRPM) from archive $i: Thus skipping it!" | tee -a "$LogFile"
      ;;
    esac
  done
fi
# rm -rf "$TmpDir"
exit 0
