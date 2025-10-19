# Default network setup
ip link add name br0 type bridge
ip addr add 192.168.100.1/24 dev br0
ip link set br0 up

# Create TAP device
ip tuntap add name tap0 mode tap
ip link set tap0 master br0
ip link set tap0 up

# NAT for internet access
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE
iptables -A FORWARD -i br0 -j ACCEPT
iptables -A FORWARD -o br0 -j ACCEPT
