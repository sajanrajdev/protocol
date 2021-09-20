import time
import brownie
from brownie import *
from brownie import (
    accounts,
    network,
    interface,
    Quad,
    AdminUpgradeabilityProxy,
)
sleep_between_tx = 1



def test_new_implementation(quad, deployer, governance, manager, tokens, weights, inputs, proxyAdmin, proxy, randomUser):
    """
    Deploys new Quad and upgrades the implementation
    """

    ## setup a args

    ## create new quad (new implementation)
    new_quad_logic = Quad.deploy({"from": deployer})

    print("New Quad was deployed at: ", new_quad_logic.address)

    time.sleep(sleep_between_tx)

    ## non-admin users cannot upgrade
    with brownie.reverts(""):
        proxy.upgradeTo(new_quad_logic, {"from": randomUser})

    ## only admin can upgrade
    proxy.upgradeTo(new_quad_logic, {"from": proxyAdmin})


