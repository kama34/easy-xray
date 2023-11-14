#!/usr/bin/env bash

bold='\033[0;1m'
underl='\033[0;4m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
normal='\033[0m'

# strip lines with comments from jsonC
jsonc2json () {
    if [ ! -v $1 ]
    then
        filename=$1
        cat $filename | grep -v \/\/
    else
        echo "${red}jsonc2json: no argument is given${red}"
        exit 1
    fi
}


export PATH=$PATH:/usr/local/bin/ # for sudo user this can be not in PATH
if command -v xray > /dev/null
then
    xray_version=$(xray --version | head -n 1 | cut -c 6-10)
    echo -e "${green}xray ${xray_version} detected${normal}"
fi

if command -v jq > /dev/null
then
    jq_installed=true
    echo -e "${green}jq found${normal}"
else
    jq_installed=false
    echo -e "${yellow}Warning: jq not installed but needed for operations with configs${normal}"
fi

if [ $(id -u) -eq 0 ]
then
    is_root=true
    echo -e "${green}running as root${normal}"
else
    is_root=false
    echo -e "${yellow}Warning: you should be root to install xray${normal}"
fi

command="help"
if [ ! -v $1 ]
then
    command=$1
fi

if [ $command = "install" ]
then

    echo -e "${bold}Download and install xray?${normal} (Y/n)"
    read answer_di
    if [ -v $answer_di ] || [ $(echo $answer_di | cut -c 1) != "n" ]
    then
        install_xray=true
        if command -v xray > /dev/null
        then
            echo -e "xray ${version} detected, install anyway? (y/N)"
            read answer_ia
            if [ -v $answer_ia ] || ([ $(echo $answer_ia | cut -c 1) != "y" ] && [ $(echo $answer_ia | cut -c 1) != "Y" ])
            then
                install_xray=false
            fi
        fi
        if $install_xray
        then
            if $is_root
            then
                if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
                then
                    dat_dir="/usr/local/share/xray/"
                    mkdir -p $dat_dir
                    cp customgeo.dat ${dat_dir}
                    echo -e "${green}xray installed${normal}"
                else
                    echo -e "${red}xray not installed, something goes wrong${normal}"
                fi
            else
                echo -e "${red}You should be root, or run this script with sudo
to install xray${normal}"
                exit 1
            fi
        fi
    fi

    echo -e "${bold}Generate configs?${normal} (Y/n)"
    read answer_gc
    if [ -v $answer_gc ] || [ $(echo $answer_gc | cut -c 1) != "n" ]
    then
        if ! $(command -v xray > /dev/null)
        then
            echo -e "${red}xray not installed, can't generate configs"
            exit 1
        fi
        if ! $jq_installed
        then
            echo -e "${red}jq not installed, can't generate configs"
            exit 1
        else
            echo -e "${bold}Enter IPv4 or IPv6 address of your xray server, or its domain name:${normal}"
            read address
            id=$(xray uuid) # generate random uuid for vless
            keys=$(xray x25519)
            private_key=$(echo $keys | cut -d " " -f 3)
            public_key=$(echo $keys | cut -d " " -f 6)
            # generate random short_id for grpc-reality
            if command -v openssl > /dev/null
            then
                short_id=$(openssl rand -hex 8)
            else
                echo -e "Enter a random (up to) 16-digit hex number,
containing only digits 0-9 and letters a-f, for instance
1234567890abcdef"
                read short_id
                if [ -v $short_id ]
                then
                    echo -e "${red}short id not set${normal}"
                    exit 1
                fi
            fi
            echo -e "${bold}Choose a fake site to mimic.${normal}
