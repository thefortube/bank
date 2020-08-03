const PoolPawn = artifacts.require('PoolPawn')

contract('PoolPawn', () => {

    let poolPawn = null;

    before(async() => {
        poolPawn = await PoolPawn.deployed();
    });


});
