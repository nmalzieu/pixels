%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_eq
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_write, dict_read

from pxls.utils.colors import Color
from pxls.PixelDrawer.storage import (
    drawing_user_colorizations,
    max_colorizations_per_token,
    number_of_colorizations_per_token,
    number_of_colorizations_total,
    drawing_user_colorizations_index,
)

const MAX_PIXEL_VALUE = 399;  // grid of 400 pixels from 0 to 399
const MAX_COLOR_VALUE = 94;  // palette of 95 colors from 0 to 94
const MAX_COLORIZATION_VALUE = MAX_PIXEL_VALUE * (MAX_COLOR_VALUE + 1) + MAX_COLOR_VALUE;
const MAX_COLORIZATIONS_PER_FELT = 8;  // There is space to store more, but we can't unpack due to div_rem bounds
const NUMBER_OF_PIXELS = 400;
const MAX_TOTAL_COLORIZATIONS = 2000;  // For performance limit to reconstitute grid

struct Colorization {
    pixel_index: felt,
    color_index: felt,
}

struct UserColorizations {
    token_id: Uint256,
    colorizations_len: felt,
    colorizations: Colorization*,
}

func pack_colorization{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorization: Colorization
) -> (pixel_colorization_packed: felt) {
    with_attr error_message("Color index is out of bounds") {
        assert_le(colorization.color_index, MAX_COLOR_VALUE);
    }
    with_attr error_message("Pixel index is out of bounds") {
        assert_le(colorization.pixel_index, MAX_PIXEL_VALUE);
    }
    let colorization_packed = colorization.pixel_index * (MAX_COLOR_VALUE + 1) + colorization.color_index;
    return (pixel_colorization_packed=colorization_packed);
}

func unpack_colorization{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    pixel_colorization_packed: felt
) -> (colorization: Colorization) {
    let (pixel_index, color_index) = unsigned_div_rem(
        pixel_colorization_packed, MAX_COLOR_VALUE + 1
    );
    return (colorization=Colorization(pixel_index, color_index));
}

func pack_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorizations_len: felt, colorizations: Colorization*, current_packed: felt
) -> (colorizations_packed: felt) {
    alloc_locals;
    if (colorizations_len == 0) {
        return (colorizations_packed=current_packed);
    }
    let (colorization_packed) = pack_colorization(colorizations[0]);
    let new_packed = current_packed * (MAX_COLORIZATION_VALUE + 1) + colorization_packed;
    return pack_colorizations(colorizations_len - 1, colorizations + Colorization.SIZE, new_packed);
}

func unpack_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorizations_packed: felt
) -> (colorizations_len: felt, colorizations: Colorization*) {
    alloc_locals;

    let (colorizations: Colorization*) = alloc();
    let (colorizations_len) = _unpack_colorizations(colorizations_packed, 0, colorizations);

    return reverse_colorizations(colorizations_len, colorizations);
}

func _unpack_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorizations_packed: felt, colorizations_len: felt, colorizations: Colorization*
) -> (colorizations_len: felt) {
    let (rest_packed, colorization_packed) = unsigned_div_rem(
        colorizations_packed, MAX_COLORIZATION_VALUE + 1
    );

    let (colorization: Colorization) = unpack_colorization(colorization_packed);
    assert colorizations[colorizations_len] = colorization;

    if (rest_packed == 0) {
        return (colorizations_len + 1,);
    }

    return _unpack_colorizations(rest_packed, colorizations_len + 1, colorizations);
}

func pack_user_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    user_colorizations: UserColorizations
) -> (user_colorizations_packed: felt) {
    let (colorizations_packed) = pack_colorizations(
        user_colorizations.colorizations_len, user_colorizations.colorizations, 0
    );
    let user_colorizations_packed = colorizations_packed * (MAX_PIXEL_VALUE + 1) + user_colorizations.token_id.low;
    return (user_colorizations_packed=user_colorizations_packed);
}

func unpack_user_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    user_colorizations_packed
) -> (user_colorizations: UserColorizations) {
    alloc_locals;
    let (rest_packed, token_id_low) = unsigned_div_rem(
        user_colorizations_packed, MAX_PIXEL_VALUE + 1
    );
    let (colorizations_len: felt, colorizations: Colorization*) = unpack_colorizations(rest_packed);
    return (UserColorizations(Uint256(token_id_low, 0), colorizations_len, colorizations),);
}

