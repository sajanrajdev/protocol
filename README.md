# Quads Finance

## Installation and Setup

1. Use this code by clicking on Use This Template

2. Download the code with `git clone URL_FROM_GITHUB`

3. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) & [Ganache-CLI](https://github.com/trufflesuite/ganache-cli), if you haven't already.

4. Install the dependencies in the package

```
## Javascript dependencies
npm i

## Python Dependencies
pip install virtualenv
virtualenv venv
source venv/bin/activate
pip install -r requirements.txt
```

5. Run the following command to install the Avalanche main network:

```
brownie networks add Avalanche avax-avash2 host=https://api.avax.network/ext/bc/C/rpc chainid=43112 explorer=https://cchain.explorer.avax.network/
```

6. Run the following command to install the Avalanche fork network:

```
brownie networks import network-config.yaml
```

## Basic Use

To deploy the demo Badger Strategy in a development environment:

1. Open the Brownie console. This automatically launches Ganache on a forked mainnet.

```bash
  brownie console
```

2. Run Scripts for Deployment

```
  brownie run deploy
```
