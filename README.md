This macOS script builds a BitClout Node on Digital Ocean, installs the BitClout stack, and while it syncs the blockchain, it prints out posts to the terminal.

This script supports macOs only.

It is in response to [this clout](https://bitclout.com/posts/d8dcdf273d1a53c02861f604d402479503f620ac8c81a07494fecafef894fb1a?feedTab=Following) by @balajis.

## Dependencies

The script will look for and if not available install:

- package manager `homebrew`
- digital ocean command line tool: `doctl`
- json cli tool: `jq`

## What do you need?

The only thing you need is a up to date macOs machine, and a DigitalOcean account.

If you dont have one, [go here to signup](https://m.do.co/c/0c7459043159).

## How to use this?

First thing you need to do is get an API token for your DigitalOcean account.

### Get your DigitalOcean token

1. Login to [DigitalOcean](https://cloud.digitalocean.com)
2. Go to the [API Page](https://cloud.digitalocean.com/account/api)
3. Click `Generate New Token`
4. Give it a name, eg `Bitclout`, and make sure `read` and `write` scopes remain enabled
5. Click `Generate Token`
6. Ones its created, click on it to copy it. !! IT WILL ONLY SHOW ONES.
7. Make sure you save the token safely in a password manager.
8. What ? You dont use a password manager. Go and sort that out right now.

### Clone this repo & run the script

Open the macOs Terminal app, and clone this repo.

As this is kinda a temporary script, just clone it to your Downloads folder.

```bash
cd ~/Dowmloads
git clone https://github.com/tijno/cloutprint.git
cd cloutprint
./print.sh
```

### Installing Dependencies

The script will check if you have the required dependencies installed.

```shell
Making sure Homebrew is installed
[ok] already installed

Do we have DOCTL?
[ok] DO cli already installed

Do we have jq tool?
[ok] jq already installed
```

### Give DOCTL access to API

If this is the first time you are running the script, you will need to provide the API token you created under the previous step.

If you have previously run the script, then this should not be needed.

### Select your DigitalOcean account

Select the context (account) you want to create the node under. For most just select the `Bitclout` option.

### Setup SSH key

The script creates a dedicated SSH key to access your droplet sould you need it. This key is installed in `./keys/bitclout` and added to DigitalOcean.

### Create droplet

Next the droplet is created. This can take a minute and you will see the IP confirmed when its live.

```shell
Creating droplet ... please wait 
[OK] Droplet created: 167.99.41.80
```

### Installing Bitclout

Ones the droplet is live, the script will install the bitclout website & backend services so it can start syncing the blockchain.

### Sync Headers

Before posts can be shown, all the headers need to be synced. So this is where we show a progress bar counting down until they are all synced.

```shell
There are 35114 blocks on Bitclout.
First we need to download the headers for all the blocks

SYNCING_HEADERS: 8731 remainingg
```

### Syncing Blocks

Next step is to download all the blocks. This will take 7 to 8 hours.

The first 10k blocks were empty, so there isnt much to show.

Ones there are less then 28734 blocks to download, we can show some posts.

```shell
🗣  diamondhands posted on on 12 03 2021 at 18:53:52 (UTC):
In retrospect, it was inevitable
```


## Improvements

Here are some other things you could help with:

- [ ] Add option to select different hosts, like AWS
- [ ] Improve post output formatting
- [ ] Show post stats 
- [ ] Launch a few tmux windows each monitoring different stats as the chain syncs
- [ ] Support Linux and Windows
- [ ] Dump posts into Redis as per [this request](https://bitclout.com/posts/85e53038e1e98903d583722b0112b318fbc4412591e2ee42b1c65ad7670aeac7)

Feel free to submit a PR for these things.
