/* ai_weights.vala
 *
 * Весовые коэффициенты и константы функций оценки позиции для ИИ (уровень «Гроссмейстер»).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class AIWeights {
    private static AIWeights? _defaults = null;

    /** Веса по умолчанию (синглтон). */
    public static AIWeights default_weights () {
        if (_defaults == null) {
            _defaults = new AIWeights ();
        }
        return _defaults;
    }

    // MARK: - Opponent Reply Score (антиципация ответа соперника)
    public double opp_reply_bear_off_bonus = 8000000.0;
    public double opp_reply_bear_off_progress_mult = 150000.0;
    public double opp_reply_progress_mult = 120000.0;
    public double opp_reply_move_from_head_bonus = 700000.0;
    public double opp_reply_move_into_home_bonus = 450000.0;
    public double opp_reply_target_stack1_bonus = 500000.0;
    public double opp_reply_target_stack2_bonus = 250000.0;
    public double opp_reply_target_stack4_plus_penalty = 500000.0;
    public double opp_reply_prime_inc_delta_mult = 900000.0;
    public double opp_reply_prime_inc_square_mult = 90000.0;
    public double opp_reply_prime5_plus_bonus = 1000000.0;
    public double opp_reply_occupied_inc_bonus = 700000.0;
    public double opp_reply_connectivity_mult = 100000.0;
    public double opp_reply_lets_trap_tail_penalty = 5000000.0;
    public double opp_reply_head_block_penalty = 350000.0;
    public double opp_reply_tail_distance_bonus_mult = 200000.0;

    // MARK: - Future Flexibility Score
    public double flex_moves_count_mult = 45000.0;
    public double flex_blocked_rolls_penalty = 900000.0;

    // MARK: - Endgame Turn Plan
    public double endgame_plan_entries_mult = 10000000.0;
    public double endgame_plan_outside_after_penalty = 1800000.0;
    public double endgame_plan_outside_pip_after_penalty = 450000.0;
    public double endgame_plan_total_pip_after_penalty = 35000.0;
    public double endgame_plan_home_depth_after_bonus = 12000.0;
    public double endgame_plan_home_only_moves_penalty = 2500000.0;

    // MARK: - Bear-Off
    public double bear_off_all_in_home_bonus = 15000000.0;
    public double bear_off_combined_penalty = 500000.0;
    public double bear_off_dist_to_finish_mult = 100000.0;
    public double bear_off_point123_penalty_mult = 80000.0;
    public double bear_off_before_all_in_home_penalty = 10000000.0;

    // MARK: - Endgame
    public double endgame_total_entries_mult = 7000000.0;
    public double endgame_no_entries_penalty = 3000000.0;
    public double endgame_combined_one_entry_penalty_mult = 4000000.0;
    public double endgame_move_inside_home_penalty = 7000000.0;
    public double endgame_move_min_idx_bonus = 6000000.0;
    public double endgame_move_min_idx_progress_mult = 350000.0;
    public double endgame_move_near_min_idx_bonus = 1000000.0;
    public double endgame_move_near_min_idx_progress_mult = 100000.0;
    public double endgame_move_far_from_min_idx_penalty_mult = 700000.0;
    public double endgame_move_to_home_bonus = 4500000.0;
    public double endgame_deep_home_bonus_mult = 600000.0;
    public double endgame_move_from_home_to_outside_penalty = 3000000.0;

    // MARK: - Opening & Midgame (Head)
    public double head_move_bonus = 12000000.0;
    public double head_stack_count_mult = 2000000.0;
    public double head_target_stack1_bonus = 1000000.0;
    public double head_target_stack2_bonus = 600000.0;
    public double head_target_stack3_plus_penalty_mult = 50000.0;
    public double head_target_empty_bonus = 2500000.0;
    public double head_move_to_opponent_half_bonus = 200000.0;
    public double head_move_to_opp_half_near_head_bonus = 250000.0;
    public double head_move_to_our_half_bonus = 50000.0;
    public double not_moving_from_head_penalty_mult = 3000000.0;

    // MARK: - Progress
    public double move_to_opp_half_first_time_bonus = 500000.0;
    public double checkers_on_opp_half_mult = 30000.0;
    public double move_to_opp_half_far_from_head_mult = 20000.0;
    public double midgame_progress_mult = 350000.0;

    // MARK: - Occupying Points
    public double occupy_new_point_bonus_target = 3000000.0;
    public double occupy_new_point_bonus_no_target = 1500000.0;
    public double tower_penalty_finishing = 300000.0;
    public double tower_penalty_normal = 5000000.0;
    public double tower4_plus_penalty_mult = 15000000.0;
    public double connectivity_midgame_mult = 250000.0;
// MARK: - Primes
    public double prime_break5_plus_penalty = 55000000.0;
    public double prime_square_mult = 300000.0;
    public double prime_block_opp_head16_bonus = 1500000.0;
    public double prime_block6_bonus = 15000000.0;
    public double prime_block5_bonus = 8000000.0;
    public double prime_block4_bonus = 3500000.0;
    public double prime_block3_bonus = 1000000.0;
    public double prime_block2_bonus = 300000.0;
    public double head_block2_bonus = 2500000.0;
    public double head_block1_bonus = 1000000.0;
    public double block_after_opponent6_bonus = 3000000.0;
    public double trapped_opponents_mult = 120000.0;

    // MARK: - Tail Progress
    public double tail_progress_min_idx_bonus = 800000.0;
    public double tail_progress_min_idx_mult = 100000.0;
    public double tail_progress_far_from_min_idx_penalty_mult = 30000.0;

    // MARK: - Blocking Opponent Prime
    public double block_opponent_prime3_plus_penalty_mult = 5000000.0;

    // MARK: - Dice Efficiency
    public double other_dice_move_bonus = 1000000.0;
    public double other_dice_no_move_penalty = 6000000.0;

    // MARK: - Danger of Empty Point
    public double empty_point_threat_mult = 2500000.0;
    public double empty_point_block_size2_penalty = 4000000.0;

    // MARK: - General Factors
    public double negative_progress_penalty = 1500000.0;
    public double progress6_plus_mult = 30000.0;
    public double empty_head_bonus = 100000.0;
    public double midgame_move_inside_home_penalty = 20000000.0;
    public double all_in_home_move_inside_home_penalty = 200000000.0;
    public double combined_move_all_in_home_penalty = 15000000.0;

    // MARK: - Tail Trapping
    public double not_saving_tail_penalty = 60000000.0;
    public double saving_tail_bonus = 45000000.0;
    public double saving_tail_progress_mult = 1000000.0;

    // MARK: - Opponent Pressure
    public double opp_pressure_endgame_mult = 0.45;
    public double opp_pressure_normal_mult = 0.75;
    public double flex_endgame_mult = 0.2;
    public double flex_normal_mult = 0.65;

    // MARK: - V4 Combined Move Penalty
    public double combined_move_penalty = 25000000.0;
}

} /* namespace Longbackgammon */