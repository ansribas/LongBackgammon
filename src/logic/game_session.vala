/* game_session.vala
 *
 * Основной класс игровой сессии: состояние, жизненный цикл партии,
 * броски кубиков, ходы игрока и компьютера, отмена ходов, логи,
 * сохранение/восстановление.
 *
 * Асинхронные операции реализованы через async/yield-методы Vala и таймеры GLib.
 * Корректная отмена устаревших задач (при старте новой игры или сбросе)
 * контролируется счётчиком поколений партии (gen): корутина завершает работу,
 * если текущее поколение больше не совпадает со значением при её запуске.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Игровая сессия. Эмитит сигнал `changed` при любом изменении состояния,
 * чтобы интерфейс мог перерисоваться.
 */
public class GameSession : Object {
    // MARK: - Статистика для финального экрана
    public int white_moves_count = 0;
    public int black_moves_count = 0;
    public int white_doubles_count = 0;
    public int black_doubles_count = 0;
    public int white_total_dice_sum = 0;
    public int black_total_dice_sum = 0;
    public int white_burned_dice_sum = 0;
    public int black_burned_dice_sum = 0;

    // MARK: - Лог ходов (новые записи добавляются в начало массива)
    public TurnRecord[] white_turn_log;
    public TurnRecord[] black_turn_log;
    public int highlighted_log_id = -1;   // −1 — нет подсветки (аналог nil)
    public string white_player_name = "";
    public string black_player_name = "";
    public TurnRecord? current_turn_record = null;
    public TurnDie[] current_turn_dice;

    // MARK: - Флаги состояния
    public bool is_game_started = false;
    public bool is_game_over = false;
    public bool showing_game_over_result = false;
    public bool is_white_first_turn = true;
    public bool is_black_first_turn = true;

    public GameBoard board;
    public CheckerColor current_player = CheckerColor.WHITE;
    public DiceRoll? dice_roll = null;
    public int[] remaining_dice;
    public BoardPoint? selected_point = null;
    public BoardPoint? hovered_target_point = null;
    public bool is_hovering_bear_off_target = false;
    public int checkers_moved_from_head_this_turn = 0;
    public string status_message = "";

    public bool is_auto_playing_black = false;
    public bool is_animating = false;
    public bool is_placing_checkers = false;

    // MARK: - Состояния анимации кубиков
    public bool is_rolling = false;
    public bool is_doubling = false;
    /** 0: четыре кости собраны в пару, 1: кости разложены в сетку 2x2. */
    public double double_division_progress = 1.0;
    public bool is_no_moves_flashing = false;
    public bool is_first_move_rolloff_in_progress = false;
    public bool suppress_dice_cursor = false;
    public bool is_dice_flash_active = false;
    public double dice_flash_opacity = 0.0;
    /** ID единственной фишки, которую нужно анимировать при отмене хода. */
    public int undo_flight_checker_id = -1;
    public bool is_undoing_move = false;
    public BoardDiceState? board_dice_state = null;

    /** Точные координаты слотов кубиков в боковой панели (в системе координат доски). */
    public void dice_slot_centers (CheckerColor color, double board_side, out double x1, out double y1, out double x2, out double y2) {
        var is_right_side = BoardLayout.is_player_on_right_side (color);
        var mid_x = is_right_side ? (board_side + 70.0) : -70.0;
        var mid_y = 74.0;
        x1 = mid_x - 26.5;
        y1 = mid_y;
        x2 = mid_x + 26.5;
        y2 = mid_y;
    }

    // MARK: - Розыгрыш первого хода (по два кубика у каждого игрока)
    public CheckerColor? rolloff_active_player = CheckerColor.WHITE;
    public DiceRoll? white_rolloff_dice = null;
    public DiceRoll? black_rolloff_dice = null;
    /** Идентификатор анимации переноса кубиков розыгрыша в лог (0 — нет). */
    public int rolloff_animation_id = 0;
    public int rolling_die_index = -1;   // −1 — оба кубика (nil), 0/1 — игрок при roll-off
    public int rolling_dice_value1 = 6;
    public int rolling_dice_value2 = 6;

    // MARK: - Кэш легальных ходов
    public MoveOption[] cached_legal_options;

    // MARK: - Сигналы
    public signal void changed ();

    // MARK: - Внутренние поля
    private MoveSnapshot[] move_history;
    /** Поколение партии: меняется при новой игре / восстановлении — отменяет висящие задачи. */
    private uint gen = 0;
    /** Токен задачи автозавершения хода (аналог currentAsyncWork для triggerAutoEndTurn). */
    private uint auto_end_token = 0;
    private int rolloff_anim_counter = 0;

    public GameSession () {
        white_turn_log = new TurnRecord[0];
        black_turn_log = new TurnRecord[0];
        remaining_dice = new int[0];
        current_turn_dice = new TurnDie[0];
        cached_legal_options = new MoveOption[0];
        move_history = new MoveSnapshot[0];
        board = GameBoard.in_tray ();

        init_player_names ();

        if (SettingsStore.shared ().is_first_move_rolloff_enabled) {
            is_first_move_rolloff_in_progress = true;
            rolloff_active_player = CheckerColor.WHITE;
            status_message = Localization.status_rolloff_prompt ();
        } else {
            is_first_move_rolloff_in_progress = false;
            rolloff_active_player = null;
            status_message = Localization.status_new_game ();
        }

        // При смене настроек (язык интерфейса, имена игроков) актуализируем статус партии
        SettingsStore.shared ().changed.connect (() => {
            var old_status = status_message;
            update_status_on_language_change ();
            if (old_status != status_message) {
                notify_changed ();
            }
        });
    }

    private void notify_changed () {
        changed ();
    }

    // MARK: - Асинхронные помощники

    /** Асинхронная пауза (аналог Task.sleep). */
    private async void sleep_async (double seconds) {
        SourceFunc cb = sleep_async.callback;
        var ms = (uint) (seconds * 1000.0);
        Timeout.add (ms, () => {
            cb ();
            return Source.REMOVE;
        });
        yield;
    }

    /** Отложенное действие (аналог DispatchQueue.main.asyncAfter). Отменяется при смене партии. */
    private void after (double seconds, owned DelayedCallback fn) {
        var g = gen;
        Timeout.add ((uint) (seconds * 1000.0), () => {
            if (g == gen) {
                fn ();
            }
            return Source.REMOVE;
        });
    }

    private void cancel_all_tasks () {
        gen++;
        auto_end_token++;
        is_placing_checkers = false;
        if (placement_timer_id > 0) {
            Source.remove (placement_timer_id);
            placement_timer_id = 0;
        }
        current_placement_targets = new TargetPlacementLocation[0];
        SoundManager.shared ().stop_placement ();
    }

    // MARK: - Вычисляемые свойства

    public bool should_show_white_die {
        get {
            if (is_first_move_rolloff_in_progress) {
                return white_rolloff_dice != null || (is_rolling && rolling_die_index == 0);
            }
            return dice_roll != null || is_rolling || is_doubling;
        }
    }

    public bool should_show_black_die {
        get {
            if (is_first_move_rolloff_in_progress) {
                return black_rolloff_dice != null || (is_rolling && rolling_die_index == 1);
            }
            return dice_roll != null || is_rolling || is_doubling;
        }
    }

    public int white_pip_count {
        get { return calculate_pip_count (CheckerColor.WHITE); }
    }

    public int black_pip_count {
        get { return calculate_pip_count (CheckerColor.BLACK); }
    }

    public bool is_black_computer {
        get { return SettingsStore.shared ().is_black_computer; }
    }

    /** Ход компьютера (чёрные против компьютера). */
    public bool is_computer_turn {
        get {
            if (is_first_move_rolloff_in_progress) {
                if (rolloff_active_player != null) {
                    return rolloff_active_player == CheckerColor.BLACK && is_black_computer;
                }
            }
            return current_player == CheckerColor.BLACK && is_black_computer;
        }
    }

    /** Проверяет возможность текущего игрока выполнить бросок костей. */
    public bool can_roll {
        get {
            if (!is_game_started || dice_roll != null || is_rolling || is_doubling || is_no_moves_flashing || is_game_over || is_animating) {
                return false;
            }
            if (is_first_move_rolloff_in_progress) {
                if (white_rolloff_dice != null && black_rolloff_dice != null) {
                    return true;
                }
                if (rolloff_active_player == null) {
                    return false;
                }
                return rolloff_active_player == CheckerColor.WHITE ? white_rolloff_dice == null : black_rolloff_dice == null;
            }
            return true;
        }
    }

    /** Доступна ли отмена последнего полухода в текущем раунде. */
    public bool can_undo {
        get {
            return !is_animating && move_history.length > 0 && !is_game_over
                   && !is_computer_turn && remaining_dice.length > 0;
        }
    }

    /** Определяет необходимость отображения интерактивного курсора-кубика на доске. */
    public bool show_dice_cursor {
        get {
            var is_rolloff_resolving = is_first_move_rolloff_in_progress
                && white_rolloff_dice != null && black_rolloff_dice != null;
            return can_roll && !is_computer_turn && !suppress_dice_cursor && !is_rolloff_resolving;
        }
    }

    public bool is_game_in_progress {
        get { return is_game_started && !is_placing_checkers && !is_game_over && !showing_game_over_result; }
    }

    /** Ходы подсвеченной записи лога. */
    public LogMove[] active_log_moves () {
        if (highlighted_log_id < 0) {
            return new LogMove[0];
        }
        foreach (var r in white_turn_log) {
            if (r.id == highlighted_log_id) {
                return r.moves;
            }
        }
        foreach (var r in black_turn_log) {
            if (r.id == highlighted_log_id) {
                return r.moves;
            }
        }
        return new LogMove[0];
    }

    /** Цвет игрока, которому принадлежит запись лога с указанным id. */
    public bool find_log_record (int id, out TurnRecord? record, out CheckerColor color) {
        foreach (var r in white_turn_log) {
            if (r.id == id) {
                record = r;
                color = CheckerColor.WHITE;
                return true;
            }
        }
        foreach (var r in black_turn_log) {
            if (r.id == id) {
                record = r;
                color = CheckerColor.BLACK;
                return true;
            }
        }
        record = null;
        color = CheckerColor.WHITE;
        return false;
    }

    /** Точки, затронутые подсвеченной записью лога. */
    public BoardPoint[] log_highlight_points () {
        var result = new BoardPoint[0];
        foreach (var m in active_log_moves ()) {
            foreach (var s in m.steps) {
                if (!contains_point (result, s.from)) {
                    result += s.from;
                }
                if (s.to != null && !contains_point (result, s.to)) {
                    result += s.to;
                }
            }
        }
        return result;
    }

    private static bool contains_point (BoardPoint[] arr, BoardPoint p) {
        foreach (var x in arr) {
            if (x == p) {
                return true;
            }
        }
        return false;
    }

    /** Можно ли вынести выбранную фишку. */
    public bool can_bear_off_selected {
        get {
            if (selected_point == null) {
                return false;
            }
            foreach (var o in options_from (selected_point)) {
                if (o.to == null) {
                    return true;
                }
            }
            return false;
        }
    }

    /** Все точки назначения (для подсветки). */
    public BoardPoint[] target_points () {
        var result = new BoardPoint[0];
        if (selected_point == null) {
            return result;
        }
        foreach (var o in options_from (selected_point)) {
            if (o.to != null && !o.is_illegal_prime && !contains_point (result, o.to)) {
                result += o.to;
            }
        }
        return result;
    }

    /** Потенциальные точки назначения (включая заблокированные). */
    public BoardPoint[] potential_targets () {
        var result = new BoardPoint[0];
        if (selected_point == null || remaining_dice.length == 0) {
            return result;
        }
        foreach (var die in remaining_dice) {
            var target = PlayerPath.point_from (selected_point, die, current_player);
            if (target != null && !contains_point (result, target)) {
                result += target;
            }
        }
        return result;
    }

    // MARK: - Pip Count

