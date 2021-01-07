pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";
import {Vat}              from "dss/vat.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai}              from "dss/dai.sol";
import {Cat}              from "dss/cat.sol";

import "./psm.sol";
import "./psmflip.sol";
import "./join-5-auth.sol";
import "./join-5.sol";
import "./lerp.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestToken is DSToken {

    constructor(bytes32 symbol_, uint256 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }

}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract TestVow is Vow {
    constructor(address vat, address flapper, address flopper)
        public Vow(vat, flapper, flopper) {}
    // Total deficit
    function Awe() public view returns (uint256) {
        return vat.sin(address(this));
    }
    // Total surplus
    function Joy() public view returns (uint256) {
        return vat.dai(address(this));
    }
    // Unqueued, pre-auction debt
    function Woe() public view returns (uint256) {
        return sub(sub(Awe(), Sin), Ash);
    }
}

contract User {

    Dai public dai;
    AuthGemJoin5 public gemJoin;
    DssPsm public psm;

    constructor(Dai dai_, AuthGemJoin5 gemJoin_, DssPsm psm_) public {
        dai = dai_;
        gemJoin = gemJoin_;
        psm = psm_;
    }

    function sellGem(uint256 wad) public {
        DSToken(address(gemJoin.gem())).approve(address(gemJoin));
        psm.sellGem(address(this), wad);
    }

    function buyGem(uint256 wad) public {
        dai.approve(address(psm), uint256(-1));
        psm.buyGem(address(this), wad);
    }

}

