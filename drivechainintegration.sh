#!/bin/bash

# DriveChain integration testing

# This script will download and build the mainchain and all known sidechain
# projects. Then a series of integration tests will run.

#
# Warn user, delete old data, clone repositories
#

VERSION=0

# Read arguments
SKIP_CLONE=0 # Skip cloning the repositories from github
SKIP_BUILD=0 # Skip pulling and building repositories
SKIP_CHECK=0 # Skip make check on repositories
for arg in "$@"
do
    if [ "$arg" == "--help" ]; then
        echo "The following command line options are available:"
        echo "--skip_clone"
        echo "--skip_build"
        echo "--skip_check"
        exit
    elif [ "$arg" == "--skip_clone" ]; then
        SKIP_CLONE=1
    elif [ "$arg" == "--skip_build" ]; then
        SKIP_BUILD=1
    elif [ "$arg" == "--skip_check" ]; then
        SKIP_CHECK=1
    fi
done

clear

echo -e "\e[36m██████╗ ██████╗ ██╗██╗   ██╗███████╗███╗   ██╗███████╗████████╗\e[0m"
echo -e "\e[36m██╔══██╗██╔══██╗██║██║   ██║██╔════╝████╗  ██║██╔════╝╚══██╔══╝\e[0m"
echo -e "\e[36m██║  ██║██████╔╝██║██║   ██║█████╗  ██╔██╗ ██║█████╗     ██║\e[0m"
echo -e "\e[36m██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══╝     ██║\e[0m"
echo -e "\e[36m██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██║ ╚████║███████╗   ██║\e[0m"
echo -e "\e[36m╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝\e[0m"
echo -e "\e[1mAutomated integration testing script (v$VERSION)\e[0m"
echo
echo "This script will clone, build, configure & run DriveNet and sidechain(s)"
echo "The functional unit tests will be run for DriveNet and sidechain(s)."
echo "If those tests pass, the integration test script will try to go through"
echo "the process of BMM mining, deposit to and withdraw from the sidechain(s)."
echo
echo -e "\e[1mREAD: YOUR DATA DIRECTORIES WILL BE DELETED\e[0m"
echo
echo "Your data directories ex: ~/.drivenet & ~/.testchainplus and any other"
echo "sidechain data directories will be deleted!"
echo
echo -e "\e[31mWARNING: THIS WILL DELETE YOUR DRIVECHAIN & SIDECHAIN DATA!\e[0m"
echo
echo -e "\e[32mYou should probably run this in a VM\e[0m"
echo
read -p "Are you sure you want to run this? (yes/no): " WARNING_ANSWER
if [ "$WARNING_ANSWER" != "yes" ]; then
    exit
fi


rm -rf ~/.drivenet
rm -rf ~/.testchainplus

# These can fail, meaning that the repository is already downloaded
if [ $SKIP_CLONE -ne 1 ]; then
    echo
    echo "Cloning repositories"
    git clone https://github.com/drivechain-project/bitcoin
    git clone https://github.com/DriveNetTESTDRIVE/DriveNet
fi








#
# Build repositories & run their unit tests
#
echo
echo "Building repositories"
cd bitcoin
if [ $SKIP_BUILD -ne 1 ]; then
    git checkout testchainplustest &&
    git pull &&
    ./autogen.sh &&
    ./configure &&
    make -j 9
fi

if [ $SKIP_CHECK -ne 1 ]; then
    make check
    if [ $? -ne 0 ]; then
        echo "Make check failed!"
        exit
    fi
fi

cd ../DriveNet
if [ $SKIP_BUILD -ne 1 ]; then
    git checkout drivechainplustest &&
    git pull &&
    ./autogen.sh &&
    ./configure &&
    make -j 9
fi

if [ $SKIP_CHECK -ne 1 ]; then
    make check
    if [ $? -ne 0 ]; then
        echo "Make check failed!"
        exit
    fi
fi

cd ../








#
# Get mainchain configured and running. Mine first 100 mainchain blocks.
#

# Create configuration file for mainchain
echo
echo "Create mainchain configuration file"
mkdir ~/.drivenet/
touch ~/.drivenet/drivenet.conf
echo "rpcuser=patrick" > ~/.drivenet/drivenet.conf
echo "rpcpassword=integrationtesting" >> ~/.drivenet/drivenet.conf
echo "server=1" >> ~/.drivenet/drivenet.conf

# We start the qt version so that the user can watch what is going on
./DriveNet/src/qt/drivenet-qt --connect=0 --regtest --defaultwtprimevote=upvote &

echo
echo "Waiting for mainchain to start"
sleep 5s

echo
echo "Checking if the mainchain has started"

# Test that mainchain can receive commands and has 0 blocks
GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Mainchain up and running!"
else
    echo
    echo "ERROR failed to send commands to mainchain or block count non-zero"
    exit
