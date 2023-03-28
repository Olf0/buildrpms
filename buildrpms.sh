#!/bin/sh
set -uC  # Add -e later

#        1         2         3         4         5         6         7         8
#2345678901234567890123456789012345678901234567890123456789012345678901234567890

# buildrpms.sh expects a colon (:) separated list of tar archive names or paths
# as each item.  The archive names may either be truncated (i.e., provide only
# the beginning of their names) or contain shell type wildcards (? * []).  No
# white-space or control characters are allowed in the argument string or real
# file names processed, except for the simple space character, which must be
# quoted by a backslash (\) in the argument string, as all other critical
# characters (|  & ; ( ) < >), too.
# buildrpms.sh currently recognises the options "-i|--in-place" and
# "-?|--help".
# If no argument is given, buildrpms.sh will use an internal list.

# Generally the "name-version" scheme and the character sets used
# for either "name" and "version", shall adhere to the RPM spec-
# file specification:
# https://rpm-software-management.github.io/rpm/manual/spec.html#preamble-tags

# Exit codes:
#   0  Everything worked fine: all applicable checks, all applicable preparatory steps, and the rpmbuild run(s)
#   1  A check failed
#   2  Help called
#   3  Called incorrectly (e.g., with wrong parameters)
#   4  Aborted upon user request
#   5  Error while interacting with the OS (reading / writing from the filesystem, calling programs, etc.)
#   6  Error while executing one of the preparatory steps
#   7  Error internal to this script

export LANG=C  # Engineering English only
export LC_CTYPE=POSIX
export LC_COLLATE=POSIX
# export IFS="$(printf '\n')"

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
  exit 3
fi
printf '%s\n' "Starting $Called at $(date -Iseconds)" | tee "$LogFile"

InPlace=N
case "$1" in
-i|--in-place)
  InPlace=Y
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
# Both Path- and File-Targets will only be expanded, where necessary.
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
# find -L $DDirs -type f \! -executable \! -empty  -perm /444 -name "${i}*.tar*" -print  # Output not directly sortable by mtime.
# find -L . -path SOURCES -prune -o -type f \! -executable \! -empty -perm /444 -name "${i}*.tar*" -printf '%T@ %p\n' | sed 's/\.//' | sort -nr
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

# Ultimately determining archives or spec files to process
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
  printf '%s\n%s\n' 'No archive files containing a spec file found after processing the target strings:' "$Targets"
  exit 1
fi

# Building the (S)RPMs
k=0
if [ "$InPlace" = Y ]
then
  for i in $ZTargets
  do
    k=$((k+1))
    o="$(printf '%s' "$STargets" | sed -n "${k}P")"
    p="${o%%/*}"
    if [ "$p" = rpm ] || [ "$p" = "$o" ]
    then p="$(eval basename "$i" | sed -e 's/\.[Tt][Gg][Zz]$//' -e 's/\.[Pp][Aa][Xx]$//' -e 's/\.[Uu][Ss][Tt][Aa][Rr]$//' -e 's/\.tar[.[:alnum:]]*$//')"
    fi
    case "$(find -L RPMS -maxdepth 2 -name "${p}*.[Rr][Pp][Mm]" -print | wc -l)_$(find -L SRPMS -maxdepth 1 -name "${p}*.[Ss]*[Rr][Pp][Mm]" -print | wc -l)" in
    0_0)
      printf '%s' "- Building RPM(s) & SRPM from archive $i" | tee -a "$LogFile"
      if eval eval rpmbuild -v -ta "$i" >> '"$LogFile"' 2>&1
      then printf '%s\n' ': success.'
      else printf '%s\n' ': failed!'
      fi
      ;;
    0_*)
      printf '%s' "- Building RPM(s) from archive $i (because its SRPM already exists)" | tee -a "$LogFile"
      if eval eval rpmbuild -v -tb "$i" >> '"$LogFile"' 2>&1
      then printf '%s\n' ': success.'
      else printf '%s\n' ': failed!'
      fi
      ;;
    *_0)
      printf '%s' "- Building SRPM from archive $i (because an RPM for it already exists)" | tee -a "$LogFile"
      if eval eval rpmbuild -v -ts "$i" >> '"$LogFile"' 2>&1
      then printf '%s\n' ': success.'
      else printf '%s\n' ': failed!'
      fi
      ;;
    *_*)
     printf '%s\n' "- Skip building from archive $i because its SRPM & an RPM both already exist." | tee -a "$LogFile"
      ;;
    *)
      printf '%s\n' "Warning: Something went wrong when determining what to build (RPM and/or SRPM) from archive $i: Thus skipping it!" | tee -a "$LogFile" 2>&1
      ;;
    esac
  done
