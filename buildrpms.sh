#!/bin/sh
set -uC  # Add -e later

#        1         2         3         4         5         6         7         8
#2345678901234567890123456789012345678901234567890123456789012345678901234567890

# buildrpms.sh expects a comma separated list of tar archive names or paths as
# each item.  The archive names may either be truncated (i.e., provide only the 
# beginning of their names) or contain shell type wildcards (? * []).  No
# white-space or control characters are allowed in the argument string or real
# file names processed, except for the simple space character (which must be
# quoted) in the argument string.
# buildrpms.sh currently only recogises a single option, "--fuzzy".
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

Called="$(basename "$0")"
if printf '%s' " $(id -un) $(id -Gn) " | fgrep -q ' root '
then
  printf '%s\n' "Aborting: $Called shall not be started with root privileges!" >&2
  exit 3
fi

ProgramName="$(printf '%s' "$Called" | rev | cut -d '.' -f 2- | rev)"
Logfile="${ProgramName}.log.txt"
if ! touch "$Logfile"
then
  printf '%s\n' 'Aborting: Failed to create logfile!' >&2
  exit 3
fi
printf '%s\n' "Starting $Called at $(date -Iseconds)" | tee "$Logfile"

Fuzzy=N
# if [ "$1" = "--fuzzy" ]
# then
#   Fuzzy=Y
#   shift
# fi
Inplace=N
case "$1" in
-i|--in-place)
  Inplace=Y
  shift
  ;;
-\?|--help)
  printf '%s\n' "Help text for $called not yet written." >&2
  exit 2
  ;;
esac

if [ -n "$2" ]
then
  printf '%s\n' "Aborting: No extra arguments expected, but called with \"${*}\"." | tee -a "$Logfile" >&2
  exit 3
elif [ -n "$1" ]
then
  Targets="$1"
else
  Targets='crypto-sdcard,mount-sdcard,sfos-upgrade'
fi
Targets="$(printf %s "$Targets" | tr ',' '\n')"

if printf '%s' "$Targets" | tr ' ' '_' | egrep -q '[[:space:]]|[[:cntrl:]]'
then
  printf '%s\n' "Aborting: Argument string \"$Targets\" contains a white-space other than the simple space or control character!" | tee -a "$Logfile" >&2
  exit 3
fi

# Quote each line and append "*" to fuzzy entries
if ! printf '%s' "$Targets" | grep -vxq '[[:alnum:]/][-[:alnum:]/ .+_~^]*'
then
  Fuzzy=Y
  FTargets="$(printf '%s' "$Targets" | fgrep -v / | sed -e "s/^/'/" -e "s/$/*'/")"
  PTargets="$(printf '%s' "$Targets" | fgrep / | sed -e "s/^/'/" -e "s/$/*'/")"
else
  FTargets="$(printf '%s' "$Targets" | fgrep -v / | sed -e "s/^/'/" -e "s/$/'/")"
  PTargets="$(printf '%s' "$Targets" | fgrep / | sed -e "s/^/'/" -e "s/$/'/")"
fi

# Expand PathTargets & check them coarsly
RTargets=""
for i in $PTargets
do
  if ! eval eval file -L --mime-type "$i" | grep '^application/'
  then continue
  fi
  RTargets="$(printf '%s\n%s' "$i" "$RTargets")"
done

# Search for FileTargets
printf '\n%s\n' 'Fetching tar archive(s) from download directories:' | tee -a "$Logfile"
DDirs='. ~/Downloads ~/android_storage/Download'
gTargets=""
# find -L $DDirs -type f ! -executable ! -empty  -perm /444 -name "${i}*.tar*" -print  # Output not directly sortable by mtime.
# find -L . -path SOURCES -prune -o -type f ! -executable ! -empty -perm /444 -name "${i}*.tar*" -printf '%T@ %p\n' | sed 's/\.//' | sort -nr
for i in $FTargets
do
  gTargets="$(eval find -L "$DDirs" -type f ! -executable ! -empty -perm /444 -name "$i" -printf "\'%s\''\n'" 2> /dev/null)$gTargets"
done
for i in $gTargets
do
  if ! eval eval file -L --mime-type "$i" | grep '^application/'
  then continue
  fi
  RTargets="$(printf '%s\n%s' "$i" "$RTargets")"
done

for i in $RTargets
do

# Specfile="$(tar --wildcards -tf "$filepath" 'rpm/*.spec')"
# Specfile="$(tar -tf "$filepath" '*.spec' | grep -x 'rpm/.*\.spec')"

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
      then printf '%s\n' "- Warning: Ignoring ${j}, because SOURCES/$Archive already exists." | tee -a "$Logfile"
      else
        printf '%s\n' "- $j" | tee -a "$Logfile"
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
  printf '%s\n' "Notice: Using solely \"${Moved}\" as target(s)." | tee -a "$Logfile"
  Targets="$Moved"
  Fuzzy=No
