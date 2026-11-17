/* statistics_view.vala
 *
 * Окно игровой статистики: игроки, набранные очки, победы (Оин/Марс/Домашний марс) и процент побед.
 * Оформлено в едином дизайне с GameOverView с модульными плашечными ячейками и звёздными индикаторами.
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
    private Gtk.Revealer reset_revealer;
    private int reset_click_count = 0;
    private ulong stats_handler = 0;

    /** Имя текущего игрока-человека: его статистика показывается при открытии окна. */
    private string? current_player_name = null;

    public StatisticsView (string? current_player_name = null) {
        base (640);
        this.current_player_name = current_player_name;
        add_css_class ("lb-popup-stats");
        height_request = 470;

        var header = new PopupHeader (Localization.stats_title (), true);
        header.close_button.clicked.connect (() => { close_requested (); });
        var title_click = new Gtk.GestureClick ();
        title_click.released.connect (() => {
            if (reset_click_count < 10) {
                reset_click_count++;
                if (reset_click_count >= 10) {
                    reset_revealer.reveal_child = true;
                }
            }
        });
        header.title_label.add_controller (title_click);
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        body.vexpand = true;
        append (body);

        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        buttons.halign = Gtk.Align.CENTER;
        buttons.margin_top = 20;
        buttons.margin_bottom = 20;
        reset_button = UiKit.button (Localization.stats_reset_button (), "lb-btn-red");
        reset_button.add_css_class ("lb-btn-narrow");
        reset_button.margin_end = 12;
        reset_button.clicked.connect (confirm_reset);
        reset_revealer = new Gtk.Revealer ();
        reset_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
        reset_revealer.transition_duration = 200;
        reset_revealer.reveal_child = false;
        reset_revealer.set_child (reset_button);
        buttons.append (reset_revealer);
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
        var stats = StatsStore.shared ().player_stats;
        stats.foreach ((name, st) => { names += name; });
        for (var i = 0; i < names.length; i++) {
            var pi = stats.lookup (names[i]).total_points;
            for (var j = i + 1; j < names.length; j++) {
                var pj = stats.lookup (names[j]).total_points;
                if (pj > pi || (pj == pi && strcmp (names[j], names[i]) < 0)) {
                    var t = names[i];
                    names[i] = names[j];
                    names[j] = t;
                    pi = pj;
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

        var exists = selected_player != null && stats.contains (selected_player);
        if (!exists && current_player_name != null && stats.contains (current_player_name)) {
            selected_player = current_player_name;
            exists = true;
        }
        if (!exists) {
            selected_player = names[0];
        }

        // Левая панель: список игроков (Sidebar)
        var list = new Gtk.ListBox ();
        list.add_css_class ("lb-stats-list");
        list.selection_mode = Gtk.SelectionMode.SINGLE;
        Gtk.ListBoxRow? sel_row = null;
        foreach (var n in names) {
            var st_item = stats.lookup (n);
            int pts = st_item != null ? st_item.total_points : 0;

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            var nl = UiKit.name_label (n, "lb-subheadline");
            nl.ellipsize = Pango.EllipsizeMode.END;
            nl.hexpand = true;
            row.append (nl);

            var pbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
            pbox.append (UiKit.label (pts.to_string (), "lb-subheadline lb-secondary", 1.0f));
            pbox.append (new StarIconWidget (pts < 0, 10.0));
            row.append (pbox);

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
        var sel_row_ref = sel_row;
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
        ls.width_request = 175;
        ls.set_child (list);
        if (sel_row_ref != null) {
            Idle.add (() => {
                Graphene.Point p;
                if (sel_row_ref.compute_point (list, Graphene.Point () { x = 0, y = 0 }, out p)) {
                    var adj = ls.vadjustment;
                    adj.value = double.max (0, p.y - (adj.page_size - sel_row_ref.get_height ()) / 2);
                }
                return Source.REMOVE;
            });
        }
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

        // Шапка детальной карточки игрока: имя слева (без ограничения длины), бейдж со звёздным индикатором справа
        var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        header_box.margin_start = 18;
        header_box.margin_end = 18;
        header_box.margin_top = 18;
        header_box.margin_bottom = 14;
        header_box.hexpand = true;

        var name_label = UiKit.name_label (name, "lb-stats-title", 0.0f, 0);
        name_label.max_width_chars = 1;
        name_label.ellipsize = Pango.EllipsizeMode.END;
        name_label.hexpand = true;
        name_label.halign = Gtk.Align.FILL;
        name_label.valign = Gtk.Align.CENTER;
        header_box.append (name_label);

        var badge = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        badge.add_css_class ("lb-stats-badge");
        badge.hexpand = false;
        badge.valign = Gtk.Align.CENTER;
        badge.append (new StarIconWidget (st.total_points < 0, 18.0));
        badge.append (UiKit.label (st.total_points.to_string (), "lb-go-total"));
        header_box.append (badge);
        box.append (header_box);

        // Сравнительная таблица в единой сетке со стилизованными плашечными ячейками (в стиле GameOverView)
        var grid = new Gtk.Grid ();
        grid.column_spacing = 3;
        grid.row_spacing = 3;
        grid.margin_start = 18;
        grid.margin_end = 18;
        grid.hexpand = true;
        grid.halign = Gtk.Align.FILL;

        // Строка 0: Заголовок таблицы
        var c_info = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        c_info.add_css_class ("lb-stats-cell");
        c_info.add_css_class ("head");
        c_info.hexpand = true;
        c_info.halign = Gtk.Align.FILL;
        c_info.height_request = 28;
        var h1 = UiKit.label (Localization.info_section_title ().up (), "lb-caption-bold lb-secondary");
        h1.margin_start = 10;
        h1.ellipsize = Pango.EllipsizeMode.END;
        h1.xalign = 0.0f;
        c_info.append (h1);
        grid.attach (c_info, 0, 0, 1, 1);

        var c_count = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        c_count.add_css_class ("lb-stats-cell");
        c_count.add_css_class ("head");
        c_count.width_request = 70;
        c_count.hexpand = false;
        c_count.halign = Gtk.Align.FILL;
        c_count.height_request = 28;
        var h2 = UiKit.label (Localization.stats_header_count ().up (), "lb-caption-bold lb-secondary");
        h2.halign = Gtk.Align.CENTER;
        h2.valign = Gtk.Align.CENTER;
        h2.hexpand = true;
        c_count.append (h2);
        grid.attach (c_count, 1, 0, 1, 1);

        var c_pts = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        c_pts.add_css_class ("lb-stats-cell");
        c_pts.add_css_class ("head");
        c_pts.width_request = 82;
        c_pts.hexpand = false;
        c_pts.halign = Gtk.Align.FILL;
        c_pts.height_request = 28;
        var h3_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
        h3_box.halign = Gtk.Align.CENTER;
        h3_box.valign = Gtk.Align.CENTER;
        h3_box.hexpand = true;
        h3_box.append (new StarIconWidget (false, 9.0));
        h3_box.append (UiKit.label (Localization.stats_header_points ().up (), "lb-caption-bold lb-secondary"));
        c_pts.append (h3_box);
        grid.attach (c_pts, 2, 0, 1, 1);

        // Строки 1-4: Категории результатов партий
        attach_stat_row (grid, 1, Localization.stats_oin_victories (), st.oin_victories, GameConfig.ICON_OIN_VICTORY, st.oin_victories, false);
        attach_stat_row (grid, 2, Localization.stats_mars_victories (), st.mars_victories, GameConfig.ICON_MARS_VICTORY, st.mars_victories * 2, false);
        attach_stat_row (grid, 3, Localization.stats_home_mars_victories (), st.home_mars_victories, GameConfig.ICON_HOME_MARS_VICTORY, st.home_mars_victories * 3, false);
        attach_stat_row (grid, 4, Localization.stats_losses (), st.losses, GameConfig.ICON_DEFEAT, -st.losses, true);

        // Строка 5: Итоговая строка «Всего очков»
        var tot_title = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        tot_title.add_css_class ("lb-stats-cell");
        tot_title.add_css_class ("total");
        tot_title.hexpand = true;
        tot_title.halign = Gtk.Align.FILL;
        tot_title.height_request = 30;
        var tl = UiKit.label (Localization.stats_total_points (), "lb-headline");
        tl.margin_start = 10;
        tl.ellipsize = Pango.EllipsizeMode.END;
        tl.xalign = 0.0f;
        tot_title.append (tl);
        grid.attach (tot_title, 0, 5, 1, 1);

        var tot_count = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        tot_count.add_css_class ("lb-stats-cell");
        tot_count.add_css_class ("total");
        tot_count.width_request = 70;
        tot_count.hexpand = false;
        tot_count.halign = Gtk.Align.FILL;
        tot_count.height_request = 30;
        var t_cnt_lbl = UiKit.label (st.games_played.to_string (), "lb-mono-bold");
        t_cnt_lbl.halign = Gtk.Align.CENTER;
        t_cnt_lbl.valign = Gtk.Align.CENTER;
        t_cnt_lbl.hexpand = true;
        tot_count.append (t_cnt_lbl);
        grid.attach (tot_count, 1, 5, 1, 1);

        var tot_pts = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        tot_pts.add_css_class ("lb-stats-cell");
        tot_pts.add_css_class ("total");
        tot_pts.width_request = 82;
        tot_pts.hexpand = false;
        tot_pts.halign = Gtk.Align.FILL;
        tot_pts.height_request = 30;
        var t_pts_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        t_pts_box.halign = Gtk.Align.CENTER;
        t_pts_box.valign = Gtk.Align.CENTER;
        t_pts_box.hexpand = true;
        var t_pts_lbl = UiKit.label (st.total_points.to_string (), "lb-mono-bold");
        if (st.total_points > 0) {
            t_pts_lbl.add_css_class ("lb-accent");
        } else if (st.total_points < 0) {
            t_pts_lbl.add_css_class ("lb-red");
        }
        t_pts_box.append (t_pts_lbl);
        t_pts_box.append (new StarIconWidget (st.total_points < 0, 12.0));
        tot_pts.append (t_pts_box);
        grid.attach (tot_pts, 2, 5, 1, 1);

        box.append (grid);

        // Процент побед (Win Rate)
        var wr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        wr.margin_start = 22;
        wr.margin_end = 22;
        wr.margin_top = 14;
        wr.append (UiKit.label ("📈", "lb-subheadline"));
        var wl = UiKit.label (Localization.stats_win_rate (), "lb-subheadline lb-secondary");
        wl.hexpand = true;
        wr.append (wl);
        wr.append (UiKit.label ("%.1f%%".printf (st.win_rate), "lb-mono-bold"));
        box.append (wr);

        return box;
    }

    private static void attach_stat_row (Gtk.Grid grid, int row_idx, string title, int count, string emoji, int points, bool is_defeat) {
        var c_title = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        c_title.add_css_class ("lb-stats-cell");
        c_title.hexpand = true;
        c_title.halign = Gtk.Align.FILL;
        c_title.height_request = 28;
        var em_lbl = UiKit.label (emoji, "lb-body");
        em_lbl.width_request = 20;
        em_lbl.halign = Gtk.Align.CENTER;
        em_lbl.margin_start = 8;
        c_title.append (em_lbl);
        var tl = UiKit.label (title, "lb-subheadline lb-secondary");
        tl.ellipsize = Pango.EllipsizeMode.END;
        tl.max_width_chars = 1;
        tl.hexpand = true;
        tl.xalign = 0.0f;
        c_title.append (tl);
        grid.attach (c_title, 0, row_idx, 1, 1);

        var c_count = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        c_count.add_css_class ("lb-stats-cell");
        c_count.width_request = 70;
        c_count.hexpand = false;
        c_count.halign = Gtk.Align.FILL;
        c_count.height_request = 28;
        var cnt_lbl = UiKit.label (count.to_string (), "lb-mono-bold");
        cnt_lbl.halign = Gtk.Align.CENTER;
        cnt_lbl.valign = Gtk.Align.CENTER;
        cnt_lbl.hexpand = true;
        c_count.append (cnt_lbl);
        grid.attach (c_count, 1, row_idx, 1, 1);

        var c_pts = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        c_pts.add_css_class ("lb-stats-cell");
        c_pts.width_request = 82;
        c_pts.hexpand = false;
        c_pts.halign = Gtk.Align.FILL;
        c_pts.height_request = 28;
        var pts_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        pts_box.halign = Gtk.Align.CENTER;
        pts_box.valign = Gtk.Align.CENTER;
        pts_box.hexpand = true;
        string pts_str = (points > 0) ? "+%d".printf (points) : points.to_string ();
        var pl = UiKit.label (pts_str, "lb-mono-bold");
        if (points > 0) {
            pl.add_css_class ("lb-accent");
        } else if (points < 0) {
            pl.add_css_class ("lb-red");
        } else {
            pl.add_css_class ("lb-secondary");
        }
        pts_box.append (pl);
        pts_box.append (new StarIconWidget (is_defeat && points < 0, 11.0));
        c_pts.append (pts_box);
        grid.attach (c_pts, 2, row_idx, 1, 1);
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