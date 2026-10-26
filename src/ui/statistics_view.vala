/* statistics_view.vala
 *
 * Окно игровой статистики: игроки, набранные очки, победы (Оин/Марс/Домашний марс) и процент побед.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Диалог статистики с боковой панелью выбора игрока и таблицей детализации исходов партий.
 */
public class StatisticsView : PopupView {
    private string? selected_player = null;
    private Gtk.Box body;
    private Gtk.Button reset_button;
    private ulong stats_handler = 0;

    public StatisticsView () {
        base (550);
        add_css_class ("lb-popup-stats");
        height_request = 470;

        var header = new PopupHeader (Localization.stats_title (), true);
        header.close_button.clicked.connect (() => { close_requested (); });
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        body.vexpand = true;
        append (body);

        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        buttons.halign = Gtk.Align.CENTER;
        buttons.margin_top = 20;
        buttons.margin_bottom = 20;
        reset_button = UiKit.button (Localization.stats_reset_button (), "lb-btn-red");
        reset_button.add_css_class ("lb-btn-narrow");
        reset_button.clicked.connect (confirm_reset);
        buttons.append (reset_button);
        var close = UiKit.button (Localization.settings_close_button (), "lb-btn-blue");
        close.clicked.connect (() => { close_requested (); });
        buttons.append (close);
        append (buttons);

        stats_handler = StatsStore.shared ().changed.connect (rebuild);
        rebuild ();
    }

    public override void dispose () {
        if (stats_handler != 0) {
            StatsStore.shared ().disconnect (stats_handler);
            stats_handler = 0;
        }
        base.dispose ();
    }

    /** Список имён игроков, отсортированный по убыванию набранных очков (при равенстве — по алфавиту). */
    private string[] sorted_names () {
        var names = new string[0];
        StatsStore.shared ().player_stats.foreach ((name, st) => { names += name; });
        var stats = StatsStore.shared ().player_stats;
        for (var i = 0; i < names.length; i++) {
            for (var j = i + 1; j < names.length; j++) {
                var pi = stats.lookup (names[i]).total_points;
                var pj = stats.lookup (names[j]).total_points;
                if (pj > pi || (pj == pi && strcmp (names[j], names[i]) < 0)) {
                    var t = names[i];
                    names[i] = names[j];
                    names[j] = t;
                }
            }
        }
        return names;
    }

