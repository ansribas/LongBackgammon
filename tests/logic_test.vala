/* logic_test.vala
 *
 * Набор регрессионных тестов правил игры, валидатора ходов,
 * алгоритмов AI и системы локализации.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Longbackgammon;

public class LogicTestSuite {
    public static int failed = 0;
    public static int test_count = 0;

    public static void assert_true (bool cond, string msg) {
        test_count++;
        if (!cond) {
            stderr.printf ("FAIL: %s\n", msg);
            failed++;
        }
    }

    public static void assert_false (bool cond, string msg) {
        assert_true (!cond, msg);
    }

    public static void assert_equal_int (int actual, int expected, string msg) {
        test_count++;
        if (actual != expected) {
            stderr.printf ("FAIL: %s (expected %d, got %d)\n", msg, expected, actual);
            failed++;
        }
    }

    public static int run () {

    // =========================================================================
    // SUITE 1: PlayerPathTests
    // =========================================================================
    // 1.1 Маршрут белых: ровно 24 пункта, старт на p24, финиш на p1
    var white_route = PlayerPath.path (CheckerColor.WHITE);
    assert_equal_int (white_route.length, 24, "white route count == 24");
    assert_true (white_route[0] == BoardPoint.P24, "white route start == P24");
    assert_true (white_route[23] == BoardPoint.P1, "white route finish == P1");
    assert_true (PlayerPath.start_point (CheckerColor.WHITE) == BoardPoint.P24, "white start point P24");
    assert_true (PlayerPath.finish_point (CheckerColor.WHITE) == BoardPoint.P1, "white finish point P1");

    // 1.2 Маршрут чёрных: ровно 24 пункта, старт на p12, финиш на p13
    var black_route = PlayerPath.path (CheckerColor.BLACK);
    assert_equal_int (black_route.length, 24, "black route count == 24");
    assert_true (black_route[0] == BoardPoint.P12, "black route start == P12");
    assert_true (black_route[23] == BoardPoint.P13, "black route finish == P13");
    assert_true (PlayerPath.start_point (CheckerColor.BLACK) == BoardPoint.P12, "black start point P12");
    assert_true (PlayerPath.finish_point (CheckerColor.BLACK) == BoardPoint.P13, "black finish point P13");

    // 1.3 Переход через границу доски у чёрных: с p1 они идут на p24
    int p1_idx = -1;
    for (var i = 0; i < black_route.length; i++) {
        if (black_route[i] == BoardPoint.P1) {
            p1_idx = i;
            break;
        }
    }
    assert_true (p1_idx >= 0 && p1_idx < 23 && black_route[p1_idx + 1] == BoardPoint.P24,
                 "black route rollover from P1 to P24");

    // 1.4 Расчёт шагов между точками
    assert_equal_int (PlayerPath.steps_between (BoardPoint.P24, BoardPoint.P20, CheckerColor.WHITE), 4,
                      "white steps P24->P20 == 4");
    assert_equal_int (PlayerPath.steps_between (BoardPoint.P20, BoardPoint.P24, CheckerColor.WHITE), -1,
                      "white backward steps returns -1");
    assert_equal_int (PlayerPath.steps_between (BoardPoint.P12, BoardPoint.P9, CheckerColor.BLACK), 3,
                      "black steps P12->P9 == 3");
    assert_equal_int (PlayerPath.steps_between (BoardPoint.P2, BoardPoint.P23, CheckerColor.BLACK), 3,
                      "black crossover steps P2->P23 == 3");

    // =========================================================================
    // SUITE 2: HeadRuleTests
    // =========================================================================
    var init_board = GameBoard.initial_long ();
    int[] normal_dice = { 3, 5 };

    // 2.1 Обычный ход: снятие 2-й фишки с головы запрещено
    var head_m0 = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, normal_dice, 0, false, false);
    assert_true (head_m0.length > 0, "0 checkers moved from head allows move");
    var head_m1 = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, new int[] { 5 }, 1, false, false);
    assert_equal_int (head_m1.length, 0, "normal turn forbids 2nd checker from head");

    // 2.2 Первый ход: дубли 3:3, 4:4, 6:6 разрешают снятие 2 фишек
    int[] d33 = { 3, 3, 3 };
    var m_d33 = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, d33, 1, true, true);
    assert_true (m_d33.length > 0, "first turn 3:3 allows 2nd checker from head");
    bool has_p21 = false;
    for (var i = 0; i < m_d33.length; i++) {
        if (m_d33[i].to == BoardPoint.P21) has_p21 = true;
    }
    assert_true (has_p21, "first turn 3:3 can move to P21");

    int[] d44 = { 4, 4, 4 };
    var m_d44 = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, d44, 1, true, true);
    assert_true (m_d44.length > 0, "first turn 4:4 allows 2nd checker from head");
    bool has_p20 = false;
    for (var i = 0; i < m_d44.length; i++) {
        if (m_d44[i].to == BoardPoint.P20) has_p20 = true;
    }
    assert_true (has_p20, "first turn 4:4 can move to P20");

    int[] d66 = { 6, 6, 6 };
    var m_d66 = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, d66, 1, true, true);
    assert_true (m_d66.length > 0, "first turn 6:6 allows 2nd checker from head");
    bool has_p18 = false;
    for (var i = 0; i < m_d66.length; i++) {
        if (m_d66[i].to == BoardPoint.P18) has_p18 = true;
    }
    assert_true (has_p18, "first turn 6:6 can move to P18");

    // 2.3 Первый ход: дубли 1:1, 2:2, 5:5 НЕ разрешают снятие 2 фишек
    int[] other_doubles = { 1, 2, 5 };
    for (var i = 0; i < other_doubles.length; i++) {
        var d = other_doubles[i];
        int[] cur_d = { d, d, d };
        var m_other = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, cur_d, 1, true, true);
        assert_equal_int (m_other.length, 0, "first turn other doubles do not allow 2nd from head");
    }

    // 2.4 Последующие ходы: дубли 3:3, 4:4, 6:6 больше НЕ разрешают 2 фишки с головы
    int[] sub_doubles = { 3, 4, 6 };
    for (var i = 0; i < sub_doubles.length; i++) {
        var d = sub_doubles[i];
        int[] cur_d = { d, d, d };
        var m_sub = MoveValidator.moves (BoardPoint.P24, init_board, CheckerColor.WHITE, cur_d, 1, true, false);
        assert_equal_int (m_sub.length, 0, "subsequent turns doubles do not allow 2nd from head");
    }

    // 2.5 Чёрные: голова на p12
    assert_true (MoveValidator.is_head (BoardPoint.P12, CheckerColor.BLACK), "black head is P12");
    assert_false (MoveValidator.is_head (BoardPoint.P24, CheckerColor.BLACK), "P24 is not black head");

    // 2.6 Чёрные: первый ход с 3:3 разрешает 2 фишки с головы
    var m_black_d3 = MoveValidator.moves (BoardPoint.P12, init_board, CheckerColor.BLACK, d33, 1, true, true);
    assert_true (m_black_d3.length > 0, "black first turn 3:3 allows 2nd checker from P12");
    bool black_has_p9 = false;
    for (var i = 0; i < m_black_d3.length; i++) {
        if (m_black_d3[i].to == BoardPoint.P9) black_has_p9 = true;
    }
    assert_true (black_has_p9, "black first turn 3:3 can move to P9");

    // =========================================================================
    // SUITE 3: PrimeRuleTests
    // =========================================================================
    var pb = new GameBoard ();
    pb.set_stack (BoardPoint.P11, CheckerColor.WHITE, new uint8[] { 1 });
    pb.set_stack (BoardPoint.P10, CheckerColor.WHITE, new uint8[] { 2 });
    pb.set_stack (BoardPoint.P9, CheckerColor.WHITE, new uint8[] { 3 });
    pb.set_stack (BoardPoint.P8, CheckerColor.WHITE, new uint8[] { 4 });
    pb.set_stack (BoardPoint.P7, CheckerColor.WHITE, new uint8[] { 5 });
    pb.set_stack (BoardPoint.P15, CheckerColor.WHITE, new uint8[] { 6 });
    var blk_ids = new uint8[15];
    for (var i = 0; i < 15; i++) blk_ids[i] = (uint8) (15 + i);
    pb.set_stack (BoardPoint.P12, CheckerColor.BLACK, blk_ids);

    // 3.1 6 фишек подряд запрещено, если впереди нет фишек соперника
    assert_true (MoveValidator.creates_illegal_prime (BoardPoint.P15, BoardPoint.P6, pb, CheckerColor.WHITE),
                 "6-prime without opponent ahead is illegal");

    // 3.2 6 фишек подряд разрешено, если соперник впереди
    pb.set_stack (BoardPoint.P3, CheckerColor.BLACK, new uint8[] { 29 });
    assert_false (MoveValidator.creates_illegal_prime (BoardPoint.P15, BoardPoint.P6, pb, CheckerColor.WHITE),
                  "6-prime with opponent ahead is legal");

    // 3.3 6 фишек подряд разрешено, если соперник вынес фишку
    var pb2 = new GameBoard ();
    pb2.set_stack (BoardPoint.P11, CheckerColor.WHITE, new uint8[] { 1 });
    pb2.set_stack (BoardPoint.P10, CheckerColor.WHITE, new uint8[] { 2 });
    pb2.set_stack (BoardPoint.P9, CheckerColor.WHITE, new uint8[] { 3 });
    pb2.set_stack (BoardPoint.P8, CheckerColor.WHITE, new uint8[] { 4 });
    pb2.set_stack (BoardPoint.P7, CheckerColor.WHITE, new uint8[] { 5 });
    pb2.set_stack (BoardPoint.P15, CheckerColor.WHITE, new uint8[] { 6 });
    pb2.set_stack (BoardPoint.P12, CheckerColor.BLACK, blk_ids);
    pb2.set_borne_off (new uint8[0], new uint8[] { 29 });
    assert_false (MoveValidator.creates_illegal_prime (BoardPoint.P15, BoardPoint.P6, pb2, CheckerColor.WHITE),
                  "6-prime when opponent borne off is legal");

    // 3.4 5 фишек подряд всегда разрешено
    var pb3 = new GameBoard ();
    pb3.set_stack (BoardPoint.P10, CheckerColor.WHITE, new uint8[] { 1 });
    pb3.set_stack (BoardPoint.P9, CheckerColor.WHITE, new uint8[] { 2 });
    pb3.set_stack (BoardPoint.P8, CheckerColor.WHITE, new uint8[] { 3 });
    pb3.set_stack (BoardPoint.P7, CheckerColor.WHITE, new uint8[] { 4 });
    pb3.set_stack (BoardPoint.P15, CheckerColor.WHITE, new uint8[] { 5 });
    pb3.set_stack (BoardPoint.P12, CheckerColor.BLACK, blk_ids);
    assert_false (MoveValidator.creates_illegal_prime (BoardPoint.P15, BoardPoint.P6, pb3, CheckerColor.WHITE),
                  "5-prime is always legal");

    // =========================================================================
    // SUITE 4: BearOffRuleTests
    // =========================================================================
    // 4.1 Белые: если хоть 1 фишка вне дома (p7), вынос запрещён
    var bob = new GameBoard ();
    var w14 = new uint8[14];
    for (var i = 0; i < 14; i++) w14[i] = (uint8) i;
    bob.set_stack (BoardPoint.P1, CheckerColor.WHITE, w14);
    bob.set_stack (BoardPoint.P7, CheckerColor.WHITE, new uint8[] { 14 });
    assert_false (MoveValidator.are_all_checkers_in_home (bob, CheckerColor.WHITE), "not all white in home");
    var bo_m = MoveValidator.moves (BoardPoint.P1, bob, CheckerColor.WHITE, new int[] { 1 }, 0, false, false);
    bool has_bo = false;
    for (var i = 0; i < bo_m.length; i++) {
        if (bo_m[i].to == null) has_bo = true;
    }
    assert_false (has_bo, "bear-off forbidden when checker on P7");

    // 4.2 Белые: все 15 в доме на p4, точный вынос кубиком 4
    bob.clear_all_stacks ();
    var w15 = new uint8[15];
    for (var i = 0; i < 15; i++) w15[i] = (uint8) i;
    bob.set_stack (BoardPoint.P4, CheckerColor.WHITE, w15);
    assert_true (MoveValidator.are_all_checkers_in_home (bob, CheckerColor.WHITE), "all white in home");
    var bo_m4 = MoveValidator.moves (BoardPoint.P4, bob, CheckerColor.WHITE, new int[] { 4 }, 0, false, false);
    bool has_bo4 = false;
    for (var i = 0; i < bo_m4.length; i++) {
        if (bo_m4[i].to == null) has_bo4 = true;
    }
    assert_true (has_bo4, "exact bear-off with die 4 is allowed");

    // 4.3 Белые: вынос старшим кубиком (6) с p3, если p4..p6 пусты
    bob.clear_all_stacks ();
    bob.set_stack (BoardPoint.P3, CheckerColor.WHITE, w15);
    var bo_m6 = MoveValidator.moves (BoardPoint.P3, bob, CheckerColor.WHITE, new int[] { 6 }, 0, false, false);
    bool has_bo6 = false;
    for (var i = 0; i < bo_m6.length; i++) {
        if (bo_m6[i].to == null) has_bo6 = true;
    }
    assert_true (has_bo6, "higher die bear-off allowed when higher points empty");

    // 4.4 Белые: вынос старшим кубиком (6) с p3 ЗАПРЕЩЁН, если есть фишка на p5
    bob.clear_all_stacks ();
    bob.set_stack (BoardPoint.P3, CheckerColor.WHITE, w14);
    bob.set_stack (BoardPoint.P5, CheckerColor.WHITE, new uint8[] { 14 });
    var bo_m6_blk = MoveValidator.moves (BoardPoint.P3, bob, CheckerColor.WHITE, new int[] { 6 }, 0, false, false);
    bool has_bo6_blk = false;
    for (var i = 0; i < bo_m6_blk.length; i++) {
        if (bo_m6_blk[i].to == null) has_bo6_blk = true;
    }
    assert_false (has_bo6_blk, "higher die bear-off forbidden when P5 occupied");

    // 4.5 Чёрные: дом p13..p18, фишки на p15 (позиция 3 в доме), точный вынос кубиком 3
    var b_bob = new GameBoard ();
    b_bob.set_stack (BoardPoint.P15, CheckerColor.BLACK, blk_ids);
    assert_true (MoveValidator.are_all_checkers_in_home (b_bob, CheckerColor.BLACK), "all black in home");
    var b_bo_m3 = MoveValidator.moves (BoardPoint.P15, b_bob, CheckerColor.BLACK, new int[] { 3 }, 0, false, false);
    bool b_has_bo3 = false;
    for (var i = 0; i < b_bo_m3.length; i++) {
        if (b_bo_m3[i].to == null) b_has_bo3 = true;
    }
    assert_true (b_has_bo3, "black exact bear-off from P15 with die 3 is allowed");

    // =========================================================================
    // SUITE 5: VictoryConditionTests
    // =========================================================================
    var vb = new GameBoard ();
    assert_false (vb.is_winner (CheckerColor.WHITE), "0 borne off is not winner");
    vb.set_borne_off (w14, new uint8[0]);
    assert_false (vb.is_winner (CheckerColor.WHITE), "14 borne off is not winner");
    vb.set_borne_off (w15, new uint8[0]);
    assert_true (vb.is_winner (CheckerColor.WHITE), "15 borne off is winner");

    // 5.1 Оин (проигравший вынес >= 1 фишки)
    var vb_oin = new GameBoard ();
    vb_oin.set_borne_off (w15, new uint8[] { 15 });
    assert_true (vb_oin.victory_type (CheckerColor.BLACK) == VictoryType.OIN, "victory type is OIN");

    // 5.2 Марс (проигравший вынес 0 фишек и фишки вне дома)
    var vb_mars = new GameBoard ();
    vb_mars.set_borne_off (w15, new uint8[0]);
    vb_mars.set_stack (BoardPoint.P12, CheckerColor.BLACK, blk_ids);
    assert_true (vb_mars.victory_type (CheckerColor.BLACK) == VictoryType.MARS, "victory type is MARS");

    // 5.3 Домашний марс (проигравший вынес 0 фишек, но все в доме)
    var vb_hmars = new GameBoard ();
    vb_hmars.set_borne_off (w15, new uint8[0]);
    vb_hmars.set_stack (BoardPoint.P14, CheckerColor.BLACK, blk_ids);
    assert_true (vb_hmars.victory_type (CheckerColor.BLACK) == VictoryType.HOME_MARS, "victory type is HOME_MARS");

    // =========================================================================
    // SUITE 6: MovementRuleTests
    // =========================================================================
    // 6.1 Ход на свободный пункт разрешён
    var dest_free = MoveValidator.destination (BoardPoint.P24, 4, init_board, CheckerColor.WHITE, 0, false, false);
    assert_true (dest_free == BoardPoint.P20, "move to empty point P20 allowed");

    // 6.2 Ход на пункт соперника заблокирован
    var mb_blk = GameBoard.initial_long ();
    mb_blk.set_stack (BoardPoint.P20, CheckerColor.BLACK, new uint8[] { 15 });
    var dest_opp = MoveValidator.destination (BoardPoint.P24, 4, mb_blk, CheckerColor.WHITE, 0, false, false);
    assert_true (dest_opp == null, "move to opponent point P20 blocked");
    assert_true (MoveValidator.is_blocked (BoardPoint.P20, mb_blk, CheckerColor.WHITE), "P20 is blocked for white");

    // 6.3 Ход на свой пункт разрешён
    var mb_own = GameBoard.initial_long ();
    mb_own.set_stack (BoardPoint.P20, CheckerColor.WHITE, new uint8[] { 1 });
    var dest_own = MoveValidator.destination (BoardPoint.P24, 4, mb_own, CheckerColor.WHITE, 0, false, false);
    assert_true (dest_own == BoardPoint.P20, "move to own point P20 allowed");

    // 6.4 Составной ход проверяет проходимость промежуточного пункта
    var mb_comb = GameBoard.initial_long ();
    mb_comb.set_stack (BoardPoint.P22, CheckerColor.BLACK, new uint8[] { 15 });
    mb_comb.set_stack (BoardPoint.P21, CheckerColor.BLACK, new uint8[] { 16 });
    int[] d23 = { 2, 3 };
    var comb_m = MoveValidator.moves (BoardPoint.P24, mb_comb, CheckerColor.WHITE, d23, 0, false, false);
    bool has_comb = false;
    for (var i = 0; i < comb_m.length; i++) {
        if (comb_m[i].is_combined) has_comb = true;
    }
    assert_false (has_comb, "combined move forbidden when intermediate points blocked");

    // Проверка выбора большего кубика при взаимоисключающих вариантах и точная позиция хода 39.
    var forced_options = new MoveOption[] {
        new MoveOption (BoardPoint.P10, BoardPoint.P7, 3, new int[] { 0 }, false),
        new MoveOption (BoardPoint.P10, BoardPoint.P5, 5, new int[] { 0 }, false)
    };
    var forced_result = MoveValidator.filter_forced_single_die (forced_options);
    assert_equal_int (forced_result.length, 1, "forced single-die filter leaves only the higher die");
    assert_equal_int (forced_result[0].die, 5, "forced single-die filter chooses 5 over 3");

    var turn39 = new GameBoard ();
    turn39.set_stack (BoardPoint.P1, CheckerColor.WHITE, new uint8[] { 0, 1 });
    turn39.set_stack (BoardPoint.P2, CheckerColor.WHITE, new uint8[] { 2, 3 });
    turn39.set_stack (BoardPoint.P3, CheckerColor.WHITE, new uint8[] { 4, 5 });
    turn39.set_stack (BoardPoint.P4, CheckerColor.WHITE, new uint8[] { 6, 7, 8 });
    turn39.set_stack (BoardPoint.P5, CheckerColor.WHITE, new uint8[] { 9, 10 });
    turn39.set_stack (BoardPoint.P6, CheckerColor.WHITE, new uint8[] { 11, 12 });
    turn39.set_stack (BoardPoint.P8, CheckerColor.WHITE, new uint8[] { 13 });
    turn39.set_stack (BoardPoint.P9, CheckerColor.WHITE, new uint8[] { 14 });
    turn39.set_stack (BoardPoint.P12, CheckerColor.BLACK, new uint8[] { 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 });
    turn39.set_stack (BoardPoint.P13, CheckerColor.BLACK, new uint8[] { 26, 27, 28, 29 });
    int[] turn39_dice = { 5, 1 };
    var turn39_raw = MoveValidator.all_moves (turn39, CheckerColor.BLACK, turn39_dice, 0, false, false);
    var turn39_legal = MoveValidator.filter_legal_moves (
        turn39_raw, turn39, CheckerColor.BLACK, turn39_dice, 0, false, false);
    assert_equal_int (turn39_raw.length, 2, "turn-39 has two raw head moves");
    assert_equal_int (turn39_legal.length, 1, "turn-39 legal filter leaves one move");
    assert_equal_int (turn39_legal[0].die, 5, "turn-39 must play die 5");
    assert_true (turn39_legal[0].to == BoardPoint.P7, "turn-39 move must be 12 to 7");
    var standard_choice = ComputerAI.choose_move (turn39_legal, turn39, CheckerColor.BLACK, turn39_dice);
    assert_true (standard_choice != null && standard_choice.die == 5,
                 "standard AI obeys the forced higher die");

    // Maximum-dice rule: 15->9 with a 6 leaves the 2 unusable, while
    // 15->13 with a 2 and 10->4 with a 6 uses both dice.
    var max_dice_board = new GameBoard ();
    max_dice_board.set_stack (BoardPoint.P15, CheckerColor.WHITE, new uint8[] { 0 });
    max_dice_board.set_stack (BoardPoint.P10, CheckerColor.WHITE, new uint8[] { 1 });
    max_dice_board.set_stack (BoardPoint.P8, CheckerColor.BLACK, new uint8[] { 15 });
    max_dice_board.set_stack (BoardPoint.P7, CheckerColor.BLACK, new uint8[] { 16 });
    max_dice_board.set_stack (BoardPoint.P2, CheckerColor.BLACK, new uint8[] { 17 });
    int[] max_dice = { 2, 6 };
    var max_raw = MoveValidator.all_moves (max_dice_board, CheckerColor.WHITE, max_dice, 0, false, false);
    var max_legal = MoveValidator.filter_legal_moves (
        max_raw, max_dice_board, CheckerColor.WHITE, max_dice, 0, false, false);
    bool rejected_dead_end = true;
    bool retained_two_die_starts = false;
    foreach (var option in max_legal) {
        if (option.from == BoardPoint.P15 && option.to == BoardPoint.P9) rejected_dead_end = false;
        if ((option.from == BoardPoint.P15 && option.to == BoardPoint.P13)
            || (option.from == BoardPoint.P10 && option.to == BoardPoint.P4)) retained_two_die_starts = true;
    }
    assert_true (rejected_dead_end, "maximum-dice rule rejects the 15->9 dead end");
    assert_true (retained_two_die_starts, "maximum-dice rule keeps starts that allow both dice");

    // Нормализация расстановки: канонический порядок идентификаторов фишек и порядок в трее.
    var restored = new GameBoard ();
    restored.set_stack (BoardPoint.P24, CheckerColor.WHITE, new uint8[] { 14, 13, 12 });
    restored.set_stack (BoardPoint.P10, CheckerColor.WHITE, new uint8[] { 11, 10 });
    restored.set_stack (BoardPoint.P5, CheckerColor.WHITE, new uint8[] { 9 });
    var white_off = new uint8[] { 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    var black_off = new uint8[10];
    for (var i = 0; i < black_off.length; i++) black_off[i] = (uint8) (29 - i);
    restored.set_borne_off (white_off, black_off);
    restored.set_stack (BoardPoint.P12, CheckerColor.BLACK, new uint8[] { 15, 16, 17, 18 });
    restored.set_stack (BoardPoint.P3, CheckerColor.BLACK, new uint8[] { 19 });
    var normalized = restored.normalized_for_placement_from_tray ();
    assert_equal_int (normalized.stack_at (BoardPoint.P24).checker_ids.length, 3, "normalized P24 stack count");
    assert_equal_int (normalized.stack_at (BoardPoint.P10).checker_ids.length, 2, "normalized P10 stack count");
    assert_equal_int (normalized.stack_at (BoardPoint.P5).checker_ids.length, 1, "normalized P5 stack count");
    assert_equal_int (normalized.borne_off_count (CheckerColor.WHITE), 9, "normalized white tray count");
    assert_equal_int (normalized.borne_off_count (CheckerColor.BLACK), 10, "normalized black tray count");
    assert_true (normalized.white_borne_off_ids[0] == 14 && normalized.white_borne_off_ids[8] == 6,
                 "normalized white tray preserves the canonical top-down order");
    assert_true (normalized.black_borne_off_ids[0] == 29 && normalized.black_borne_off_ids[9] == 20,
                 "normalized black tray preserves the canonical top-down order");
    assert_true (normalized.stack_at (BoardPoint.P24).checker_ids[0] == 0
                 && normalized.stack_at (BoardPoint.P10).checker_ids[0] == 1
                 && normalized.stack_at (BoardPoint.P5).checker_ids[0] == 2,
                 "normalized white checker IDs follow route order");

    // =========================================================================
    // SUITE 7: LocalizationTests
    // =========================================================================
    var loc = LocalizationManager.shared ();
    var ru_lang = Language.get ("ru");
    var en_lang = Language.get ("en");

    assert_equal_int (loc.string_for_key ("buttonNewGame", ru_lang) == "Новая партия" ? 1 : 0, 1,
                      "RU string buttonNewGame");
    assert_equal_int (loc.string_for_key ("buttonNewGame", en_lang) == "New Game" ? 1 : 0, 1,
                      "EN string buttonNewGame");

    var unknown_key = loc.string_for_key ("unknownKey9999", ru_lang);
    assert_equal_int (unknown_key == "unknownKey9999" ? 1 : 0, 1,
                      "fallback for unknown key");

    string[] rep_ru = { "player", "Алексей" };
    var formatted_ru = loc.format_string ("statusRollOffResult", ru_lang, rep_ru);
    assert_equal_int (formatted_ru == "Алексей ходит первый!" ? 1 : 0, 1,
                      "format parameter replacement RU");

    // Сценарии тестирования локализации: английский формат, дополнительные языки,
    // динамическое обнаружение языков, имена, названия тем и строка roll-off.
    string[] rep_en = { "player", "Alex" };
    assert_true (loc.string_for_key ("windowTitle", ru_lang) == "Длинные нарды",
                 "RU window title");
    assert_true (loc.string_for_key ("windowTitle", en_lang) == "Long Backgammon",
                 "EN window title");
    assert_true (loc.format_string ("statusRollOffResult", en_lang, rep_en) == "Alex starts first!",
                 "format parameter replacement EN");

    var de_lang = Language.get ("de");
    var es_lang = Language.get ("es");
    assert_true (loc.string_for_key ("windowTitle", de_lang) == "Langes Backgammon",
                 "DE window title");
    assert_true (loc.string_for_key ("buttonNewGame", de_lang) == "Neues Spiel",
                 "DE new game label");
    assert_true (loc.string_for_key ("windowTitle", es_lang) == "Backgammon largo",
                 "ES window title");
    assert_true (loc.string_for_key ("buttonNewGame", es_lang) == "Nueva partida",
                 "ES new game label");

    string[] expected_codes = { "ru", "en", "de", "es", "az", "fr", "hy", "it", "ka", "kk", "tg", "tk", "tr", "uz" };
    var discovered = Language.all_cases ();
    foreach (var code in expected_codes) {
        var found = false;
        foreach (var candidate in discovered) {
            if (candidate.to_raw () == code) found = true;
        }
        assert_true (found, "language discovered: " + code);
        var title = loc.string_for_key ("windowTitle", Language.get (code));
        assert_true (title != "" && title != "windowTitle", "translated title: " + code);
    }

    string[] name_codes = { "ru", "en", "de", "es", "fr", "it", "tr", "az", "kk", "uz", "hy", "ka", "tg", "tk" };
    string[] expected_names = { "Русский", "English", "Deutsch", "Español", "Français", "Italiano", "Türkçe", "Azərbaycan", "Қазақша", "Oʻzbekcha", "Հայերեն", "ქართული", "Тоҷикӣ", "Türkmençe" };
    for (var i = 0; i < name_codes.length; i++) {
        assert_true (Language.get (name_codes[i]).display_name () == expected_names[i],
                     "localized language name: " + name_codes[i]);
    }

    assert_true (loc.string_for_key ("settingsThemeWood", ru_lang) == "Дерево", "RU wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", en_lang) == "Wood", "EN wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", de_lang) == "Holz", "DE wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", es_lang) == "Madera", "ES wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", Language.get ("fr")) == "Bois", "FR wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", Language.get ("it")) == "Legno", "IT wood theme");
    assert_true (loc.string_for_key ("settingsThemeWood", Language.get ("tr")) == "Ahşap", "TR wood theme");
    assert_true (loc.string_for_key ("settingsThemeMarble", de_lang) == "Marmor", "DE marble theme");
    assert_true (loc.string_for_key ("settingsThemeMarble", es_lang) == "Mármol", "ES marble theme");

    assert_true (loc.string_for_key ("statusRollOffAI", ru_lang) == "Розыгрыш хода\nИИ Бросил кубики",
                 "RU roll-off AI status");
    assert_true (loc.string_for_key ("statusRollOffAI", en_lang) == "First roll\nAI rolled the dice",
                 "EN roll-off AI status");
    foreach (var language in discovered) {
        var status = loc.string_for_key ("statusRollOffAI", language);
        assert_true (status != "" && status != "statusRollOffAI",
                     "translated roll-off status: " + language.to_raw ());

        var game_settings = loc.string_for_key ("settingsGameSettingsSection", language);
        assert_true (game_settings != "" && game_settings != "settingsGameSettingsSection",
                     "translated settingsGameSettingsSection: " + language.to_raw ());
        var side_label = loc.string_for_key ("settingsBoardSideLabel", language);
        assert_true (side_label != "" && side_label != "settingsBoardSideLabel",
                     "translated settingsBoardSideLabel: " + language.to_raw ());
        var side_left = BoardSide.LEFT.display_name (language);
        assert_true (side_left != "" && side_left != "settingsBoardSideLeft",
                     "translated settingsBoardSideLeft: " + language.to_raw ());
        var side_right = BoardSide.RIGHT.display_name (language);
        assert_true (side_right != "" && side_right != "settingsBoardSideRight",
                     "translated settingsBoardSideRight: " + language.to_raw ());
    }

    // Проверка визуального переворота доски (BoardSide.RIGHT vs BoardSide.LEFT)
    assert_true (BoardLayout.visual_point (BoardPoint.P24, BoardSide.RIGHT) == BoardPoint.P24, "visual_point P24 right");
    assert_true (BoardLayout.visual_point (BoardPoint.P24, BoardSide.LEFT) == BoardPoint.P12, "visual_point P24 left");
    assert_true (BoardLayout.visual_point (BoardPoint.P12, BoardSide.LEFT) == BoardPoint.P24, "visual_point P12 left");
    assert_true (BoardLayout.visual_point (BoardPoint.P1, BoardSide.LEFT) == BoardPoint.P13, "visual_point P1 left");
    assert_true (BoardLayout.visual_point (BoardPoint.P13, BoardSide.LEFT) == BoardPoint.P1, "visual_point P13 left");

    assert_true (BoardPoint.P24.is_top_half_for (BoardSide.RIGHT), "P24 top half on right");
    assert_true (!BoardPoint.P24.is_top_half_for (BoardSide.LEFT), "P24 bottom half on left");
    assert_equal_int (BoardPoint.P24.stack_direction_for (BoardSide.RIGHT), 1, "P24 stack dir right");
    assert_equal_int (BoardPoint.P24.stack_direction_for (BoardSide.LEFT), -1, "P24 stack dir left");

    assert_true (BoardLayout.is_player_on_right_side (CheckerColor.WHITE, BoardSide.RIGHT), "White on right when RIGHT");
    assert_true (!BoardLayout.is_player_on_right_side (CheckerColor.BLACK, BoardSide.RIGHT), "Black on left when RIGHT");
    assert_true (!BoardLayout.is_player_on_right_side (CheckerColor.WHITE, BoardSide.LEFT), "White on left when LEFT");
    assert_true (BoardLayout.is_player_on_right_side (CheckerColor.BLACK, BoardSide.LEFT), "Black on right when LEFT");

    double rx, ry, lx, ly;
    BoardLayout.bear_off_position (CheckerColor.WHITE, 0, 1.0, out rx, out ry, BoardSide.RIGHT);
    BoardLayout.bear_off_position (CheckerColor.BLACK, 0, 1.0, out lx, out ly, BoardSide.LEFT);
    assert_true (Math.fabs (rx - lx) < 1e-6 && Math.fabs (ry - ly) < 1e-6, "bear_off right side matches for White(RIGHT) and Black(LEFT)");

    // Проверка инвариантности игровой логики и ИИ от выбранной стороны доски
    var saved_side = SettingsStore.shared ().board_side;
    SettingsStore.shared ().set_board_side (BoardSide.RIGHT);
    var moves_right = MoveValidator.all_moves (init_board, CheckerColor.WHITE, new int[] { 6, 5 }, 0, false, false);
    SettingsStore.shared ().set_board_side (BoardSide.LEFT);
    var moves_left = MoveValidator.all_moves (init_board, CheckerColor.WHITE, new int[] { 6, 5 }, 0, false, false);
    SettingsStore.shared ().set_board_side (saved_side);
    assert_equal_int (moves_right.length, moves_left.length, "MoveValidator count invariant to board_side");

    // =========================================================================
    // SUITE 8: AdvancedAITests
    // =========================================================================
    // Сценарий turn39: ИИ обязан выбрать старший кубик 5 и пойти 12 -> 7
    var ai_b = new GameBoard ();
    ai_b.set_stack (BoardPoint.P1, CheckerColor.WHITE, new uint8[] { 0, 1 });
    ai_b.set_stack (BoardPoint.P2, CheckerColor.WHITE, new uint8[] { 2, 3 });
    ai_b.set_stack (BoardPoint.P3, CheckerColor.WHITE, new uint8[] { 4, 5 });
    ai_b.set_stack (BoardPoint.P4, CheckerColor.WHITE, new uint8[] { 6, 7, 8 });
    ai_b.set_stack (BoardPoint.P5, CheckerColor.WHITE, new uint8[] { 9, 10 });
    ai_b.set_stack (BoardPoint.P6, CheckerColor.WHITE, new uint8[] { 11, 12 });
    ai_b.set_stack (BoardPoint.P8, CheckerColor.WHITE, new uint8[] { 13 });
    ai_b.set_stack (BoardPoint.P9, CheckerColor.WHITE, new uint8[] { 14 });

    var blk_12 = new uint8[11];
    for (var i = 0; i < 11; i++) blk_12[i] = (uint8) (15 + i);
    ai_b.set_stack (BoardPoint.P12, CheckerColor.BLACK, blk_12);

    var blk_13 = new uint8[4];
    for (var i = 0; i < 4; i++) blk_13[i] = (uint8) (26 + i);
    ai_b.set_stack (BoardPoint.P13, CheckerColor.BLACK, blk_13);

    int[] ai_dice = { 5, 1 };
    var raw_moves = MoveValidator.all_moves (ai_b, CheckerColor.BLACK, ai_dice, 0, false, false);
    var chosen = AdvancedAI.choose_move (raw_moves, ai_b, CheckerColor.BLACK, ai_dice);

    assert_true (chosen != null, "AdvancedAI chosen move != null");
    if (chosen != null) {
        assert_equal_int (chosen.die, 5, "AdvancedAI must choose die 5 on turn 39");
        assert_true (chosen.to == BoardPoint.P7, "AdvancedAI must move 12->7");

        var rem = AdvancedAI.remaining_dice_after (chosen, ai_dice);
        assert_equal_int (rem.length, 1, "remaining dice count == 1");
        assert_equal_int (rem[0], 1, "remaining die value == 1");
    }

    // Сценарий turn5: удержание сплошного забора 8-9-10 (сыграв 8->3 и 12->8)
    var t5_board = new GameBoard ();
    var w_t5 = new uint8[11];
    for (var i = 0; i < 11; i++) w_t5[i] = (uint8) i;
    t5_board.set_stack (BoardPoint.P24, CheckerColor.WHITE, w_t5);
    t5_board.set_stack (BoardPoint.P21, CheckerColor.WHITE, new uint8[] { 11 });
    t5_board.set_stack (BoardPoint.P20, CheckerColor.WHITE, new uint8[] { 12 });
    t5_board.set_stack (BoardPoint.P19, CheckerColor.WHITE, new uint8[] { 13 });
    t5_board.set_stack (BoardPoint.P7, CheckerColor.WHITE, new uint8[] { 14 });

    var b_t5 = new uint8[11];
    for (var i = 0; i < 11; i++) b_t5[i] = (uint8) (15 + i);
    t5_board.set_stack (BoardPoint.P12, CheckerColor.BLACK, b_t5);
    t5_board.set_stack (BoardPoint.P10, CheckerColor.BLACK, new uint8[] { 26 });
    t5_board.set_stack (BoardPoint.P9, CheckerColor.BLACK, new uint8[] { 27 });
    t5_board.set_stack (BoardPoint.P8, CheckerColor.BLACK, new uint8[] { 28 });
    t5_board.set_stack (BoardPoint.P23, CheckerColor.BLACK, new uint8[] { 29 });

    int[] t5_dice = { 4, 5 };
    var cur_b = t5_board;
    var rem_d = t5_dice;
    var head_cnt = 0;
    while (rem_d.length > 0) {
        var mvs = MoveValidator.all_moves (cur_b, CheckerColor.BLACK, rem_d, head_cnt, false, false);
        var chosen_t5 = AdvancedAI.choose_move (mvs, cur_b, CheckerColor.BLACK, rem_d);
        if (chosen_t5 == null) break;
        cur_b.move_one_checker (chosen_t5.from, chosen_t5.to);
        rem_d = AdvancedAI.remaining_dice_after (chosen_t5, rem_d);
        if (MoveValidator.is_head (chosen_t5.from, CheckerColor.BLACK)) head_cnt++;
    }
    var st9 = cur_b.stack_at (BoardPoint.P9);
    var st8 = cur_b.stack_at (BoardPoint.P8);
    assert_true (st9 != null && st9.color == CheckerColor.BLACK, "turn5: AI retains point 9");
    assert_true (st8 != null && st8.color == CheckerColor.BLACK, "turn5: AI retains point 8");
    assert_equal_int (st8 != null ? st8.checker_ids.length : 0, 1, "turn5: point 8 has 1 checker");

    var pip_w = AdvancedAI.calculate_pip_count (init_board, CheckerColor.WHITE);
    var pip_b = AdvancedAI.calculate_pip_count (init_board, CheckerColor.BLACK);
    assert_equal_int (pip_w, 360, "initial white pip count == 360");
    assert_equal_int (pip_b, 360, "initial black pip count == 360");

    var score_initial = AdvancedAI.evaluate_board (init_board, CheckerColor.WHITE);
    assert_true (!score_initial.is_nan () && score_initial.is_infinity () == 0,
                 "evaluate_board initial score is finite number");

    // =========================================================================
    // Финальный отчет
    // =========================================================================
    if (failed == 0) {
        stdout.printf ("ALL %d LOGIC ASSERTIONS PASSED OK\n", test_count);
        return 0;
    }
    stderr.printf ("logic_test FAILED with %d error(s) out of %d assertions\n", failed, test_count);
    return 1;
    }
}

int main (string[] args) {
    return LogicTestSuite.run ();
}
