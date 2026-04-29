function randmac --argument-names iface
    set -l mac (python -c "import random; b=[random.randint(0,255) for _ in range(6)]; b[0]=(b[0] & 0b11111100) | 0b00000010; print(':'.join(f'{x:02x}' for x in b))")
    sudo ip link set dev $iface down
    sudo ip link set dev $iface address $mac
    sudo ip link set dev $iface up
end
