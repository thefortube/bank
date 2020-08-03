const PriceOracles = artifacts.require('PriceOracles')

contract('PriceOracles', () => {
    // 如果要测试，需要提前在 ganache 部署 ETH/USD USDT/ETH USDC/ETH 三个 chainlink 合约
    let priceOracles = null;

    before(async() => {
        priceOracles = await PriceOracles.deployed();
    });


    it('get eth price', async() => {
        const price = await priceOracles.get('0x0000000000000000000000000000000000000000');
        console.log(price[0].toString());
        console.log(price[1]);
    })

    // 这个测试需要 ganache 部署 usdt 合约，这是本地 usdt 的地址
    it('get usdt price', async() => {
        const price = await priceOracles.get('0x5333026000087e4cb49fFAA91f6cA69d77e28f20');
        console.log(price[0].toString());
        console.log(price[1]);
    })

    // 需要部署 ht 合约
    it('get ht price', async() => {
        const price = await priceOracles.get('0x488AC8553AA274393e118f96FC52bD4D3EF0cc7e');
        console.log(price[0].toString());
        console.log(price[1]);
    })

});
