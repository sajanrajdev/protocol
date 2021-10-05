import brownie
from brownie import *

# Objective: Ensure correct roles are setup for proxy, governance.

def test_quad_pausing_permissions(quad, randomUser):


    authorizedPausers = [
        quad.governance(),
        quad.manager(),
    ]

    authorizedUnpausers = [
        quad.governance(),
    ]

    # pause onlyPausers

    print(quad.governance())
    print(quad.manager())


    for pauser in authorizedPausers:
        quad.pause({"from": pauser})
        quad.unpause({"from": authorizedUnpausers[0]})

    with brownie.reverts("onlyPausers"):
        quad.pause({"from": randomUser})

    # unpause onlyPausers

    for unpauser in authorizedUnpausers:
        quad.pause({"from": unpauser})
        quad.unpause({"from": unpauser})

    with brownie.reverts("onlyGovernance"):
        quad.unpause({"from": randomUser})

    quad.pause({"from": authorizedPausers[0]})

    #  other roles

    with brownie.reverts("Pausable: paused"):
        quad.mint("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", 100000000000000000000, 25000000000000000000, {"from": randomUser})
    with brownie.reverts("Pausable: paused"):
        quad.burn(1, {"from": randomUser})

    
    quad.unpause({"from": authorizedUnpausers[0]})

    quad.mint("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", 100000000000000000000, 25000000000000000000, {"from": randomUser})

    burnAmount = quad.balanceOf(randomUser)

    print(burnAmount)

    quad.burn(burnAmount, {"from": randomUser} )





