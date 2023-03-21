#!/bin/sh
set -uC  # Add -e later

# buildrpms.sh expects a comma separated list of tar archive names 
# without their file name extension(s) (!) as each item.
# These archive names may be truncated (i.e., provide only the 
# beginning of their names) or contain wildcards (e.g., ? * [])!
# If they are truncated the must start with a alpha character
# (i.e., '[a-zA-Z]') and must contain the beginning of a version
# indicator, i.e., '-[-0-9]'.
# The true archive names (i.e., on the file system) must contain 
# the string ".tar" as first part of their file name extension.
# No white-space or control characters are allowed in the argument
# string or real file names processed.
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
  printf '%s\n' "Aborting: Failed to create logfile!" >&2
  exit 3
fi
printf '%s\n' "Starting $Called at $(date -Iseconds)" | tee "$Logfile"

if [ -n "$*" ]
then
  Targets="$1"
  Fuzzy=No
  if printf %s "$Targets" | tr ',' '\n' | grep -vxq '[[:alnum:]][[:alnum:]+_~-]*-[[:digit:]][[:alnum:]+_~^]*'
  then Fuzzy=Yes
  fi
else
  Targets='crypto-sdcard,mount-sdcard,sfos-upgrade'
  Fuzzy=Yes
fi
if printf '%s' "$Targets" | egrep -q '[[:space:]]|[[:cntrl:]]'
then
  printf '%s\n' "Aborting: Argument string \"$Targets\" contains a white-space or control character!" | tee -a "$Logfile" >&2
  exit 3
fi
shift
if [ -n "$*" ]
then
  printf '%s\n' "Aborting: No extra arguments expected, but called with \"${*}\"." | tee -a "$Logfile" >&2
  exit 3
fi

printf '\n%s\n' "Fetching tar archive(s) from download directories:" | tee -a "$Logfile"
Moved=""
for i in $(printf '%s' "$Targets" | tr ',' '\n')
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
else printf '%s\n' "- Nothing." | tee -a "$Logfile"
fi