    private void rebuild () {
        UiKit.clear_box (body);
        var names = sorted_names ();
        var stats = StatsStore.shared ().player_stats;
        reset_button.sensitive = names.length > 0;
        if (names.length > 0) {
            reset_button.remove_css_class ("lb-btn-gray");
            reset_button.add_css_class ("lb-btn-red");
        } else {
            reset_button.remove_css_class ("lb-btn-red");
            reset_button.add_css_class ("lb-btn-gray");
        }

        if (names.length == 0) {
            var empty = new Gtk.Box (Gtk.Orientation.VERTICAL, 20);
            empty.hexpand = true;
            empty.valign = Gtk.Align.CENTER;
            var icon = new SFIcon ("chart.bar.xaxis", 50, null, 0.3);
            icon.halign = Gtk.Align.CENTER;
            empty.append (icon);
            empty.append (UiKit.label (Localization.stats_no_data (), "lb-headline lb-secondary", 0.5f));
            body.append (empty);
            return;
        }

        var exists = false;
        foreach (var n in names) {
            if (n == selected_player) {
                exists = true;
            }
        }
        if (!exists) {
            selected_player = names[0];
        }

        // Левая панель: список игроков
        var list = new Gtk.ListBox ();
        list.add_css_class ("navigation-sidebar");
        list.add_css_class ("lb-stats-list");
        list.selection_mode = Gtk.SelectionMode.SINGLE;
        Gtk.ListBoxRow? sel_row = null;
        foreach (var n in names) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            row.margin_top = 2;
            row.margin_bottom = 2;
            var nl = UiKit.label (n, "lb-body");
            nl.ellipsize = Pango.EllipsizeMode.END;
            nl.hexpand = true;
            row.append (nl);
            row.append (UiKit.label (stats.lookup (n).total_points.to_string (), "lb-subheadline lb-secondary", 1.0f));
            var lr = new Gtk.ListBoxRow ();
            lr.set_child (row);
            lr.set_cursor_from_name ("pointer");
            lr.set_data<string> ("player", n);
            list.append (lr);
            if (n == selected_player) {
                sel_row = lr;
            }
        }
        if (sel_row != null) {
            list.select_row (sel_row);
        }
        var detail_holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        detail_holder.hexpand = true;
        list.row_selected.connect ((r) => {
            if (r == null) {
                return;
            }
            selected_player = r.get_data<string> ("player");
            UiKit.clear_box (detail_holder);
            detail_holder.append (build_detail (selected_player));
        });
        var ls = new Gtk.ScrolledWindow ();
        ls.hscrollbar_policy = Gtk.PolicyType.NEVER;
        ls.width_request = 170;
        ls.set_child (list);
        body.append (ls);
        body.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
        detail_holder.append (build_detail (selected_player));
        body.append (detail_holder);
    }

    private Gtk.Widget build_detail (string name) {
        var st = StatsStore.shared ().player_stats.lookup (name);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        if (st == null) {
            return box;
        }
        var title = UiKit.label (name, "lb-title", 0.5f);
        title.wrap = true;
        title.justify = Gtk.Justification.CENTER;
        title.margin_top = 20;
        title.margin_bottom = 20;
        box.append (title);

        var table = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
        table.add_css_class ("lb-stats-table");
        // Заголовок таблицы
        var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        head.add_css_class ("lb-stats-head");
        var h1 = UiKit.label (Localization.info_section_title (), "lb-caption-bold lb-secondary");
        h1.hexpand = true;
        head.append (h1);
        head.append (fixed (UiKit.label (Localization.stats_header_count (), "lb-caption-bold lb-secondary", 1.0f), 60));
        head.append (fixed (UiKit.label (Localization.stats_header_points (), "lb-caption-bold lb-secondary", 1.0f), 70));
        table.append (head);
        table.append (detail_row (Localization.stats_oin_victories (), st.oin_victories, "🏅", st.oin_victories));
        table.append (detail_row (Localization.stats_mars_victories (), st.mars_victories, "🏆", st.mars_victories * 2));
        table.append (detail_row (Localization.stats_home_mars_victories (), st.home_mars_victories, "👑", st.home_mars_victories * 3));
        table.append (detail_row (Localization.stats_losses (), st.losses, "❌", -st.losses));
        // Итоговая строка
        var total = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        total.add_css_class ("lb-stats-total");
        var tl = UiKit.label (Localization.stats_total_points (), "lb-headline");
        tl.hexpand = true;
        total.append (tl);
        total.append (fixed (UiKit.label (st.games_played.to_string (), "lb-mono-bold", 1.0f), 60));
        total.append (fixed (UiKit.label (st.total_points.to_string (), "lb-mono-title3 lb-accent", 1.0f), 70));
        table.append (total);
        box.append (table);

        // Процент побед
        var wr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        wr.margin_start = 24;
        wr.margin_end = 24;
        wr.margin_top = 24;
        wr.margin_bottom = 24;
        wr.append (UiKit.label ("📈", "lb-headline lb-secondary"));
        var wl = UiKit.label (Localization.stats_win_rate (), "lb-headline lb-secondary");
        wl.hexpand = true;
        wr.append (wl);
        wr.append (UiKit.label ("%.1f%%".printf (st.win_rate), "lb-mono-title3", 1.0f));
        box.append (wr);
        return box;
    }

    private static Gtk.Widget fixed (Gtk.Widget w, int width) {
        w.width_request = width;
        return w;
    }

    private static Gtk.Widget detail_row (string title, int value, string emoji, int points) {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        row.add_css_class ("lb-stats-row");
        var left = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        left.hexpand = true;
        left.append (fixed (UiKit.label (emoji, "lb-body"), 24));
        var tl = UiKit.label (title, "lb-body lb-secondary");
        tl.ellipsize = Pango.EllipsizeMode.END;
        left.append (tl);
        row.append (left);
        row.append (fixed (UiKit.label (value.to_string (), "lb-mono-bold", 1.0f), 60));
        var pl = UiKit.label (points.to_string (), "lb-mono-bold", 1.0f);
        if (points > 0) {
            pl.add_css_class ("lb-accent");
        } else if (points < 0) {
            pl.add_css_class ("lb-red");
        }
        row.append (fixed (pl, 70));
        return row;
    }

    private void confirm_reset () {
        var dialog = new Adw.AlertDialog (Localization.stats_reset_confirmation_title (),
            Localization.stats_reset_confirmation_message ());
        dialog.add_response ("cancel", Localization.stats_reset_cancel_button ());
        dialog.add_response ("reset", Localization.stats_reset_confirm_button ());
        dialog.set_response_appearance ("reset", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";
        dialog.response.connect ((r) => {
            if (r == "reset") {
                selected_player = null;
                StatsStore.shared ().reset ();
            }
        });
        dialog.present (this);
    }
}

} /* namespace Longbackgammon */
