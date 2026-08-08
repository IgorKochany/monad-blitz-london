// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RideMarket} from "../src/RideMarket.sol";

contract RideMarketTest is Test {
    RideMarket market;

    address rider  = makeAddr("rider");
    address driver = makeAddr("driver");

    function setUp() public {
        market = new RideMarket();
        vm.deal(rider, 100 ether);
        vm.deal(driver, 100 ether);
    }

    /// Happy path: review-bids mode. post -> bid -> acceptBid -> completeRide.
    /// Rider pays exactly the agreed price; driver receives it.
    function test_ReviewFlow_PostBidAcceptComplete() public {
        uint256 expiry = block.timestamp + 1 hours;

        // Rider posts with NO escrow (maxPrice 0 => manual review).
        vm.prank(rider);
        uint256 rideId = market.postRide("Shoreditch @51.5246,-0.0795", "Canary Wharf @51.5054,-0.0235", 0, expiry);

        // Driver bids 5 MON.
        uint256 price = 5 ether;
        vm.prank(driver);
        market.bid(rideId, price, block.timestamp + 30 minutes);
        assertEq(market.bidCount(rideId), 1);

        // Rider accepts bid 0, escrowing the price now.
        uint256 riderBefore = rider.balance;
        vm.prank(rider);
        market.acceptBid{value: price}(rideId, 0);
        assertEq(rider.balance, riderBefore - price, "rider debited exactly price");

        // Rider confirms completion -> driver paid.
        uint256 driverBefore = driver.balance;
        vm.prank(rider);
        market.completeRide(rideId);
        assertEq(driver.balance, driverBefore + price, "driver paid escrow");
    }

    /// Auto-accept path: rider escrows a max price; a bid at/under it matches
    /// instantly and the difference is refunded to the rider.
    function test_AutoAccept_InstantMatchWithRefund() public {
        uint256 maxPrice = 10 ether;
        uint256 expiry = block.timestamp + 1 hours;

        vm.prank(rider);
        uint256 rideId = market.postRide{value: maxPrice}("A @0,0", "B @1,1", maxPrice, expiry);

        // Driver underbids at 7 MON => instant match, 3 MON refunded to rider.
        uint256 bidPrice = 7 ether;
        uint256 riderBefore = rider.balance;
        vm.prank(driver);
        market.bid(rideId, bidPrice, block.timestamp + 30 minutes);

        // Refund of (10 - 7) = 3 landed back with the rider.
        assertEq(rider.balance, riderBefore + (maxPrice - bidPrice), "excess refunded");

        (, , , , , RideMarket.Status status, address matchedDriver, uint256 agreed, uint256 deposit) = market.rides(rideId);
        assertEq(uint256(status), uint256(RideMarket.Status.Matched), "matched");
        assertEq(matchedDriver, driver, "driver matched");
        assertEq(agreed, bidPrice, "agreed price = bid");
        assertEq(deposit, bidPrice, "deposit trimmed to bid");

        // Completion pays the driver exactly the bid price.
        uint256 driverBefore = driver.balance;
        vm.prank(rider);
        market.completeRide(rideId);
        assertEq(driver.balance, driverBefore + bidPrice, "driver paid");
    }

    /// Expiry: once a ride's window passes, new bids revert.
    function test_Bid_RevertsAfterExpiry() public {
        uint256 expiry = block.timestamp + 1 hours;
        vm.prank(rider);
        uint256 rideId = market.postRide("A @0,0", "B @1,1", 0, expiry);

        // Jump past the ride expiry.
        vm.warp(expiry + 1);

        vm.prank(driver);
        vm.expectRevert(bytes("ride expired"));
        market.bid(rideId, 5 ether, block.timestamp + 30 minutes);
    }
}
