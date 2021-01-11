#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# detect image arch
####

OS_ARCH=$(cat /etc/os-release | grep -P -o -m 1 "(?=^ID\=).*" | grep -P -o -m 1 "[a-z]+$")
if [[ ! -z "${OS_ARCH}" ]]; then
	if [[ "${OS_ARCH}" == "arch" ]]; then
		OS_ARCH="x86-64"
	else
		OS_ARCH="aarch64"
	fi
	echo "[info] OS_ARCH defined as '${OS_ARCH}'"
else
	echo "[warn] Unable to identify OS_ARCH, defaulting to 'x86-64'"
	OS_ARCH="x86-64"
fi

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
# following needed for flextget are unzip unrar python2-twisted python2-pip nano gcc pkg-config freetype2
pacman_packages="unzip unrar libtorrent-rasterbar openssl python-chardet python-dbus python-distro python-geoip python-idna python-mako python-pillow python-pyopenssl python-rencode python-service-identity python-setproctitle python-six python-future python-requests python-twisted python-xdg python-zope-interface xdg-utils libappindicator-gtk3 python-pip nano gcc pkg-config freetype2 deluge"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages=""

# call aur install script (arch user repo)
source aur.sh

# tweaks
####

# start flexget stuff
mkdir -p /home/nobody/.cache
mkdir -p /home/nobody/.flexget
mkdir -p /home/nobody/.cache/pip
mkdir -p /home/nobody/.cache/pip/http

# start install flextget
pip install --upgrade pip
pip install --upgrade funcsigs
pip install --upgrade requests[security]
pip install --upgrade setuptools
pip install --upgrade wheel
pip install --upgrade deluge-client
pip install --upgrade flexget
# end install flexget

# end flexget stuff

# create path to store deluge python eggs
mkdir -p /home/nobody/.cache/Python-Eggs

# folders for flexget are /home/nobody/.flexget /home/nobody/.cache
#chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody /home/nobody/.flexget /home/nobody/.cache
#chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody /home/nobody/.flexget /home/nobody/.cache

# remove permissions for group and other from the Python-Eggs folder
chmod -R 700 /home/nobody/.cache/Python-Eggs

# container perms
####

# define comma separated list of paths
install_paths="/etc/privoxy,/home/nobody,/home/nobody/.cache,/home/nobody/.flexget"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# set permissions for python eggs to be a more restrictive 755, this prevents the warning message thrown by deluge on startup
mkdir -p /home/nobody/.cache/Python-Eggs ; chmod -R 755 /home/nobody/.cache/Python-Eggs

# disable built-in Deluge Plugin 'stats', as its currently broken in Deluge 2.x and causes log spam
# see here for details https://dev.deluge-torrent.org/ticket/3310
chmod 000 "/usr/lib/python3.8/site-packages/deluge/plugins/Stats-0.4-py3.8.egg"

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc
# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)
# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different 
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then
	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}
fi
# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid
EOF

# nothing below here has to do with flexget

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/local/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc
# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)
# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export DELUGE_DAEMON_LOG_LEVEL=$(echo "${DELUGE_DAEMON_LOG_LEVEL}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_DAEMON_LOG_LEVEL}" ]]; then
	echo "[info] DELUGE_DAEMON_LOG_LEVEL defined as '${DELUGE_DAEMON_LOG_LEVEL}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[info] DELUGE_DAEMON_LOG_LEVEL not defined,(via -e DELUGE_DAEMON_LOG_LEVEL), defaulting to 'info'" | ts '%Y-%m-%d %H:%M:%.S'
	export DELUGE_DAEMON_LOG_LEVEL="info"
fi

