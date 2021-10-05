from brownie import *
from tabulate import tabulate
from rich.console import Console


console = Console()

class SnapshotManager:
    def __init__(self, quad, key):
        self.key = key
        self.quad = quad
        self.entities = {}
        self.assets = {}


        self.addEntity("quad", self.quad.address)
        self.addEntity("governance", self.quad.governance())
        self.addEntity("manager", self.quad.manager())
        self.addEntity("randomUser", accounts.at("0xd09e4C2AB4C42cA5afd1756ad5899634421ABF07", force=True).address)
        
        
        self.addAsset("token1", self.quad.tokens(0))
        self.addAsset("token2", self.quad.tokens(1))
        self.addAsset("token3", self.quad.tokens(2))
        self.addAsset("token4", self.quad.tokens(3))
        self.addAsset("token5", self.quad.tokens(4))

        self.addAsset("inputToken1", self.quad.inputs(0))
        self.addAsset("inputToken2", self.quad.inputs(1))
        self.addAsset("inputToken3", self.quad.inputs(2))
       
        
        print(self.entities)
        print(self.assets)



    def addEntity(self, key, entity):
        self.entities[key] = entity
    
    def addAsset(self, key, asset):
        self.assets[key] = asset
    

    def quad_mint(self, inputToken, amount, qty, overrides):
        user = overrides["from"].address
        trackedUsers = {"user": user}
        before = self.snap(trackedUsers)
        self.quad.mint(inputToken, amount, qty, overrides)
        after = self.snap(trackedUsers)

        print(before)
        print(after)
    

    def before(self):
        table = []
        for x in self.entities.items():
            metric = x[0]
            before = interface.IERC20(self.quad.address).balanceOf(x[1])
            after = 1
            print(type(before))
            print(type(after))

            table.append([
                metric,
                before
            ])
        print(
            tabulate(
                table, headers=["metric", "before"], tablefmt="grid"
            )
        )       

    
    def diff(self, a, b):
        if type(a) is int and type(b) is int:
            return b - a
        else:
            return "-"
    
    






        

