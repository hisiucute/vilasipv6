#!/bin/sh

### define variable

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
user=vilas
pass=Vilas123
FIRST_PORT=10000
LAST_PORT=10350
ifname=eth0

### end define variable
random() {
        tr </dev/urandom -dc A-Za-z0-9 | head -c5
        echo
}

gen64() {
        ip64() {
                echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
        }
        echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}


enable_ipv6() {
	echo "net.ipv6.conf.default.disable_ipv6=0" >> /etc/sysctl.conf
	echo "net.ipv6.conf.all.disable_ipv6=0" >> /etc/sysctl.conf
	cat >>/etc/network/interfaces <<EOF
iface ens3 inet6 static
pre-up modprobe ipv6
address 2604:7c00:16:184::2/64
gateway 2604:7c00:16::1
EOF
	systemctl restart networking
}

install_3proxy() {
    echo "installing 3proxy"
    git clone https://github.com/z3apa3a/3proxy
	cd 3proxy
	ln -s Makefile.Linux Makefile
	make
	sudo make install
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    echo "net.ipv6.conf.$ifname.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
	systemctl stop ufw
    systemctl disable ufw

    cd $WORKDIR
}
gen_3proxy() {
    cat <<EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver 1.0.0.1
nserver 2606:4700:4700::64
nserver 2606:4700:4700::6400
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
# setgid 65535
# setuid 65535
stacksize 6291456
flush
auth strong
users $user:CL:$pass
auth strong
allow $user
$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5""}' ${WORKDATA})
flush
EOF
	systemctl restart 3proxy
}



gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "$user/$pass/$IP4/$port/$(gen64 $IP6)/$ifname"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig " $6 " inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

gen_ping () {
	cat <<EOF
$(awk -F "/" '{print "ping6 -c 5 -I " $5 " ipv6.google.com"}' ${WORKDATA})
EOF
}


#enable_ipv6

echo "installing apps"

sudo apt install build-essential net-tools curl wget git zip ifupdown libarchive-tools make gcc -y >/dev/null
install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
echo $IP4
echo $IP6


gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
#gen_ping >$WORKDIR/ping.sh
gen_3proxy >/usr/local/3proxy/conf/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
bash $WORKDIR/ping.sh
EOF
chmod +x $WORKDIR/*.sh
bash /etc/rc.local
