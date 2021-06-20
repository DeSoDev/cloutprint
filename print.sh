#!/bin/bash

# set details
DOIMAGE="72401866"
DOSIZE="m3-4vcpu-32gb"
DOREGION="AMS3"
DONAME="bitclout-$RANDOM"

# introduction
echo "Welcome to CloutPrinter by @tijn!"
echo "---------------------------------"
echo
echo "Running this script will:"
echo
echo "- launch a BitClout node on the DigitalOcean clout"
echo "- wait for it to sync the blockchain"
echo "- print out all posts to the screen"
echo
echo "To be able to do this, it needs to make sure you have the following tools installed:"
echo "- Package manager: homebrew"
echo "- cli tools: jq & wget"
echo "- Digital Ocean CLI: doctl"
echo

# check were on macos
if [[ ! "$OSTYPE" == "darwin"* ]]; then
    echo "This script only works on MacOs"
    exit
fi

# install homebrew
echo
echo "Need to make sure you have a few apps installed."
echo "Press enter to start"
read

if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew"
    echo "You will be required to enter your admin password"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo "[ok] Homebrew installed"
echo

if ! command -v doctl &> /dev/null; then
    echo "Installing doctl"
    brew install doctl
fi
echo "[ok] doctl installed"
echo

if ! command -v jq &> /dev/null; then
    echo "Installing jq"
    brew install jq
fi
echo "[ok] jq installed"
echo

if ! command -v wget &> /dev/null; then
    echo "Installing wget"
    brew install wget
fi
echo "[ok] wget installed"
echo

# configure account
echo
echo "Please authenticate the DO cli tool to your account"

if ! DOAUTH=(`doctl auth list | sed -e "s/(current)//"`); then
    echo "You are not logged into your DO account."
    echo "If you dont have an account create one here:"
    echo "https://m.do.co/c/0c7459043159"
    echo
    echo "Then create a API token here:"
    echo "https://cloud.digitalocean.com/account/api/tokens"
    echo "* Make sure you enable read & write access"
    echo
    doctl auth init --context bitclout
    DOAUTH=(`doctl auth list | sed -e "s/(current)//"`)
fi
select ACCOUNT in "${DOAUTH[@]}"; do
    doctl auth switch --context $ACCOUNT
    break
done
echo
echo "DO account selected: $ACCOUNT"
doctl account get --format "Email"
echo
echo -n "Do you want to proceed? Enter to continue"
read

# create keypair
echo
echo "Is the SSH key set already?"
if [ ! -f ./keys/bitclout ]; then
    echo "Creating new key file"
    ssh-keygen -f ./keys/bitclout -t rsa -b 4096 -C "dummy@email.com" -q -N ""
    doctl compute ssh-key import bitclout --public-key-file ./keys/bitclout.pub
    echo "[ok] ssh key created, and uploaded to digital ocean"
else
    echo "[ok] SSH Key exists already"
fi

FINGERPRINT=$(ssh-keygen -E md5 -lf ./keys/bitclout | cut -d' ' -f2 | cut -c 5-)

# make sure it exists on DO
doctl compute ssh-key get $FINGERPRINT &> /dev/null
if [ $? -ne 0 ]; then
    echo "[ERROR] Your ssh key file exists locally, but has not been created in Digital Ocean"
    echo "- please remove the files in: ./keys/, and restart the script"
    exit
fi

# create droplet
echo
echo "Creating droplet ... please wait "

DROPLETIP=$(doctl compute droplet create $DONAME \
    --enable-backups \
    --enable-ipv6 \
    --enable-monitoring \
    --image $DOIMAGE \
    --region $DOREGION \
    --size $DOSIZE \
    --ssh-keys $FINGERPRINT \
    --user-data-file ./userdata.sh \
    --wait \
    --no-header \
    --format "PublicIPv4")

echo "[OK] Droplet created: $DROPLETIP"

#wait for web to come up
echo 
echo -n "Bitclout is now being installed..."
until $(curl --max-time 2 --output /dev/null --silent --head --fail "http://$DROPLETIP"); do
    echo -n "."
    sleep 5
done
echo
echo "[ok] droplet created"

