#!/usr/bin/env bash

#
# Copyright (c) 2024 Ocean Protocol contributors
# SPDX-License-Identifier: Apache-2.0
#

validate_hex() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "The private key seems invalid, exiting ..."
    exit 1
  fi
}

validate_address() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Invalid wallet address, exiting!"
    exit 1
  fi
}

validate_port() {
  if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -le 1024 ] || [ "$1" -ge 65535 ]; then
    echo "Invalid port number, it must be between 1024 and 65535."
    exit 1
  fi
}

validate_ip_or_fqdn() {
  local input=$1

  if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r -a octets <<< "$input"
    for octet in "${octets[@]}"; do
      if (( octet < 0 || octet > 255 )); then
        echo "Invalid IPv4 address. Each octet must be between 0 and 255."
        return 1
      fi
    done

    if [[ "$input" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^169\.254\.|^100\.64\.|^198\.51\.100\.|^203\.0\.113\.|^224\.|^240\. ]]; then
      echo "The provided IP address belongs to a private or non-routable range and might not be accessible from other nodes."
      return 1
    fi
  elif [[ "$input" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    return 0
  else
    echo "Invalid input, must be a valid IPv4 address or FQDN."
    return 1
  fi

  return 0
}


read -p "Do you have your private key for running the Ocean Node [ y/n ]: " has_key

if [ "$has_key" == "y" ]; then
  read -p "Enter your private key: " PRIVATE_KEY
  validate_hex "$PRIVATE_KEY"
else
  read -p "Do you want me to create a private key for you [ y/n ]: " create_key
  if [ "$create_key" == "n" ]; then
    echo "Exiting! Private Key is a mandatory variable"
    exit 1
  fi
  
  echo "Generating Private Key, please wait..."
  output=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n' | awk '{print "0x" $0}')
  PRIVATE_KEY=$(echo "$output")
  echo -e "Generated Private Key: \e[1;31m$PRIVATE_KEY\e[0m" 
  validate_hex "$PRIVATE_KEY"
fi

read -p "Please provide the wallet address to be added as Ocean Node admin account: " ALLOWED_ADMINS
validate_address "$ALLOWED_ADMINS"

echo -ne "Provide the HTTP_API_PORT value or accept the default (press Enter) [\e[1;32m8000\e[0m]: "
read HTTP_API_PORT
HTTP_API_PORT=${HTTP_API_PORT:-8000}
validate_port "$HTTP_API_PORT"

echo -ne "Provide the P2P_ipV4BindTcpPort or accept the default (press Enter) [\e[1;32m9000\e[0m]: "
read P2P_ipV4BindTcpPort
P2P_ipV4BindTcpPort=${P2P_ipV4BindTcpPort:-9000}
validate_port "$P2P_ipV4BindTcpPort"

echo -ne "Provide the P2P_ipV4BindWsPort or accept the default (press Enter) [\e[1;32m9001\e[0m]: "
read P2P_ipV4BindWsPort
P2P_ipV4BindWsPort=${P2P_ipV4BindWsPort:-9001}
validate_port "$P2P_ipV4BindWsPort"

echo -ne "Provide the P2P_ipV6BindTcpPort or accept the default (press Enter) [\e[1;32m9002\e[0m]: "
read P2P_ipV6BindTcpPort
P2P_ipV6BindTcpPort=${P2P_ipV6BindTcpPort:-9002}
validate_port "$P2P_ipV6BindTcpPort"

echo -ne "Provide the P2P_ipV6BindWsPort or accept the default (press Enter) [\e[1;32m9003\e[0m]: "
read P2P_ipV6BindWsPort
P2P_ipV6BindWsPort=${P2P_ipV6BindWsPort:-9003}
validate_port "$P2P_ipV6BindWsPort"

read -p "Provide the public IPv4 address or FQDN where this node will be accessible: " P2P_ANNOUNCE_ADDRESS

if [ -n "$P2P_ANNOUNCE_ADDRESS" ]; then
  validate_ip_or_fqdn "$P2P_ANNOUNCE_ADDRESS"
  if [ $? -ne 0 ]; then
    echo "Invalid address. Exiting!"
    exit 1
  fi

if [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # IPv4
    P2P_ANNOUNCE_ADDRESSES='["/ip4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_ipV4BindTcpPort'", "/ip4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_ipV4BindWsPort'"]'
  elif [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    # FQDN
    P2P_ANNOUNCE_ADDRESSES='["/dns4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_ipV4BindTcpPort'", "/dns4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_ipV4BindWsPort'"]'
  fi
else
  P2P_ANNOUNCE_ADDRESSES=''
  echo "No input provided, the Ocean Node might not be accessible from other nodes."
fi

read -p "Do you want to run docker C2D jobs on your Ocean Node [ y/n ]: " run_c2d_jobs

if [ "$run_c2d_jobs" == "y" ]; then
  echo "########################################################"
  echo "### Docker Engine Compute Environments Configuration ###"
  echo "########################################################"
  echo "Check 'ComputeEnvironment' definition for more details on the format"
  echo "_____________________________________________________"
  echo ""
  read -p "Do you want to add a specific docker environment configuration?
  (Hint: You can enter multiple in JSON format) [ y/n ]: " c2d_env
  if [ "$c2d_env" == "y" ]; then
    read -p "Enter the array of docker environment(s): " DOCKER_COMPUTE_ENVIRONMENTS 
  fi
else
  echo "Running node without docker C2D capabilities!"
fi

# Set default compute environments if not already defined
if [ -z "$DOCKER_COMPUTE_ENVIRONMENTS" ]; then
  echo "Setting default DOCKER_COMPUTE_ENVIRONMENTS configuration"
  export DOCKER_COMPUTE_ENVIRONMENTS="[{\"socketPath\":\"/var/run/docker.sock\",\"resources\":[{\"id\":\"disk\",\"total\":1000000000}],\"storageExpiry\":604800,\"maxJobDuration\":36000,\"fees\":{\"1\":[{\"feeToken\":\"0x123\",\"prices\":[{\"id\":\"cpu\",\"price\":1}]}]},\"free\":{\"maxJobDuration\":360000,\"maxJobs\":3,\"resources\":[{\"id\":\"cpu\",\"max\":1},{\"id\":\"ram\",\"max\":1000000000},{\"id\":\"disk\",\"max\":1000000000}]}}]"
fi

cat <<EOF > docker-compose.yml
services:
  ocean-node:
    image: oceanprotocol/ocean-node:0.2.3
    pull_policy: always
    container_name: ocean-node
    restart: on-failure
    ports:
      - "$HTTP_API_PORT:$HTTP_API_PORT"
      - "$P2P_ipV4BindTcpPort:$P2P_ipV4BindTcpPort"
      - "$P2P_ipV4BindWsPort:$P2P_ipV4BindWsPort"
      - "$P2P_ipV6BindTcpPort:$P2P_ipV6BindTcpPort"
      - "$P2P_ipV6BindWsPort:$P2P_ipV6BindWsPort"
    environment:
      PRIVATE_KEY: '$PRIVATE_KEY'
      RPCS: '{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'
#     DB_URL: 'http://typesense:8108/?apiKey=xyz'
      IPFS_GATEWAY: 'https://ipfs.io/'
      ARWEAVE_GATEWAY: 'https://arweave.net/'
#      LOAD_INITIAL_DDOS: ''
#      FEE_TOKENS: ''
#      FEE_AMOUNT: ''
#      ADDRESS_FILE: ''
#      NODE_ENV: ''
#      AUTHORIZED_DECRYPTERS: ''
#      AUTHORIZED_DECRYPTERS_LIST: ''
#      OPERATOR_SERVICE_URL: ''
#      POLICY_SERVER_URL: ''
      INTERFACES: '["HTTP","P2P"]'
#      ALLOWED_VALIDATORS: ''
#      ALLOWED_VALIDATORS_LIST: ''
#      AUTHORIZED_PUBLISHERS: ''
#      AUTHORIZED_PUBLISHERS_LIST: ''
      INDEXER_NETWORKS: '[]'
      ALLOWED_ADMINS: '["$ALLOWED_ADMINS"]'
#      ALLOWED_ADMINS_LIST: ''
#      INDEXER_INTERVAL: ''
      CONTROL_PANEL: 'true'
#      RATE_DENY_LIST: ''
#      MAX_REQ_PER_MINUTE: ''
#      MAX_CONNECTIONS_PER_MINUTE: ''
#      MAX_CHECKSUM_LENGTH: ''
#      LOG_LEVEL: ''
      HTTP_API_PORT: '$HTTP_API_PORT'
      P2P_ENABLE_IPV4: 'true'
      P2P_ENABLE_IPV6: 'false'
      P2P_ipV4BindAddress: '0.0.0.0'
      P2P_ipV4BindTcpPort: '$P2P_ipV4BindTcpPort'
      P2P_ipV4BindWsPort: '$P2P_ipV4BindWsPort'
      P2P_ipV6BindAddress: '::'
      P2P_ipV6BindTcpPort: '$P2P_ipV6BindTcpPort'
      P2P_ipV6BindWsPort: '$P2P_ipV6BindWsPort'
      P2P_ANNOUNCE_ADDRESSES: '$P2P_ANNOUNCE_ADDRESSES'
      P2P_MAX_CONNECTIONS: '100'
      DOCKER_COMPUTE_ENVIRONMENTS: '[{"socketPath":"/var/run/docker.sock","resources":[{"id":"disk","total":1000000000}],"storageExpiry":604800,"maxJobDuration":36000,"fees":{"1":[{"feeToken":"0x123","prices":[{"id":"cpu","price":1}]}]},"free":{"maxJobDuration":360000,"maxJobs":1,"resources":[{"id":"cpu","max":1},{"id":"ram","max":1000000000},{"id":"disk","max":1000000000}]}}]'

EOF

echo -e "\e[1;32mDocker Compose file has been generated successfully.\e[0m"
echo ""
echo -e "\e[1;32mYou are now ready to start your Ocean Node.\e[0m"
echo ""
echo -e "\e[1;32m1)\e[0m If further customization is required, edit the \e[1;32mdocker-compose.yml\e[0m file."
echo -e "For all available configurations, refer to the environment variables documentation:"
echo -e "\e[1;34mhttps://github.com/oceanprotocol/ocean-node/blob/main/docs/env.md\e[0m"
echo ""
echo -e "\e[1;32m2)\e[0m Start your Ocean Node by running the command:"
echo -e "\e[1;32mdocker-compose up -d\e[0m"
echo ""
echo -e "\e[1;32m3)\e[0m Allow and forward the following incoming TCP ports through the firewall to the Ocean Node host:"
echo -e "\e[1;32mHTTP API Port: $HTTP_API_PORT\e[0m"
echo -e "\e[1;32mP2P IPv4 TCP Port: $P2P_ipV4BindTcpPort\e[0m"
echo -e "\e[1;32mP2P IPv4 WebSocket Port: $P2P_ipV4BindWsPort\e[0m"
echo -e "\e[1;32mP2P IPv6 TCP Port: $P2P_ipV6BindTcpPort\e[0m"
echo -e "\e[1;32mP2P IPv6 WebSocket Port: $P2P_ipV6BindWsPort\e[0m"