else printf '%s\n' '- Nothing.' | tee -a "$Logfile"
fi

  # Minimum requirements of RPM for %{name}-%{version} strings, according to
  # https://rpm-software-management.github.io/rpm/manual/spec.html#preamble-tags
  # [[:graph:]][[:graph:]]*-[[:alnum:].+_~^][[:alnum:].+_~^]*
  # This also covers %{name}-%{version}-%{release} strings.
  # Below my stronger, but usual requirements:
  # [[:alnum:]][-[:alnum:].+_~^]*-[[:digit:]][[:alnum:].+_~^]*'

printf '\n%s\n' 'Extracting spec file(s) from:' | tee -a "$Logfile"
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
        printf '%s' "- $ThisArch" | tee -a "$Logfile"
        tar -C "$TmpDir" -xof "$ThisArch" 2>&1 | tee -a "$Logfile"
        Hit="$(find -P "$TmpDir/$b" -type f -perm /444 -name '*.spec' -print)"
        Hits="$(printf '%s' "$Hit" | wc -l)"
        if [ "$Hits" = 0 ]
        then printf '%s\n' ': No spec-file found!' | tee -a "$Logfile"
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
                else printf '%s' ": Notice that icon referenced in the spec file exists at SOURCES/$IconFile, but is not usable." | tee -a "$Logfile"
                fi
              else
                IconPath="$(find -P "$TmpDir/$b" -type f -perm /444 -name "$IconFile" -print | head -1)"
                if [ -n "$IconPath" ]
                then ln -s "$IconPath" "SOURCES/$IconFile" && sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon $IconFile is referenced in $Hit, but not found in $ThisArch." | tee -a "$Logfile"
                fi
              fi
            fi
          fi
          SpecFiles="$(printf '%s\n%s' "$SpecFiles" "$Hit")"
          printf '\n' | tee -a "$Logfile"
        elif [ "$Hits" -gt 1 ] 2>/dev/null
        then printf '%s\n' ': More than one spec-file found, ignoring them all!' | tee -a "$Logfile"
        else printf '%s\n' ': Failed to find a spec-file!' | tee -a "$Logfile"
        fi
      else break
      fi
      PrevArch="$ThisArch"
      a="$b"
      c="$d"
      e="$f"
    done
  #elif [ "$Archives" -gt 1 ] 2>/dev/null
  #then printf '%s\n' "Notice: More than one matching archive for a single target found, ignoring them all: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  else printf '%s\n' "Notice: Failed to find an archive via provided target(s), see: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  fi
done
if [ -n "$SpecFiles" ]
then
  SpecFiles="$(printf '%s' "$SpecFiles" | grep -vx '')"
else
  printf '%s\n' 'Aborting: Not a single spec-file found!' | tee -a "$Logfile" >&2
  rm -rf "$TmpDir"
  exit 6
fi

printf '\n%s\n' 'Building (S)RPM(s):' | tee -a "$Logfile"
QuotedTempDir="$(printf '%s' "${TmpDir}/" | sed 's/\//\\\//g')"
for i in $SpecFiles
do
  a="$(printf '%s' "$i" | sed "s/^${QuotedTempDir}//")"
  RPMname="$(dirname "$a" | grep -o '^[^/]*')"
  case "$(find RPMS -maxdepth 2 -name "${RPMname}*.rpm" -print | wc -l)_$(find SRPMS -maxdepth 1 -name "${RPMname}*.s*rpm" -print | wc -l)" in
  0_0)
    printf '%s' "- Building RPM(s) & SRPM for $RPMname" | tee -a "$Logfile"
    if rpmbuild -v -ba "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  0_*)
    printf '%s' "- Building RPM(s) for $RPMname (because its SRPM already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bb "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  *_0)
    printf '%s' "- Building SRPM for $RPMname (because an RPM for it already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bs "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ': success.'
    else printf '%s\n' ': failed!'
    fi
    ;;
  *_*)
    printf '%s\n' "- Skip building for $RPMname, because its SRPM & an RPM both already exist." | tee -a "$Logfile"
    ;;
  *)
    printf '%s\n' "Warning: Something went severely wrong while determining what to build (RPM and/or SRPM) for $RPMname, thus skipping it!" | tee -a "$Logfile" 2>&1
    ;;
  esac
done

rm -rf "$TmpDir"
exit 0

