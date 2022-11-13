%define _bashcompletiondir %(pkg-config --variable=completionsdir bash-completion)

Name:       asbru-cm
Version:    %{_version}
Release:    %{_release}%{?dist}
Summary:    A user interface that helps organizing remote terminal sessions and automating repetitive tasks.
License:    GPLv3+
URL:        https://asbru-cm.net
Source0:    https://github.com/asbru-cm/asbru-cm/archive/%{version}.tar.gz
BuildArch:  noarch
Autoreq:    no
Requires:   perl
Requires:   perl(Carp)
Requires:   perl(Compress::Raw::Zlib)
Requires:   perl(Crypt::Blowfish)
Requires:   perl(Data::Dumper)
Requires:   perl(Digest::SHA)
Requires:   perl(DynaLoader)
Requires:   perl(Encode)
Requires:   perl(Expect)
Requires:   perl(Exporter)
Requires:   perl(File::Basename)
Requires:   perl(File::Copy)
Requires:   perl(FindBin)
Requires:   perl(Gtk3)
Requires:   perl(Gtk3::SimpleList)
Requires:   perl(IO::Handle)
Requires:   perl(IO::Socket)
Requires:   perl(IO::Socket::INET)
Requires:   perl(MIME::Base64)
Requires:   perl(Net::ARP)
Requires:   perl(Net::Ping)
Requires:   perl(OSSP::uuid)
Requires:   perl(POSIX)
Requires:   perl(Socket)
Requires:   perl(Socket6)
Requires:   perl(Storable)
Requires:   perl(Sys::Hostname)
Requires:   perl(Time::HiRes)
Requires:   perl(XML::Parser)
Requires:   perl(YAML)
Requires:   perl(constant)
Requires:   perl(lib)
Requires:   perl(strict)
Requires:   perl(utf8)
Requires:   perl(vars)
Requires:   perl(warnings)
Requires:   vte291
Requires:   bash
Requires:   perl-Crypt-CBC
Requires:   perl-Crypt-Rijndael
Requires:   perl-IO-Tty
Requires:   perl-IO-Stty
Requires:   libwnck3
Requires:   nmap-ncat
%if 0%{?el7}
Requires: telnet
Requires: ftp
%else
Recommends: keepassxc
Suggests: freerdp or rdesktop
Suggests: tigervnc or tightvnc
Suggests: mosh
Suggests: cu
Suggests: x3270-x11
Suggests: tn5250
Suggests: telnet
Suggests: ftp
Suggests: perl-X11-GUITest
%endif
BuildRequires: pkgconfig
BuildRequires: bash-completion
BuildRequires: desktop-file-utils
BuildRoot:  %{_topdir}/tmp/%{name}-%{version}-%{release}-root

%description
Ásbrú Connection Manager is a user interface that helps organizing remote terminal sessions and automating repetitive tasks.

%prep
%autosetup -n asbru-cm-%{_github_version} -p1
sed -ri -e "s|\\\$RealBin[ ]*\.[ ]*'|'%{_datadir}/%{name}/lib|g" lib/asbru_conn
sed -ri -e "s|\\\$RealBin,|'%{_datadir}/%{name}/lib',|g" lib/asbru_conn
sed -ri -e "s|\\\$RealBin/\.\./|%{_datadir}/%{name}/|g" lib/asbru_conn
sed -ri -e "s|\\\$RealBin/|%{_datadir}/%{name}/lib/|g" lib/asbru_conn
find . -not -path './utils/*' -type f -exec sed -i \
  -e "s|\$RealBin[ ]*\.[ ]*'|'%{_datadir}/%{name}|g" \
  -e 's|"\$RealBin/|"%{_datadir}/%{name}/|g' \
  -e 's|/\.\.\(/\)|\1|' \
  '{}' \+


%build


%check
desktop-file-validate res/asbru-cm.desktop


%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/{%{_mandir}/man1,%{_bindir}}
mkdir -p %{buildroot}/%{_datadir}/{%{name}/{lib,res,utils},applications}
mkdir -p %{buildroot}/%{_bashcompletiondir}
mkdir -p %{buildroot}/%{_datadir}/icons/hicolor/{24x24,64x64,256x256,scalable}/apps

