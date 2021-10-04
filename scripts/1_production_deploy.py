import time

from brownie import (
    accounts,
    network,
    interface,
    Quad,
    AdminUpgradeabilityProxy,
)
from config import PRODUCTION_TOKENS, PRODUCTION_WEIGHTS, PRODUCTION_UNITS, PRODUCTION_INPUTS

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
    proxyAdmin = "0x0000000000000000000000000000000000000000" # In production, governance cannot be proxy admin.
    randomUser = accounts.at("0xd09e4C2AB4C42cA5afd1756ad5899634421ABF07", force=True)

    # Deploy Quad

    quad = deploy_quad(dev, proxyAdmin, governance, manager)

    quad.unpause({"from": governance})

    DAI = interface.IERC20("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70")

    DAI.approve(
      quad,
      10000000000000000000000, 
      {"from": randomUser}
    )

    preview = quad.getEstimatedQuadsGivenInput("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", 100000000000000000000)
    
    console.print("[green]RandUser bal of DAI is [/green]", DAI.balanceOf(randomUser))

    console.print("[green]100 DAI is [/green]", preview)

    quad.mint("0xd586E7F844cEa2F87f50152665BCbc2C279D8d70",100000000000000000000, 25000000000000000000, {"from": randomUser} )
    
    console.print("[green]Total Supply [/green]", quad.totalSupply())

    JOE = interface.IERC20("0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd")

    console.print("[green]JOE balance in Quad after mint:[/green]", JOE.balanceOf(quad))

    quad.burn(quad.balanceOf(randomUser),  {"from": randomUser} )

    console.print("[green]JOE balance in Quad after burn:[/green]", JOE.balanceOf(quad))

    console.print("[green]JOE balance in RandomUser after burn:[/green]", JOE.balanceOf(randomUser))
    
    console.print("[green]Quad balance totalSupply after burn:[/green]", quad.totalSupply())

    console.print("[green]RandUser bal of DAI is [/green]", DAI.balanceOf(randomUser))





    return quad

def deploy_quad(dev, proxyAdmin, governance, manager):

    args = [
        governance,
        manager,
        PRODUCTION_TOKENS,
        PRODUCTION_WEIGHTS,
        PRODUCTION_UNITS,
        PRODUCTION_INPUTS,
        False,
        "",
        ""
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