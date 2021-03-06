#!/bin/sh
set -uC  # Add -e later

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
# export IFS="$(echo -e "\n")"

# buildrpms.sh expects a comma separated list of tar archive names 
# without their file name extension(s) (!) as single argument.
# These archive names may be truncated (i.e., provide only the 
# beginning of their names) or contain wildcards (e.g., ? * [])!
# The true archive names (i.e., on the file system) must contain 
# the string ".tar" as part of their file name extension.
# Currently also no capital letters (i.e., upper-case characters)
# or white-space characters are allowed in the argument string or
# real file names processed.  Allowing for capital letters is easy
# to resolve (but what for?), but for white-spaces this is rather
# hard.
# If no argument is given, it will use an internal list.

Called="$(basename "$0")"
if echo " $(id -un) $(id -Gn) " | fgrep -q ' root '
then
  echo "Aborting: $Called shall not be started with root privileges!" >&2
  exit 3
fi

TmpDir="$(echo "$Called" | rev | cut -d '.' -f 2- | rev)"
Logfile="${TmpDir}.log.txt"
TmpDir="/tmp/$TmpDir"
if ! touch "$Logfile"
then
  echo "Aborting: Failed to create logfile!" >&2
  exit 3
fi
echo "Starting $Called at $(date)" | tee "$Logfile"

if [ -n "$*" ]
then
  Targets="$1"
  Fuzzy=No
  if echo "$Targets" | tr ',' '\n' | grep -vq '^[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][+.0-9_a-z~-]*$'
  then Fuzzy=Yes
  fi
else
  Targets='crypto-sdcard,mount-sdcard,sfos-upgrade'
  Fuzzy=Yes
fi
if echo "$Targets" | egrep -q '[[:space:]]|[[:upper:]]'
then
  echo "Aborting: Argument string \"$Targets\" contains a white-space or upper-case character!" | tee -a "$Logfile" >&2
  exit 3
fi
shift
if [ -n "$*" ]
then
  echo "Aborting: No extra arguments expected, but called with \"${*}\"." | tee -a "$Logfile" >&2
  exit 3
fi

echo -e "\nFetching tar-archives from download directories" | tee -a "$Logfile"
Moved=""
for i in $(echo "$Targets" | tr ',' '\n')
do
  for j in ~/android_storage/Download/${i}*.tar* ~/Downloads/${i}*.tar*  # Hardcoded!
  do
    if [ -s "$j" ] 2>/dev/null && [ -r "$j" ] 2>/dev/null && [ ! -d "$j" ] 2>/dev/null
    then
      Archive="$(basename "$j")"
      if [ -e "SOURCES/$Archive" ]
      then echo "- Warning: Ignoring ${j}, because SOURCES/$Archive already exists." | tee -a "$Logfile"
      else
        echo "- $j" | tee -a "$Logfile"
        mkdir -p SOURCES
        mv "$j" SOURCES/
        Moved="${Moved},$(echo "$Archive" | sed 's/\.tar.*$//')"
      fi
    fi
  done
done
if [ -n "$Moved" ]
then
  Moved="$(echo "$Moved" | sed 's/^,//')"
  echo "Notice: Using solely \"${Moved}\" as target(s)." | tee -a "$Logfile"
  Targets="$Moved"
  Fuzzy=No
else echo "- Nothing." | tee -a "$Logfile"
fi

