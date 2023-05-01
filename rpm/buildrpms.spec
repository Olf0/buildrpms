Name:           buildrpms
Summary:        Script for building RPM packages from tar archives
# The Git release tag format shall adhere to just <version>.
# The <version> field adheres to semantic versioning and the <release> field 
# is comprised of {alpha,beta,rc,release} postfixed with a natural number
# greater or equal to 1 (e.g., "beta3") and may additonally be postfixed with a
# plus character ("+"), the name of the packager and a release number chosen by
# her (e.g., "rc2+jane4").  `{alpha|beta|rc|release}` indicates the expected
# status of the software.  No other identifiers shall be used for any published
# version, but for the purpose of testing infrastructure other nonsensical
# identifiers as `adud` may be used, which do *not* trigger a build at GitHub
# and OBS, when configured accordingly; mind the sorting (`adud` < `alpha`).
# For details and reasons, see
# https://github.com/Olf0/sfos-upgrade/wiki/Git-tag-format
Version:        0.8.4
Release:        release5
# The contents of the Group field should be one of the groups listed here:
# https://github.com/mer-tools/spectacle/blob/master/data/GROUPS
Group:          Applications/System
Distribution:   SailfishOS
License:        LGPL-2.1-only
URL:            https://github.com/Olf0/%{name}
# The "Source0:" line below requires that the value of %%{name} is also the
# project name at GitHub and the value of %%{version} is also the name of a
# correspondingly set git-tag.
Source0:        %{url}/archive/%{version}/%{name}-%{version}.tar.gz
# Note that the rpmlintrc file shall be named so according to
# https://en.opensuse.org/openSUSE:Packaging_checks#Building_Packages_in_spite_of_errors
Source99:       %{name}.rpmlintrc
BuildArch:      noarch
Requires:       rpm

# This description section includes metadata for SailfishOS:Chum, see
# https://github.com/sailfishos-chum/main/blob/main/Metadata.md
%description
`buildrpms` takes a list of paths to tar archives, both files and
directories.  For directories the whole tree below is searched for valid
archives, for paths without slashes, the directories . and ~/Download.  The
archive paths may either contain shell type wildcards or be truncated
(without unquoted wildcards).
    
`buildrpms` currently recognises the mutually exclusive options "-?|--help",
"-i|--in-place", "-n|--no-move" and "-d|--debug".  By default `buildrpms`
extracts the spec file of each archive found, processes it and moves each
valid archive to the ./SOURCES directory; "-n|--no-move" links each valid
archive in ./SOURCES instead of moving.  "-i|--in-place" omits extracting and
processing of spec files and directly uses the archives at their original
location.

For details, see %{url}#readme
  
%if 0%{?_chum}
Title: buildrpms builds rpms
Type: console-application
DeveloperName: olf (Olf0)
Categories:
 - System
 - Utility
 - ConsoleOnly
Custom:
  Repo: %{url}
Links:
  Homepage: %{url}#readme
  Help: %{url}/issues
  Bugtracker: %{url}/issues
  Donation: https://noyb.eu/en
%endif

%define _binary_payload w6.gzdio
%define _source_payload w6.gzdio

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}%{_bindir}
cp bin/* %{buildroot}%{_bindir}/

%files
%defattr(0755,root,root,-)
%{_bindir}/%{name}

# Changelog format: https://lists.fedoraproject.org/archives/list/devel@lists.fedoraproject.org/thread/SF4VVE4NBEDQJDJZ4DJ6YW2DTGMWP23E/#6O6DFC6GDOLCU7QC3QJKJ3VCUGAOTD24
%changelog
* Thu Sep  9 1999 olf <Olf0@users.noreply.github.com> - 99.99.99
- See https://github.com/Olf0/buildrpms/releases
