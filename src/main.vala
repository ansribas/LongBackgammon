/* main.vala
 *
 * Copyright 2026 Aleksey Svetlov
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

int main (string[] args) {
    GLib.Intl.setlocale (GLib.LocaleCategory.ALL, "");

    GLib.Environment.set_prgname ("io.github.ansribas.LongBackgammon");
    GLib.Environment.set_application_name ("LongBackgammon");

    var localedir = Config.LOCALEDIR;
    var uninstalled_locale = GLib.Path.build_filename (Config.SOURCE_DATA_DIR, "..", "build", "po");
    if (!GLib.FileUtils.test (localedir + "/ru/LC_MESSAGES/" + Config.GETTEXT_PACKAGE + ".mo", GLib.FileTest.EXISTS) &&
        GLib.FileUtils.test (uninstalled_locale, GLib.FileTest.IS_DIR)) {
        localedir = uninstalled_locale;
    }

    GLib.Intl.bindtextdomain (Config.GETTEXT_PACKAGE, localedir);
    GLib.Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    GLib.Intl.textdomain (Config.GETTEXT_PACKAGE);

    var app = new Longbackgammon.Application ();
    return app.run (args);
}
