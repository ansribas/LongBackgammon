Name:           longbackgammon
Version:        1.0.7.5
Release:        1%{?dist}
Summary:        Classic Long Backgammon Board Game

License:        GPL-3.0-or-later AND CC0-1.0
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

Requires:       %{name}-data = %{version}-%{release}
Requires:       hicolor-icon-theme

%description
Long Backgammon is a popular variant of backgammon played with fifteen checkers
on a standard board. Players compete to move all their checkers into the home
board and bear them off first, following strict strategic rules and smart
positioning.

%package        data
Summary:        Data files for Long Backgammon
License:        CC0-1.0 AND GPL-3.0-or-later
BuildArch:      noarch

%description    data
Data files for Long Backgammon, including graphics, sounds, and board themes.

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
%meson_test

%files -f %{name}.lang
%license COPYING
%doc README.md README.ru.md
%{_bindir}/longbackgammon
%{_datadir}/applications/io.github.ansribas.LongBackgammon.desktop
%{_datadir}/metainfo/io.github.ansribas.LongBackgammon.metainfo.xml
%{_datadir}/glib-2.0/schemas/io.github.ansribas.LongBackgammon.gschema.xml
%dir %{_datadir}/dbus-1
%dir %{_datadir}/dbus-1/services
%{_datadir}/dbus-1/services/io.github.ansribas.LongBackgammon.service
%{_datadir}/icons/hicolor/*/apps/io.github.ansribas.LongBackgammon.png

%files data
%license COPYING
%doc data/README.md
%{_datadir}/longbackgammon/

%changelog
* Thu Nov 19 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.5-1
- Release 1.0.7.5
- Document commercial subscription origin for audio assets in data/README.md
- Document application icon origin and CC0-1.0 license in data/README.md
- Update data subpackage license to CC0-1.0 AND GPL-3.0-or-later
- Fix %%meson_test macro escaping in changelog

* Wed Nov 18 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.4-1
- Release 1.0.7.4
- Document multimedia asset origins and license under CC0-1.0 in data/README.md
- Clean audio metadata tags from WAV files
- Update License tags to GPL-3.0-or-later AND CC0-1.0
- Co-own /usr/share/dbus-1 and /usr/share/dbus-1/services directories
- Execute %%meson_test in %%check
- Fix macro-in-changelog warning

* Tue Nov 17 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.3-1
- Redesign player statistics window with modular cells and star rating indicators
- Compact sidebar player list styled with native GNOME accent color
- Widen statistics dialog to 640px with adaptive player name truncation
- Update translations across all supported languages

* Sun Nov 15 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.2-2
- Move architecture-independent game assets to a noarch data subpackage
* Sat Nov 14 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7.2-1
- Release 1.0.7.2

* Tue Nov 10 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7-2
- Validate AppStream metainfo using appstream-util in %%check

* Sun Nov 08 2026 Aleksey Svetlov <ans.ribas@gmail.com> - 1.0.7-1
- Release 1.0.7