else
  Moved=""
  Specs=""
  TmpDir="$(mktemp -p -d "${ProgramName}.XXX")"  # -t instead of -p should yield the same
  printf '\n%s\n' 'Extracting spec file from:' | tee -a "$LogFile"
  for i in $ZTargets
  do
    k=$((k+1))
    printf '%s' "- $i" | tee -a "$LogFile"
    o="$(printf '%s' "$STargets" | sed -n "${k}P")"  # points to a file ending in ".spec" here
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
      printf '%s/n' "- $i succeded."
      Specs="$Specs$(printf '\n%s' "$t$o")"
    else
      cd "$MyPWD"
      printf '%s/n' "- $i failed!"
      continue
    fi
    sPre="$(sed -n '1,\_^[[:blank:]]*%prep$_P' "$t$o" | sed -n '1,\_^[[:blank:]]*%prep[[:blank:]]*$_P' | sed -n '1,\_^[[:blank:]]*%prep[[:blank:]]*#_P')"
    sNam="$(printf %s "$sPre" | grep '^[[:blank:]]*Name:' | tail -1 | cut -s -d ':' -f 2 | grep -o '[[:alnum:]][-+.[:alnum:]_~^]*' | head -1)"
    sVer="$(printf %s "$sPre" | grep '^[[:blank:]]*Version:' | tail -1 | cut -s -d ':' -f 2 | grep -o '[[:alnum:]][+.[:alnum:]_~^]*' | head -1)"
    sRel="$(printf %s "$sPre" | grep '^[[:blank:]]*Release:' | tail -1 | cut -s -d ':' -f 2 | grep -o '[[:alnum:]][+.[:alnum:]_~^]*' | head -1)"
    if [ -n "$sNam" ] && [ -n "$sVer" ]
    then sNVR="${sNam}*-${sVer}*-${sRel}*"
    else sNVR="$p"
    fi
    sIco="$(printf %s "$sPre" | grep -i '^[[:blank:]]*##*[[:blank:]]*Icon:' | tail -1 | cut -s -d ':' -f 2 | grep -o '[[:alnum:]][+.[:alnum:]_~^]*' | head -1)"
    
    

          if [ -n "$IconFile" ]
            then
              if [ -e "SOURCES/$IconFile" ]
              then
                if [ -r "SOURCES/$IconFile" ] && [ ! -d "SOURCES/$IconFile" ] && [ -s "SOURCES/$IconFile" ]
                then sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon referenced in the spec file exists at SOURCES/$IconFile, but is not usable." | tee -a "$LogFile"
                fi
              else
                IconPath="$(find -P "$TmpDir/$b" -type f -perm /444 -name "$IconFile" -print | head -1)"
                if [ -n "$IconPath" ]
                then ln -s "$IconPath" "SOURCES/$IconFile" && sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon $IconFile is referenced in $Hit, but not found in $ThisArch." | tee -a "$LogFile"
                fi
              fi
            fi
# #  ="$(find -L SOURCES -maxdepth 1 -type f ! -executable ! -empty -perm /444 -name "${i}*.tar*" -print)"  # Output not directly sortable by mtime.
# For "maxdepth=1":  ="$(ls -QL1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here. 
# For "maxdepth=2":  ="$(ls -QL1pFt SOURCES/${i}*.tar* 2>/dev/null | egrep -v '/$|:$|^$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here.
# For no "maxdepth": ="$(ls -RQL1pFt SOURCES/${i}*.tar* 2>/dev/null | egrep -v '/$|:$|^$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here.

