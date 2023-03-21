#!/bin/sh
set -uC  # Add -e later

# buildrpms.sh expects a comma separated list of tar archive names 
# without their file name extension(s) (!) as single argument.
# These archive names may be truncated (i.e., provide only the 
# beginning of their names) or contain wildcards (e.g., ? * [])!
# The true archive names (i.e., on the file system) must contain 
# the string ".tar" as part of their file name extension.
# Currently also no capital letters (i.e., upper-case characters)
# or white-space characters are allowed in the argument string or
# real file names processed.  Allowing for capital letters is easy
# to resolve (but what for?), but for white-spaces this seems rather
# hard to accomplish.
# If no argument is given, buildrpms.sh will use an internal list.

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

Called="$(basename "$0")"
if echo " $(id -un) $(id -Gn) " | fgrep -q ' root '
then
  echo "Aborting: $Called shall not be started with root privileges!" >&2
  exit 3
fi

ProgramName="$(echo "$Called" | rev | cut -d '.' -f 2- | rev)"
Logfile="${ProgramName}.log.txt"
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
  if echo "$Targets" | tr ',' '\n' | grep -vxq '[a-z][+0-9_a-z-]*[+0-9_a-z]-[0-9][+.0-9_a-z~-]*'
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

echo -e "\nFetching tar archive(s) from download directories:" | tee -a "$Logfile"
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
        mkdir -p SOURCES  # ToDo: Stop creating any directory, instead test for their existance at the start!
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

echo -e "\nExtracting spec file(s) from:" | tee -a "$Logfile"
SpecFiles=""
TmpDir="$(mktemp --tmpdir -d "${ProgramName}.XXX")"
for i in $(echo "$Targets" | tr ',' '\n')
do
  # Archive="$(find -L SOURCES -maxdepth 1 -type f -perm /444 -name "${i}*.tar*" -print)"  # Output not sortable for mtime (or ctime)!?!
  Archive="$(ls -L1pdt SOURCES/${i}*.tar* 2>/dev/null | grep -v '/$' | grep -v ':$' | grep -vx '')"  # ls' options -vr also looked interesting (instead of -t or -tcß), but fail in corner cases here
  Archives="$(echo "$Archive" | grep -vx '' | wc -l)"
  if [ "$Archives" = "0" ]
  then continue
  elif [ "$Archives" -gt "0" ] 2>/dev/null
  then
  #if [ "$Fuzzy" != "No" ]
  #then Archive="$(echo "$Archive" | head -1)"
  #fi
    PrevArch="$(echo "$Archive" | head -1)"
    a="$(basename "$PrevArch" | sed 's/\.tar.*$//')"
    c="$(echo "$a" | grep -x '[a-z][+0-9_a-z-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~]')"
    e="$(echo "$a" | grep -x '[a-z][+0-9_a-z-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos[1-9][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos')"
    for ThisArch in $Archive
    do
      b="$(basename "$ThisArch" | sed 's/\.tar.*$//')"
      d="$(echo "$b" | grep -x '[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~]')"
      f="$(echo "$b" | grep -x '[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos[1-9][+.0-9_a-z~-]*' | grep -o '^[a-z][+0-9_a-z~-]*[+0-9_a-z~]-[0-9][+.0-9_a-z~]*[+0-9_a-z~]-[+0-9_a-z~][+.0-9_a-z~-]*fos')"
      if [ -n "$f" -a "$f" = "$e" ] || [ -n "$d" -a "$Fuzzy" = "No" -a "$d" = "$c" ] || [ -n "$ThisArch" -a "$ThisArch" = "$PrevArch" ]  # Last statement is for detecting the first loop run
      then
        echo -n "- $ThisArch" | tee -a "$Logfile"
        tar -C "$TmpDir" -xf "$ThisArch" 2>&1 | tee -a "$Logfile"
        Hit="$(find -P "$TmpDir/$b" -type f -perm /444 -name '*.spec' -print)"
        Hits="$(echo "$Hit" | grep -v '^$' | wc -l)"
        if [ "$Hits" = "0" ]
        then echo ": No spec-file found!" | tee -a "$Logfile"
        elif [ "$Hits" = "1" ]
        then
          if x="$(grep -o 'Icon:[^#]*' "$Hit")"
          then
            IconFile="$(echo "$x" | head -1 | sed 's/Icon://' | sed 's/[[:space:]]//g')"
            if [ -n "$IconFile" ]
            then
              if [ -e "SOURCES/$IconFile" ]
              then
                if [ -r "SOURCES/$IconFile" ] && [ ! -d "SOURCES/$IconFile" ] && [ -s "SOURCES/$IconFile" ]
                then sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else echo -n ": Notice that icon SOURCES/$IconFile exists, but is not usable." | tee -a "$Logfile"
                fi
              else
                IconPath="$(find -P "$TmpDir/$b" -type f -perm /444 -name "$IconFile" -print | head -1)"
                if [ -n "$IconPath" ]
                then ln -s "$IconPath" "SOURCES/$IconFile" && sed -i 's/##* *Icon:/Icon:/' "$Hit"
                else echo -n ": Notice that icon $IconFile is referenced in $Hit, but not found in $ThisArch." | tee -a "$Logfile"
                fi
              fi
            fi
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
      a="$b"
      c="$d"
      e="$f"
    done
  #elif [ "$Archives" -gt "1" ] 2>/dev/null
  #then echo "Notice: More than one matching archive for a single target found, ignoring them all: $(echo "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  else echo "Notice: Failed to find an archive per provided target(s), see: $(echo "$Archive" | tr '\n' '\t')" | tee -a "$Logfile"
  fi
done
if [ -n "$SpecFiles" ]
then
  SpecFiles="$(echo "$SpecFiles" | grep -vx '')"
else
  echo "Aborting: Not a single spec-file found!" | tee -a "$Logfile" >&2
  rm -rf "$TmpDir"
  exit 6
fi

echo -e "\nBuilding (S)RPM(s):" | tee -a "$Logfile"
QuotedTempDir="$(echo "${TmpDir}/" | sed 's/\//\\\//g')"
for i in $SpecFiles
do
  a="$(echo "$i" | sed "s/^${QuotedTempDir}//")"
  RPMname="$(dirname "$a" | grep -o '^[^/]*')"
  case "$(find RPMS -maxdepth 2 -name "${RPMname}*.rpm" -print | wc -l)_$(find SRPMS -maxdepth 1 -name "${RPMname}*.s*rpm" -print | wc -l)" in
  0_0)
    echo -n "- Building RPM(s) & SRPM for $RPMname" | tee -a "$Logfile"
    if rpmbuild -v -ba "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  0_*)
    echo -n "- Building RPM(s) for $RPMname (because its SRPM already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bb "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  *_0)
    echo -n "- Building SRPM for $RPMname (because an RPM for it already exists)" | tee -a "$Logfile"
    if rpmbuild -v -bs "$i" >> "$Logfile" 2>&1
    then echo ": success."
    else echo ": failed!"
    fi
    ;;
  *_*)
    echo "- Skip building for $RPMname, because its SRPM & an RPM both already exist." | tee -a "$Logfile"
    ;;
  *)
    echo "Warning: Something went severely wrong while determining what to build (RPM and/or SRPM) for $RPMname, thus skipping it!" | tee -a "$Logfile" 2>&1
    ;;
  esac
done

rm -rf "$TmpDir"
exit 0

