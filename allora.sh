#!/bin/bash

BOLD="\033[1m"
UNDERLINE="\033[4m"
DARK_YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0;32m"

execute_with_prompt() {
    echo -e "${BOLD}Executing: $1${RESET}"
    if eval "$1"; then
        echo "Command executed successfully."
    else
        echo -e "${BOLD}${DARK_YELLOW}Error executing command: $1${RESET}"
        exit 1
    fi
}

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Requirement for running allora-worker-node${RESET}"
echo
echo -e "${BOLD}${DARK_YELLOW}Operating System : Ubuntu 22.04${RESET}"
echo -e "${BOLD}${DARK_YELLOW}CPU : Min of 1/2 core.${RESET}"
echo -e "${BOLD}${DARK_YELLOW}RAM : 2 to 4 GB.${RESET}"
echo -e "${BOLD}${DARK_YELLOW}Storage : SSD or NVMe with at least 5GB of space.${RESET}"
echo

echo -e "${CYAN}Do you meet all of these requirements? (Y/N):${RESET}"
read -p "" response
echo

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo -e "${BOLD}${DARK_YELLOW}Error: You do not meet the required specifications. Exiting...${RESET}"
    echo
    exit 1
fi

echo -e "${BOLD}${DARK_YELLOW}Updating system dependencies...${RESET}"
execute_with_prompt "sudo apt update -y && sudo apt upgrade -y"
echo

echo -e "${BOLD}${DARK_YELLOW}Installing jq packages...${RESET}"
execute_with_prompt "sudo apt install jq"
echo

echo -e "${BOLD}${DARK_YELLOW}Installing Docker...${RESET}"
execute_with_prompt 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg'
echo
execute_with_prompt 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'
echo
execute_with_prompt 'sudo apt-get update'
echo
execute_with_prompt 'sudo apt-get install docker-ce docker-ce-cli containerd.io -y'
echo
sleep 2
echo -e "${BOLD}${DARK_YELLOW}Checking docker version...${RESET}"
execute_with_prompt 'docker version'
echo

echo -e "${BOLD}${DARK_YELLOW}Installing Docker Compose...${RESET}"
VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
echo
execute_with_prompt 'sudo curl -L "https://github.com/docker/compose/releases/download/'"$VER"'/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose'
echo
execute_with_prompt 'sudo chmod +x /usr/local/bin/docker-compose'
echo

echo -e "${BOLD}${DARK_YELLOW}Checking docker-compose version...${RESET}"
execute_with_prompt 'docker-compose --version'
echo

if ! grep -q '^docker:' /etc/group; then
    execute_with_prompt 'sudo groupadd docker'
    echo
fi

execute_with_prompt 'sudo usermod -aG docker $USER'
echo
echo "Request faucet to your wallet from this link: https://faucet.testnet-1.testnet.allora.network/"
echo

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Installing worker node...${RESET}"
git clone https://github.com/allora-network/basic-coin-prediction-node
cd basic-coin-prediction-node
echo
read -p "Enter WALLET_SEED_PHRASE: " WALLET_SEED_PHRASE
echo
echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Generating config.json file...${RESET}"
cat <<EOF > config.json
{
  "wallet": {
    "addressKeyName": "test",
    "addressRestoreMnemonic": "$WALLET_SEED_PHRASE",
    "alloraHomeDir": "",
    "gas": "1000000",
    "gasAdjustment": 1.0,
    "nodeRpc": "https://sentries-rpc.testnet-1.testnet.allora.network/",
    "maxRetries": 5,
    "delay": 5,
    "submitTx": false
  },
  "worker": [
    {
      "topicId": 1,
      "inferenceEntrypointName": "api-worker-reputer",
      "loopSeconds": 5,
      "parameters": {
        "InferenceEndpoint": "http://inference:8000/inference/{Token}",
        "Token": "ETH"
      }
    },
    {
      "topicId": 1,
      "inferenceEntrypointName": "api-worker-reputer",
      "loopSeconds": 5,
      "parameters": {
        "InferenceEndpoint": "http://inference:8000/inference/{Token}",
        "Token": "ETH"
      }
    }
  ]
}
EOF

echo -e "${BOLD}${DARK_YELLOW}config.json file generated successfully!${RESET}"
echo
mkdir worker-data
chmod +x init.config
sleep 2
./init.config

echo
echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Building and starting Docker containers...${RESET}"
docker-compose up -d
echo
sleep 2
echo -e "${BOLD}${DARK_YELLOW}Checking running Docker containers...${RESET}"
docker ps
echo

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Monitoring Docker logs...${RESET}"

# Add a retry mechanism to handle potential node issues
MAX_RETRIES=5
RETRY_DELAY=10
RETRIES=0

while [[ $RETRIES -lt $MAX_RETRIES ]]; do
    docker logs -f worker | grep -q "error unmarshalling"
    if [[ $? -eq 0 ]]; then
        echo -e "${BOLD}${DARK_YELLOW}Error detected. Retrying...${RESET}"
        RETRIES=$((RETRIES + 1))
        sleep $RETRY_DELAY
    else
        echo -e "${BOLD}${CYAN}No unmarshalling errors detected. Continuing...${RESET}"
        break
    fi
done

if [[ $RETRIES -eq $MAX_RETRIES ]]; then
    echo -e "${BOLD}${DARK_YELLOW}Maximum retries reached. Please check the RPC node or network status.${RESET}"
    exit 1
fi

docker logs -f worker