contract DssPsmTest is DSTest {
    
    Hevm hevm;

    address me;

    TestVat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    TestToken usdx;
    DaiJoin daiJoin;
    Dai dai;
    Cat cat;

    AuthGemJoin5 gemA;
    DssPsm psmA;
    PsmFlipper flip;

    GemJoin5 gemB;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "usdx-psm";
    bytes32 constant ilkNonPsm = "usdx";

    uint256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant USDX_WAD = 10 ** 6;
    uint256 constant WAD = 10 ** 18;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new TestVat();
        vat = vat;

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        cat = new Cat(address(vat));
        cat.file("vow", address(vow));
        cat.file("box", rad(2000 ether));
        cat.file(ilkNonPsm, "chop", 113 * WAD / 100);
        cat.file(ilkNonPsm, "dunk", rad(50000 ether));
        vat.rely(address(cat));

        usdx = new TestToken("USDX", 6);
        usdx.mint(1000 * USDX_WAD);

        vat.init(ilk);

        gemA = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(gemA));

        gemB = new GemJoin5(address(vat), ilkNonPsm, address(usdx));
        vat.rely(address(gemB));

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        psmA = new DssPsm(address(gemA), address(daiJoin), address(vow));
        gemA.rely(address(psmA));
        gemA.deny(me);

        flip = new PsmFlipper(PsmLike(address(psmA)), address(cat));
        cat.file(ilkNonPsm, "flip", address(flip));

        pip = new DSValue();
        pip.poke(bytes32(uint256(1 ether))); // Spot = $1

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(1 ether));
        spot.poke(ilk);

        spot.file(ilkNonPsm, bytes32("pip"), address(pip));
        spot.file(ilkNonPsm, bytes32("mat"), ray(101 * (1 ether) / 100));
        spot.poke(ilkNonPsm);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file(ilkNonPsm, "line", rad(1000 ether));
        vat.file("Line",      rad(2000 ether));
    }

    function test_sellGem_no_fee() public {
        assertEq(usdx.balanceOf(me), 1000 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 0);
        assertEq(vow.Joy(), 0);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 900 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(vow.Joy(), 0);
        (uint256 inkme, uint256 artme) = vat.urns(ilk, me);
        assertEq(inkme, 0);
        assertEq(artme, 0);
        (uint256 inkpsm, uint256 artpsm) = vat.urns(ilk, address(psmA));
        assertEq(inkpsm, 100 ether);
        assertEq(artpsm, 100 ether);
    }

    function test_sellGem_fee() public {
        psmA.file("tin", TOLL_ONE_PCT);

        assertEq(usdx.balanceOf(me), 1000 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 0);
        assertEq(vow.Joy(), 0);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 900 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 99 ether);
        assertEq(vow.Joy(), rad(1 ether));
    }

    function test_swap_both_no_fee() public {
        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * USDX_WAD);
        dai.approve(address(psmA), 40 ether);
        psmA.buyGem(me, 40 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 940 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 60 ether);
        assertEq(vow.Joy(), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function test_swap_both_fees() public {
        psmA.file("tin", 5 * TOLL_ONE_PCT);
        psmA.file("tout", 10 * TOLL_ONE_PCT);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 900 * USDX_WAD);
        assertEq(dai.balanceOf(me), 95 ether);
        assertEq(vow.Joy(), rad(5 ether));
        (uint256 ink1, uint256 art1) = vat.urns(ilk, address(psmA));
        assertEq(ink1, 100 ether);
        assertEq(art1, 100 ether);

        dai.approve(address(psmA), 44 ether);
        psmA.buyGem(me, 40 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 940 * USDX_WAD);
        assertEq(dai.balanceOf(me), 51 ether);
        assertEq(vow.Joy(), rad(9 ether));
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(psmA));
        assertEq(ink2, 60 ether);
        assertEq(art2, 60 ether);
    }

    function test_swap_both_other() public {
        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 900 * USDX_WAD);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(vow.Joy(), rad(0 ether));

        User someUser = new User(dai, gemA, psmA);
        dai.mint(address(someUser), 45 ether);
        someUser.buyGem(40 * USDX_WAD);

        assertEq(usdx.balanceOf(me), 900 * USDX_WAD);
        assertEq(usdx.balanceOf(address(someUser)), 40 * USDX_WAD);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.gem(ilk, address(someUser)), 0 ether);
        assertEq(vat.dai(me), 0);
        assertEq(vat.dai(address(someUser)), 0);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(dai.balanceOf(address(someUser)), 5 ether);
        assertEq(vow.Joy(), rad(0 ether));
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function test_swap_both_other_small_fee() public {
        psmA.file("tin", 1);

        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * USDX_WAD);
        user1.sellGem(40 * USDX_WAD);

        assertEq(usdx.balanceOf(address(user1)), 0 * USDX_WAD);
        assertEq(dai.balanceOf(address(user1)), 40 ether - 40);
        assertEq(vow.Joy(), rad(40));
        (uint256 ink1, uint256 art1) = vat.urns(ilk, address(psmA));
        assertEq(ink1, 40 ether);
        assertEq(art1, 40 ether);

        user1.buyGem(40 * USDX_WAD - 1);

        assertEq(usdx.balanceOf(address(user1)), 40 * USDX_WAD - 1);
        assertEq(dai.balanceOf(address(user1)), 999999999960);
        assertEq(vow.Joy(), rad(40));
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(psmA));
        assertEq(ink2, 1 * 10 ** 12);
        assertEq(art2, 1 * 10 ** 12);
    }

    function testFail_sellGem_insufficient_gem() public {
        User user1 = new User(dai, gemA, psmA);
        user1.sellGem(40 * USDX_WAD);
    }

    function testFail_swap_both_small_fee_insufficient_dai() public {
        psmA.file("tin", 1);        // Very small fee pushes you over the edge

        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * USDX_WAD);
        user1.sellGem(40 * USDX_WAD);
        user1.buyGem(40 * USDX_WAD);
    }

    function testFail_sellGem_over_line() public {
        usdx.mint(1000 * USDX_WAD);
        usdx.approve(address(gemA));
        psmA.buyGem(me, 2000 * USDX_WAD);
    }

    function testFail_two_users_insufficient_dai() public {
        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * USDX_WAD);
        user1.sellGem(40 * USDX_WAD);

        User user2 = new User(dai, gemA, psmA);
        dai.mint(address(user2), 39 ether);
        user2.buyGem(40 * USDX_WAD);
    }

    function test_swap_both_zero() public {
        usdx.approve(address(gemA), uint(-1));
        psmA.sellGem(me, 0);
        dai.approve(address(psmA), uint(-1));
        psmA.buyGem(me, 0);
    }

    function testFail_direct_deposit() public {
        usdx.approve(address(gemA), uint(-1));
        gemA.join(me, 10 * USDX_WAD, me);
    }

    function test_lerp_tin() public {
        Lerp lerp = new Lerp(address(psmA), "tin", 1 * TOLL_ONE_PCT, 1 * TOLL_ONE_PCT / 10, 9 days);
        assertEq(lerp.what(), "tin");
        assertEq(lerp.start(), 1 * TOLL_ONE_PCT);
        assertEq(lerp.end(), 1 * TOLL_ONE_PCT / 10);
        assertEq(lerp.duration(), 9 days);
        assertTrue(!lerp.started());
        assertTrue(!lerp.done());
        assertEq(lerp.startTime(), 0);
        assertEq(psmA.tin(), 0);
        psmA.rely(address(lerp));
        lerp.init();
        assertTrue(lerp.started());
        assertTrue(!lerp.done());
        assertEq(lerp.startTime(), block.timestamp);
        assertEq(psmA.tin(), 1 * TOLL_ONE_PCT);
        hevm.warp(1 days);
        assertEq(psmA.tin(), 1 * TOLL_ONE_PCT);
        lerp.tick();
        assertEq(psmA.tin(), 9 * TOLL_ONE_PCT / 10);    // 0.9%
        hevm.warp(2 days);
        lerp.tick();
        assertEq(psmA.tin(), 8 * TOLL_ONE_PCT / 10);    // 0.8%
        hevm.warp(2 days + 12 hours);
        lerp.tick();
        assertEq(psmA.tin(), 75 * TOLL_ONE_PCT / 100);    // 0.75%
        hevm.warp(12 days);
        assertEq(psmA.wards(address(lerp)), 1);
        lerp.tick();
        assertEq(psmA.tin(), 1 * TOLL_ONE_PCT / 10);    // 0.1%
        assertTrue(lerp.done());
        assertEq(psmA.wards(address(lerp)), 0);
    }
    
}