func get_all_drawing_user_colorizations{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr
}(drawing_round: felt, step: felt) -> (
    user_colorizations_len: felt, user_colorizations: UserColorizations*
) {
    let (user_colorizations: UserColorizations*) = alloc();
    return _get_all_drawing_user_colorizations(drawing_round, 0, user_colorizations, step);
}

func _get_all_drawing_user_colorizations{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr
}(
    drawing_round: felt,
    user_colorizations_len: felt,
    user_colorizations: UserColorizations*,
    step: felt,
) -> (user_colorizations_len: felt, user_colorizations: UserColorizations*) {
    alloc_locals;
    let (storage_user_colorizations_packed) = drawing_user_colorizations.read(
        drawing_round, user_colorizations_len
    );
    // We reached the end of the colorizations array
    if (storage_user_colorizations_packed == 0) {
        return (user_colorizations_len, user_colorizations);
    }
    // If we provided a step, let's stop at this step
    if (user_colorizations_len != 0) {
        if (user_colorizations_len == step) {
            return (user_colorizations_len, user_colorizations);
        }
    }
    let (unpacked_user_colorizations: UserColorizations) = unpack_user_colorizations(
        storage_user_colorizations_packed
    );
    assert user_colorizations[user_colorizations_len] = unpacked_user_colorizations;
    return _get_all_drawing_user_colorizations(
        drawing_round, user_colorizations_len + 1, user_colorizations, step
    );
}

func save_drawing_user_colorizations{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr
}(drawing_round: felt, token_id: Uint256, colorizations_len: felt, colorizations: Colorization*) {
    alloc_locals;
    // First find # of already saved slots
    let (stored_user_colorizations_len: felt) = drawing_user_colorizations_index.read(
        drawing_round
    );
    // Then # of colorizations done by this token
    let (colorizations_from_this_token_id) = number_of_colorizations_per_token.read(
        drawing_round, token_id
    );
    // Then total # of colorizations for all tokens
    let (total_colorizations_count) = number_of_colorizations_total.read(drawing_round);
    // Then max colorizations allowed per token
    let (max_token_colorizations) = max_colorizations_per_token.read();
    let colorizations_remaining = max_token_colorizations - colorizations_from_this_token_id;
    with_attr error_message(
            "You have reached the max number of allowed colorizations for this round") {
        assert_le(colorizations_len, colorizations_remaining);
    }

    // Then total max colorizations allowed
    let total_colorizations_remaining = MAX_TOTAL_COLORIZATIONS - total_colorizations_count;
    with_attr error_message(
            "The max total number of allowed colorizations for this round has been reached") {
        assert_le(colorizations_len, total_colorizations_remaining);
    }

    // We can pack up to 8 colorizations per felt so we need to split
    save_user_colorizations_per_batch(
        drawing_round, token_id, colorizations_len, colorizations, stored_user_colorizations_len
    );
    number_of_colorizations_per_token.write(
        drawing_round, token_id, colorizations_from_this_token_id + colorizations_len
    );
    number_of_colorizations_total.write(
        drawing_round, total_colorizations_count + colorizations_len
    );

    return ();
}

func save_user_colorizations_per_batch{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr
}(
    drawing_round: felt,
    token_id: Uint256,
    colorizations_len: felt,
    colorizations: Colorization*,
    already_stored_len: felt,
) {
    let (current_batch: Colorization*) = alloc();
    _save_user_colorizations_per_batch(
        drawing_round,
        token_id,
        colorizations_len,
        colorizations,
        already_stored_len,
        0,
        current_batch,
    );
    return ();
}

func should_save_to_slot{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    new_batch_len: felt, remaining_colorizations_len: felt
) -> (should_save: felt) {
    if (new_batch_len == MAX_COLORIZATIONS_PER_FELT) {
        return (TRUE,);
    }
    if (remaining_colorizations_len == 0) {
        let current_match_not_empty = is_le(1, new_batch_len);
        return (current_match_not_empty,);
    }
    return (FALSE,);
}

