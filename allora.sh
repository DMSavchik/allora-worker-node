#!/bin/bash

BOLD="\033[1m"
UNDERLINE="\033[4m"
DARK_YELLOW="\033[0;33m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
RESET="\033[0m"

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
echo -e "${GREEN}${BOLD}Request faucet to your wallet from this link:${RESET} https://faucet.testnet-1.testnet.allora.network/"
echo

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Installing worker node...${RESET}"
if [ ! -d "/root/basic-coin-prediction-node" ]; then
    git clone https://github.com/allora-network/basic-coin-prediction-node /root/basic-coin-prediction-node
fi
cd /root/basic-coin-prediction-node || exit
echo

read -p "Enter WALLET_SEED_PHRASE: " WALLET_SEED_PHRASE
echo

echo -e "${BOLD}${DARK_YELLOW}Select an RPC server or enter a custom one:${RESET}"
echo "1) https://rpc.ankr.com/allora_testnet"
echo "2) https://allora-rpc.testnet-1.testnet.allora.network/"
echo "3) https://beta.multi-rpc.com/allora_testnet/"
echo "4) https://allora-testnet-1-rpc.testnet.nodium.xyz/"
echo "5) Enter custom RPC"
read -p "Enter your choice (1-5): " rpc_choice

case $rpc_choice in
    1) RPC_URL="https://rpc.ankr.com/allora_testnet" ;;
    2) RPC_URL="https://allora-rpc.testnet-1.testnet.allora.network/" ;;
    3) RPC_URL="https://beta.multi-rpc.com/allora_testnet/" ;;
    4) RPC_URL="https://allora-testnet-1-rpc.testnet.nodium.xyz/" ;;
    5)
        read -p "Enter custom RPC URL: " RPC_URL
        # Basic URL validation
        if [[ ! $RPC_URL =~ ^https?:// ]]; then
            echo "Invalid URL. Please enter a valid URL starting with http:// or https://"
            exit 1
        fi
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Generating config.json file...${RESET}"
cat <<EOF > config.json
{
  "wallet": {
    "addressKeyName": "test",
    "addressRestoreMnemonic": "$WALLET_SEED_PHRASE",
    "alloraHomeDir": "",
    "gas": "1000000",
    "gasAdjustment": 1.0,
    "nodeRpc": "$RPC_URL",
    "maxRetries": 1,
    "delay": 1,
    "submitTx": true
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


# Create updater script in root directory
cat <<EOF > /root/allora_updater.sh
#!/bin/bash

# Directory of your repository
REPO_DIR=/root/basic-coin-prediction-node

# Change to the repository directory
cd \$REPO_DIR

# Function to log messages
log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> /var/log/allora_updater.log
}

# Fetch the latest changes from the remote repository
git fetch

# Check if there are new changes in the main branch
LOCAL=\$(git rev-parse HEAD)
REMOTE=\$(git rev-parse @{u})

if [ \$LOCAL != \$REMOTE ]; then
    log_message "Updates found. Pulling changes and restarting services..."

    # Pull the latest changes
    if git pull; then
        log_message "Git pull successful."

        # Update config.json if necessary
        if [ -f config.json ]; then
            # Backup the existing config
            cp config.json config.json.bak

            # Update the config file (you may need to adjust this part based on what needs to be updated)
            # For example, updating the RPC URL:
            # sed -i 's#"nodeRpc": ".*"#"nodeRpc": "https://new-rpc-url.com"#' config.json

            log_message "config.json updated."
        else
            log_message "config.json not found. Skipping config update."
        fi

        # Stop and restart the Docker containers with the new changes
        if docker compose down && docker compose up -d; then
            log_message "Docker containers restarted successfully."
        else
            log_message "Error restarting Docker containers."
        fi

        log_message "Update completed and services restarted."
    else
        log_message "Error pulling changes from git."
    fi
else
    log_message "No updates found. Everything is up to date."
fi
EOF

chmod +x /root/allora_updater.sh

# Set up cron job to run the updater script every hour
(crontab -l 2>/dev/null; echo "0 * * * * /root/allora_updater.sh") | crontab -

# Set up autostart for the updater script
cat <<EOF > /etc/systemd/system/allora-updater.service
[Unit]
Description=Allora Worker Node Updater
After=network.target

[Service]
ExecStart=/root/allora_updater.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable allora-updater.service
systemctl start allora-updater.service

echo -e "${BOLD}${DARK_YELLOW}Updater script created in /root and configured to run every hour and on system startup.${RESET}"

echo -e "${BOLD}${UNDERLINE}${DARK_YELLOW}Building and starting Docker containers...${RESET}"
execute_with_prompt "docker compose build"
execute_with_prompt "docker compose up -d"
echo

echo -e "${BOLD}${DARK_YELLOW}Checking running Docker containers...${RESET}"
execute_with_prompt "docker ps"
echo

echo -e "${BOLD}${DARK_YELLOW}Showing logs from the worker container...${RESET}"
execute_with_prompt "docker logs -f worker"

echo -e "${BOLD}${DARK_YELLOW}Installation completed successfully!${RESET}"