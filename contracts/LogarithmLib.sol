pragma solidity 0.5.13;

import "./FixidityLib.sol";

library LogarithmLib {
    using FixidityLib for FixidityLib.Fixidity;

    uint8 public constant longer_digits = 36;
    int256
        public constant longer_fixed_log_e_1_5 = 405465108108164381978013115464349137;
    int256
        public constant longer_fixed_1 = 1000000000000000000000000000000000000;
    int256
        public constant longer_fixed_log_e_10 = 2302585092994045684017991454684364208;

    function log_e(FixidityLib.Fixidity storage fixidity, int256 v)
        public
        view
        returns (int256)
    {
        require(v > 0, "v shoule be larger than 0");
        int256 r = 0;
        uint8 digits = fixidity.digits;
        int256 fixed_1 = fixidity.fixed_1;
        int256 fixed_e = fixidity.fixed_e;
        uint8 extra_digits = longer_digits - digits;
        int256 t = int256(uint256(10)**uint256(extra_digits));
        while (v <= fixed_1 / 10) {
            v = v * 10;
            r -= longer_fixed_log_e_10;
        }
        while (v >= 10 * fixed_1) {
            v = v / 10;
            r += longer_fixed_log_e_10;
        }
        while (v < fixed_1) {
            v = fixidity.multiply(v, fixed_e);
            r -= longer_fixed_1;
        }
        while (v > fixed_e) {
            v = fixidity.divide(v, fixed_e);
            r += longer_fixed_1;
        }
        if (v == fixed_1) {
            return FixidityLib.round_off(fixidity, r, extra_digits) / t;
        }
        if (v == fixed_e) {
            return
                fixed_1 + FixidityLib.round_off(fixidity, r, extra_digits) / t;
        }
        v *= t;
        v = v - (3 * longer_fixed_1) / 2;
        r = r + longer_fixed_log_e_1_5;
        int256 m = (longer_fixed_1 * v) / (v + 3 * longer_fixed_1);
        r = r + 2 * m;
        int256 m_2 = (m * m) / longer_fixed_1;
        uint8 i = 3;
        while (true) {
            m = (m * m_2) / longer_fixed_1;
            r = r + (2 * m) / int256(i);
            i += 2;
            if (i >= 3 + 2 * digits) break;
        }
        return FixidityLib.round_off(fixidity, r, extra_digits) / t;
    }

    function log_any(
        FixidityLib.Fixidity storage fixidity,
        int256 base,
        int256 v
    ) public view returns (int256) {
        return fixidity.divide(log_e(fixidity, v), log_e(fixidity, base));
    }
}