Moved=""
for i in $(printf '%s' "$Targets" | sed -e "s/^/'/" -e "s/$/'/")
do
  for j in ~/android_storage/Download/${i}*.tar* ~/Downloads/${i}*.tar*  # Hardcoded!
  do
    if [ -s "$j" ] 2>/dev/null && [ -r "$j" ] 2>/dev/null && [ ! -d "$j" ] 2>/dev/null
    then
      Archive="$(basename "$j")"
      if [ -e "SOURCES/$Archive" ]
      then printf '%s\n' "- Warning: Ignoring ${j}, because SOURCES/$Archive already exists." | tee -a "$LogFile"
      else
        printf '%s\n' "- $j" | tee -a "$LogFile"
        mkdir -p SOURCES  # ToDo: Stop creating any directory, instead test for their existance at the start!
        mv "$j" SOURCES/
        Moved="${Moved},$(printf '%s' "$Archive" | sed 's/\.tar.*$//')"
      fi
    fi
  done
done
if [ -n "$Moved" ]
then
  Moved="$(printf '%s' "$Moved" | sed 's/^,//')"
  printf '%s\n' "Notice: Using solely \"${Moved}\" as target(s)." | tee -a "$LogFile"
  Targets="$Moved"
  Fuzzy=No
else printf '%s\n' '- Nothing.' | tee -a "$LogFile"
fi

  # Minimum requirements of RPM for %{name}-%{version} strings, according to
  # https://rpm-software-management.github.io/rpm/manual/spec.html#preamble-tags
  # [[:graph:]][[:graph:]]*-[[:alnum:]][[:alnum:].+_~^]*
  # This also covers %{name}-%{version}-%{release} strings.
  # Below my stronger, but usual requirements:
  # [[:alnum:]][-[:alnum:].+_~^]*-[[:digit:]][[:alnum:].+_~^]*'

printf '\n%s\n' 'Extracting spec file(s) from:' | tee -a "$LogFile"
SpecFiles=""
TmpDir="$(mktemp --tmpdir -d "${ProgramName}.XXX")"
for i in $(printf '%s' "$Targets" | tr ',' '\n')
do
  # Archive="$(find -L SOURCES -maxdepth 1 -type f -perm /444 -name "${i}*.tar*" -print)"  # Output not sortable for mtime (or ctime)!?!
  Archive="$(ls -L1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here; -F is an unneeded superset of -p.
  Archives="$(printf '%s' "$Archive" | wc -l)"
  if [ "$Archives" = 0 ]
  then continue
  elif [ "$Archives" -gt 0 ] 2>/dev/null
  then
  #if [ "$Fuzzy" != "No" ]
  #then Archive="$(printf '%s' "$Archive" | head -1)"
  #fi
    PrevArch="$(printf '%s' "$Archive" | head -1)"
    a="$(basename "$PrevArch" | sed 's/\.tar.*$//')"
    c="$(printf '%s' "$a" | grep -x '[[:graph:]][[:graph:]]*-[[:alnum:].+_~^][[:alnum:].+_~^]*')"  # Fulfils the minimum naming requirements, see line 58.
    e="$(printf '%s' "$a" | grep -x '[[:alnum:]][-[:alnum:].+_~^]*-[[:digit:]][[:alnum:].+_~^]*')"  # Fulfils the naming requirements for my "fuzzy evaluation", see line 60.
    for ThisArch in $Archive
    do
      b="$(basename "$ThisArch" | sed 's/\.tar.*$//')"
      d="$(printf '%s' "$b" | grep -x '[[:graph:]][[:graph:]]*-[[:alnum:].+_~^][[:alnum:].+_~^]*')"  # Fulfils the minimum naming requirements, see line 58.
      f="$(printf '%s' "$b" | grep -x '[[:alnum:]][-[:alnum:].+_~^]*-[[:digit:]][[:alnum:].+_~^]*')"  # Fulfils the naming requirements for my "fuzzy evaluation", see line 60.
      if { [ -n "$f" ] && [ "$f" = "$e" ]; } || { [ -n "$d" ] && [ "$Fuzzy" = "No" ] && [ "$d" = "$c" ]; } || { [ -n "$ThisArch" ] && [ "$ThisArch" = "$PrevArch" ]; }  # Last statement is for detecting the first loop run
      then
        printf '%s' "- $ThisArch" | tee -a "$LogFile"
        tar -C "$TmpDir" -xof "$ThisArch" 2>&1 | tee -a "$LogFile"
        Hit="$(find -P "$TmpDir/$b" -type f -perm /444 -name '*.spec' -print)"
        Hits="$(printf '%s' "$Hit" | wc -l)"
        if [ "$Hits" = 0 ]
        then printf '%s\n' ': No spec file found!' | tee -a "$LogFile"
        elif [ "$Hits" = 1 ]
        then
          if x="$(grep -o 'Icon:[^#]*' "$Hit")"
          then
            IconFile="$(printf '%s' "$x" | head -1 | sed -e 's/Icon://' -e 's/^[[:blank:]]*//')"
            if [ -n "$IconFile" ]
            then
              if [ -e "SOURCES/$IconFile" ]
              then
                if [ -r "SOURCES/$IconFile" ] && [ ! -d "SOURCES/$IconFile" ] && [ -s "SOURCES/$IconFile" ]
                then sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon referenced in the spec file exists at SOURCES/$IconFile, but is not usable." | tee -a "$LogFile"
                fi
              else
                IconPath="$(find -P "$TmpDir/$b" -type f -perm /444 -name "$IconFile" -print | head -1)"
                if [ -n "$IconPath" ]
                then ln -s "$IconPath" "SOURCES/$IconFile" && sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon $IconFile is referenced in $Hit, but not found in $ThisArch." | tee -a "$LogFile"
                fi
              fi
            fi
          fi
          SpecFiles="$(printf '%s\n%s' "$SpecFiles" "$Hit")"
          printf '\n' | tee -a "$LogFile"
        elif [ "$Hits" -gt 1 ] 2>/dev/null
        then printf '%s\n' ': More than one spec file found, ignoring them all!' | tee -a "$LogFile"
        else printf '%s\n' ': Failed to find a spec file!' | tee -a "$LogFile"
        fi
      else break
      fi
      PrevArch="$ThisArch"
      a="$b"
      c="$d"
      e="$f"
    done
  #elif [ "$Archives" -gt 1 ] 2>/dev/null
  #then printf '%s\n' "Notice: More than one matching archive for a single target found, ignoring them all: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$LogFile"
  else printf '%s\n' "Notice: Failed to find an archive via provided target(s), see: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$LogFile"
  fi
