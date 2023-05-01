# buildrpms
**Script for building RPM packages from archives**<br />
<br />

### Detailed description
`buildrpms` takes a list of paths to tar archives (including simple file names, absolute, relative paths and homedir expansion by a leading tilde "~") with each list item (i.e., archive path) as a single argument.  Provided paths may point to files or directories; if a directory is addressed, the whole directory tree below this directory is searched for valid archive files.

If an archive path contains no slashes (/), it is used as a simple archive file name; still the wildcard rules denoted below apply.  This name is used to search for valid archive files in a list of directories comprising "." and "~/Downloads"; for each of these directories the whole directory tree below is searched.  The only exception are directories named "SOURCES", if the option "-i|--in-place" is used or a simple name containing no digit somewhere after the last dash-hyphen (-).

Without the option "-i|--in-place", `buildrpms` avoids re-building archives for which an (S)RPM in the directories ./RPMS or ./SRPMS exists by analysing spec file content, the archive's top level directory and the archive name (in this order of precedence).

The archive paths may either contain shell type wildcard characters (? * [ ]), or be truncated (i.e., provide only a path without unquoted wildcard characters, including or comprising the beginning of a archive file name or a complete such name).
File paths ending in a slash are the only exception: They may contain wildcard characters, even though the whole directory tree below the provided path is searched for valid archive files.

Control characters, which include all horizontal and vertical white spaces except for the simple space character, are not allowed in the provided archive paths.

Mind to protect wildcards, the tilde and other special characters from being expanded by a shell, if `buildrpms` is intended to interpret them.

Also mind, that `buildrpms` lastly calls `rpmbuild`, which expects the real archive file names to conform to "\<name>-\<version>.tar.gz" (i.e., the ones on mass-storage), unless `buildrpms`' option "-i|--in-place" is specified.

`buildrpms` currently recognises the mutually exclusive options "-?|--help", "-i|--in-place", "-n|--no-move" and "-d|--debug".  By default `buildrpms` extracts the spec file of each archive found, processes it and moves each valid archive to the ./SOURCES directory; "-n|--no-move" links each valid archive in ./SOURCES instead of moving.  "-i|--in-place" omits extracting and processing of spec files and directly uses the archives at their original location.
If no archive path list is provided, `buildrpms` will use an internal list of archive paths.

`Buildrpms` outputs (to StdOUT) a the list of archive paths, with which ultimately `rpmbuild` is called after a multitude of checks.  All user oriented messages are directed to StdERR, except for the aforementioned archive paths and the help output.  The option "-d|--debug" provides some additional output to StdERR when processing the argument list.

	Exit codes:
	   0  Everything worked fine: all applicable checks, all applicable preparatory steps, and the rpmbuild run(s)
	   1  A check failed
	   2  Help called
	   3  Called incorrectly (e.g., with wrong parameters)
	   4  Aborted upon user request
	   5  Error while interacting with the OS (reading / writing from the filesystem, calling programs, etc.)
	   6  Error while executing one of the preparatory steps
	   7  Error internal to this script
