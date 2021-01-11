This is a fork of the fine work of Binhex at https://github.com/binhex/arch-delugevpn

**Application**

[Flexget website](http://flexget.com/)    
[Deluge website](http://deluge-torrent.org/) 

[OpenVPN website](https://openvpn.net/)  
[WireGuard](https://www.wireguard.com/)

**Description Binhex's DelugeVPN**

Deluge is a full-featured ​BitTorrent client for Linux, OS X, Unix and Windows. It uses ​libtorrent in its backend and features multiple user-interfaces including: GTK+, web and console. It has been designed using the client server model with a daemon process that handles all the bittorrent activity. The Deluge daemon is able to run on headless machines with the user-interfaces being able to connect remotely from any platform. This Docker includes OpenVPN to ensure a secure and private connection to the Internet, including use of iptables to prevent IP leakage when the tunnel is down. It also includes Privoxy to allow unfiltered access to index sites, to use Privoxy please point your application at `http://<host ip>:8118`.

**Description Flexget with webui daemon**

FlexGet is a multipurpose automation tool for content like torrents, nzbs, podcasts, comics, series, movies, etc. It can use different kinds of sources like RSS-feeds, html pages, csv files, search engines and there are even plugins for sites that do not provide any kind of useful feeds.  There are numerous plugins that allow utilizing FlexGet in interesting ways and more are being added continuously.  FlexGet is extremely useful in conjunction with applications which have watch directory support or provide interface for external utilities like FlexGet.

**Access Flexget-webui** [password is flexpass]

 Change passord with:   

    docker exec -it paulpoco-delugevpn /bin/bash
    flexget web passwd <some_password>  #from inside container

`http://<host ip>:3539`

**Build notes**

Latest stable Deluge release from Arch Linux repo.
Latest stable Privoxy release from Arch Linux repo.
Latest stable OpenVPN release from Arch Linux repo. 
Latest stable WireGuard release from Arch Linux repo.
Latest stable Flexget release from Python.

**Usage**
```
docker run -d \
    --cap-add=NET_ADMIN \
    -p 8112:8112 \
    -p 8118:8118 \
    -p 58846:58846 \
    -p 58946:58946 \
    --name=<container name> \
    -v <path for data files>:/data \
    -v <path for config files>:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=<yes|no> \
    -e VPN_USER=<vpn username> \
    -e VPN_PASS=<vpn password> \
    -e VPN_PROV=<pia|airvpn|custom> \
    -e VPN_CLIENT=<openvpn|wireguard> \
    -e VPN_OPTIONS=<additional openvpn cli options> \
    -e STRICT_PORT_FORWARD=<yes|no> \
    -e ENABLE_PRIVOXY=<yes|no> \
    -e LAN_NETWORK=<lan ipv4 network>/<cidr notation> \
    -e NAME_SERVERS=<name server ip(s)> \
    -e DELUGE_DAEMON_LOG_LEVEL=<critical|error|warning|info|debug> \
    -e DELUGE_WEB_LOG_LEVEL=<critical|error|warning|info|debug> \
    -e ADDITIONAL_PORTS=<port number(s)> \
    -e DEBUG=<true|false> \
    -e UMASK=<umask for created files> \
    -e PUID=<UID for user> \
    -e PGID=<GID for user> \
    binhex/arch-delugevpn
```
&nbsp;
Please replace all user variables in the above command defined by <> with the correct values.

**Access Deluge**

Default password for the webui is "deluge"

`http://<host ip>:8112`

**Access Privoxy**

`http://<host ip>:8118`

**PIA example**
```
 docker run -d \
     --cap-add=NET_ADMIN \
     -p 8112:8112 \
     -p 8118:8118 \
     -p 58846:58846 \
     -p 58946:58946 \
     --name=delugevpn \
     -v /apps/docker/deluge/data:/data \
     -v /apps/docker/deluge/config:/config \
     -v /etc/localtime:/etc/localtime:ro \
     -e VPN_ENABLED=yes \
     -e VPN_USER=myusername \
     -e VPN_PASS=mypassword \
     -e VPN_PROV=pia \
     -e VPN_CLIENT=openvpn \
     -e STRICT_PORT_FORWARD=yes \
     -e ENABLE_PRIVOXY=yes \
     -e LAN_NETWORK=192.168.1.0/24 \
     -e NAME_SERVERS=209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1 \
     -e DELUGE_DAEMON_LOG_LEVEL=info \
     -e DELUGE_WEB_LOG_LEVEL=info \
     -e ADDITIONAL_PORTS=1234 \
     -e DEBUG=false \
     -e UMASK=000 \
     -e PUID=0 \
     -e PGID=0 \
     binhex/arch-delugevpn
```
&nbsp;
**AirVPN provider**

AirVPN users will need to generate a unique OpenVPN configuration file by using the following link https://airvpn.org/generator/

1. Please select Linux and then choose the country you want to connect to
2. Save the ovpn file to somewhere safe
3. Start the delugevpn docker to create the folder structure
4. Stop delugevpn docker and copy the saved ovpn file to the /config/openvpn/ folder on the host
5. Start delugevpn docker
6. Check supervisor.log to make sure you are connected to the tunnel

**AirVPN example**
```
 docker run -d \
     --cap-add=NET_ADMIN \
     -p 8112:8112 \
     -p 8118:8118 \
     -p 58846:58846 \
     -p 58946:58946 \
     --name=delugevpn \
     -v /apps/docker/deluge/data:/data \
     -v /apps/docker/deluge/config:/config \
     -v /etc/localtime:/etc/localtime:ro \
     -e VPN_ENABLED=yes \
     -e VPN_PROV=airvpn \
     -e VPN_CLIENT=openvpn \
     -e ENABLE_PRIVOXY=yes \
     -e LAN_NETWORK=192.168.1.0/24 \
     -e NAME_SERVERS=209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1 \
     -e DELUGE_DAEMON_LOG_LEVEL=info \
     -e DELUGE_WEB_LOG_LEVEL=info \
     -e ADDITIONAL_PORTS=1234 \
     -e DEBUG=false \
     -e UMASK=000 \
     -e PUID=0 \
     -e PGID=0 \
     binhex/arch-delugevpn
```
&nbsp;
**Notes**

OpenVPN
=======
Please note this Docker image does not include the required OpenVPN configuration file and certificates. These will typically be downloaded from your VPN providers website (look for OpenVPN configuration files), and generally are zipped.

PIA users - The URL to download the OpenVPN configuration files and certs is:-

https://www.privateinternetaccess.com/openvpn/openvpn.zip

Once you have downloaded the zip (normally a zip as they contain multiple ovpn files) then extract it to /config/openvpn/ folder (if that folder doesn't exist then start and stop the docker container to force the creation of the folder).

If there are multiple ovpn files then please delete the ones you don't want to use (normally filename follows location of the endpoint) leaving just a single ovpn file and the certificates referenced in the ovpn file (certificates will normally have a crt and/or pem extension).

WireGuard
=========
Due to the enhanced security and kernel integration, WireGuard will require the container to be defined with privileged permissions, so please ensure you change the following from:-
```
    --cap-add=NET_ADMIN \
```
to
```
    --privileged=true \
```

Various
=======
Due to Google and OpenDNS supporting EDNS Client Subnet it is recommended NOT to use either of these NS providers.
The list of default NS providers in the above example(s) is as follows:-

209.222.x.x = PIA
84.200.x.x = DNS Watch
37.235.x.x = FreeDNS
1.x.x.x = Cloudflare

User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:-

`id <username>`
___
If you appreciate Binhex's work, then please consider buying him a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Support forum] Coming soon