Better if it is: hosted by your VPS provider,
in the same country, it is popular,
and have only ports 80 (http) and 443 (https) open
(can check with `nmap -T4 hostname`)
(1) www.youtube.com (default)
(2) www.microsoft.com
(3) www.google.com
(4) www.bing.com
(5) www.yahoo.com
(6) your variant"
            read number
            default_fake_site="www.youtube.com"
            if [ ! -v $number ]
            then
                if [ $number -eq 2 ]
                then
                    fake_site="www.microsoft.com"
                elif [ $number -eq 3 ]
                then
                    fake_site="www.google.com"
                elif [ $number -eq 4 ]
                then
                    fake_site="www.bing.com"
                elif [ $number -eq 5 ]
                then
                    fake_site="www.yahoo.com"
                elif [ $number -eq 6 ]
                then
                    echo -e "type your variant:"
                    read fake_site
                    if [ -v $fake_site ]
                    then
                        fake_site=$default_fake_site
                    fi
                else
                    fake_site=$default_fake_site
                fi
            else
                fake_site=$default_fake_site
            fi
            server_names="[ \"$fake_site\" ]"
            echo -e "${green}mimic ${fake_site}${normal}"
            email="love@xray.com"
            # make server config
            jsonc2json template_config_server.jsonc \
                | jq ".inbounds[].settings.clients[0].id=\"${id}\"
                    | .inbounds[].settings.clients[0].email=\"${email}\"
                    | .inbounds[0].streamSettings.realitySettings.dest=\"${fake_site}:443\"
                    | .inbounds[1].streamSettings.realitySettings.dest=\"${fake_site}:80\"
                    | .inbounds[].streamSettings.realitySettings.serverNames=${server_names}
                    | .inbounds[].streamSettings.realitySettings.privateKey=\"${private_key}\"
                    | .inbounds[].streamSettings.realitySettings.shortIds=[ \"${short_id}\" ]" \
                > config_server.json
            # then make the user (not root) the owner of the file
            [[ $SUDO_USER ]] && chown "$SUDO_USER:$SUDO_USER" config_server.json
            vnext=" [
                    {
                        \"address\": \"${address}\",
                        \"port\": 443,
                        \"users\": [
                            {
                                \"id\": \"${id}\",
                                \"email\": \"${email}\",
                                \"encryption\": \"none\",
                                \"flow\": \"xtls-rprx-vision\"
                            }
                        ]
                    }
                ]"
            clientRealitySettings=" {
                    \"fingerprint\": \"chrome\",
                    \"serverName\": \"${fake_site}\",
                    \"show\": false,
                    \"publicKey\": \"${public_key}\",
                    \"shortId\": \"${short_id}\",
                }"
            # make main client config
            jsonc2json template_config_client.jsonc | jq ".outbounds |= map(if .settings.vnext then .settings.vnext=${vnext} else . end) | .outbounds |= map(if .streamSettings.realitySettings then .streamSettings.realitySettings=${clientRealitySettings} else . end)" > config_client.json
            # then make the user (not root) an owner of a file
            [[ $SUDO_USER ]] && chown "$SUDO_USER:$SUDO_USER" config_client.json
        fi
    fi

elif [ $command = "add" ]
then
    echo -e "${bold}add${normal}"
    if ! $(command -v xray > /dev/null)
    then
        echo -e "${red}xray needed but not installed${normal}"
        exit 1
    fi
    if ! $jq_installed
    then
        echo -e "${red}jq needed but not installed${normal}"
        exit 1
    fi
    if [ ! -f "config_client.json" ] || [ ! -r "config_server.json" ]
    then
        echo -e "${red}server config and config for default user are needed but not present,
first generate them with ${normal}install${red} command.${normal}"
        exit 1
    fi
    if [ -v $2 ]
    then
        echo -e "${red}username not set${normal}
For default user, use config_client.json generated
by ${underl}install${normal} command. Otherwise use non-void username,
preferably of letters and digits only."
        exit 1
    else
        username=$2
    fi
    configs=(config_client_*.json)
    username_exists=false
    for c in ${configs[@]}
    do
        if [ -f $c ]
        then
            email=$(jq '.outbounds[0].settings.vnext[0].users[0].email' $c)
            name=$(echo $email | cut -d "@" -f 1 | cut -c 2-)
            if [ $username = $name ]
            then
                username_exists=true
            fi
        fi
    done
    if $username_exists
    then
        echo -e "${red}username ${username} already exists, try another one${normal}"
        exit 1
    else
        id=$(xray uuid) # generate random uuid for vless
        # generate random short_id for grpc-reality
        if command -v openssl > /dev/null
        then
            short_id=$(openssl rand -hex 8)
        else
            echo -e "Enter a random (up to) 16-digit hex number,