install -m 755 asbru-cm %{buildroot}/%{_bindir}/%{name}

echo Bashcompletion Directory %{_bashcompletiondir}

cp -a res/asbru-cm.desktop %{buildroot}/%{_datadir}/applications/%{name}.desktop
cp -a res/asbru-cm.1 %{buildroot}/%{_mandir}/man1/%{name}.1
cp -a res/asbru_bash_completion %{buildroot}/%{_bashcompletiondir}/%{name}

# Copy the icons over to /usr/share/icons/
cp -a res/asbru-logo-24.png %{buildroot}/%{_datadir}/icons/hicolor/24x24/apps/%{name}.png
cp -a res/asbru-logo-64.png %{buildroot}/%{_datadir}/icons/hicolor/64x64/apps/%{name}.png
cp -a res/asbru-logo-256.png %{buildroot}/%{_datadir}/icons/hicolor/256x256/apps/%{name}.png
cp -a res/asbru-logo.svg %{buildroot}/%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg

# Copy the remaining resources and libraries
cp -a res/*.{png,pl,glade,svg} %{buildroot}/%{_datadir}/%{name}/res/
cp -ar res/themes/ %{buildroot}/%{_datadir}/%{name}/res/
cp -a lib/* %{buildroot}/%{_datadir}/%{name}/lib/
cp -a utils/*.pl %{buildroot}/%{_datadir}/%{name}/utils/

%files
%doc README.md
%license LICENSE
%{_mandir}/man1/%{name}*
%{_datadir}/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.*
%{_bashcompletiondir}/%{name}*
%{_bindir}/%{name}*


%post
/bin/touch --no-create %{_datadir}/icons/hicolor &>/dev/null || :


%postun
if [ $1 -eq 0 ] ; then
    /bin/touch --no-create %{_datadir}/icons/hicolor &>/dev/null
    /usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :
fi


%posttrans
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :


%changelog
* Sun Nov 13 2022 Ásbrú Project Team <contact@asbru-cm.net> 6.4.0
- 6.4.0 Release
* Sat May 21 2022 Ásbrú Project Team <contact@asbru-cm.net> 6.3.3
- 6.3.3 Release
* Sat Feb 27 2021 Ásbrú Project Team <contact@asbru-cm.net> 6.3.2
- 6.3.2 Release
* Mon Feb 22 2021 Ásbrú Project Team <contact@asbru-cm.net> 6.3.1
- 6.3.1 Release
* Tue Feb 16 2021 Ásbrú Project Team <contact@asbru-cm.net> 6.3.0
- 6.3.0 Release
* Sat Nov 07 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.2.2
- 6.2.2 release
- Moved repositories from Packagecloud to Cloudsmith
* Sat Jun 06 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.2.1
- 6.2.1 release
* Fri May 15 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.2.0
- 6.2.0 release
* Tue Apr 28 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.1.3
- 6.1.3 release
* Sun Apr 12 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.1.2
- 6.1.2 release
* Fri Mar 27 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.1.0
- 6.1.0 release
* Sat Mar 14 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.1.0rc2
- 6.1.0rc2 release
* Sun Mar 01 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.1.0rc1
- 6.1.0rc1 release
* Tue Feb 04 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.0.4
- 6.0.4 release
* Fri Jan 17 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.0.3
- 6.0.3 release
* Sat Jan 11 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.0.2
- 6.0.2 release
* Sat Jan 04 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.0.1
- 6.0.1 release
* Thu Jan 02 2020 Ásbrú Project Team <contact@asbru-cm.net> 6.0.0
- 6.0.0 release
* Tue Oct 15 2019 Ásbrú Project Team <contact@asbru-cm.net> 5.2.1
- 5.2.1 release
* Fri Apr 19 2019 Ásbrú Project Team <contact@asbru-cm.net> 5.2.0
- 5.2.0 release
* Mon Jul 23 2018 Ásbrú Project Team <contact@asbru-cm.net> 5.1.0
- 5.1.0 release
* Fri Dec 29 2017 Asbru Project Team <contact@asbru-cm.net> 5.0.0
- Final 5.0.0 release
* Sat Nov 4 2017 Asbru Project Team <contact@asbru-cm.net> 5.0.0
- Initial packaging of Ásbrú Connection Manager RPM