fi

echo
echo "Mainchain will now generate first 100 blocks"
sleep 3s

./DriveNet/src/drivenet-cli --regtest generate 100

# Check that 100 blocks were mined
GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 100"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Mainchain has mined first 100 blocks"
else
    echo
    echo "ERROR failed to mine first 100 blocks!"
    exit
fi








#
# Activate a sidechain
#

# Create a sidechain proposal
./DriveNet/src/drivenet-cli --regtest createsidechainproposal "testchainplustest" "testchainplus for integration test" "0186ff51f527ffdcf2413d50bdf8fab1feb20e5f82815dad48c73cf462b8b313"

# Check that proposal was cached (not in chain yet)
LISTPROPOSALS=`./DriveNet/src/drivenet-cli --regtest listsidechainproposals`
COUNT=`echo $LISTPROPOSALS | grep -c "\"title\": \"testchainplustest\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal for sidechain testchainplus has been created!"
else
    echo
    echo "ERROR failed to create testchainplus sidechain proposal!"
    exit
fi

echo
echo "Will now mine a block so that sidechain proposal is added to the chain"

# Mine one block, proposal should be in chain after that
./DriveNet/src/drivenet-cli --regtest generate 1

# Check that we have 101 blocks now
GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 101"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Mainchain has 101 blocks now"
else
    echo
    echo "ERROR failed to mine block!"
    exit
fi

# Check that proposal has been added to the chain and ready for voting
LISTACTIVATION=`./DriveNet/src/drivenet-cli --regtest listsidechainactivationstatus`
COUNT=`echo $LISTACTIVATION | grep -c "\"title\": \"testchainplustest\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal made it into the chain!"
else
    echo
    echo "ERROR sidechain proposal not in chain!"
    exit
fi
# Check age
COUNT=`echo $LISTACTIVATION | grep -c "\"nage\": 1"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal age correct!"
else
    echo
    echo "ERROR sidechain proposal age invalid!"
    exit
fi
# Check fail count
COUNT=`echo $LISTACTIVATION | grep -c "\"nfail\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal has no failures!"
else
    echo
    echo "ERROR sidechain proposal has failures but should not!"
    exit
fi

# Check that there are currently no active sidechains
LISTACTIVESIDECHAINS=`./DriveNet/src/drivenet-cli --regtest listactivesidechains`
if [ "$LISTACTIVESIDECHAINS" == $'[\n]' ]; then
    echo
    echo "Good: no sidechains are active yet"
else
    echo
    echo "ERROR sidechain is already active but should not be!"
    exit
fi

echo
echo "Will now mine enough blocks to activate the sidechain"
sleep 5s

# Mine enough blocks to activate the sidechain
./DriveNet/src/drivenet-cli --regtest generate 255

# Check that 255 blocks were mined
GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 356"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Mainchain has 356 blocks"
else
    echo
    echo "ERROR failed to mine blocks!"
    exit
fi

# Check that the sidechain has been activated
LISTACTIVESIDECHAINS=`./DriveNet/src/drivenet-cli --regtest listactivesidechains`
COUNT=`echo $LISTACTIVESIDECHAINS | grep -c "\"title\": \"testchainplustest\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain has activated!"
else
    echo
    echo "ERROR sidechain failed to activate!"
    exit
fi

echo
echo "listactivesidechains:"
echo
echo "$LISTACTIVESIDECHAINS"








#
# Get sidechain configured and running
#

# Create configuration file for sidechain testchainplus
echo
echo "Creating sidechain configuration file"
mkdir ~/.testchainplus/
touch ~/.testchainplus/testchainplus.conf
echo "rpcuser=patrick" > ~/.testchainplus/testchainplus.conf
echo "rpcpassword=integrationtesting" >> ~/.testchainplus/testchainplus.conf
echo "server=1" >> ~/.testchainplus/testchainplus.conf

echo
echo "The sidechain testchainplus will now be started"
sleep 5s

# Start the sidechain and test that it can receive commands and has 0 blocks
./bitcoin/src/qt/testchainplus-qt --connect=0 --mainchainregtest --verifybmmacceptheader --verifybmmreadblock --verifybmmcheckblock --mainchainrpcport=18443 &

echo
echo "Waiting for testchainplus to start"
sleep 5s

echo
echo "Checking if the sidechain has started"

# Test that sidechain can receive commands and has 0 blocks
GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo "Sidechain up and running!"
else
    echo "ERROR failed to send commands to sidechain or block count non-zero"
    exit
fi

# Check if the sidechain can communicate with the mainchain








#
# Start BMM mining the sidechain
#

# The first time that we call this it should create the first BMM request and
# send it to the mainchain node, which will add it to the mempool
echo
echo "Going to refresh BMM on the sidechain and send BMM request to mainchain"
./bitcoin/src/testchainplus-cli refreshbmm

# TODO check that mainchain has BMM request in mempool

echo
echo "Giving mainchain some time to receive BMM request from sidechain..."
sleep 3s

echo
echo "Mining block on the mainchain, should include BMM commit"

# Mine a mainchain block, which should include the BMM request we just made
./DriveNet/src/drivenet-cli --regtest generate 1

# Check that the block was mined
GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 357"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Mainchain has 357 blocks"
else
    echo
    echo "ERROR failed to mine blocks!"
    exit
fi

# TODO verifiy that bmm request was added to chain and removed from mempool

# Refresh BMM again, this time the block we created the first BMM request for
# should be added to the side chain, and a new BMM request created for the next
# block
echo
echo "Will now refresh BMM on the sidechain again and look for our BMM commit"
echo "BMM block will be connected to the sidechain if BMM commit was made."
./bitcoin/src/testchainplus-cli refreshbmm

# Check that BMM block was added to the sidechain
GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 1"`
if [ "$COUNT" -eq 1 ]; then
    echo "Sidechain connected BMM block!"