BLOCK=0
POSTBLOCK=6044 #this was block with first post
MAXHEIGHT=$(curl -s https://api.bitclout.com/api/v1 | jq '.Header.Height')
echo
echo "There are $MAXHEIGHT blocks on Bitclout."
echo
echo "First we need to download the headers for all the blocks."
echo "Then we download a bunch of empty blocks before the first post."
echo "After that you enter the timemachine, seeing old posts scroll by."
echo

until [ "$BLOCK" -eq "$MAXHEIGHT" ]; do
    NODESTATUS=$(curl -s "http://$DROPLETIP/api/v0/admin/node-control" -X 'POST' -H 'Content-Type: application/json' --data-binary '{"AdminPublicKey":"","Address":"","OperationType":"get_info"}' | jq '.BitCloutStatus')
    STATE=$(jq -r '.State' <<< $NODESTATUS)
    HEADERS=$(jq -r '.HeadersRemaining' <<< $NODESTATUS)
    BLOCKS=$(jq -r '.BlocksRemaining' <<< $NODESTATUS)
    TSINDEX=$(jq -r '.LatestTxIndexHeight' <<< $NODESTATUS)
    LASTHEIGHT=$(jq -r '.LatestHeaderHeight' <<< $NODESTATUS)
    CURHEIGHT=$(jq -r '.LatestBlockHeight' <<< $NODESTATUS)

    if [ "$STATE" = "SYNCING_HEADERS" ]; then
        echo -ne "$STATE: $HEADERS remaining...                            \r"
        sleep 2
        continue
    elif [ "$STATE" = "SYNCING_BITCOIN" ]; then
        echo -ne "Just a quick sync with Bitcoin! You wont even see this   \r"
        sleep 2
        continue
    elif [ "$STATE" = "SYNCING_BLOCKS" ]; then
        if [ "$CURHEIGHT" -lt "$POSTBLOCK" ]; then
            LEFT="$(($POSTBLOCK-$CURHEIGHT))"
            echo -ne "$STATE: Load Empty Blocks First, $LEFT remaining         \r"
            sleep 2
            continue
        else
            # OK now show some posts while we sync remainder
            POSTS=$(curl -s "http://$DROPLETIP/api/v0/get-posts-stateless" -X POST -H 'Content-Type: application/json' --data-raw '{ "ReaderPublicKeyBase58Check":"", "PostHashHex":"", "NumToFetch":100, "GetPostsForFollowFeed": false, "GetPostsForGlobalWhitelist": false, "GetPostsByClout": false, "OrderBy": "oldest", "StartTstampSecs": 0, "PostContent": "", "FetchSubcomments": true, "MediaRequired": false, "PostsByCloutMinutesLookback": 0, "AddGlobalFeedBool": false }' | jq -c '.PostsFound[]')
            
            while read -r POST
            do
                USER=$(jq -r '.ProfileEntryResponse.Username' <<< $POST)
                DATE=$(jq -r '.TimestampNanos / 1000000000 | strftime("on %d %m %Y at %H:%M:%S (UTC)")' <<< $POST)
                BODY=$(jq -r '.Body' <<< $POST)
                RC=$(jq '.RecloutedPostEntryResponse' <<< $POST)
                COMMENTS=$(jq '.Comments' <<< $POST)

                # set username to annonymous if username not set
                if [ "$USER" = "null" ]; then
                    USER="anonymous"
                fi

                #Is it a ReClout?
                if [ ! -z "$RC" ] && [ ! "$RC" = "null" ]; then
                    # RC is not is empty, its a reclout so need a different output
                    RCUSER=$(jq -r '.ProfileEntryResponse.Username' <<< $RC)
                    RCBODY=$(jq -r '.Body' <<< $RC)

                    # set username to annonymous if username not set
                    if [ "$RCUSER" = "null" ]; then
                        RCUSER="anonymous"
                    fi

                    echo "🔁 $USER reclouted $RCUSER on $DATE:"
                    if [ ! -z "$BODY" ] && [ ! "$BODY" = "null" ]; then
                        printf "%s\n" "$BODY"
                    else
                        printf "%s\n" "=>\" $RCBODY \""
                    fi
                else
                    echo "🗣  $USER posted on $DATE:"
                    printf "%s\n" "$BODY"
                fi

                echo
                #only sleep the first 1000 blocks after postblock, then go fast
                PAUSEBLOCK=$(($POSTBLOCK+1000))
                if [ "$CURHEIGHT" -lt "$PAUSEBLOCK" ]; then
                    sleep 2
                fi
            done <<< "$POSTS"    

        fi
        BLOCK="$CURHEIGHT"

        echo
        echo "[SYNC STATUS] $STATE at $BLOCK OF $MAXHEIGHT, with index at $TSINDEX"
        echo

        continue
    fi

    MAXHEIGHT="$LASTHEIGHT"

    # if there are indexed blocks, get the posts
    until [ $BLOCK -ge $MAXHEIGHT ]; do
        NODESTATUS=$(curl -s "http://$DROPLETIP/api/v0/admin/node-control" -X 'POST' -H 'Content-Type: application/json' --data-binary '{"AdminPublicKey":"","Address":"","OperationType":"get_info"}' | jq '.BitCloutStatus')
        STATE=$(jq -r '.State' <<< $NODESTATUS)
        HEADERS=$(jq -r '.HeadersRemaining' <<< $NODESTATUS)
        BLOCKS=$(jq -r '.BlocksRemaining' <<< $NODESTATUS)
        TSINDEX=$(jq -r '.LatestTxIndexHeight' <<< $NODESTATUS)
        LASTHEIGHT=$(jq -r '.LatestHeaderHeight' <<< $NODESTATUS)
        CURHEIGHT=$(jq -r '.LatestBlockHeight' <<< $NODESTATUS)
        if [ $TSINDEX -gt $BLOCK ]; then
            BLOCKDATA=$(curl -s "http://$DROPLETIP/api/v1/block" -X 'POST' -H 'Content-Type: application/json' --data-binary "{\"Height\":${BLOCK}, \"FullBlock\":true}")
            POSTS=$(jq -r '.Transactions[] | select(.TransactionType=="SUBMIT_POST") | .TransactionMetadata.SubmitPostTxindexMetadata.PostHashBeingModifiedHex' <<< $BLOCKDATA )
            if [ ! -z "$POSTS" ]; then
                while read -r POSTID
                do
                    POST=$(curl -s "http://$DROPLETIP/api/v0/get-single-post" -X POST -H 'Content-Type: application/json' --data-raw "{ \"ReaderPublicKeyBase58Check\":\"\", \"PostHashHex\":\"$POSTID\",  \"FetchParents\": false, \"CommentOffset\": 0, \"CommentLimit\": 0, \"AddGlobalFeedBool\": false }" | jq -c '.PostFound')
                    if [ ! -z "$POST" ] && [ ! "$POST" = "null" ]; then
                        USER=$(jq -r '.ProfileEntryResponse.Username' <<< $POST)
                        DATE=$(jq -r '.TimestampNanos / 1000000000 | strftime("on %d %m %Y at %H:%M:%S (UTC)")' <<< $POST)
                        BODY=$(jq -r '.Body' <<< $POST)
                        RC=$(jq '.RecloutedPostEntryResponse' <<< $POST)
                        COMMENTS=$(jq '.Comments' <<< $POST)

                        # set username to annonymous if username not set
                        if [ "$USER" = "null" ]; then
                            USER="anonymous"
                        fi

                        #Is it a ReClout?
                        if [ ! -z "$RC" ] && [ ! "$RC" = "null" ]; then
                            # RC is not is empty, its a reclout so need a different output
                            RCUSER=$(jq -r '.ProfileEntryResponse.Username' <<< $RC)
                            RCBODY=$(jq -r '.Body' <<< $RC)

                            # set username to annonymous if username not set
                            if [ "$RCUSER" = "null" ]; then
                                RCUSER="anonymous"
                            fi

                            echo "🔁 $USER reclouted $RCUSER on $DATE:"
                            if [ ! -z "$BODY" ] && [ ! "$BODY" = "null" ]; then
                                printf "%s\n" "$BODY"
                            else
                                printf "%s\n" "=>\" $RCBODY \""
                            fi
                        else
                            echo "🗣  $USER posted on $DATE:"
                            printf "%s\n" "$BODY"
                        fi
                    fi
                done <<< "$POSTS"
            fi
            BLOCK=$((BLOCK+1))
        else
            echo -ne "WAITING FOR INDEXED BLOCKS: $BLOCK vs $TSINDEX       \r"
            sleep 3
        fi
    done
    echo "$BLOCK vs $MAXHEIGHT & $TSINDEX"
done

echo 
echo "DONE!!"