func _save_user_colorizations_per_batch{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr
}(
    drawing_round: felt,
    token_id: Uint256,
    remaining_colorizations_len: felt,
    remaining_colorizations: Colorization*,
    already_stored_len: felt,
    current_batch_len: felt,
    current_batch: Colorization*,
) {
    if (remaining_colorizations_len == 0) {
        // Saving the new index!
        drawing_user_colorizations_index.write(drawing_round, already_stored_len);
        return ();
    }

    // Need to append to current bach
    assert current_batch[current_batch_len] = remaining_colorizations[0];

    // We must save to a slot for two reasons:
    // - we have reached MAX_COLORIZATIONS_PER_FELT
    // - we have reached end of remaining colorizations and batch not empty

    let (should_save) = should_save_to_slot(current_batch_len + 1, remaining_colorizations_len - 1);

    if (should_save == TRUE) {
        // Pack in a single felt
        let (packed_value_to_save) = pack_user_colorizations(
            UserColorizations(token_id, current_batch_len + 1, current_batch)
        );
        // Save in a new slot
        drawing_user_colorizations.write(drawing_round, already_stored_len, packed_value_to_save);
        let (new_batch: Colorization*) = alloc();
        return _save_user_colorizations_per_batch(
            drawing_round,
            token_id,
            remaining_colorizations_len - 1,
            remaining_colorizations + Colorization.SIZE,
            already_stored_len + 1,
            0,
            new_batch,
        );
    } else {
        return _save_user_colorizations_per_batch(
            drawing_round,
            token_id,
            remaining_colorizations_len - 1,
            remaining_colorizations + Colorization.SIZE,
            already_stored_len,
            current_batch_len + 1,
            current_batch,
        );
    }
}

func reverse_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorizations_len: felt, colorizations: Colorization*
) -> (colorizations_len: felt, colorizations: Colorization*) {
    let (colorizations_reversed: Colorization*) = alloc();
    return _reverse_colorizations(colorizations_len, colorizations, 0, colorizations_reversed);
}

func _reverse_colorizations{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    colorizations_len: felt,
    colorizations: Colorization*,
    colorizations_reversed_len: felt,
    colorizations_reversed: Colorization*,
) -> (colorizations_len: felt, colorizations: Colorization*) {
    if (colorizations_len == 0) {
        return (colorizations_reversed_len, colorizations_reversed);
    }
    assert colorizations_reversed[colorizations_reversed_len] = colorizations[colorizations_len - 1];
    return _reverse_colorizations(
        colorizations_len - 1, colorizations, colorizations_reversed_len + 1, colorizations_reversed
    );
}

func get_number_of_colorizers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    drawing_round: felt, step: felt
) -> (count: felt) {
    alloc_locals;
    // Returns the number of tokenId (= number of people)
    // that did at least one colorization during a given round

    // First get all colorizations for this round
    let (
        user_colorizations_len: felt, user_colorizations: UserColorizations*
    ) = get_all_drawing_user_colorizations(drawing_round, step);

    let (token_id_has_colorizations: DictAccess*) = default_dict_new(default_value=FALSE);
    default_dict_finalize(token_id_has_colorizations, token_id_has_colorizations, FALSE);
    let (number_of_colorizers) = fill_colorizations_per_token_id(
        0, token_id_has_colorizations, user_colorizations_len, user_colorizations
    );
    return (number_of_colorizers,);
}

func fill_colorizations_per_token_id{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    number_of_colorizers: felt,
    token_id_has_colorizations: DictAccess*,
    user_colorizations_len: felt,
    user_colorizations: UserColorizations*,
) -> (number_of_colorizers: felt) {
    if (user_colorizations_len == 0) {
        return (number_of_colorizers,);
    }
    let token_id = user_colorizations[0].token_id;
    let (token_has_already_colorized) = dict_read{dict_ptr=token_id_has_colorizations}(
        key=token_id.low
    );
    if (token_has_already_colorized == TRUE) {
        return fill_colorizations_per_token_id(
            number_of_colorizers,
            token_id_has_colorizations,
            user_colorizations_len - 1,
            user_colorizations + UserColorizations.SIZE,
        );
    } else {
        dict_write{dict_ptr=token_id_has_colorizations}(key=token_id.low, new_value=TRUE);
        return fill_colorizations_per_token_id(
            number_of_colorizers + 1,
            token_id_has_colorizations,
            user_colorizations_len - 1,
            user_colorizations + UserColorizations.SIZE,
        );
    }
}