echo -e "\nExtracting spec-file from" | tee -a "$Logfile"
SpecFiles=""
mkdir -p "$TmpDir"
for i in $(echo "$Targets" | tr ',' '\n')
do
  # Archive="$(find -L SOURCES -maxdepth 1 -type f -perm +444 -name "${i}*.tar*" -print)"  # Output not sortable for mtime (or ctime)!?!
  Archive="$(ls -L1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$' | grep -v ':$' | grep -v '^$')"  # ls' options -vr also looked interesting (instead of -t), but fail in corner cases here
  Archives="$(echo "$Archive" | wc -l)"
  if [ "$Archives" = "0" ]
  then continue
  elif [ "$Archives" -gt "0" ] 2>/dev/null
  then
  #if [ "$Fuzzy" != "No" ]
  #then Archive="$(echo "$Archive" | sed -n 1P)"
  #fi
    PrevArch="$(echo "$Archive" | sed -n 1P)"
    for ThisArch in $Archive
    do
      a="$(basename "$PrevArch" | sed 's/\.tar.*$//')"
      b="$(basename "$ThisArch" | sed 's/\.tar.*$//')"
      c="$(echo "$a" | grep '^[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][.0-9]*-[0-9a-z][+.0-9_a-z~-]*fos[0-9][+.0-9_a-z~-]*$' | grep -o '^[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][.0-9]*-')"
      d="$(echo "$b" | grep '^[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][.0-9]*-[0-9a-z][+.0-9_a-z~-]*fos[0-9][+.0-9_a-z~-]*$' | grep -o '^[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][.0-9]*-')"
      if [ -n "$ThisArch" -a "$ThisArch" = "$PrevArch" ] || [ -n "$d" -a "$d" = "$c" ]
      then
        echo -n "- $ThisArch" | tee -a "$Logfile"
        tar -C "$TmpDir" -xf "$ThisArch" 2>&1 | tee -a "$Logfile"
        Hit="$(find -P "$TmpDir/$b" -type f -perm +444 -name '*.spec' -print)"
        Hits="$(echo "$Hit" | wc -l)"
        if [ "$Hits" = "0" ]
        then echo ": No spec-file found!" | tee -a "$Logfile"
        elif [ "$Hits" = "1" ]
        then
          if e="$(fgrep 'Icon:' "$Hit")"
          then
            IconFile="$(echo "$e" | grep -o 'Icon:[^#]*' | sed -n 1P | sed 's/Icon://' | sed 's/[[:space:]]//g')"
            IconPath="$(find -P "$TmpDir/$b" -type f -perm +444 -name "$IconFile" -print | sed -n 1P)"
            [ ! -e "SOURCES/$IconFile" ] && ln -s "$IconPath" "SOURCES/$IconFile"
            sed -i 's/# *Icon:/Icon:/' "$Hit"
          fi
          SpecFiles="$(echo -e "${SpecFiles}\n$Hit")"
          echo | tee -a "$Logfile"
        elif [ "$Hits" -gt "1" ] 2>/dev/null
        then echo ": More than one spec-file found, ignoring them all!" | tee -a "$Logfile"
        else echo ": Failed to find a spec-file!" | tee -a "$Logfile"
        fi
      else break
      fi
      PrevArch="$ThisArch"
    done
  #elif [ "$Archives" -gt "1" ] 2>/dev/null
  #then echo "Notice: More than one matching archive for a single target found, ignoring them all: $(echo "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  else echo "Notice: Failed to find an archive per provided target(s), see: $(echo "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  fi
done
if [ -n "$SpecFiles" ]
then
  SpecFiles="$(echo "$SpecFiles" | grep -v '^$')"
else
  echo "Aborting: Not a single spec-file found!" | tee -a "$Logfile" >&2
  rm -rf "$TmpDir"
  exit 2
fi

echo -e "\nBuilding (S)RPM(s)" | tee -a "$Logfile"
for i in $SpecFiles
do
  QuotedTempDir="$(echo "${TmpDir}/" | sed 's/\//\\\//g')"
  a="$(echo "$i" | sed "s/^${QuotedTempDir}//")"
  RPMname="$(dirname "$a" | grep -o '^[^/]*')"
  case "$(find RPMS -maxdepth 2 -name "${RPMname}*.rpm" -print | wc -l)_$(find SRPMS -maxdepth 1 -name "${RPMname}*.s*rpm" -print | wc -l)" in
  0_0)
    echo -n "- Building RPM(s) & SRPM for $RPMname" | tee -a "$Logfile"
    if rpmbuild -ba "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  0_*)
    echo -n "- Building RPM(s) for $RPMname (because its SRPM already exists)" | tee -a "$Logfile"
    if rpmbuild -bb "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  *_0)
    echo -n "- Building SRPM for $RPMname (because an RPM for it already exists)" | tee -a "$Logfile"
    if rpmbuild -bs "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  *_*)
    echo "- Skip building for $RPMname, because its SRPM & an RPM both already exist." | tee -a "$Logfile"
    ;;
  *)
    echo "Warning: Something went severely wrong, while determining what to build (RPM and/or SRPM) for $RPMname: Skipping it!" | tee -a "$Logfile" 2>&1
    ;;
  esac
done

rm -rf "$TmpDir"
exit 0