containing only digits 0-9 and letters a-f, for instance
1234567890abcdef"
            read short_id
            if [ -v $short_id ]
            then
                echo -e "${red}short id not set${normal}"
                exit 1
            fi
        fi
        # make new user config from default user config
        cat config_client.json | jq ".outbounds[0].settings.vnext[0].users[0].id=\"${id}\" | .outbounds[0].settings.vnext[0].users[0].email=\"${username}@example.com\" | .outbounds[0].streamSettings.realitySettings.shortId=\"${short_id}\"" > config_client_${username}.json
        # then make the user (not root) an owner of a file
        [[ $SUDO_USER ]] && chown "$SUDO_USER:$SUDO_USER" config_client.json
        # update server config
        client="
          {
            \"id\": \"${id}\",
            \"email\": \"${username}@example.com\",
            \"flow\": \"xtls-rprx-vision\"
          }
        "
        cp config_server.json config_server.json.backup
        # update server config
        cat config_server.json.backup | jq ".inbounds[0].settings.clients += [${client}] | .inbounds[0].streamSettings.realitySettings.shortIds += [\"${short_id}\"]" > config_server.json
        # then make the user (not root) an owner of a file
        [[ $SUDO_USER ]] && chown "$SUDO_USER:$SUDO_USER" config_server.json
        echo -e "${green}config_client_${username}.json is written,
config_server.json is updated${normal}"
    fi

elif [ $command = "del" ]
then
    echo -e "${bold}del${normal}"
    if ! $jq_installed
    then
        echo -e "${red}jq needed but not installed${normal}"
        exit 1
    fi
    if [ -v $2 ]
    then
        echo -e "${red}username not set${normal}"
        exit 1
    else
        username=$2
    fi
    config="config_client_${username}.json"
    if [ ! -f $config ]
    then
        echo -e "${red}no config for user ${username}${normal}"
        exit 1
    fi
    short_id=$(jq ".outbounds[0].streamSettings.realitySettings.shortId" $config)
    cp config_server.json config_server.json.backup
    # update server config
    cat config_server.json.backup | jq "del(.inbounds[0].settings.clients[] | select(.email == \"${username}@example.com\")) | del(.inbounds[0].streamSettings.realitySettings.shortIds[] | select(. == ${short_id}))" > config_server.json
    # then make the user (not root) an owner of a file
    [[ $SUDO_USER ]] && chown "$SUDO_USER:$SUDO_USER" config_server.json
    rm config_client_${username}.json
        echo -e "${green}config_client_${username}.json is deleted,
config_server.json is updated${normal}"

elif [ $command = "upgrade" ]
then
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    then
        echo -e "${green}xray upgraded${normal}"
    else
        echo -e "${red}xray not upgraded${normal}"
    fi

elif [ $command = "remove" ]
then
    echo -e "Remove xray? (y/N)"
    read answer_rx
    if [ ! -v $answer_rx ] && ([ $(echo $answer_rx | cut -c 1) = "y" ] || [ $(echo $answer_rx | cut -c 1) = "Y" ])
    then
        echo -e "${red}Please type YES to remove${normal}"
        read answer_y
        if [ ! -v $answer_y ] && ([ $answer_y = "YES" ] || [ $answer_y = "yes" ])
        then
            if $is_root
            then
                if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
                then
                    echo -e "${green}xray removed${normal}"
                else
                    echo -e "${red}xray not removed${normal}"
                fi
            else
                echo -e "${red}You should be root, or run this script with sudo
to remove xray${normal}"
                exit 1
            fi
        fi
    fi

else # "help", default
    echo -e "
${green}**** Hi, there! How to use: ****${normal}

    ${bold}./ex.sh ${underl}command${normal}

Here is the list of all available commands:

    ${bold}help${normal}            show this message (default)
    ${bold}install${normal}         run interactive prompt, which asks to download and install
                    XRay and generate configs for server and client
    ${bold}add ${underl}username${normal}    add user with (any, fake) username to configs
    ${bold}del ${underl}username${normal}    delete user with given username from configs
    ${bold}upgrade${normal}         upgrade xray, do not touch configs
    ${bold}remove${normal}          remove xray"
fi

echo -e "
Command is done.

${bold}Important:${normal} It is assumed that configs are stored and updated
locally as config_server.json, config_client.json or
config_client_username.json files. You should manually
start XRay with one of configs, depending
which role - server or client - XRay should play:
    sudo cp config_(role).json /usr/local/etc/xray/config.json
    sudo systemctl start xray
or
    sudo xray run -c config_(role).json
"