done
if [ -n "$SpecFiles" ]
then
  SpecFiles="$(printf '%s' "$SpecFiles" | grep -vx '')"
else
  printf '%s\n' 'Aborting: Not a single spec file found!' | tee -a "$LogFile" >&2
  rm -rf "$TmpDir"
  exit 6
fi

printf '\n%s\n' 'Building (S)RPM(s):' | tee -a "$LogFile"
QuotedTempDir="$(printf '%s' "${TmpDir}/" | sed 's/\//\\\//g')"
for i in $SpecFiles
do
  a="$(printf '%s' "$i" | sed "s/^${QuotedTempDir}//")"
  RPMname="$(dirname "$a" | grep -o '^[^/]*')"
  case "$(find RPMS -maxdepth 2 -name "${RPMname}*.rpm" -print | wc -l)_$(find SRPMS -maxdepth 1 -name "${RPMname}*.s*rpm" -print | wc -l)" in
  0_0)
    printf '%s' "- Building RPM(s) & SRPM for $RPMname" | tee -a "$LogFile"
    if rpmbuild -v -ba "$i" >> "$LogFile" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  0_*)
    printf '%s' "- Building RPM(s) for $RPMname (because its SRPM already exists)" | tee -a "$LogFile"
    if rpmbuild -v -bb "$i" >> "$LogF" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  *_0)
    printf '%s' "- Building SRPM for $RPMname (because an RPM for it already exists)" | tee -a "$LogFile"
    if rpmbuild -v -bs "$i" >> "$LogFile" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  *_*)
    printf '%s\n' "- Skip building for $RPMname, because its SRPM & an RPM both already exist." | tee -a "$LogFile"
    ;;
  *)
    printf '%s\n' "Warning: Something went severely wrong while determining what to build (RPM and/or SRPM) for $RPMname, thus skipping it!" | tee -a "$LogFile" 2>&1
    ;;
  esac
done

rm -rf "$TmpDir"
exit 0