    public int calculate_pip_count (CheckerColor color) {
        var route = PlayerPath.path (color);
        var total = 0;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                total += stack.checker_ids.length * (route.length - i);
            }
        }
        return total;
    }

    public double progress_percentage (CheckerColor color) {
        var pips = (double) calculate_pip_count (color);
        var progress = (1.0 - (pips / 360.0)) * 100.0;
        return double.min (100.0, double.max (0.0, progress));
    }

    public double white_progress { get { return progress_percentage (CheckerColor.WHITE); } }
    public double black_progress { get { return progress_percentage (CheckerColor.BLACK); } }

    /** Количество фишек вынесенных за борт цветом. */
    public int borne_off_count_for (CheckerColor color) {
        return board.borne_off_count (color);
    }

    // MARK: - Доступные ходы

    public MoveOption[] options_from (BoardPoint point) {
        var result = new MoveOption[0];
        if (remaining_dice.length == 0) {
            return result;
        }
        foreach (var o in cached_legal_options) {
            if (o.from == point) {
                result += o;
            }
        }
        return result;
    }

    // MARK: - Выбор точки (аналог didSet у selectedPoint)

    /** Устанавливает выбранную точку с фишкой; при сбросе обновляет подсказку статуса. */
    public void set_selected_point (BoardPoint? point) {
        if (selected_point != point) {
            hovered_target_point = null;
            is_hovering_bear_off_target = false;
        }
        selected_point = point;
        if (selected_point == null && dice_roll != null && remaining_dice.length > 0 && !is_animating
            && !is_game_over && !is_rolling && !is_computer_turn) {
            status_message = Localization.status_select_checker ();
        }
    }

    /** Сброс выбора фишки (клик по пустому месту / по панели). */
    public void select_point_none () {
        hovered_target_point = null;
        is_hovering_bear_off_target = false;
        if (selected_point != null) {
            set_selected_point (null);
            notify_changed ();
        }
    }

    // MARK: - Управление показом экрана победы

    /** Управляет отображением финального экрана завершения партии. */
    public void set_showing_game_over_result (bool value) {
        var old = showing_game_over_result;
        showing_game_over_result = value;
        if (!value && old) {
            is_game_started = false;
        }
        notify_changed ();
    }

    public void set_game_started (bool value) {
        is_game_started = value;
        notify_changed ();
    }

    // MARK: - Кубики текущего хода

    public void consume_die (int value) {
        foreach (var d in current_turn_dice) {
            if (!d.is_used && !d.is_skipped && d.value == value) {
                d.is_used = true;
                break;
            }
        }
        if (current_turn_record != null) {
            foreach (var d in current_turn_record.dice) {
                if (!d.is_used && !d.is_skipped && d.value == value) {
                    d.is_used = true;
                    break;
                }
            }
        }
    }

    private static int[] move_values (DiceRoll roll) {
        if (roll.is_double) {
            return { roll.die1, roll.die1, roll.die1, roll.die1 };
        }
        return { roll.die1, roll.die2 };
    }

    private static int sum_ints (int[] a) {
        var s = 0;
        foreach (var v in a) {
            s += v;
        }
        return s;
    }

    private static bool same_roll (DiceRoll? a, DiceRoll? b) {
        if (a == null || b == null) {
            return a == b;
        }
        return a.die1 == b.die1 && a.die2 == b.die2;
    }

    private int[] remove_at (int[] arr, int index) {
        var result = new int[0];
        for (var i = 0; i < arr.length; i++) {
            if (i != index) {
                result += arr[i];
            }
        }
        return result;
    }

    private int index_of (int[] arr, int value) {
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return i;
            }
        }
        return -1;
    }

    private static int[] copy_int_array (int[] src) {
        var copy = new int[src.length];
        for (var i = 0; i < src.length; i++) {
            copy[i] = src[i];
        }
        return copy;
    }

    private static int[] sorted_desc (int[] src) {
        var a = copy_int_array (src);
        for (var i = 0; i < a.length; i++) {
            for (var j = i + 1; j < a.length; j++) {
                if (a[j] > a[i]) {
                    var t = a[i];
                    a[i] = a[j];
                    a[j] = t;
                }
            }
        }
        return a;
    }

    /** Удаляет использованные кубики по индексам (от большего к меньшему) и отмечает их в текущем ходе. */
    private void remove_used_dice (int[] indices) {
        foreach (var index in sorted_desc (indices)) {
            if (index < remaining_dice.length) {
                var val = remaining_dice[index];
                remaining_dice = remove_at (remaining_dice, index);
                consume_die (val);
            }
        }
    }

    /** Удаляет первый кубик с указанным значением (для поэтапной анимации). */
    private void remove_die_by_value (int value) {
        var idx = index_of (remaining_dice, value);
        if (idx >= 0) {
            remaining_dice = remove_at (remaining_dice, idx);
            consume_die (value);
        }
    }

    private void insert_log_record (CheckerColor color, TurnRecord record) {
        if (color == CheckerColor.WHITE) {
            var arr = new TurnRecord[0];
            arr += record;
            foreach (var r in white_turn_log) {
                arr += r;
            }
            white_turn_log = arr;
        } else {
            var arr = new TurnRecord[0];
            arr += record;
            foreach (var r in black_turn_log) {
                arr += r;
            }
            black_turn_log = arr;
        }
    }

    private int non_rolloff_count (TurnRecord[] log) {
        var n = 0;
        foreach (var r in log) {
            if (!r.is_rolloff) {
                n++;
            }
        }
        return n;
    }

    // MARK: - Жизненный цикл: конец хода, новая игра, форсированный сброс

    public void end_turn () {
        if (is_game_over) {
            return;
        }
        move_history = new MoveSnapshot[0];

        if (current_turn_record != null) {
            var record = current_turn_record;
            if (current_turn_dice.length > 0) {
                record.dice = TurnDie.clone_array (current_turn_dice);
            }
            insert_log_record (current_player, record);
        }
        current_turn_record = null;
        current_turn_dice = new TurnDie[0];

        if (current_player == CheckerColor.WHITE) {
            is_white_first_turn = false;
        } else {
            is_black_first_turn = false;
        }

        current_player = current_player.opposite ();
        dice_roll = null;
        rolling_die_index = -1;
        remaining_dice = new int[0];
        cached_legal_options = new MoveOption[0];
        selected_point = null;
        checkers_moved_from_head_this_turn = 0;

        is_doubling = false;
        double_division_progress = 1.0;
        is_dice_flash_active = false;
        dice_flash_opacity = 0.0;
        is_no_moves_flashing = false;
        is_rolling = false;
        is_animating = false;
        is_auto_playing_black = false;

        status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        notify_changed ();
        if (is_computer_turn) {
            auto_play_if_needed ();
        }
    }

    /** Сброс партии без старта новой (после подтверждения «Новая игра»). */
    public void force_new_game () {
        cancel_all_tasks ();

        if (is_game_started && !is_game_over) {
            var loser_color = current_player;
            var loser_name = player_name (loser_color);
            if (!is_computer_player (loser_color)) {
                StatsStore.shared ().record_loss (loser_name);
            }
            var winner_color = loser_color.opposite ();
            if (!is_computer_player (winner_color)) {
                StatsStore.shared ().record_victory (player_name (winner_color), VictoryType.OIN);
            }
            save_game_log ();
        }

        is_animating = false;
        is_rolling = false;
        is_auto_playing_black = false;
        is_doubling = false;
        is_no_moves_flashing = false;
        is_dice_flash_active = false;
        dice_flash_opacity = 0.0;
        is_undoing_move = false;
        undo_flight_checker_id = -1;
        suppress_dice_cursor = false;
        board_dice_state = null;

        is_white_first_turn = true;
        is_black_first_turn = true;

        dice_roll = null;
        remaining_dice = new int[0];
        rolling_dice_value1 = 6;
        rolling_dice_value2 = 6;
        selected_point = null;
        checkers_moved_from_head_this_turn = 0;

        current_turn_record = null;
        current_turn_dice = new TurnDie[0];
        highlighted_log_id = -1;

        is_game_over = false;
        showing_game_over_result = false;

        white_rolloff_dice = null;
        black_rolloff_dice = null;
        rolloff_animation_id = 0;
        rolling_die_index = -1;
        is_first_move_rolloff_in_progress = false;
        rolloff_active_player = null;

        reset_stats ();
        move_history = new MoveSnapshot[0];
        cached_legal_options = new MoveOption[0];

        init_player_names ();
        status_message = Localization.status_new_game ();

        SavedGameStore.shared ().clear ();

        board = GameBoard.in_tray ();
        is_game_started = false;
        notify_changed ();
    }

    /** Новая партия. */
    public void new_game (bool silent = false, bool animated = true) {
        SavedGameStore.shared ().clear ();
        init_player_names ();
        is_game_started = true;

        cancel_all_tasks ();

        is_animating = false;
        is_placing_checkers = false;
        is_rolling = false;
        is_auto_playing_black = false;
        is_doubling = false;
        is_no_moves_flashing = false;
        is_dice_flash_active = false;
        dice_flash_opacity = 0.0;
        is_undoing_move = false;
        undo_flight_checker_id = -1;
        suppress_dice_cursor = false;

        is_white_first_turn = true;
        is_black_first_turn = true;

        current_player = CheckerColor.WHITE;
        dice_roll = null;
        remaining_dice = new int[0];
        rolling_dice_value1 = 6;
        rolling_dice_value2 = 6;
        selected_point = null;
        hovered_target_point = null;
        is_hovering_bear_off_target = false;
        checkers_moved_from_head_this_turn = 0;

        white_turn_log = new TurnRecord[0];
        black_turn_log = new TurnRecord[0];
        current_turn_record = null;
        current_turn_dice = new TurnDie[0];
        highlighted_log_id = -1;

        is_game_over = false;
        showing_game_over_result = false;

        white_rolloff_dice = null;
        black_rolloff_dice = null;
        rolloff_animation_id = 0;
        rolling_die_index = -1;

        if (SettingsStore.shared ().is_first_move_rolloff_enabled) {
            is_first_move_rolloff_in_progress = true;
            rolloff_active_player = CheckerColor.WHITE;
            status_message = Localization.status_rolloff_prompt ();
        } else {
            is_first_move_rolloff_in_progress = false;
            rolloff_active_player = null;
            status_message = Localization.status_new_game ();
        }

        reset_stats ();
        move_history = new MoveSnapshot[0];
        cached_legal_options = new MoveOption[0];

        if (animated) {
            is_animating = true;
            is_placing_checkers = true;
            board = GameBoard.in_tray ();
            notify_changed ();
            animate_placement (GameBoard.initial_long (), !silent, !silent);
        } else {
            board = GameBoard.initial_long ();
            is_animating = false;
            is_placing_checkers = false;
            if (!silent) {
                SoundManager.shared ().play_new_game_start ();
            }
            notify_changed ();
        }
    }

    public delegate void PlacementCompletion ();

    private TargetPlacementLocation[] current_placement_targets = new TargetPlacementLocation[0];
    private int current_placement_index = 0;
    private GameBoard? current_placement_target_board = null;
    private bool current_placement_sound = true;
    private bool current_placement_new_game_sound = false;
    private PlacementCompletion? current_placement_completion = null;
    private uint placement_timer_id = 0;
    private double placement_start_time = 0.0;

    /** Анимирует последовательную расстановку фишек на доске. */
    public void animate_placement (
        GameBoard target_board,
        bool play_placement_sound = true,
        bool play_new_game_sound_on_completion = false,
        owned PlacementCompletion? completion = null
    ) {
        cancel_all_tasks ();
        current_placement_completion = (owned) completion;
        var cur_gen = gen;
        is_animating = true;
        is_placing_checkers = true;

        GameBoard effective_target_board;
        if (board.is_in_tray ()) {
            effective_target_board = target_board.normalized_for_placement_from_tray ();
        } else {
            effective_target_board = target_board;
        }

        var target_locations = new TargetPlacementLocation?[30];

        for (var raw = 1; raw <= 24; raw++) {
            var stack = effective_target_board.stacks[raw];
            if (stack != null) {
                var pt = BoardPoint.from_raw (raw);
                for (var idx = 0; idx < stack.checker_ids.length; idx++) {
                    var cid = stack.checker_ids[idx];
                    if (cid < 30) {
                        target_locations[cid] = new TargetPlacementLocation (
                            cid,
                            stack.color,
                            pt,
                            idx
                        );
                    }
                }
            }
        }

        for (var idx = 0; idx < effective_target_board.white_borne_off_ids.length; idx++) {
            var cid = effective_target_board.white_borne_off_ids[idx];
            if (cid < 30) {
                target_locations[cid] = new TargetPlacementLocation (
                    cid,
                    CheckerColor.WHITE,
                    null,
                    idx
                );
            }
        }

        for (var idx = 0; idx < effective_target_board.black_borne_off_ids.length; idx++) {
            var cid = effective_target_board.black_borne_off_ids[idx];
            if (cid < 30) {
                target_locations[cid] = new TargetPlacementLocation (
                    cid,
                    CheckerColor.BLACK,
                    null,
                    idx
                );
            }
        }

        TargetPlacementLocation[] moving_targets = new TargetPlacementLocation[0];
        for (uint8 id = 0; id < 30; id++) {
            var tgt = target_locations[id];
            if (tgt != null) {
                BoardPoint? cur_pt;
                int cur_idx;
                var found = board.find_checker_location (id, out cur_pt, out cur_idx);
                if (found) {
                    if (cur_pt != tgt.point || cur_idx != tgt.stack_index) {
                        moving_targets += tgt;
                    }
                } else {
                    moving_targets += tgt;
                }
            }
        }

        if (moving_targets.length == 0) {
            board = effective_target_board;
            is_animating = false;
            is_placing_checkers = false;
            if (play_new_game_sound_on_completion) {
                SoundManager.shared ().play_new_game_start ();
            }
            if (current_placement_completion != null) {
                var cb = (owned) current_placement_completion;
                cb ();
            }
            notify_changed ();
            return;
        }

        // Сортировка: белые перед чёрными, затем уровень стопки снизу вверх (stack_index), затем id
        for (var i = 0; i < moving_targets.length - 1; i++) {
            for (var j = i + 1; j < moving_targets.length; j++) {
                var a = moving_targets[i];
                var b = moving_targets[j];
                bool swap = false;
                if (a.color != b.color) {
                    swap = (a.color != CheckerColor.WHITE);
                } else if (a.stack_index != b.stack_index) {
                    swap = (a.stack_index > b.stack_index);
                } else {
                    swap = (a.id > b.id);
                }
                if (swap) {
                    moving_targets[i] = b;
                    moving_targets[j] = a;
                }
            }
        }

        current_placement_targets = moving_targets;
        current_placement_index = 0;
        current_placement_target_board = effective_target_board;
        current_placement_sound = play_placement_sound;
        current_placement_new_game_sound = play_new_game_sound_on_completion;

        if (play_placement_sound) {
            SoundManager.shared ().play_dynamic_placement (moving_targets.length, 0.30f);
        }

        placement_start_time = GLib.get_monotonic_time () / 1000000.0;
        start_placement_timer (cur_gen);
    }

    private void start_placement_timer (uint token) {
        if (placement_timer_id > 0) {
            Source.remove (placement_timer_id);
            placement_timer_id = 0;
        }

        // Первый шаг выполняем немедленно при t = 0
        tick_placement (token);

        placement_timer_id = Timeout.add (8, () => {
            return tick_placement (token);
        });
    }

    private bool tick_placement (uint token) {
        if (token != gen || !is_placing_checkers) {
            is_placing_checkers = false;
            placement_timer_id = 0;
            SoundManager.shared ().stop_placement ();
            return Source.REMOVE;
        }

        var now = GLib.get_monotonic_time () / 1000000.0;
        var elapsed = double.max (0.0, now - placement_start_time);

        // Количество фишек, которые уже должны быть на доске к моменту elapsed:
        // Первая фишка (индекс 0) вылетает при t = 0.
        // Следующая фишка (индекс i) вылетает при t >= i * STEP_INTERVAL.
        int target_count = int.min (
            (int) (elapsed / PlacementAnimation.STEP_INTERVAL) + 1,
            current_placement_targets.length
        );

        bool changed = false;
        while (current_placement_index < target_count) {
            var t = current_placement_targets[current_placement_index];
            board.place_checker (t.id, t.color, t.point, t.stack_index);
            current_placement_index++;
            changed = true;
        }

        if (changed) {
            notify_changed ();
        }

        if (current_placement_index >= current_placement_targets.length) {
            placement_timer_id = 0;
            after (PlacementAnimation.COMPLETION_DELAY, () => {
                if (token != gen) {
                    is_placing_checkers = false;
                    return;
                }
                if (current_placement_target_board != null) {
                    board = current_placement_target_board;
                }
                is_animating = false;
                is_placing_checkers = false;
                if (current_placement_new_game_sound) {
                    SoundManager.shared ().play_new_game_start ();
                }
                if (current_placement_completion != null) {
                    var cb = (owned) current_placement_completion;
                    cb ();
                }
                notify_changed ();
            });
            return Source.REMOVE;
        }

        return Source.CONTINUE;
    }

    private void reset_stats () {
        white_moves_count = 0;
        black_moves_count = 0;
        white_doubles_count = 0;
        black_doubles_count = 0;
        white_total_dice_sum = 0;
        black_total_dice_sum = 0;
        white_burned_dice_sum = 0;
        black_burned_dice_sum = 0;
    }

    // MARK: - Вспомогательные методы

    public string player_name (CheckerColor color) {
        return color == CheckerColor.WHITE ? white_player_name : black_player_name;
    }

    public bool is_computer_player (CheckerColor color) {
        return color == CheckerColor.BLACK && is_black_computer;
    }

    public void init_player_names () {
        var store = SettingsStore.shared ();
        if (store.opponent == Opponent.COMPUTER) {
            white_player_name = store.white_player_name.strip () == ""
                ? Localization.default_player_name () : store.white_player_name;
            black_player_name = Localization.settings_opponent_computer ();
        } else {
            white_player_name = store.white_player_name.strip () == ""
                ? Localization.default_player1_name () : store.white_player_name;
            black_player_name = store.black_player_name.strip () == ""
                ? Localization.default_player2_name () : store.black_player_name;
        }
    }

    public void update_status_on_language_change () {
        init_player_names ();
        if (is_game_over) {
            status_message = (current_player == CheckerColor.WHITE) ? Localization.victory_white () : Localization.victory_black ();
        } else if (is_first_move_rolloff_in_progress) {
            if (white_rolloff_dice != null && black_rolloff_dice != null) {
                var w_sum = white_rolloff_dice.die1 + white_rolloff_dice.die2;
                var b_sum = black_rolloff_dice.die1 + black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    status_message = Localization.status_rolloff_tie ();
                } else {
                    var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                    status_message = Localization.status_rolloff_result (player_name (winner));
                }
            } else {
                status_message = is_computer_turn ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
            }
        } else if (dice_roll == null) {
            status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        } else if (is_animating && is_computer_turn) {
            status_message = Localization.status_computer_moving ();
        } else {
            status_message = (selected_point == null) ? Localization.status_select_checker () : Localization.status_select_target ();
        }
    }

    // MARK: - Запись в лог (GameSession+Log)

    /** Записывает выполненный ход в текущую запись лога. */
    public void record_move_in_log (MoveOption move, IntermediateStep[] steps) {
        if (current_turn_record == null) {
            return;
        }
        var log_steps = new LogStep[0];
        string move_str;

        if (steps.length > 0) {
            foreach (var s in steps) {
                log_steps += new LogStep (s.from, s.to);
            }
            var b = new StringBuilder (move.from.raw_value ().to_string ());
            foreach (var s in steps) {
                b.append_c ('-');
                b.append (s.to == null ? "^" : s.to.raw_value ().to_string ());
            }
            move_str = b.str;
        } else {
            log_steps += new LogStep (move.from, move.to);
            move_str = "%d-%s".printf (move.from.raw_value (), move.to == null ? "^" : move.to.raw_value ().to_string ());
        }

        current_turn_record.move_strings = ArrUtil.append_str (current_turn_record.move_strings, move_str);
        current_turn_record.moves = ArrUtil.append_move (current_turn_record.moves, new LogMove (log_steps));
    }

    /** Обновляет кэш легальных ходов по текущему состоянию. */
    public void update_available_moves_cache () {
        if (remaining_dice.length == 0) {
            cached_legal_options = new MoveOption[0];
            return;
        }
        var is_first_turn = (current_player == CheckerColor.WHITE) ? is_white_first_turn : is_black_first_turn;
        var all = MoveValidator.all_moves (
            board,
            current_player,
            remaining_dice,
            checkers_moved_from_head_this_turn,
            dice_roll != null && dice_roll.is_double,
            is_first_turn);
        cached_legal_options = MoveValidator.filter_legal_moves (
            all, board, current_player, remaining_dice,
            checkers_moved_from_head_this_turn,
            dice_roll != null && dice_roll.is_double,
            is_first_turn);
    }

    /** Строка текущих кубиков: "3, 5" и т.п. */
    public string current_dice_string () {
        var parts = new string[remaining_dice.length];
        for (var i = 0; i < remaining_dice.length; i++) {
            parts[i] = remaining_dice[i].to_string ();
        }
        return string.joinv (", ", parts);
    }

    /** Завершение партии: фиксация победы, запись статистики и отложенный показ итогового окна. */
    public void handle_delayed_victory () {
        // Немедленно блокируем доску и управление, но сохраняем сессию незавершённой
        // до окончания полёта сгоревших/использованных кубиков в лог
        is_animating = true;
        selected_point = null;
        remaining_dice = new int[0];
        move_history = new MoveSnapshot[0];

        status_message = (current_player == CheckerColor.WHITE)
            ? Localization.victory_white ()
            : Localization.victory_black ();

        // Определяем победителя и проигравшего
        var winner_name = player_name (current_player);
        var loser_color = current_player.opposite ();
        var loser_name = player_name (loser_color);

        var is_home_mars = board.borne_off_count (loser_color) == 0
                           && MoveValidator.are_all_checkers_in_home (board, loser_color);
        var is_mars = board.borne_off_count (loser_color) == 0 && !is_home_mars;
        var victory_type = is_home_mars ? VictoryType.HOME_MARS : (is_mars ? VictoryType.MARS : VictoryType.OIN);

        if (!is_computer_player (current_player)) {
            StatsStore.shared ().record_victory (winner_name, victory_type);
        }
        if (!is_computer_player (loser_color)) {
            StatsStore.shared ().record_loss (loser_name);
        }

        notify_changed ();
        delayed_victory_task.begin (gen);
    }

    private async void delayed_victory_task (uint g) {
        var checker_duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;

        bool has_unused_dice = false;
        foreach (var d in current_turn_dice) {
            if (!d.is_used && !d.is_skipped) {
                has_unused_dice = true;
                break;
            }
        }

        if (has_unused_dice) {
            // 1. Ждём завершения движения победной фишки
            yield sleep_async (checker_duration);
            if (g != gen) {
                return;
            }

            // 2. Пауза перед перечёркиванием: оставшийся кубик (или кубики при дубле) виден неперечёркнутым
            yield sleep_async (pause);
            if (g != gen) {
                return;
            }

            // Считаем сгоревшие очки и добавляем запись о пропуске в лог
            int burned = 0;
            string[] unused_dice_values = new string[0];
            foreach (var d in current_turn_dice) {
                if (!d.is_used && !d.is_skipped) {
                    burned += d.value;
                    unused_dice_values += d.value.to_string ();
                }
            }
            if (current_player == CheckerColor.WHITE) {
                white_burned_dice_sum += burned;
            } else {
                black_burned_dice_sum += burned;
            }

            if (unused_dice_values.length > 0 && current_turn_record != null) {
                var skipped_str = string.joinv (", ", unused_dice_values);
                var skip_suffix = Localization.skipped_dice_status (skipped_str).strip ();
                current_turn_record.move_strings = ArrUtil.append_str (current_turn_record.move_strings, skip_suffix);
            }

            // 3. Перечёркиваем оставшиеся кубики на месте
            foreach (var d in current_turn_dice) {
                if (!d.is_used) {
                    d.is_skipped = true;
                }
            }
            if (current_turn_record != null) {
                current_turn_record.dice = TurnDie.clone_array (current_turn_dice);
            }
            notify_changed ();

            // 4. Даём время кубикам показаться перечёркнутыми на месте и перенестись в лог
            var flight_duration = checker_duration;
            var staggers = (double) current_turn_dice.length * 0.08;
            var total_wait = pause + flight_duration + staggers + 0.25;
            yield sleep_async (total_wait);
            if (g != gen) {
                return;
            }
        } else {
            // Все кубики были использованы для победы — ждем завершения анимации фишки и обычного перелета кубика в лог
            double die_landing_duration = 0.55;
            double wait_time = double.max (checker_duration, die_landing_duration);
            yield sleep_async (wait_time);
            if (g != gen) {
                return;
            }
        }

        // 5. Финализируем состояние лога и игры после приземления всех кубиков в слоты лога
        is_game_over = true;
        if (current_turn_record != null) {
            var record = current_turn_record;
            if (current_turn_dice.length > 0) {
                record.dice = TurnDie.clone_array (current_turn_dice);
            }
            insert_log_record (current_player, record);
        }
        current_turn_record = null;
        current_turn_dice = new TurnDie[0];

        // Сохраняем полный лог партии после добавления победного хода в историю
        save_game_log ();
        notify_changed ();

        // 6. Отдельная дополнительная пауза в 0.5 секунды:
        // Игрок видит финальное спокойное состояние доски и завершенный лог
        yield sleep_async (0.50);
        if (g != gen) {
            return;
        }

        // 7. Торжественное появление экрана победы со звуком
        SoundManager.shared ().play_victory ();
        showing_game_over_result = true;
        is_animating = false;
        notify_changed ();
    }

    // MARK: - Бросок кубиков (GameSession+RollDice)

    /** Основной метод броска кубиков. */
    public void roll_dice () {
        if (!can_roll) {
            return;
        }
        if (!is_first_move_rolloff_in_progress) {
            dice_roll = null;
        }
        int target_index;
        if (is_first_move_rolloff_in_progress) {
            target_index = (rolloff_active_player == CheckerColor.BLACK) ? 1 : 0;
        } else {
            target_index = -1;
        }

        is_rolling = true;
        rolling_die_index = target_index;
        is_animating = true;
        if (is_first_move_rolloff_in_progress) {
            status_message = is_computer_turn ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
        } else if (is_computer_turn) {
            status_message = Localization.status_computer_moving ();
        } else {
            status_message = "";
        }
        notify_changed ();

        roll_task.begin (gen);
    }

    private async void roll_task (uint g) {
        var anim = SettingsStore.shared ().animation_speed;
        var use_board_animation = SettingsStore.shared ().use_board_dice_animation;
        if (is_first_move_rolloff_in_progress) {
            if (use_board_animation) {
                yield handle_board_rolloff_phase (g);
            } else {
                SoundManager.shared ().play_dice_roll ();
                yield handle_rolloff_phase (anim, g);
            }
            return;
        }
        if (use_board_animation) {
            yield handle_board_normal_roll (g);
        } else {
            SoundManager.shared ().play_dice_roll ();
            yield handle_normal_roll (anim, g);
        }
    }

    private async bool animate_rolling (AnimationSpeed anim, uint g) {
        for (var i = 0; i < anim.dice_rolling_steps; i++) {
            rolling_dice_value1 = GLib.Random.int_range (1, 7);
            rolling_dice_value2 = GLib.Random.int_range (1, 7);
            notify_changed ();
            var progress = (double) i / (double) anim.dice_rolling_steps;
            yield sleep_async (anim.dice_rolling_step_delay * (0.5 + progress));
            if (g != gen) {
                return false;
            }
        }
        return true;
    }

    private async void handle_rolloff_phase (AnimationSpeed anim, uint g) {
        if (white_rolloff_dice == null) {
            yield rolloff_white (anim, g);
        } else if (black_rolloff_dice == null) {
            yield rolloff_black (anim, g);
        } else {
            var w_roll = white_rolloff_dice;
            var b_roll = black_rolloff_dice;
            var w_sum = w_roll.die1 + w_roll.die2;
            var b_sum = b_roll.die1 + b_roll.die2;
            if (w_sum == b_sum) {
                yield handle_rolloff_tie (w_roll, b_roll, g);
            } else {
                var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                yield handle_rolloff_win (winner, w_roll, b_roll, g);
            }
            if (g != gen) {
                return;
            }
            is_animating = false;
            notify_changed ();
            if (is_computer_turn) {
                auto_play_if_needed ();
            }
            return;
        }
        if (g != gen) {
            return;
        }
        if (white_rolloff_dice != null && black_rolloff_dice != null) {
            is_animating = false;
            notify_changed ();
        }
    }

    private async void rolloff_white (AnimationSpeed anim, uint g) {
        if (!(yield animate_rolling (anim, g))) {
            return;
        }
        var roll = DiceRoll.random ();
        white_rolloff_dice = roll;
        rolling_dice_value1 = roll.die1;
        rolling_dice_value2 = roll.die2;
        white_total_dice_sum += roll.die1 + roll.die2;
        is_rolling = false;
        rolling_die_index = 0;
        suppress_dice_cursor = true;
        is_animating = false;
        status_message = "";
        notify_changed ();

        yield sleep_async (0.75);
        if (g != gen) {
            return;
        }

        rolloff_active_player = CheckerColor.BLACK;

        if (is_black_computer) {
            status_message = Localization.status_rolloff_ai ();
            notify_changed ();
            yield sleep_async (0.60);
            if (g != gen) {
                return;
            }
            suppress_dice_cursor = false;
            roll_dice ();
        } else {
            status_message = Localization.status_rolloff_prompt ();
            suppress_dice_cursor = false;
            notify_changed ();
        }
    }

    private async void rolloff_black (AnimationSpeed anim, uint g) {
        if (!(yield animate_rolling (anim, g))) {
            return;
        }
        var roll = DiceRoll.random ();
        black_rolloff_dice = roll;
        rolling_dice_value1 = roll.die1;
        rolling_dice_value2 = roll.die2;
        black_total_dice_sum += roll.die1 + roll.die2;
        is_rolling = false;
        rolling_die_index = 1;
        notify_changed ();

        yield sleep_async (0.75);
        if (g != gen) {
            return;
        }

        var w_roll = white_rolloff_dice;
        var b_roll = black_rolloff_dice;
        if (w_roll == null || b_roll == null) {
            is_animating = false;
            notify_changed ();
            return;
        }
        var w_sum = w_roll.die1 + w_roll.die2;
        var b_sum = b_roll.die1 + b_roll.die2;

        if (w_sum == b_sum) {
            yield handle_rolloff_tie (w_roll, b_roll, g);
        } else {
            var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
            yield handle_rolloff_win (winner, w_roll, b_roll, g);
        }
        if (g != gen) {
            return;
        }
        is_animating = false;
        notify_changed ();
        if (is_computer_turn) {
            auto_play_if_needed ();
        }
    }

    private TurnRecord make_rolloff_record (DiceRoll roll, string text, bool winner, CheckerColor? winner_color) {
        var r = new TurnRecord.with_dice (0, new DiceRoll (roll.die1, roll.die2));
        r.is_rolloff = true;
        r.is_rolloff_winner = winner;
        r.rolloff_winner = winner_color;
        r.move_strings = new string[] { text };
        return r;
    }

    private async void handle_rolloff_tie (DiceRoll w_roll, DiceRoll b_roll, uint g) {
        rolloff_active_player = null;
        status_message = Localization.status_rolloff_tie ();
        var tie_label = Localization.status_rolloff_tie_label ();
        var is_already_logged = white_turn_log.length > 0 && black_turn_log.length > 0
            && white_turn_log[0].is_rolloff_tie ()
            && same_roll (white_turn_log[0].dice_roll, w_roll)
            && same_roll (black_turn_log[0].dice_roll, b_roll);
        if (!is_already_logged) {
            insert_log_record (CheckerColor.WHITE, make_rolloff_record (w_roll, tie_label, false, null));
            insert_log_record (CheckerColor.BLACK, make_rolloff_record (b_roll, tie_label, false, null));
        }

        rolloff_animation_id = ++rolloff_anim_counter;
        notify_changed ();

        yield sleep_async (1.2);
        if (g != gen) {
            return;
        }
        rolloff_active_player = CheckerColor.WHITE;
        suppress_dice_cursor = false;
        white_rolloff_dice = null;
        black_rolloff_dice = null;
        board_dice_state = null;
        rolloff_animation_id = 0;
        rolling_dice_value1 = 6;
        rolling_dice_value2 = 6;
        rolling_die_index = -1;
        status_message = Localization.status_rolloff_prompt ();
        notify_changed ();
    }

    private async void handle_rolloff_win (CheckerColor winner, DiceRoll w_roll, DiceRoll b_roll, uint g) {
        rolloff_active_player = winner;
        var result_msg = Localization.status_rolloff_result (player_name (winner));
        status_message = result_msg;
        var is_already_logged = white_turn_log.length > 0 && black_turn_log.length > 0
            && white_turn_log[0].is_rolloff && white_turn_log[0].rolloff_winner == winner
            && same_roll (white_turn_log[0].dice_roll, w_roll)
            && same_roll (black_turn_log[0].dice_roll, b_roll);
        if (!is_already_logged) {
            insert_log_record (CheckerColor.WHITE, make_rolloff_record (w_roll, result_msg, winner == CheckerColor.WHITE, winner));
            insert_log_record (CheckerColor.BLACK, make_rolloff_record (b_roll, result_msg, winner == CheckerColor.BLACK, winner));
        }

        rolloff_animation_id = ++rolloff_anim_counter;
        notify_changed ();

        yield sleep_async (1.2);
        if (g != gen) {
            return;
        }

        is_first_move_rolloff_in_progress = false;
        rolloff_active_player = null;
        suppress_dice_cursor = false;
        current_player = winner;
        white_rolloff_dice = null;
        black_rolloff_dice = null;
        board_dice_state = null;
        rolloff_animation_id = 0;
        dice_roll = null;
        remaining_dice = new int[0];
        rolling_die_index = -1;
        status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        notify_changed ();
    }

    public void apply_dice_roll (DiceRoll roll) {
        dice_roll = roll;
        is_rolling = false;
        rolling_dice_value1 = roll.die1;
        rolling_dice_value2 = roll.die2;

        var t_num = (current_player == CheckerColor.WHITE
            ? non_rolloff_count (white_turn_log)
            : non_rolloff_count (black_turn_log)) + 1;
        current_turn_record = new TurnRecord.with_dice (t_num, roll);

        var values = move_values (roll);
        if (current_player == CheckerColor.WHITE) {
            white_moves_count += 1;
            white_total_dice_sum += sum_ints (values);
            if (roll.is_double) {
                white_doubles_count += 1;
            }
        } else {
            black_moves_count += 1;
            black_total_dice_sum += sum_ints (values);
            if (roll.is_double) {
                black_doubles_count += 1;
            }
        }

        move_history = new MoveSnapshot[0];
        remaining_dice = values;
        var dice = new TurnDie[0];
        for (var i = 0; i < values.length; i++) {
            dice += new TurnDie (i, values[i]);
        }
        current_turn_dice = dice;
        double_division_progress = roll.is_double ? 0.0 : 1.0;
        current_turn_record.dice = TurnDie.clone_array (current_turn_dice);
        selected_point = null;
        checkers_moved_from_head_this_turn = 0;
    }

    private async void handle_board_rolloff_phase (uint g) {
        var duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 2.10 : 1.75;
        if (white_rolloff_dice == null) {
            yield rolloff_white_board (duration, g);
        } else if (black_rolloff_dice == null) {
            yield rolloff_black_board (duration, g);
        } else {
            var w_roll = white_rolloff_dice;
            var b_roll = black_rolloff_dice;
            var w_sum = w_roll.die1 + w_roll.die2;
            var b_sum = b_roll.die1 + b_roll.die2;
            if (w_sum == b_sum) {
                yield handle_rolloff_tie (w_roll, b_roll, g);
            } else {
                var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                yield handle_rolloff_win (winner, w_roll, b_roll, g);
            }
            is_animating = false;
            notify_changed ();
            if (is_computer_turn) {
                auto_play_if_needed ();
            }
        }
    }

    private async void rolloff_white_board (double duration, uint g) {
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (CheckerColor.WHITE, roll, duration);
        var state_id = state.id;
        board_dice_state = state;
        rolling_die_index = -1;
        notify_changed ();

        // 1. Ожидаем завершения физического броска на доске
        yield sleep_async (duration);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 2. Пауза в покое на доске (0.70 с)
        yield sleep_async (0.70);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 3. Быстрый перенос кубиков точно в слоты панели (0.38 с)
        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state.is_transferring = true;
            board_dice_state.transfer_start_time_us = GLib.get_monotonic_time ();
            notify_changed ();
        }
        yield sleep_async (0.38);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state = null;
        }
        white_rolloff_dice = roll;
        rolling_dice_value1 = roll.die1;
        rolling_dice_value2 = roll.die2;
        white_total_dice_sum += roll.die1 + roll.die2;
        is_rolling = false;
        rolling_die_index = 0;
        suppress_dice_cursor = true;
        is_animating = false;
        status_message = "";
        notify_changed ();

        // Пауза фиксации кубиков в панели белого игрока перед переходом хода
        yield sleep_async (0.75);
        if (g != gen) {
            return;
        }

        rolloff_active_player = CheckerColor.BLACK;

        if (is_black_computer) {
            status_message = Localization.status_rolloff_ai ();
            notify_changed ();
            yield sleep_async (0.60);
            if (g != gen) {
                return;
            }
            suppress_dice_cursor = false;
            roll_dice ();
        } else {
            status_message = Localization.status_rolloff_prompt ();
            suppress_dice_cursor = false;
            notify_changed ();
        }
    }

    private async void rolloff_black_board (double duration, uint g) {
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (CheckerColor.BLACK, roll, duration);
        var state_id = state.id;
        board_dice_state = state;
        rolling_die_index = -1;
        notify_changed ();

        // 1. Ожидаем завершения физического броска на доске
        yield sleep_async (duration);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 2. Пауза в покое на доске (0.70 с)
        yield sleep_async (0.70);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 3. Быстрый перенос кубиков точно в слоты панели (0.38 с)
        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state.is_transferring = true;
            board_dice_state.transfer_start_time_us = GLib.get_monotonic_time ();
            notify_changed ();
        }
        yield sleep_async (0.38);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state = null;
        }
        black_rolloff_dice = roll;
        rolling_dice_value1 = roll.die1;
        rolling_dice_value2 = roll.die2;
        black_total_dice_sum += roll.die1 + roll.die2;
        is_rolling = false;
        rolling_die_index = 1;
        notify_changed ();

        // Пауза фиксации кубиков в панели чёрного игрока
        yield sleep_async (0.75);
        if (g != gen) {
            return;
        }

        var w_roll = white_rolloff_dice;
        var b_roll = black_rolloff_dice;
        if (w_roll == null || b_roll == null) {
            is_animating = false;
            notify_changed ();
            return;
        }

        var w_sum = w_roll.die1 + w_roll.die2;
        var b_sum = b_roll.die1 + b_roll.die2;

        if (w_sum == b_sum) {
            yield handle_rolloff_tie (w_roll, b_roll, g);
        } else {
            var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
            yield handle_rolloff_win (winner, w_roll, b_roll, g);
        }
        if (g != gen) {
            return;
        }
        is_animating = false;
        notify_changed ();
        if (is_computer_turn) {
            auto_play_if_needed ();
        }
    }

    private async void handle_board_normal_roll (uint g) {
        var is_comp = is_computer_turn;
        rolling_die_index = -1;
        if (is_comp) {
            status_message = Localization.status_computer_moving ();
        }
        var duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 2.10 : 1.75;
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (current_player, roll, duration);
        var state_id = state.id;
        board_dice_state = state;
        notify_changed ();

        // 1. Ожидаем завершения физического броска на доске (звук удара t = 0.35 воспроизводится в BoardView)
        yield sleep_async (duration);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        var rolling_player = current_player;

        // 2. Пауза в покое на доске (0.70 с) — кубики застывают на доске
        yield sleep_async (0.70);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 3. Быстрый перенос кубиков точно в слоты панели (0.38 с)
        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state.is_transferring = true;
            board_dice_state.transfer_start_time_us = GLib.get_monotonic_time ();
            notify_changed ();
        }
        yield sleep_async (0.38);
        if (g != gen) {
            if (board_dice_state != null && board_dice_state.id == state_id) {
                board_dice_state = null;
            }
            return;
        }

        // 4. Очищаем доску и включаем кубики в панели управления
        if (board_dice_state != null && board_dice_state.id == state_id) {
            board_dice_state = null;
        }
        apply_dice_roll (roll);
        update_available_moves_cache ();
        notify_changed ();

        if (current_player == rolling_player && is_game_started && !is_game_over) {
            if (roll.is_double) {
                yield handle_double_animation (g);
                if (g != gen) {
                    return;
                }
            }
        }

        if (current_player != rolling_player || !is_game_started || is_game_over) {
            return;
        }

        if (!is_comp) {
            status_message = Localization.status_select_checker ();
            is_animating = false;
            notify_changed ();
        }

        var has_playable = false;
        foreach (var o in cached_legal_options) {
            if (!o.is_illegal_prime) {
                has_playable = true;
                break;
            }
        }
        var initial_dice_count = move_values (roll).length;
        if (!has_playable && remaining_dice.length == initial_dice_count) {
            notify_changed ();
            yield handle_no_moves (roll, g);
            return;
        }

        if (is_comp) {
            is_animating = false;
            notify_changed ();
            if (is_computer_turn) {
                status_message = Localization.status_computer_moving ();
                notify_changed ();
                yield perform_computer_turn (g);
            }
        }
    }

    private async void handle_normal_roll (AnimationSpeed anim, uint g) {
        rolling_die_index = -1;
        if (is_computer_turn) {
            status_message = Localization.status_computer_moving ();
        }
        if (!(yield animate_rolling (anim, g))) {
            return;
        }

        var roll = DiceRoll.random ();
        var rolling_player = current_player;
        apply_dice_roll (roll);
        update_available_moves_cache ();
        notify_changed ();

        if (roll.is_double) {
            yield handle_double_animation (g);
            if (g != gen) {
                return;
            }
        }

        if (current_player != rolling_player || !is_game_started || is_game_over) {
            return;
        }

        if (!is_computer_turn) {
            status_message = Localization.status_select_checker ();
            is_animating = false;
            notify_changed ();
        }

        var has_playable = false;
        foreach (var o in cached_legal_options) {
            if (!o.is_illegal_prime) {
                has_playable = true;
                break;
            }
        }
        var initial_dice_count = move_values (roll).length;
        if (!has_playable && remaining_dice.length == initial_dice_count) {
            notify_changed ();
            yield handle_no_moves (roll, g);
            return;
        }

        is_animating = false;
        notify_changed ();
        if (is_computer_turn) {
            status_message = Localization.status_computer_moving ();
            notify_changed ();
            yield perform_computer_turn (g);
        }
    }

    private async void handle_double_animation (uint g) {
        var rolling_player = current_player;
        is_doubling = true;
        notify_changed ();

        // Задержка 350 мс перед началом раскрытия костей на доске
        yield sleep_async (0.35);
        if (g != gen || !is_game_in_progress || current_player != rolling_player) {
            is_doubling = false;
            is_dice_flash_active = false;
            dice_flash_opacity = 0.0;
            double_division_progress = 1.0;
            notify_changed ();
            return;
        }

        // Spring(response: 0.50, dampingFraction: 0.65) раскладывает их в сетку 2x2.
        is_dice_flash_active = true;
        dice_flash_opacity = 0.0;
        var started_us = GLib.get_monotonic_time ();
        const double response = 0.50;
        const double damping = 0.65;
        var omega = 2.0 * Math.PI / response;
        var damped_omega = omega * Math.sqrt (1.0 - damping * damping);
        while (true) {
            var elapsed = (GLib.get_monotonic_time () - started_us) / 1000000.0;
            var spring_t = double.min (response, elapsed);
            var progress = 1.0 - Math.exp (-damping * omega * spring_t) *
                (Math.cos (damped_omega * spring_t) + damping * omega / damped_omega * Math.sin (damped_omega * spring_t));
            double_division_progress = double.min (1.08, double.max (0.0, progress));
            if (elapsed < 0.12) {
                var flash_t = elapsed / 0.12;
                dice_flash_opacity = flash_t * flash_t * flash_t;
            } else if (elapsed < 0.53) {
                var flash_t = (elapsed - 0.18) / 0.35;
                flash_t = double.max (0.0, double.min (1.0, flash_t));
                dice_flash_opacity = 1.0 - (1.0 - flash_t) * (1.0 - flash_t) * (1.0 - flash_t);
            } else {
                dice_flash_opacity = 0.0;
            }
            is_dice_flash_active = dice_flash_opacity > 0.0;
            if (elapsed >= response) {
                double_division_progress = 1.0;
            }
            notify_changed ();
            if (elapsed >= 0.53) {
                break;
            }
            yield sleep_async (0.016);
            if (g != gen || !is_game_in_progress || current_player != rolling_player) {
                is_doubling = false;
                is_dice_flash_active = false;
                dice_flash_opacity = 0.0;
                double_division_progress = 1.0;
                notify_changed ();
                return;
            }
        }
        is_dice_flash_active = false;
        dice_flash_opacity = 0.0;
        double_division_progress = 1.0;
        notify_changed ();

        // Фиксация раскрытых костей на экране перед передачей управления ходом
        yield sleep_async (0.22);
        is_doubling = false;
        if (g != gen || !is_game_in_progress || current_player != rolling_player) {
            notify_changed ();
            return;
        }
        if (is_computer_turn) {
            status_message = Localization.status_computer_moving ();
        }
        notify_changed ();
    }

    private async void handle_no_moves (DiceRoll roll, uint g) {
        board_dice_state = null;
        is_animating = true;
        status_message = Localization.no_available_moves ();
        notify_changed ();

        var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        yield sleep_async (pause);
        if (g != gen) {
            return;
        }

        var burned = sum_ints (remaining_dice);
        if (current_player == CheckerColor.WHITE) {
            white_burned_dice_sum += burned;
        } else {
            black_burned_dice_sum += burned;
        }

        var skipped_str = current_dice_string ();

        foreach (var d in current_turn_dice) {
            if (!d.is_used) {
                d.is_skipped = true;
            }
        }
        if (current_turn_record != null) {
            current_turn_record.dice = TurnDie.clone_array (current_turn_dice);
        }
        remaining_dice = new int[0];
        if (current_turn_record != null) {
            current_turn_record.move_strings = ArrUtil.append_str (
                current_turn_record.move_strings, Localization.skipped_dice_status (skipped_str));
        }
        notify_changed ();

        var animation = SettingsStore.shared ().animation_speed;
        var transfer_wait = pause + animation.checker_move_duration + current_turn_dice.length * 0.08 + 0.25;
        yield sleep_async (transfer_wait);
        if (g != gen) {
            return;
        }
        trigger_auto_end_turn (0.1, roll);
    }

    /** Автобросок компьютера после задержки. */
    public void auto_play_if_needed () {
        if (!is_computer_turn || !can_roll) {
            return;
        }
        is_auto_playing_black = true;
        var g = gen;
        var delay = SettingsStore.shared ().computer_delay.before_roll_delay;
        after (delay, () => {
            if (g != gen) {
                return;
            }
            if (!is_computer_turn || !can_roll) {
                is_auto_playing_black = false;
                return;
            }
            roll_dice ();
        });
    }

    // MARK: - Ход компьютера (GameSession+Computer)

    /** Полный цикл хода компьютера. */
    public async void perform_computer_turn (uint g) {
        is_animating = true;
        notify_changed ();

        var before_delay = SettingsStore.shared ().computer_delay.before_roll_delay;
        yield sleep_async (before_delay);
        if (g != gen) {
            return;
        }
        status_message = Localization.status_computer_moving ();
        notify_changed ();

        var max_iterations = 20;
        while (remaining_dice.length > 0 && !is_game_over && !board.is_winner (current_player) && max_iterations > 0) {
            max_iterations--;
            if (g != gen) {
                return;
            }
            MoveOption? move = null;
            if (SettingsStore.shared ().ai_difficulty == AIDifficulty.MASTER) {
                move = AdvancedAI.choose_move (cached_legal_options, board, current_player, remaining_dice);
            } else {
                move = ComputerAI.choose_move (cached_legal_options, board, current_player, remaining_dice);
            }
            if (move == null) {
                break;
            }

            var show_path = SettingsStore.shared ().show_path_computer;
            if (show_path && move.is_combined) {
                if (yield apply_computer_combined_move (move, g)) {
                    if (g != gen) {
                        return;
                    }
                    continue;
                }
            }

            apply (move);
            if (board.is_winner (current_player)) {
                return;
            }
            notify_changed ();
            var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
            var between = SettingsStore.shared ().computer_delay.between_moves_delay;
            yield sleep_async (duration + between);
            if (g != gen) {
                return;
            }
        }

        is_auto_playing_black = false;
        if (!is_game_over && !board.is_winner (current_player)) {
            check_and_auto_end_turn ();
        } else {
            is_animating = false;
        }
        notify_changed ();
    }

    private async bool apply_computer_combined_move (MoveOption move, uint g) {
        var steps = intermediate_steps (move);
        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < remaining_dice.length) {
                dice_values += remaining_dice[idx];
            }
        }
        if (steps.length < 2 || steps.length != dice_values.length) {
            return false;
        }
        var is_head_move = MoveValidator.is_head (move.from, current_player);
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var intermediate_delay = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        var between = SettingsStore.shared ().computer_delay.between_moves_delay;

        record_move_in_log (move, steps);

        for (var i = 0; i < steps.length - 1; i++) {
            board.move_one_checker (steps[i].from, steps[i].to);
            remove_die_by_value (dice_values[i]);
            SoundManager.shared ().play_checker_move ();
            notify_changed ();
            yield sleep_async (duration + intermediate_delay);
            if (g != gen) {
                return true;
            }
        }

        var last = steps[steps.length - 1];
        board.move_one_checker (last.from, last.to);
        remove_die_by_value (dice_values[dice_values.length - 1]);
        SoundManager.shared ().play_checker_move ();
        notify_changed ();
        yield sleep_async (duration);

        if (g != gen) {
            return true;
        }

        if (board.is_winner (current_player)) {
            handle_delayed_victory ();
            return true;
        }
        if (is_head_move) {
            checkers_moved_from_head_this_turn += 1;
        }
        selected_point = null;
        update_available_moves_cache ();
        notify_changed ();

        yield sleep_async (between);
        return true;
    }

    /** Проверяет после хода, нужно ли автоматически завершить ход. */
    public void check_and_auto_end_turn () {
        update_available_moves_cache ();

        if (remaining_dice.length == 0) {
            move_history = new MoveSnapshot[0];
            is_animating = true;
            var delay = is_computer_turn
                ? SettingsStore.shared ().computer_delay.auto_end_turn_delay
                : (double.max (SettingsStore.shared ().animation_speed.checker_move_duration, 0.55) + SettingsStore.shared ().computer_delay.auto_end_turn_delay);
            trigger_auto_end_turn (delay, dice_roll);
            notify_changed ();
            return;
        }

        var has_playable = false;
        foreach (var o in cached_legal_options) {
            if (!o.is_illegal_prime) {
                has_playable = true;
                break;
            }
        }

        if (!has_playable) {
            move_history = new MoveSnapshot[0];
            status_message = Localization.no_available_moves ();
            is_animating = true;
            notify_changed ();
            no_moves_after_move_task.begin (gen);
        } else {
            status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_select_checker ();
            notify_changed ();
        }
    }

    private async void no_moves_after_move_task (uint g) {
        var animation = SettingsStore.shared ().animation_speed;
        var has_used_die = false;
        foreach (var d in current_turn_dice) {
            if (d.is_used) {
                has_used_die = true;
                break;
            }
        }
        if (!is_computer_turn && has_used_die) {
            yield sleep_async (animation.checker_move_duration);
            if (g != gen) {
                return;
            }
        }
        var pause = animation.intermediate_step_delay;
        yield sleep_async (pause);
        if (g != gen) {
            return;
        }
        if (remaining_dice.length > 0) {
            var burned = sum_ints (remaining_dice);
            if (current_player == CheckerColor.WHITE) {
                white_burned_dice_sum += burned;
            } else {
                black_burned_dice_sum += burned;
            }
            if (current_turn_record != null) {
                var skip_suffix = Localization.skipped_dice_status (current_dice_string ()).strip ();
                current_turn_record.move_strings = ArrUtil.append_str (current_turn_record.move_strings, skip_suffix);
            }
        }
        foreach (var d in current_turn_dice) {
            if (!d.is_used) {
                d.is_skipped = true;
            }
        }
        if (current_turn_record != null) {
            current_turn_record.dice = TurnDie.clone_array (current_turn_dice);
        }
        remaining_dice = new int[0];
        notify_changed ();

        var transfer_wait = pause + animation.checker_move_duration + current_turn_dice.length * 0.08 + 0.25;
        yield sleep_async (transfer_wait);
        if (g != gen) {
            return;
        }
        trigger_auto_end_turn (0.1, dice_roll);
    }

    /** Отложенное завершение хода. Проверяет, что состояние игры не изменилось за время ожидания. */
    public void trigger_auto_end_turn (double delay, DiceRoll? current_roll) {
        var player_at_trigger = current_player;
        var token = ++auto_end_token;
        var g = gen;
        Timeout.add ((uint) (delay * 1000.0), () => {
            if (token != auto_end_token || g != gen) {
                return Source.REMOVE;
            }
            if (!is_game_over && current_player == player_at_trigger
                && (current_roll == null || same_roll (dice_roll, current_roll))) {
                is_animating = false;
                end_turn ();
            }
            return Source.REMOVE;
        });
    }

    // MARK: - Логика ходов игрока (GameSession+Moves)

    /** Применяет одиночный ход: перемещает фишку, записывает в лог, обновляет кэш. */
    public void apply (MoveOption move, bool is_dragged = false) {
        board.move_one_checker (move.from, move.to);
        record_move_in_log (move, new IntermediateStep[0]);

        if (MoveValidator.is_head (move.from, current_player)) {
            checkers_moved_from_head_this_turn += 1;
        }
        remove_used_dice (move.die_indices);
        SoundManager.shared ().play_checker_move ();

        if (board.is_winner (current_player)) {
            handle_delayed_victory ();
            return;
        }
        update_available_moves_cache ();
    }

    /** Разбивает составной ход на промежуточные шаги (по одному кубику). */
    public IntermediateStep[] intermediate_steps (MoveOption move) {
        if (!move.is_combined || move.die_indices.length < 2) {
            return new IntermediateStep[0];
        }
        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < remaining_dice.length) {
                dice_values += remaining_dice[idx];
            }
        }
        if (dice_values.length < 2) {
            return new IntermediateStep[0];
        }

        var steps = new IntermediateStep[0];
        BoardPoint current = move.from;
        for (var i = 0; i < dice_values.length; i++) {
            var next = PlayerPath.point_from (current, dice_values[i], current_player);
            if (next != null) {
                if (MoveValidator.is_blocked (next, board, current_player)) {
                    return new IntermediateStep[0];
                }
                steps += new IntermediateStep (current, next);
                current = next;
            } else {
                if (i == dice_values.length - 1) {
                    steps += new IntermediateStep (current, null);
                }
                break;
            }
        }
        return steps;
    }

    /** Завершится ли ход игрока после указанного перемещения. */
    public bool will_turn_end_after (MoveOption move) {
        var temp_board = board.clone ();
        var steps = move.is_combined ? intermediate_steps (move) : new IntermediateStep[0];
        if (move.is_combined && steps.length > 0) {
            foreach (var s in steps) {
                temp_board.move_one_checker (s.from, s.to);
            }
        } else {
            temp_board.move_one_checker (move.from, move.to);
        }

        var temp_dice = copy_int_array (remaining_dice);
        foreach (var index in sorted_desc (move.die_indices)) {
            if (index < temp_dice.length) {
                temp_dice = remove_at (temp_dice, index);
            }
        }
        if (temp_dice.length == 0) {
            return true;
        }

        var next_head = checkers_moved_from_head_this_turn + (MoveValidator.is_head (move.from, current_player) ? 1 : 0);
        var is_first_turn = (current_player == CheckerColor.WHITE) ? is_white_first_turn : is_black_first_turn;
        var all = MoveValidator.all_moves (temp_board, current_player, temp_dice, next_head,
                                           dice_roll != null && dice_roll.is_double, is_first_turn);
        foreach (var o in MoveValidator.filter_legal_moves (
            all, temp_board, current_player, temp_dice, next_head,
            dice_roll != null && dice_roll.is_double, is_first_turn)) {
            if (!o.is_illegal_prime) {
                return false;
            }
        }
        return true;
    }

    /**
     * Обрабатывает клик игрока по ячейке доски:
     * - Повторный клик по выбранной фишке — быстрый ход.
     * - Клик по цели выбранной фишки — перемещение (в т.ч. на свои фишки).
     * - Своя фишка — выбор; чужая/пустая — сброс выбора.
     */
    public void select (BoardPoint point) {
        if (remaining_dice.length == 0 || is_animating) {
            return;
        }
        if (selected_point != null && selected_point == point) {
            quick_move (point);
            return;
        }
        if (selected_point != null && contains_point (target_points (), point)) {
            apply_move (point, selected_point);
            return;
        }

        var stack = board.stack_at (point);
        if (stack == null || stack.color != current_player) {
            set_selected_point (null);
            status_message = Localization.status_select_checker ();
            notify_changed ();
            return;
        }

        selected_point = point;
        if (options_from (point).length == 0) {
            var is_head = MoveValidator.is_head (point, current_player);
            var is_first_turn = (current_player == CheckerColor.WHITE) ? is_white_first_turn : is_black_first_turn;
            var is_double = dice_roll != null && dice_roll.is_double;
            var first_die = remaining_dice.length > 0 ? remaining_dice[0] : 0;
            var max_head = 1;
            if (is_double && is_first_turn && (first_die == 3 || first_die == 4 || first_die == 6)) {
                max_head = 2;
            }
            if (is_head && checkers_moved_from_head_this_turn >= max_head) {
                status_message = Localization.status_head_limit_reached ();
            } else {
                var is_blocked_by_opponent = false;
                foreach (var die in remaining_dice) {
                    var target = PlayerPath.point_from (point, die, current_player);
                    if (target != null && MoveValidator.is_blocked (target, board, current_player)) {
                        is_blocked_by_opponent = true;
                        break;
                    }
                }
                status_message = is_blocked_by_opponent
                    ? Localization.status_move_blocked_by_opponent ()
                    : Localization.no_available_moves ();
            }
        } else {
            status_message = Localization.status_select_target ();
        }
        notify_changed ();
    }

    /** Быстрый ход (двойной клик): вынос за борт или ближайшая точка. */
    public void quick_move (BoardPoint point) {
        if (remaining_dice.length == 0 || is_animating || is_game_over) {
            return;
        }
        var available = new MoveOption[0];
        foreach (var o in options_from (point)) {
            if (!o.is_illegal_prime) {
                available += o;
            }
        }
        if (available.length == 0) {
            return;
        }
        foreach (var o in available) {
            if (o.to == null) {
                selected_point = point;
                bear_off_selected ();
                return;
            }
        }
        MoveOption? nearest = null;
        foreach (var o in available) {
            if (nearest == null || o.die < nearest.die) {
                nearest = o;
            }
        }
        if (nearest != null && nearest.to != null) {
            apply_move (nearest.to, point);
        }
    }

    /** Основной метод перемещения фишки from → to. */
    public void apply_move (BoardPoint to, BoardPoint from, bool is_dragged = false) {
        if (is_computer_turn || is_animating) {
            return;
        }

        MoveOption? move = null;
        foreach (var o in options_from (from)) {
            if (o.to != null && o.to == to && !o.is_illegal_prime) {
                move = o;
                break;
            }
        }
        if (move == null) {
            return;
        }

        var is_turn_ending = will_turn_end_after (move);
        save_snapshot ();

        is_animating = true;
        selected_point = null;

        if (!is_computer_turn) {
            status_message = is_turn_ending ? "" : Localization.status_select_checker ();
        }

        var show_path = SettingsStore.shared ().show_path_player;
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;

        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < remaining_dice.length) {
                dice_values += remaining_dice[idx];
            }
        }

        if (show_path && move.is_combined && !is_dragged) {
            animate_combined_move.begin (move, (owned) dice_values, true, gen);
            return;
        }

        record_move_in_log (move, new IntermediateStep[0]);

        board.move_one_checker (from, to);
        if (MoveValidator.is_head (from, current_player)) {
            checkers_moved_from_head_this_turn += 1;
        }
        remove_used_dice (move.die_indices);
        SoundManager.shared ().play_checker_move ();

        if (board.is_winner (current_player)) {
            handle_delayed_victory ();
            return;
        }

        update_available_moves_cache ();
        check_and_auto_end_turn ();
        notify_changed ();

        if (!is_turn_ending) {
            after (duration, () => {
                is_animating = false;
                notify_changed ();
            });
        }
    }

    /**
     * Поэтапная анимация составного хода (и составного выноса за борт).
     * record_steps = true — запись в лог с промежуточными шагами.
     */
    private async void animate_combined_move (MoveOption move, owned int[] dice_values, bool record_steps, uint g) {
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var intermediate_delay = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        var steps = intermediate_steps (move);

        if (steps.length < 2 || steps.length != dice_values.length) {
            apply (move);
            if (board.is_winner (current_player)) {
                return;
            }
            check_and_auto_end_turn ();
            is_animating = false;
            notify_changed ();
            return;
        }

        var is_head_move = MoveValidator.is_head (move.from, current_player);
        if (record_steps) {
            record_move_in_log (move, steps);
        }

        for (var i = 0; i < steps.length - 1; i++) {
            board.move_one_checker (steps[i].from, steps[i].to);
            remove_die_by_value (dice_values[i]);
            SoundManager.shared ().play_checker_move ();
            notify_changed ();
            yield sleep_async (duration + intermediate_delay);
            if (g != gen) {
                return;
            }
        }

        var last = steps[steps.length - 1];
        board.move_one_checker (last.from, last.to);
        remove_die_by_value (dice_values[dice_values.length - 1]);
        SoundManager.shared ().play_checker_move ();
        notify_changed ();
        yield sleep_async (duration);

        if (g != gen) {
            return;
        }


        if (board.is_winner (current_player)) {
            handle_delayed_victory ();
            return;
        }
        if (is_head_move) {
            checkers_moved_from_head_this_turn += 1;
        }
        selected_point = null;
        update_available_moves_cache ();
        check_and_auto_end_turn ();
        is_animating = false;
        notify_changed ();
    }

    /** Вынос выбранной фишки за борт. */
    public void bear_off_selected (bool is_dragged = false) {
        if (is_animating || selected_point == null || !can_bear_off_selected) {
            return;
        }
        var from = selected_point;
        MoveOption? move = null;
        foreach (var o in options_from (from)) {
            if (o.to == null && !o.is_illegal_prime) {
                move = o;
                break;
            }
        }
        if (move == null) {
            return;
        }

        var is_turn_ending = will_turn_end_after (move);
        save_snapshot ();

        is_animating = true;
        selected_point = null;

        if (!is_computer_turn) {
            status_message = is_turn_ending ? "" : Localization.status_select_checker ();
        }

        var show_path = SettingsStore.shared ().show_path_player;
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;

        if (show_path && move.is_combined && !is_dragged) {
            var dice_values = new int[0];
            foreach (var idx in move.die_indices) {
                if (idx < remaining_dice.length) {
                    dice_values += remaining_dice[idx];
                }
            }
            animate_combined_move.begin (move, (owned) dice_values, true, gen);
            return;
        }

        apply (move, is_dragged);
        if (board.is_winner (current_player)) {
            return;
        }
        check_and_auto_end_turn ();
        notify_changed ();

        if (!is_turn_ending) {
            after (duration, () => {
                is_animating = false;
                notify_changed ();
            });
        }
    }

    /** Сохраняет снимок состояния для отмены хода (только для игрока). */
    public void save_snapshot () {
        if (is_computer_turn) {
            return;
        }
        move_history += new MoveSnapshot (
            board.clone (),
            copy_int_array (remaining_dice),
            checkers_moved_from_head_this_turn,
            status_message,
            current_turn_record,
            current_turn_dice);
    }

    // MARK: - Отмена хода (GameSession+Undo)

    public void undo_move () {
        if (is_animating || move_history.length == 0 || is_game_over) {
            return;
        }
        SoundManager.shared ().play_undo ();

        var last = move_history[move_history.length - 1];
        var new_history = new MoveSnapshot[0];
        for (var i = 0; i < move_history.length - 1; i++) {
            new_history += move_history[i];
        }
        move_history = new_history;

        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        is_animating = true;

        // Находим одиночную фишку, совершающую обратный полёт при отмене шага;
        // остальные перемещения восстанавливаются мгновенно из снимка.
        undo_flight_checker_id = find_reverse_undo_checker (board, last.board, current_player);
        is_undoing_move = undo_flight_checker_id >= 0;

        board = last.board.clone ();
        remaining_dice = copy_int_array (last.remaining_dice);
        current_turn_dice = TurnDie.clone_array (last.current_turn_dice);
        checkers_moved_from_head_this_turn = last.head_count;
        status_message = last.status;
        current_turn_record = last.current_turn_record == null ? null : last.current_turn_record.clone ();
        selected_point = null;
        update_available_moves_cache ();
        notify_changed ();

        var undo_generation = gen;
        after (duration, () => {
            if (undo_generation != gen) {
                return;
            }
            is_undoing_move = false;
            undo_flight_checker_id = -1;
            is_animating = false;
            notify_changed ();
        });
    }

    private static int undo_stack_count (GameBoard board, BoardPoint point) {
        var stack = board.stack_at (point);
        return stack != null ? stack.checker_ids.length : 0;
    }

    private static int find_reverse_undo_checker (GameBoard current, GameBoard target, CheckerColor preferred) {
        CheckerColor[] colors = { preferred, preferred == CheckerColor.WHITE ? CheckerColor.BLACK : CheckerColor.WHITE };
        foreach (var color in colors) {
            var current_off = color == CheckerColor.WHITE ? current.white_borne_off_ids : current.black_borne_off_ids;
            var target_off = color == CheckerColor.WHITE ? target.white_borne_off_ids : target.black_borne_off_ids;
            if (current_off.length > target_off.length && current_off.length > 0) {
                for (var raw = 1; raw <= 24; raw++) {
                    var point = (BoardPoint) raw;
                    if (undo_stack_count (target, point) > undo_stack_count (current, point)) {
                        return (int) current_off[current_off.length - 1];
                    }
                }
            }
        }

        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            if (undo_stack_count (current, point) <= undo_stack_count (target, point)) {
                continue;
            }
            var stack = current.stack_at (point);
            if (stack != null && stack.checker_ids.length > 0) {
                return (int) stack.checker_ids[stack.checker_ids.length - 1];
            }
        }
        return -1;
    }

    // MARK: - Генерация текста лога партии

    /** Имя игрока на английском для логов (GameLogStore). */
    public string english_player_name (CheckerColor color) {
        var store = SettingsStore.shared ();
        if (color == CheckerColor.WHITE) {
            var trimmed = store.white_player_name.strip ();
            if (trimmed != "") {
                return trimmed;
            }
            return store.opponent == Opponent.COMPUTER ? "Player" : "Player 1";
        }
        if (store.opponent == Opponent.COMPUTER) {
            return "Computer";
        }
        var trimmed = store.black_player_name.strip ();
        return trimmed == "" ? "Player 2" : trimmed;
    }

    /** Текстовый дамп состояния на английском (для GameLogStore). */
    public string generate_log_text () {
        var b = new StringBuilder ();
        b.append ("--- LONG BACKGAMMON DEBUG ---\n");
        b.append ("Turn: %s\n".printf (english_player_name (current_player)));
        b.append ("Pips: W:%d B:%d\n".printf (white_pip_count, black_pip_count));
        b.append ("\n--- BOARD STACKS ---\n");
        append_board (b);
        b.append ("\n--- WHITE LOG ---\n");
        append_log_english (b, white_turn_log, CheckerColor.WHITE);
        b.append ("\n--- BLACK LOG ---\n");
        append_log_english (b, black_turn_log, CheckerColor.BLACK);
        b.append ("\n--- SETTINGS ---\n");
        b.append ("Game Speed: %s\n".printf (SettingsStore.shared ().game_speed == GameSpeed.FAST ? "Fast" : "Slow"));
        return b.str;
    }

    private void append_board (StringBuilder b) {
        for (var raw = 1; raw <= 24; raw++) {
            var stack = board.stack_at ((BoardPoint) raw);
            if (stack != null) {
                b.append ("%d:%s%d ".printf (raw, stack.color == CheckerColor.WHITE ? "W" : "B", stack.checker_ids.length));
            }
        }
    }

    private void append_log_english (StringBuilder b, TurnRecord[] log, CheckerColor color = CheckerColor.WHITE) {
        foreach (var record in log) {
            b.append ("%d. [%d:%d] ".printf (record.turn_number, record.dice_roll.die1, record.dice_roll.die2));
            var moves = record.export_moves_string (color, this, true);
            b.append (moves == "" ? "NONE" : moves).append_c ('\n');
        }
    }

    /** Сохраняет лог завершённой партии в GameLogStore. */
    public void save_game_log () {
        var text = generate_log_text ();
        if (SettingsStore.shared ().opponent == Opponent.COMPUTER) {
            GameLogStore.shared ().add_entry (white_player_name, "Computer", text);
        } else {
            GameLogStore.shared ().add_entry (white_player_name, black_player_name, text);
        }
    }

    /** Локализованный дамп состояния (для копирования в буфер обмена). */
    public string debug_export_text () {
        var b = new StringBuilder ();
        b.append (Localization.debug_export_title ()).append_c ('\n');
        b.append (Localization.debug_export_turn ()).append (" ").append (player_name (current_player)).append_c ('\n');
        b.append (Localization.debug_export_pips ()).append (" W:%d B:%d\n".printf (white_pip_count, black_pip_count));
        b.append ("\n").append (Localization.debug_export_board ()).append_c ('\n');
        append_board (b);
        b.append ("\n\n").append (Localization.debug_export_white_log ()).append_c ('\n');
        append_log_localized (b, white_turn_log, CheckerColor.WHITE);
        b.append ("\n").append (Localization.debug_export_black_log ()).append_c ('\n');
        append_log_localized (b, black_turn_log, CheckerColor.BLACK);
        b.append ("\n").append (Localization.debug_export_settings ()).append_c ('\n');
        b.append (Localization.settings_speed_label ()).append (": ")
         .append (SettingsStore.shared ().game_speed == GameSpeed.FAST
                  ? Localization.settings_speed_fast () : Localization.settings_speed_slow ())
         .append_c ('\n');
        return b.str;
    }

    private void append_log_localized (StringBuilder b, TurnRecord[] log, CheckerColor color = CheckerColor.WHITE) {
        foreach (var record in log) {
            b.append ("%d. [%d:%d] ".printf (record.turn_number, record.dice_roll.die1, record.dice_roll.die2));
            var moves = record.export_moves_string (color, this, false);
            b.append (moves == "" ? Localization.debug_export_none () : moves);
            b.append_c ('\n');
        }
    }

    /** После копирования отладочной информации — временное сообщение в статусе (2 с). */
    public void show_debug_copied_status () {
        var old_status = status_message;
        status_message = Localization.debug_export_success_prefix () + Localization.debug_export_success ();
        notify_changed ();
        after (2.0, () => {
            status_message = old_status;
            notify_changed ();
        });
    }

    // MARK: - Сохранение и форфейт при закрытии

    public void save_on_close () {
        if (is_game_in_progress) {
            save_to_store ();
        } else if (!SavedGameStore.shared ().has_saved_game) {
            SavedGameStore.shared ().clear ();
        }
    }

    /** Завершает текущую игру форфейтом: текущий игрок проигрывает. */
    public void forfeit_current_game () {
        if (!is_game_started || is_game_over) {
            return;
        }
        var loser_color = current_player;
        var loser_name = player_name (loser_color);
        if (!is_computer_player (loser_color)) {
            StatsStore.shared ().record_loss (loser_name);
        }
        var winner_color = loser_color.opposite ();
        if (!is_computer_player (winner_color)) {
            StatsStore.shared ().record_victory (player_name (winner_color), VictoryType.OIN);
        }
        SavedGameStore.shared ().clear ();
        force_new_game ();
    }

    /** Сохраняет текущее состояние игры в SavedGameStore. */
    public void save_to_store () {
        var data = new SavedGameData ();
        data.stacks = SavedGameStore.stacks_from_board (board);
        data.white_borne_off_ids = copy_uint8 (board.white_borne_off_ids);
        data.black_borne_off_ids = copy_uint8 (board.black_borne_off_ids);

        data.current_player = current_player;
        data.is_game_started = is_game_started;
        data.is_game_over = is_game_over;
        data.showing_game_over_result = showing_game_over_result;
        data.is_white_first_turn = is_white_first_turn;
        data.is_black_first_turn = is_black_first_turn;
        data.is_first_move_rolloff_in_progress = is_first_move_rolloff_in_progress;
        data.white_rolloff_die1 = white_rolloff_dice == null ? 0 : white_rolloff_dice.die1;
        data.white_rolloff_die2 = white_rolloff_dice == null ? 0 : white_rolloff_dice.die2;
        data.black_rolloff_die1 = black_rolloff_dice == null ? 0 : black_rolloff_dice.die1;
        data.black_rolloff_die2 = black_rolloff_dice == null ? 0 : black_rolloff_dice.die2;
        data.dice_roll_die1 = dice_roll == null ? 0 : dice_roll.die1;
        data.dice_roll_die2 = dice_roll == null ? 0 : dice_roll.die2;
        data.remaining_dice = copy_int_array (remaining_dice);

        data.white_moves_count = white_moves_count;
        data.black_moves_count = black_moves_count;
        data.white_doubles_count = white_doubles_count;
        data.black_doubles_count = black_doubles_count;
        data.white_total_dice_sum = white_total_dice_sum;
        data.black_total_dice_sum = black_total_dice_sum;
        data.white_burned_dice_sum = white_burned_dice_sum;
        data.black_burned_dice_sum = black_burned_dice_sum;

        data.white_turn_log = white_turn_log;
        data.black_turn_log = black_turn_log;
        data.white_player_name = white_player_name;
        data.black_player_name = black_player_name;
        data.is_black_computer = is_black_computer;
        data.is_auto_playing_black = is_auto_playing_black;
        data.board_side = SettingsStore.shared ().board_side.to_raw ();
        data.checkers_moved_from_head_this_turn = checkers_moved_from_head_this_turn;
        data.current_turn_record = current_turn_record;
        data.move_history = move_history;

        SavedGameStore.shared ().save (data);
    }

    /** Восстанавливает игру из структуры сохранённых данных партии. */
    public void restore_from_store (SavedGameData data) {
        cancel_all_tasks ();

        var target_board = SavedGameStore.board_from_data (data.stacks, data.white_borne_off_ids, data.black_borne_off_ids);
        board = GameBoard.in_tray ();
        current_player = data.current_player;
        is_game_started = data.is_game_started;
        is_game_over = data.is_game_over;
        showing_game_over_result = data.showing_game_over_result;
        is_white_first_turn = data.is_white_first_turn;
        is_black_first_turn = data.is_black_first_turn;
        is_first_move_rolloff_in_progress = data.is_first_move_rolloff_in_progress;
        white_rolloff_dice = (data.white_rolloff_die1 > 0 && data.white_rolloff_die2 > 0)
            ? new DiceRoll (data.white_rolloff_die1, data.white_rolloff_die2) : null;
        black_rolloff_dice = (data.black_rolloff_die1 > 0 && data.black_rolloff_die2 > 0)
            ? new DiceRoll (data.black_rolloff_die1, data.black_rolloff_die2) : null;
        if (data.is_first_move_rolloff_in_progress) {
            if (white_rolloff_dice != null && black_rolloff_dice != null) {
                var w_sum = white_rolloff_dice.die1 + white_rolloff_dice.die2;
                var b_sum = black_rolloff_dice.die1 + black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    rolloff_active_player = null;
                } else {
                    rolloff_active_player = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                }
            } else {
                rolloff_active_player = (white_rolloff_dice == null) ? CheckerColor.WHITE : CheckerColor.BLACK;
            }
        } else {
            rolloff_active_player = null;
        }
        rolloff_animation_id = 0;
        rolling_die_index = -1;
        is_rolling = false;
        is_doubling = false;
        is_no_moves_flashing = false;
        is_dice_flash_active = false;
        dice_flash_opacity = 0.0;
        suppress_dice_cursor = false;

        dice_roll = (data.dice_roll_die1 > 0 && data.dice_roll_die2 > 0)
            ? new DiceRoll (data.dice_roll_die1, data.dice_roll_die2) : null;
        remaining_dice = copy_int_array (data.remaining_dice);

        white_moves_count = data.white_moves_count;
        black_moves_count = data.black_moves_count;
        white_doubles_count = data.white_doubles_count;
        black_doubles_count = data.black_doubles_count;
        white_total_dice_sum = data.white_total_dice_sum;
        black_total_dice_sum = data.black_total_dice_sum;
        white_burned_dice_sum = data.white_burned_dice_sum;
        black_burned_dice_sum = data.black_burned_dice_sum;

        SettingsStore.shared ().set_opponent (data.is_black_computer ? Opponent.COMPUTER : Opponent.HUMAN);
        if (data.board_side != null && data.board_side != "") {
            SettingsStore.shared ().set_board_side (BoardSide.from_raw (data.board_side));
        }

        white_player_name = data.white_player_name;
        black_player_name = data.black_player_name;
        checkers_moved_from_head_this_turn = data.checkers_moved_from_head_this_turn;
        is_auto_playing_black = data.is_auto_playing_black;

        white_turn_log = data.white_turn_log;
        black_turn_log = data.black_turn_log;

        if (data.current_turn_record != null) {
            current_turn_record = data.current_turn_record;
        } else if (dice_roll != null) {
            var t_num = (current_player == CheckerColor.WHITE
                ? non_rolloff_count (white_turn_log) : non_rolloff_count (black_turn_log)) + 1;
            current_turn_record = new TurnRecord.with_dice (t_num, new DiceRoll (dice_roll.die1, dice_roll.die2));
        } else {
            current_turn_record = null;
        }

        if (dice_roll != null) {
            var all_vals = move_values (dice_roll);
            var rem = copy_int_array (remaining_dice);
            var dice = new TurnDie[0];
            for (var i = 0; i < all_vals.length; i++) {
                var r_idx = index_of (rem, all_vals[i]);
                if (r_idx >= 0) {
                    rem = remove_at (rem, r_idx);
                    dice += new TurnDie (i, all_vals[i], false);
                } else {
                    dice += new TurnDie (i, all_vals[i], true);
                }
            }
            current_turn_dice = dice;
        } else {
            current_turn_dice = new TurnDie[0];
        }

        highlighted_log_id = -1;
        selected_point = null;
        move_history = data.move_history;

        notify_changed ();

        animate_placement (target_board, true, false, () => {
            update_status_on_restore ();
            update_available_moves_cache ();

            var g = gen;
            if (is_first_move_rolloff_in_progress) {
                if (white_rolloff_dice != null && black_rolloff_dice != null) {
                    // A saved game may have been closed after both players rolled
                    // but before the tie/winner presentation completed.
                    var white_result = new DiceRoll (white_rolloff_dice.die1, white_rolloff_dice.die2);
                    var black_result = new DiceRoll (black_rolloff_dice.die1, black_rolloff_dice.die2);
                    after (0.6, () => {
                        var white_sum = white_result.die1 + white_result.die2;
                        var black_sum = black_result.die1 + black_result.die2;
                        if (white_sum == black_sum) {
                            handle_rolloff_tie.begin (white_result, black_result, g);
                        } else {
                            var winner = white_sum > black_sum
                                ? CheckerColor.WHITE : CheckerColor.BLACK;
                            handle_rolloff_win.begin (winner, white_result, black_result, g);
                        }
                    });
                } else if (is_computer_turn) {
                    after (0.6, () => {
                        roll_dice ();
                    });
                }
            } else if (is_computer_turn) {
                if (dice_roll != null) {
                    if (remaining_dice.length > 0) {
                        status_message = Localization.status_computer_moving ();
                        after (0.5, () => {
                            perform_computer_turn.begin (g);
                        });
                    } else {
                        status_message = Localization.status_roll_dice ();
                        after (0.0, () => {
                            end_turn ();
                        });
                    }
                } else {
                    auto_play_if_needed ();
                }
            } else {
                if (dice_roll != null) {
                    check_and_auto_end_turn ();
                }
            }
            notify_changed ();
        });
    }

    private void update_status_on_restore () {
        if (is_game_over) {
            status_message = (current_player == CheckerColor.WHITE) ? Localization.victory_white () : Localization.victory_black ();
        } else if (is_first_move_rolloff_in_progress) {
            if (white_rolloff_dice != null && black_rolloff_dice != null) {
                var w_sum = white_rolloff_dice.die1 + white_rolloff_dice.die2;
                var b_sum = black_rolloff_dice.die1 + black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    status_message = Localization.status_rolloff_tie ();
                } else {
                    var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                    status_message = Localization.status_rolloff_result (player_name (winner));
                }
            } else {
                status_message = is_computer_turn ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
            }
        } else if (dice_roll == null) {
            status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        } else if (remaining_dice.length == 0) {
            status_message = Localization.status_roll_dice ();
        } else {
            status_message = (selected_point == null) ? Localization.status_select_checker () : Localization.status_select_target ();
        }
    }

    private static uint8[] copy_uint8 (uint8[] src) {
        var copy = new uint8[src.length];
        for (var i = 0; i < src.length; i++) {
            copy[i] = src[i];
        }
        return copy;
    }

    /** Настройка тестовой расстановки перед победным ходом дублем 2-2. */
    public void setup_test_last_move () {
        board = new GameBoard ();
        // У белых осталась 1 фишка на лунке 1 (P1)
        board.stacks[1] = new PointStack.with_ids (CheckerColor.WHITE, new uint8[] { 0 });
        var w_off = new uint8[14];
        for (var i = 0; i < 14; i++) {
            w_off[i] = (uint8) (i + 1);
        }
        board.white_borne_off_ids = w_off;

        // У чёрных 15 фишек: 2:B1 3:B1 4:B1 5:B1 6:B2 13:B6 14:B2 24:B1
        board.stacks[2] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 15 });
        board.stacks[3] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 16 });
        board.stacks[4] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 17 });
        board.stacks[5] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 18 });
        board.stacks[6] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 19, 20 });
        board.stacks[13] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 21, 22, 23, 24, 25, 26 });
        board.stacks[14] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 27, 28 });
        board.stacks[24] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 29 });
        board.black_borne_off_ids = new uint8[0];

        is_game_started = true;
        is_game_over = false;
        showing_game_over_result = false;
        current_player = CheckerColor.WHITE;
        SettingsStore.shared ().set_opponent (Opponent.COMPUTER);
        is_auto_playing_black = false;
        white_player_name = "Алексей";
        black_player_name = "Computer";
        is_first_move_rolloff_in_progress = false;
        rolloff_active_player = null;
        is_rolling = false;
        is_animating = false;
        selected_point = null;
        move_history = new MoveSnapshot[0];
        checkers_moved_from_head_this_turn = 0;

        white_moves_count = 41;
        black_moves_count = 41;
        white_doubles_count = 5;
        black_doubles_count = 6;
        white_total_dice_sum = 300;
        black_total_dice_sum = 240;
        white_burned_dice_sum = 0;
        black_burned_dice_sum = 38;

        dice_roll = new DiceRoll (2, 2);
        remaining_dice = new int[] { 2, 2, 2, 2 };
        current_turn_dice = new TurnDie[] {
            new TurnDie (0, 2, false, false),
            new TurnDie (1, 2, false, false),
            new TurnDie (2, 2, false, false),
            new TurnDie (3, 2, false, false)
        };
        current_turn_record = new TurnRecord.with_dice (42, new DiceRoll (2, 2));
        current_turn_record.dice = TurnDie.clone_array (current_turn_dice);
        double_division_progress = 1.0;
        status_message = Localization.status_select_checker ();

        // Предыдущие ходы в логах для полноты картины
        var prev_w = new TurnRecord.with_dice (41, new DiceRoll (6, 1));
        prev_w.move_strings = new string[] { "1-^", "1-^" };
        prev_w.dice = new TurnDie[] { new TurnDie (0, 6, true, false), new TurnDie (1, 1, true, false) };
        white_turn_log = new TurnRecord[] { prev_w };

        var prev_b = new TurnRecord.with_dice (41, new DiceRoll (1, 1));
        prev_b.move_strings = new string[] { "6-5-4-3-2" };
        prev_b.dice = new TurnDie[] {
            new TurnDie (0, 1, true, false), new TurnDie (1, 1, true, false),
            new TurnDie (2, 1, true, false), new TurnDie (3, 1, true, false)
        };
        black_turn_log = new TurnRecord[] { prev_b };

        update_available_moves_cache ();
        notify_changed ();
    }
}

} /* namespace Longbackgammon */
