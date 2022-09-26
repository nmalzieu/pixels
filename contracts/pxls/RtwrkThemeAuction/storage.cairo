%lang starknet
from pxls.RtwrkThemeAuction.bid import Bid

//
// Storage
//

// This is the address of the Rtwrk drawer contract
@storage_var
func rtwrk_drawer_address() -> (address: felt) {
}

// This is the address of the Rtwrk NFT contract
@storage_var
func rtwrk_erc721_address() -> (address: felt) {
}

// Store the last (= current if < 24hours) auction id
@storage_var
func current_auction_id() -> (auction_id: felt) {
}

// Store the timestamp of the start of an auction
@storage_var
func auction_timestamp(auction_id) -> (timestamp: felt) {
}

// Store the amount of a bid
@storage_var
func bid_amount(auction_id, bid_index) -> (amount: felt) {
}

// Store the account that does of a bid
@storage_var
func bid_account(auction_id, bid_index) -> (account: felt) {
}

// Store the theme of a bid (may be multiple felts)
@storage_var
func bid_theme(auction_id, bid_index, theme_index) -> (theme_part: felt) {
}
