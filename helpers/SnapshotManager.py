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
        self.addEntity("randomUser", accounts.at("0x2DDde1E646557328F3709E07Ca1E2176eCcF1465", force=True).address)
        
        self.addAsset("QUAD_LP", self.quad.address)
        self.addAsset("JOE", self.quad.tokens(0))
        self.addAsset("PNG", self.quad.tokens(1))
        self.addAsset("QI", self.quad.tokens(2))
        self.addAsset("SNOB", self.quad.tokens(3))
        self.addAsset("YAK", self.quad.tokens(4))

        self.addAsset("USDT", self.quad.inputs(0))
        self.addAsset("DAI", self.quad.inputs(1))
        self.addAsset("USDC", self.quad.inputs(2))

    def addEntity(self, key, entity):
        self.entities[key] = entity
    
    def addAsset(self, key, asset):
        self.assets[key] = asset
    
    def before(self):
        table = []

        for x in self.entities.items():
            entityName = x[0]
            entityAddress = x[1]
            for a in self.assets.items():
                tokenName = a[0]
                tokenBalance = interface.IERC20(a[1]).balanceOf(entityAddress)
                metric = '{} balance of {}'.format(entityName, tokenName)
                table.append([metric, tokenBalance])
        
        print(tabulate( table, headers=["metric", "before"], tablefmt="grid"))


    def after(self):
        table = []

        for x in self.entities.items():
            entityName = x[0]
            entityAddress = x[1]
            for a in self.assets.items():
                tokenName = a[0]
                tokenBalance = interface.IERC20(a[1]).balanceOf(entityAddress)
                metric = '{} balance of {}'.format(entityName, tokenName)
                table.append([metric, tokenBalance])
        
        print(tabulate( table, headers=["metric", "after"], tablefmt="grid"))  
    
    def quad_mint(self, inputToken, amount, qty, overrides):
        self.quad.mint(inputToken, amount, qty, overrides)



    


        





    # def quad_mint(self, inputToken, amount, qty, overrides):
    #     user = overrides["from"].address
    #     trackedUsers = {"user": user}
    #     before = self.snap(trackedUsers)
    #     self.quad.mint(inputToken, amount, qty, overrides)
    #     after = self.snap(trackedUsers)

    #     print(before)
    #     print(after)
    

    # def before(self):

    #     table = []
    #     for x in self.entities.items():
    #         metric = x[0]
    #         before = interface.IERC20(self.quad.address).balanceOf(x[1])
    #         after = 1
    #         print(type(before))
    #         print(type(after))

    #         table.append([
    #             metric,
    #             before
    #         ])
            
    #     print(
    #         tabulate(
    #             table, headers=["metric", "before"], tablefmt="grid"
    #         )
    #     )       

    
    # def diff(self, a, b):
    #     if type(a) is int and type(b) is int:
    #         return b - a
    #     else:
    #         return "-"