printf '\n%s\n' "Extracting spec file(s) from:" | tee -a "$Logfile"
SpecFiles=""
TmpDir="$(mktemp --tmpdir -d "${ProgramName}.XXX")"
for i in $(printf '%s' "$Targets" | tr ',' '\n')
do
  # Archive="$(find -L SOURCES -maxdepth 1 -type f -perm /444 -name "${i}*.tar*" -print)"  # Output not sortable for mtime (or ctime)!?!
  Archive="$(ls -L1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$')"  # ls' options -vr instead of -t also looked interesting, but fail in corner cases here; -F is an unneeded superset of -p.
  Archives="$(printf '%s' "$Archive" | wc -l)"
  if [ "$Archives" = "0" ]
  then continue
  elif [ "$Archives" -gt "0" ] 2>/dev/null
  then
  #if [ "$Fuzzy" != "No" ]
  #then Archive="$(printf '%s' "$Archive" | head -1)"
  #fi
    PrevArch="$(printf '%s' "$Archive" | head -1)"
    a="$(basename "$PrevArch" | sed 's/\.tar.*$//')"
    c="$(printf '%s' "$a" | grep -x '[a-z][+0-9_a-z-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~]')"
    e="$(printf '%s' "$a" | grep -x '[a-z][+0-9_a-z-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos[1-9][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos')"
    for ThisArch in $Archive
    do
      b="$(basename "$ThisArch" | sed 's/\.tar.*$//')"
      d="$(printf '%s' "$b" | grep -x '[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~]')"
      f="$(printf '%s' "$b" | grep -x '[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos[1-9][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos')"
      if [ -n "$f" -a "$f" = "$e" ] || [ -n "$d" -a "$Fuzzy" = "No" -a "$d" = "$c" ] || [ -n "$ThisArch" -a "$ThisArch" = "$PrevArch" ]  # Last statement is for detecting the first loop run
      then
        printf '%s' "- $ThisArch" | tee -a "$Logfile"
        tar -C "$TmpDir" -xf "$ThisArch" 2>&1 | tee -a "$Logfile"
        Hit="$(find -P "$TmpDir/$b" -type f -perm /444 -name '*.spec' -print)"
        Hits="$(printf '%s' "$Hit" | wc -l)"
        if [ "$Hits" = "0" ]
        then printf '%s\n' ": No spec-file found!" | tee -a "$Logfile"
        elif [ "$Hits" = "1" ]
        then
          if x="$(grep -o 'Icon:[^#]*' "$Hit")"
          then
            IconFile="$(printf '%s' "$x" | head -1 | sed 's/Icon://' | sed 's/[[:space:]]//g')"
            if [ -n "$IconFile" ]
            then
              if [ -e "SOURCES/$IconFile" ]
              then
                if [ -r "SOURCES/$IconFile" ] && [ ! -d "SOURCES/$IconFile" ] && [ -s "SOURCES/$IconFile" ]
                then sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon SOURCES/$IconFile exists, but is not usable." | tee -a "$Logfile"
                fi
              else
                IconPath="$(find -P "$TmpDir/$b" -type f -perm /444 -name "$IconFile" -print | sed -n 1P)"
                if [ -n "$IconPath" ]
                then ln -s "$IconPath" "SOURCES/$IconFile" && sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else printf '%s' ": Notice that icon $IconFile is referenced in $Hit, but not found in $ThisArch." | tee -a "$Logfile"
                fi
              fi
            fi
          fi
          SpecFiles="$(printf '%s\n%s' "$SpecFiles" "$Hit")"
          printf '\n' | tee -a "$Logfile"
        elif [ "$Hits" -gt "1" ] 2>/dev/null
        then printf '%s\n' ": More than one spec-file found, ignoring them all!" | tee -a "$Logfile"
        else printf '%s\n' ": Failed to find a spec-file!" | tee -a "$Logfile"
        fi
      else break
      fi
      PrevArch="$ThisArch"
      a="$b"
      c="$d"
      e="$f"
    done
  #elif [ "$Archives" -gt "1" ] 2>/dev/null
  #then printf '%s\n' "Notice: More than one matching archive for a single target found, ignoring them all: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  else printf '%s\n' "Notice: Failed to find an archive via provided target(s), see: $(printf '%s' "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  fi
done
if [ -n "$SpecFiles" ]
then
  SpecFiles="$(printf '%s' "$SpecFiles")"
else
  printf '%s\n' "Aborting: Not a single spec-file found!" | tee -a "$Logfile" >&2
  rm -rf "$TmpDir"
  exit 6
fi

printf '\n%s\n' "Building (S)RPM(s):" | tee -a "$Logfile"
QuotedTempDir="$(printf '%s' "${TmpDir}/" | sed 's/\//\\\//g')"
for i in $SpecFiles
do
  a="$(printf '%s' "$i" | sed "s/^${QuotedTempDir}//")"
  RPMname="$(dirname "$a" | grep -o '^[^/]*')"
  case "$(find RPMS -maxdepth 2 -name "${RPMname}*.rpm" -print | wc -l)_$(find SRPMS -maxdepth 1 -name "${RPMname}*.s*rpm" -print | wc -l)" in
  0_0)
    printf '%s' "- Building RPM(s) & SRPM for $RPMname" | tee -a "$Logfile"
    if rpmbuild -v -ba "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ": success."
    else printf '%s\n' ": failed!"
    fi
    ;;
  0_*)
    printf '%s' "- Building RPM(s) for $RPMname (because its SRPM already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bb "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ": success."
    else printf '%s\n' ": failed!"
    fi
    ;;
  *_0)
    printf '%s' "- Building SRPM for $RPMname (because an RPM for it already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bs "$i" >> "$Logfile" 2>&1
    then printf '%s\n' ": success."
    else printf '%s\n' ": failed!"
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

