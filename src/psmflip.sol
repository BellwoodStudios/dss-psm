pragma solidity ^0.6.7;

import { CatAbstract } from "dss-interfaces/dss/CatAbstract.sol";
import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";

interface PsmLike {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
}

// PSM Flipper
// Liquidate a collateral of the same type into the PSM

contract PsmFlipper {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth { require(wards[msg.sender] == 1); _; }

    VatAbstract immutable public vat;
    address immutable public psm;
    bytes32 immutable public ilk;
    CatAbstract immutable public cat;
    uint256 public kicks = 0;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kick(
        uint256 id,
        uint256 lot,
        uint256 bid,
        uint256 tab,
        address indexed usr,
        address indexed gal
    );

    // --- Init ---
    constructor(PsmLike psm_, address cat_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        psm = address(psm_);
        vat = VatAbstract(psm_.vat());
        ilk = psm_.ilk();
        cat = CatAbstract(cat_);
    }

    // --- Kick ---
    function kick(address usr, address gal, uint256 tab, uint256 lot, uint256 bid)
        external auth returns (uint256 id)
    {
        require(kicks < uint256(-1), "PsmFlipper/overflow");
        id = ++kicks;

        vat.frob(ilk, psm, address(msg.sender), address(gal), int256(lot), int256(lot));
        cat.claw(tab);

        emit Kick(id, lot, bid, tab, usr, gal);
    }

}
