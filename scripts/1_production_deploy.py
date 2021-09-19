import time

from brownie import (
    accounts,
    network,
    interface,
    Quad,
    AdminUpgradeabilityProxy,
)
from config import PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_INPUTS

import click
from rich.console import Console
console = Console()
sleep_between_tx = 1

def main():
    """
    FOR DEVELOPERS
    Deploys a Quad contract with parameters sent in the config. Also includes the deployment 
    of both proxy and implementation contracts using OZ Admin
    """

    # Get deployer account from local keystore
    dev = connect_account()

    # Get actors
    governance = dev.address
    manager = dev.address
    proxyAdmin = dev.address # In production, governance cannot be governance.

    # Deploy Quad

    quad = deploy_quad(dev, proxyAdmin, governance, manager)

    lp = interface.IERC20(quad)
    console.print("[green] LP supply before mint [/green]", lp.totalSupply())

    DAI = interface.IERC20("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70")

    DAI.approve(
      quad,
      100000000000000000000, 
      {"from": "0xf258c32069e40d2AadCb8788BC0F29884845AEBA"}
    )
    quad.mint("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", 100000000000000000000, {"from": "0xf258c32069e40d2AadCb8788BC0F29884845AEBA"})

    console.print("[green] LP total supply after mint [/green]", lp.totalSupply())

    bal = lp.balanceOf("0xf258c32069e40d2AadCb8788BC0F29884845AEBA")

    console.print("[green] The LP token balance of User is: [/green]", bal)

    quad.burn(50000000000000000000, {"from": "0xf258c32069e40d2AadCb8788BC0F29884845AEBA"} )
    
    newBal = lp.balanceOf("0xf258c32069e40d2AadCb8788BC0F29884845AEBA")

    console.print("[green] The LP token balance of User after burn is: [/green]", newBal)
    console.print("[green] LP total supply after burn [/green]", lp.totalSupply())


    return quad

def deploy_quad(dev, proxyAdmin, governance, manager):

    args = [
        governance,
        manager,
        PRODUCTION_TOKENS,
        PRODUCTION_WEIGHTS,
        PRODUCTION_INPUTS
    ]
    
    print("Quad Arguments: ", args)


    quad_logic = Quad.deploy({"from": dev}) #Quad Logic

    time.sleep(sleep_between_tx)


    quad_proxy = AdminUpgradeabilityProxy.deploy(
        quad_logic,
        proxyAdmin,
        quad_logic.initialize.encode_input(*args),
        {"from": dev},
    )

     ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(quad_proxy)
    quad_proxy = Quad.at(quad_proxy.address)

    console.print("[green]Quad was deployed at: [/green]", quad_proxy.address)

    return quad_proxy

def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev