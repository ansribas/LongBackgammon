Name:           longbackgammon
Version:        1.0.7.2
Release:        1%{?dist}
Summary:        Classic Long Backgammon Board Game

License:        GPL-3.0-or-later
URL:            https://github.com/ansribas/LongBackgammon
Source0:        %{url}/archive/v%{version}/LongBackgammon-%{version}.tar.gz

BuildRequires:  meson >= 1.0.0
BuildRequires:  gcc
BuildRequires:  vala
BuildRequires:  gettext
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1) >= 1.5

Requires:       hicolor-icon-theme

%description
Long Backgammon is a popular variant of backgammon played with fifteen checkers
on a standard board. Players compete to move all their checkers into the home
board and bear them off first, following strict strategic rules and smart
positioning.

%prep
%autosetup -n LongBackgammon-%{version}

%build
%meson
%meson_build

%install
%meson_install
%find_lang %{name}

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/io.github.ansribas.LongBackgammon.desktop
appstream-util validate-relax --nonet %{buildroot}%{_datadir}/metainfo/io.github.ansribas.LongBackgammon.metainfo.xml

%files -f %{name}.lang
%license COPYING
%doc README.md README.ru.md
%{_bindir}/longbackgammon
%{_datadir}/longbackgammon/
%{_datadir}/applications/io.github.ansribas.LongBackgammon.desktop
%{_datadir}/metainfo/io.github.ansribas.LongBackgammon.metainfo.xml
%{_datadir}/glib-2.0/schemas/io.github.ansribas.LongBackgammon.gschema.xml
%{_datadir}/dbus-1/services/io.github.ansribas.LongBackgammon.service
%{_datadir}/icons/hicolor/*/apps/io.github.ansribas.LongBackgammon.png

%changelog
* Sat Nov 14 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.2-1
- Release 1.0.7.2

* Tue Nov 10 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7-2
- Validate AppStream metainfo using appstream-util in %check

* Sun Nov 08 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7-1
- Release 1.0.7