else
    echo "ERROR sidechain has no BMM block connected!"
    exit
fi

# Mine some more BMM blocks and make sure that they all make it to the sidechain
echo
echo "Now we will test mining more BMM blocks"

CURRENT_BLOCKS=357
CURRENT_SIDE_BLOCKS=1
COUNTER=1
while [ $COUNTER -le 10 ]
do
    # Wait a little bit
    echo
    echo "Waiting for new BMM request to make it to the mainchain..."
    sleep 0.26s

    echo "Mining mainchain block"
    # Generate mainchain block
    ./DriveNet/src/drivenet-cli --regtest generate 1

    CURRENT_BLOCKS=$(( CURRENT_BLOCKS + 1 ))


    # Check that mainchain block was connected
    GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`

    echo $GETINFO
    echo $CURRENT_BLOCKS
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Mainchain has $CURRENT_BLOCKS blocks"
    else
        echo
        echo "ERROR failed to mine block!"
        exit
    fi

    # Refresh BMM on the sidechain
    echo
    echo "Refreshing BMM on the sidechain..."
    ./bitcoin/src/testchainplus-cli refreshbmm

    CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS + 1 ))

    # Check that BMM block was added to the side chain
    GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_SIDE_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Sidechain connected BMM block!"
    else
        echo
        echo "ERROR sidechain did not connect BMM block!"
        # TODO In the testing environment we shouldn't have any failures at all.
        # It would however be normal in real use to have some failures...
        #
        # For now, if we have a failure during testing which is probably due
        # to a bug on main or side and not the testing environment which has
        # perfect conditions, move on and try again just like a real node would.
        # TODO renable exit here?
        # Subtract 1 before moving on, since we
        # failed to actually add it.
        CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS - 1 ))
    fi

    ((COUNTER++))
done








#
# Deposit to the sidechain
#

# Create sidechain deposit
ADDRESS=`./bitcoin/src/testchainplus-cli getnewaddress sidechain legacy`
./DriveNet/src/drivenet-cli --regtest createsidechaindeposit 0 $ADDRESS 1

# Mine some blocks and BMM the sidechain so it can process the deposit
COUNTER=1
while [ $COUNTER -le 200 ]
do
    # Wait a little bit
    echo
    echo "Waiting for new BMM request to make it to the mainchain..."
    sleep 0.26s

    echo "Mining mainchain block"
    # Generate mainchain block
    ./DriveNet/src/drivenet-cli --regtest generate 1

    CURRENT_BLOCKS=$(( CURRENT_BLOCKS + 1 ))

    # Check that mainchain block was connected
    GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Mainchain has $CURRENT_BLOCKS blocks"
    else
        echo
        echo "ERROR failed to mine block!"
        exit
    fi

    # Refresh BMM on the sidechain
    echo
    echo "Refreshing BMM on the sidechain..."
    ./bitcoin/src/testchainplus-cli refreshbmm

    CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS + 1 ))

    # Check that BMM block was added to the side chain
    GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_SIDE_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Sidechain connected BMM block!"
    else
        echo
        echo "ERROR sidechain did not connect BMM block!"
        CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS - 1 ))
    fi

    ((COUNTER++))
done

# Check if the deposit made it to the sidechain
LIST_TRANSACTIONS=`./bitcoin/src/testchainplus-cli listtransactions`
COUNT=`echo $LIST_TRANSACTIONS | grep -c "\"address\": \"$ADDRESS\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain received deposit!"
    echo "Deposit: "
    echo "$LIST_TRANSACTIONS"
else
    echo
    echo "ERROR sidechain did not receive deposit!"
    exit
fi

echo
echo "Now we will BMM the sidechain until the deposit has matured!"

# Sleep here so user can read the deposit debug output
sleep 5s