export DELUGE_WEB_LOG_LEVEL=$(echo "${DELUGE_WEB_LOG_LEVEL}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_WEB_LOG_LEVEL}" ]]; then
	echo "[info] DELUGE_WEB_LOG_LEVEL defined as '${DELUGE_WEB_LOG_LEVEL}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[info] DELUGE_WEB_LOG_LEVEL not defined,(via -e DELUGE_WEB_LOG_LEVEL), defaulting to 'info'" | ts '%Y-%m-%d %H:%M:%.S'
	export DELUGE_WEB_LOG_LEVEL="info"
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	if [ "${VPN_ENABLED}" != "no" ] && [ "${VPN_ENABLED}" != "No" ] && [ "${VPN_ENABLED}" != "NO" ]; then
		export VPN_ENABLED="yes"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_ENABLED="no"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[warn] !!IMPORTANT!! VPN IS SET TO DISABLED', YOU WILL NOT BE SECURE" | ts '%Y-%m-%d %H:%M:%.S'
	fi
	
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then
	# create directory to store openvpn config files
	mkdir -p /config/openvpn
	# set perms and owner for files in /config/openvpn directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/openvpn" &> /dev/null
	exit_code_chmod=$?
	set -e
	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[warn] Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi
	
	# force removal of mac os resource fork files in ovpn folder
	rm -rf /config/openvpn/._*.ovpn
	
	# wildcard search for openvpn config files (match on first result)
	export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
	# if ovpn file not found in /config/openvpn then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi
	
	echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
	
	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/local/bin/dos2unix.sh "${VPN_CONFIG}"
	
	# get all remote lines in ovpn file and save comma separated 
	vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=remote\s).*' | paste -s -d, - || true)
	
	if [[ -n "${vpn_remote_line}" ]]; then
	
		# split comma separated string into list from vpn_remote_line variable
		IFS=',' read -ra vpn_remote_line_list <<< "${vpn_remote_line}"
		
		# process each remote line from ovpn file
		for vpn_remote_line_item in "${vpn_remote_line_list[@]}"; do
		
			# if remote line contains comments then remove
			vpn_remote_line_item=$(echo "${vpn_remote_line_item}" | sed -r 's~\s?+#.*$~~g')
			
			vpn_remote_server_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f1 || true)
			
			if [[ -z "${vpn_remote_server_cut}" ]]; then
				echo "[warn] VPN configuration file ${VPN_CONFIG} remote line is missing or malformed, skipping to next remote line..." | ts '%Y-%m-%d %H:%M:%.S'
				continue
			fi
			
			vpn_remote_port_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f2 || true)
			if [[ -z "${vpn_remote_port_cut}" ]]; then
			
				echo "[warn] VPN configuration file ${VPN_CONFIG} remote port is missing or malformed, assuming port '1194'" | ts '%Y-%m-%d %H:%M:%.S'
				vpn_remote_port_cut="1194"
			fi
			
			vpn_remote_protocol_cut=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=proto\s).*' || true)
			if [[ -z "${vpn_remote_protocol_cut}" ]]; then
				vpn_remote_protocol_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f3 || true)
				if [[ -z "${vpn_remote_protocol_cut}" ]]; then
					echo "[warn] VPN configuration file ${VPN_CONFIG} remote protocol is missing or malformed, assuming protocol 'udp'" | ts '%Y-%m-%d %H:%M:%.S'
					vpn_remote_protocol_cut="udp"
				fi
			fi
			if [[ "${vpn_remote_protocol_cut}" == "tcp" ]]; then
				# if remote line contains old format 'tcp' then replace with newer 'tcp-client' format
				vpn_remote_protocol_cut="tcp-client"
			fi
				
			vpn_remote_server+="${vpn_remote_server_cut},"
			vpn_remote_port+="${vpn_remote_port_cut},"
			vpn_remote_protocol+="${vpn_remote_protocol_cut},"
			
		done
		
		echo "[info] VPN remote server(s) defined as '${vpn_remote_server}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[info] VPN remote port(s) defined as '${vpn_remote_port}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[info] VPN remote protcol(s) defined as '${vpn_remote_protocol}'" | ts '%Y-%m-%d %H:%M:%.S'
		
		export VPN_REMOTE_SERVER="${vpn_remote_server}"
		export VPN_REMOTE_PORT="${vpn_remote_port}"
		export VPN_REMOTE_PROTOCOL="${vpn_remote_protocol}"
	
	else

		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1
		
	fi
	
	VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
		echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi
	
	# get values from env vars as defined by user
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi
	
	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi
	
	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to name servers defined in readme.md" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1"
	fi
	
	if [[ $VPN_PROV != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
		
		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi
	
	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi
	
	if [[ $VPN_PROV == "pia" ]]; then
	
		export STRICT_PORT_FORWARD=$(echo "${STRICT_PORT_FORWARD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${STRICT_PORT_FORWARD}" ]]; then
			echo "[info] STRICT_PORT_FORWARD defined as '${STRICT_PORT_FORWARD}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRICT_PORT_FORWARD not defined (via -e STRICT_PORT_FORWARD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRICT_PORT_FORWARD="yes"
		fi
		
	fi

        export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

	export ADDITIONAL_PORTS=$(echo "${ADDITIONAL_PORTS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ADDITIONAL_PORTS}" ]]; then
			echo "[info] ADDITIONAL_PORTS defined as '${ADDITIONAL_PORTS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
			echo "[info] ADDITIONAL_PORTS not defined (via -e ADDITIONAL_PORTS), skipping allow for custom incoming ports" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	export APPLICATION="deluge"

fi

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /usr/local/bin/init.sh
rm /tmp/envvars_heredoc

# cleanup
cleanup.sh