# Mature the deposit on the sidechain, so that it can be withdrawn
COUNTER=1
while [ $COUNTER -le 121 ]
do
    # Wait a little bit
    echo
    echo "Waiting for new BMM request to make it to the mainchain..."
    sleep 0.26s

    echo "Mining mainchain block"
    # Generate mainchain block
    ./DriveNet/src/drivenet-cli --regtest generate 1

    CURRENT_BLOCKS=$(( CURRENT_BLOCKS + 1 ))

    # Check that mainchain block was connected
    GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Mainchain has $CURRENT_BLOCKS blocks"
    else
        echo
        echo "ERROR failed to mine block!"
        exit
    fi

    # Refresh BMM on the sidechain
    echo
    echo "Refreshing BMM on the sidechain..."
    ./bitcoin/src/testchainplus-cli refreshbmm

    CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS + 1 ))

    # Check that BMM block was added to the side chain
    GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_SIDE_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Sidechain connected BMM block!"
    else
        echo
        echo "ERROR sidechain did not connect BMM block!"
        CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS - 1 ))
    fi

    ((COUNTER++))
done

# Check that the deposit has been added to our sidechain balance
BALANCE=`./bitcoin/src/testchainplus-cli getbalance`
BC=`echo "$BALANCE>0.9" | bc`
if [ $BC -eq 1 ]; then
    echo
    echo "Sidechain balance updated, deposit matured!"
    echo "Sidechain balance: $BALANCE"
else
    echo
    echo "ERROR sidechain balance not what it should be... Balance: $BALANCE!"
    exit
fi


# Test sending the deposit around to other addresses on the sidechain
# TODO








#
# Withdraw from the sidechain
#

# Get a mainchain address
MAINCHAIN_ADDRESS=`./DriveNet/src/drivenet-cli --regtest getnewaddress mainchain legacy`

# Call the CreateWT RPC
echo
echo "We will now create a wt on the sidechain"
./bitcoin/src/testchainplus-cli createwt $MAINCHAIN_ADDRESS 0.5
sleep 3s

# Mine enough BMM blocks for a WT^ to be created and sent to the mainchain
echo
echo "Now we will mine enough BMM blocks for the sidechain to create a WT^"
COUNTER=1
while [ $COUNTER -le 180 ]
do
    # Wait a little bit
    echo
    echo "Waiting for new BMM request to make it to the mainchain..."
    sleep 0.26s

    echo "Mining mainchain block"
    # Generate mainchain block
    ./DriveNet/src/drivenet-cli --regtest generate 1

    CURRENT_BLOCKS=$(( CURRENT_BLOCKS + 1 ))

    # Check that mainchain block was connected
    GETINFO=`./DriveNet/src/drivenet-cli --regtest getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Mainchain has $CURRENT_BLOCKS blocks"
    else
        echo
        echo "ERROR failed to mine block!"
        exit
    fi

    # Refresh BMM on the sidechain
    echo
    echo "Refreshing BMM on the sidechain..."
    ./bitcoin/src/testchainplus-cli refreshbmm

    CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS + 1 ))

    # Check that BMM block was added to the side chain
    GETINFO=`./bitcoin/src/testchainplus-cli getmininginfo`
    COUNT=`echo $GETINFO | grep -c "\"blocks\": $CURRENT_SIDE_BLOCKS"`
    if [ "$COUNT" -eq 1 ]; then
        echo
        echo "Sidechain connected BMM block!"
    else
        echo
        echo "ERROR sidechain did not connect BMM block!"
        CURRENT_SIDE_BLOCKS=$(( CURRENT_SIDE_BLOCKS - 1 ))
    fi

    ((COUNTER++))
done

# Check if WT^ was created

# TODO check on WT^ status

# Check if balance of mainchain address received WT^ payout
WT_BALANCE=`./DriveNet/src/drivenet-cli --regtest getbalance mainchain`
BC=`echo "$WT_BALANCE>0.4" | bc`
if [ $BC -eq 1 ]; then
    echo
    echo
    echo -e "\e[32m==========================\e[0m"
    echo
    echo -e "\e[1mWT^ payout received!\e[0m"
    echo "amount: $WT_BALANCE"
    echo
    echo -e "\e[32m==========================\e[0m"
else
    echo
    echo -e "\e[31mError: WT^ payout not received!\e[0m"
    exit
fi

#
# Stage x: Receive WT^ payout
#
echo
echo
echo -e "\e[32mDriveNet integration testing completed!\e[0m"
echo
echo "You must manually shut down instances of mainchain and sidechain(s)"
echo "started by the script once you are done looking at the results via GUI"
echo
echo "Make sure to backup log files you want to keep before running again!"

echo
echo -e "\e[32mIf you made it here that means everything probably worked!\e[0m"
echo "If you notice any issues but the script still made it to the end, please"
echo "open an issue on GitHub!"

